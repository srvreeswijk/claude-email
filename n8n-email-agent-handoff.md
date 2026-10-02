# Handoff: build the payslip email agent in n8n

This file carries over a conversation from Claude (Cowork) to Claude Code on Sebastiaan's own machine. Read it fully before starting. It describes what already exists, what to build next, and which decisions are still open.

## Goal

Build a self-hosted n8n workflow that does what an existing Cowork scheduled task already does: detect a new payslip email in Gmail, read the attached PDF, label the email, mark it as read, and send a short summary to Sebastiaan's phone.

The purpose is to learn and compare. Sebastiaan was asked by someone else to implement email automation, and he is using his personal mailbox to try out approaches. Payslips stand in for invoices: an email with a PDF attachment that has numbers in it. A solution that only works for payslips is less useful than one whose structure carries over to invoices from many senders.

## What already exists (do not break it)

A working Claude-based version, built in the earlier conversation:

1. **Google Apps Script** in Sebastiaan's Google account, running hourly. It saves PDF attachments from P-Direkt mail to Drive folder `Mail-bijlagen/Salarisstroken` and adds the Gmail label `pdf-in-drive`. This exists because the Claude Gmail connector cannot open attachments.
2. **Cowork scheduled task** "Salarisstrook check", running at 07:56 Europe/Amsterdam on the 22nd–26th of each month. It finds new P-Direkt mail, reads the PDF from Drive, adds the label `salarisstrook`, marks the mail as read, and sends a push notification through the Claude app.

Both keep running. The n8n version runs next to them so the two can be compared on the same payslip. To make that possible, n8n uses its own label, **`salarisstrook-n8n`**, and must not depend on or change the labels `salarisstrook` and `pdf-in-drive`.

n8n downloads the attachment itself, so it needs neither the Apps Script nor Drive.

## Facts about the mail and the PDF

- Mailbox: personal Gmail, s.vreeswijk@gmail.com.
- Sender: `noreply@p-direkt.minbzk.nl`.
- Subject: `Salarisstrook <maand> <jaar>`, for example `Salarisstrook september 2026`.
- One PDF attachment, named like the subject, about 20 KB, two pages, real text (no OCR needed).
- The email body is a generic notice and contains no amounts.
- Timing: every payslip so far arrived in the night between the 21st and the 24th of the month.
- A month can have two payslips. January 2026 has one from the 22nd and one from the 27th.
- Test data: 15 payslip emails from August 2025 through September 2026 are in the mailbox.

Lines in the PDF text that matter, in Dutch number format (`6.545,34`):

- `Salaris + <amount>` (gross)
- `Betaling IKB + <amount>` (present in some months)
- `Netto maandelijks salaris + <amount>`
- `Herberekening` section, with a specification on page 2 (lines such as commuting allowance and working-from-home allowance), present in some months
- `U ontvangt + <amount>` (amount paid out)

The PDF also contains a bank account number and a personnel number. Neither may appear in notifications, logs, or files in the repository.

## What to build

A project folder containing:

- `docker-compose.yml` for n8n with a persistent volume, timezone `Europe/Amsterdam`, bound to localhost.
- `.env.example` listing the variables needed, and a `.gitignore` that excludes `.env` and the n8n data volume.
- A workflow file to import into n8n.
- A short `README.md` with the setup steps, including the manual steps below.

Workflow outline:

```
Gmail Trigger (poll; from:noreply@p-direkt.minbzk.nl; download attachments)
  → skip if the mail already has label salarisstrook-n8n
  → Extract from File (PDF → text)
  → Claude via the Anthropic API (return gross, IKB, net, recalculations, paid out as JSON)
  → Gmail: add label salarisstrook-n8n, mark as read
  → push notification
```

Notification text, in Dutch, modelled on the Cowork version:

```
Salarisstrook september 2026: bruto €… + IKB €… · netto €… · herberekening +€… (reiskosten, thuiswerk) · uitbetaald €…
```

Also replicate the safety net: if no payslip has arrived by the 26th of the month, send "Nog geen salarisstrook ontvangen deze maand." This needs a second, scheduled branch or workflow.

## Rules

- Non-destructive only. Allowed Gmail actions: read, add a label, remove the UNREAD label. Never delete, trash, archive, move, send, forward or reply. Sebastiaan wants to build trust first and expand later.
- No secrets in files that could be committed. API keys and OAuth client secrets go in `.env` or in n8n's credential store.
- No salary amounts, bank account numbers or personnel numbers in the repository, in test fixtures, or in committed execution logs.
- This is a personal project. Do not use work infrastructure (OpenShift, GitLab, Harbor) for it.

## Steps only Sebastiaan can do (guide him through them)

1. **Google Cloud project**: enable the Gmail API, configure the OAuth consent screen, create an OAuth client ID, and add n8n's callback URL as redirect URI. n8n shows the exact URL in its Gmail credential screen. Set the consent screen to "In production"; in "Testing" mode Google expires the token after 7 days and the workflow stops silently.
2. **Anthropic API key** from the Anthropic Console. This is billed per use and is separate from his Claude subscription.
3. **Notification app** on his phone, once the channel is chosen.
4. **Authorising the Gmail credential** in the n8n web interface.

## Open decisions (ask before assuming)

- **Where n8n runs.** Not decided yet. Options discussed: his local machine or a home server, a VPS, or n8n Cloud. He said the work happens on his local machine, so start by checking whether Docker is available there. The Gmail trigger polls, so n8n does not need to be reachable from the internet.
- **Notification channel.** Proposed: ntfy (one HTTP call, phone app, can be self-hosted). Telegram and Pushover were the alternatives. Not confirmed.
- **Claude or regex for extraction.** Payslips have a fixed layout, so a regex would work. Claude was proposed because the same workflow should later handle invoices with varying layouts. Not confirmed.

## How to verify

- n8n starts and its interface loads on localhost.
- The Gmail credential authorises, and still works after a container restart.
- Run the workflow manually against the September 2026 payslip. Check that the label `salarisstrook-n8n` is added, the mail is marked as read, and the notification arrives with the right fields. Compare the amounts with the PDF itself.
- Run it again on the same mail and confirm it is skipped.
- Test a month with a recalculation section and a month without one, and test January 2026, which has two payslips.

n8n's node names and parameters change between versions. Check the installed version's nodes when writing the workflow file instead of relying on memory, and confirm the import works before reporting it as done.

## About Sebastiaan

DevOps and infrastructure engineer, comfortable with Docker, Kubernetes, bash and CI/CD. He prefers concise answers, wants to understand how things work in daily use, and likes to test each step on real data before moving on. English is fine for conversation; labels and notification texts are in Dutch.
