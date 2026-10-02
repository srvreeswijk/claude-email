# Payslip email agent in n8n

An n8n workflow that finds new P-Direkt payslip mail in Gmail, reads the PDF, extracts the amounts with Claude, sends a summary to Telegram, adds the label `salarisstrook-n8n` and marks the mail as read. It runs next to the existing Apps Script and Cowork task and does not touch their labels (`salarisstrook`, `pdf-in-drive`).

## How it works

```
Elk uur ─────────► Zoekopdracht (automatisch) ─┐
Handmatige test ─► Zoekopdracht (test) ────────┤
                                               ▼
  Zoek P-Direkt mail → Labels ophalen → Label-ID erbij → Nog niet verwerkt
  → Mail met PDF ophalen → PDF naar tekst → Maskeren en prompt bouwen
  → Claude: bedragen uitlezen → Bericht opstellen → Telegram
  → Label salarisstrook-n8n → Markeer als gelezen

Op de 26e om 09:00 → Strook deze maand? → Niets gevonden → Telegram: nog geen strook
```

- **Hourly search instead of a Gmail Trigger.** The search is `from:noreply@p-direkt.minbzk.nl has:attachment -label:salarisstrook-n8n newer_than:30d`. A mail stays in that result until the workflow has labelled it, so a failed run (Claude down, Telegram error, machine off) is retried the next hour. The Gmail Trigger node only delivers each mail once, so a failure there means the payslip is skipped for good.
- **The skip check is explicit.** `Label-ID erbij` looks up the label ID and flags mails that already have the label; `Nog niet verwerkt` drops them. This matters for the manual test path, which does not exclude the label in its query.
- **Notify first, then label.** If labelling fails after the notification was sent, the next run sends it again. The other order would lose the notification silently.
- **Masking.** Before the text goes to Claude, IBANs and bare runs of 6-12 digits (personnel number, BSN) are replaced with `[IBAN]` / `[NUMMER]`. Amounts always contain a comma, so they are untouched.
- **Cross-check.** Every amount Claude returns is formatted back to Dutch notation (`6.545,34`) and looked up in the PDF text. If one is missing, the notification gets a warning line. This catches invented amounts, not amounts copied from the wrong line.
- **Model.** `claude-opus-5` with `effort: low` and structured output (JSON schema). One payslip is roughly 3-4k input tokens, so a few cents per run. `fallbacks: "default"` re-runs the request on another model if a safety classifier declines it. For a cheaper run, change `model` in `Maskeren en prompt bouwen` to `claude-haiku-4-5` and remove `effort` and `fallbacks` (plus the `anthropic-beta` header in `Claude: bedragen uitlezen`); Haiku supports neither.
- **Errors** go to the second workflow, `Salarisstrook (n8n) - foutmelding`, which sends the node name and error message to Telegram. With the hourly retry, a persistent error (for example an expired Google token) repeats every hour until fixed.
- **Gmail actions used:** search, get, add label, remove `UNREAD`. Nothing is deleted, moved, sent or archived. Note that n8n's Gmail credential asks Google for broader scopes than that; the restriction is in the workflow, not in the token.

## Setup

### 1. Start n8n (Podman, rootless)

```bash
cp .env.example .env
sed -i "s/^N8N_ENCRYPTION_KEY=$/N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)/" .env
export DOCKER_HOST=unix:///run/user/$(id -u)/podman/podman.sock
docker-compose up -d
```

Open http://localhost:5678 and create the owner account.

Keep `N8N_ENCRYPTION_KEY`: it encrypts the stored credentials. A new key means re-entering all of them.

To start n8n after a reboot (rootless Podman ignores `restart:` at boot):

```bash
systemctl --user enable --now podman-restart.service
loginctl enable-linger $USER
```

### 2. Gmail credential (Google Cloud)

1. In https://console.cloud.google.com create a project, for example `n8n-mail`.
2. *APIs & Services → Library*: enable **Gmail API**.
3. *Google Auth Platform* (OAuth consent screen): user type **External**, fill in app name and your email, add yourself as test user.
4. *Clients → Create client*: type **Web application**, authorized redirect URI `http://localhost:5678/rest/oauth2-credential/callback` (n8n shows the same URL in the credential screen).
5. *Audience*: **Publish app** so the status is **In production**. In *Testing* mode Google expires the refresh token after 7 days and the workflow stops. Google will not verify the app; that is fine for personal use. While signing in, choose *Advanced → Go to n8n-mail (unsafe)*.
6. In n8n: *Credentials → Add → Gmail OAuth2 API*, name it exactly **`Gmail account`**, paste client ID and secret, click *Sign in with Google*.

### 3. Anthropic API key

Create a key in https://console.anthropic.com (billed per use, separate from a Claude subscription). In n8n: *Credentials → Add → Header Auth*, name **`Anthropic API`**, header name `x-api-key`, value the key.

### 4. Telegram bot

1. In Telegram, message `@BotFather`, send `/newbot`, keep the token.
2. Send your new bot any message, then get your chat ID:
   ```bash
   curl -s "https://api.telegram.org/bot<TOKEN>/getUpdates" | jq '.result[0].message.chat.id'
   ```
3. In n8n: *Credentials → Add → Telegram API*, name **`Telegram bot`**, paste the token.

### 5. Gmail label

In Gmail, create the label **`salarisstrook-n8n`**. The workflow fails with a clear message if it is missing.

### 6. Import the workflows

With the three credentials in place (names must match, n8n links them by name):

```bash
podman exec n8n n8n import:workflow --separate --input=/workflows
```

Then open both workflows and replace `VUL-HIER-JE-TELEGRAM-CHAT-ID-IN` with your chat ID in the Telegram nodes (two in the main workflow, one in the error workflow). Do not commit the chat ID: export it back only after replacing it with the placeholder, or keep your edits in n8n only.

Activate both workflows when testing is done (*Publish* / *Active* toggle).

## Testing

1. **One payslip.** Open `Salarisstrook (n8n)`, click *Execute workflow* on `Handmatige test`. It searches `subject:"Salarisstrook september 2026"`. Check:
   - The Telegram message, against the PDF.
   - In the execution, node `Maskeren en prompt bouwen`: the text sent to Claude contains no account or personnel number.
   - In Gmail: label `salarisstrook-n8n` added, mail read.
2. **Skip.** Run it again: `Nog niet verwerkt` outputs nothing, no message.
3. **Other months.** Change the query in `Zoekopdracht (test)`, e.g. a month with and one without `Herberekening`, and `subject:"Salarisstrook januari 2026"` (two payslips, two messages).
4. **Safety net.** Execute `Op de 26e om 09:00` manually. With a payslip this month it sends nothing. To see the message, temporarily change `after:` in `Strook deze maand?` to a future date.
5. **Restart.** `docker-compose restart` and run a test again: the Gmail credential must still work.

To re-test a mail, remove the `salarisstrook-n8n` label in Gmail.

## Data and privacy

- Execution data (including the PDF text and amounts) stays in the `n8n_data` volume and is pruned after 7 days (`EXECUTIONS_DATA_MAX_AGE`).
- Never commit execution exports, PDFs or `.env`; `.gitignore` covers the common cases.
- The masked PDF text is sent to the Anthropic API.

## Limitations

- n8n only runs while this machine is on. Missed hourly runs are caught up by the next one (the search looks back 30 days). The 26th check uses `misfirePolicy: coalesce`, which runs a missed check once n8n is back; that relies on n8n's durable scheduler, which is still in preview in 2.41.
- The cross-check cannot tell whether an amount was taken from the right line.
