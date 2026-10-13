# Running n8n on the VPS

The payslip workflow runs on the same TransIP VPS as GPXDock, at **https://n8n.proeftuin.tech**:

```
browser ──HTTPS──> Caddy (ports 80/443, Let's Encrypt, login) ─┬─> gpxdock-web   gpxdock.proeftuin.tech
                                                               └─> n8n           n8n.proeftuin.tech
```

- The VPS and Caddy are set up by the scripts in `GPXDock/GPXDock.Web/deploy` (see its README). Caddy
  serves every hostname that has a file in `/opt/apps/caddy/etc/sites/`; this repo only adds `n8n.caddy`.
- n8n runs in Docker in `/opt/apps/n8n` on the VPS, with the official `n8nio/n8n` image. Nothing is built.
- Two locks: a Caddy login (basic auth) in front, then n8n's own owner account.
- Secrets (the encryption key, the Caddy login hash and everything in n8n's credential store) only exist
  on the VPS, never in git.

All scripts run **on your laptop** from this `deploy/` directory. They read `config.env` and use ssh to
work on the VPS. For running n8n on your own machine instead, see the main [README](../README.md).

## Where do I start?

| Situation | Start at |
|---|---|
| First time on this VPS | step 1 |
| New n8n version | "Update n8n" |
| Workflow changed in git | "Update the workflows" |
| New laptop | step 2, then whatever you came for |

## One-time setup

1. **VPS, Caddy and DNS** (already done)
   - The VPS is prepared and Caddy runs: steps 1-6 in `GPXDock/GPXDock.Web/deploy/README.md`.
   - DNS: an `A` record `n8n` → the VPS IPv4 address. Check: `dig +short n8n.proeftuin.tech`.

2. **Local settings** (once per laptop)
   ```bash
   cd deploy
   cp config.env.example config.env
   vi config.env      # VPS IP, n8n hostname, n8n version, Telegram chat ID
   ```

3. **Set up n8n:** `./setup_n8n.sh`
   Asks you to choose a **new** user name and password for the Caddy basic auth on `https://<N8N_HOST>`:
   the browser asks for it before n8n opens, like an htpasswd login in nginx or Apache. It is not an ssh
   login; ssh uses your key, as in all scripts. Generates the n8n encryption key, writes
   the Caddy site and reloads Caddy (the other sites keep running).

4. **Start n8n:** `./deploy.sh`
   Waits for the health check. Then open https://n8n.proeftuin.tech, log in with the Caddy login and
   create the n8n owner account.

5. **Credentials** (manual, in n8n). Same names as in the main README, steps 2-4:
   - **`Gmail account`**: first add the redirect URI `https://n8n.proeftuin.tech/rest/oauth2-credential/callback`
     to the OAuth client in Google Cloud (*Clients → your client → Authorized redirect URIs*). You can keep the
     `localhost` one next to it. Then create the credential with the same client ID and secret and sign in.
     During the Google sign-in the browser may ask for the Caddy login again; that is fine.
   - **`Header Auth account`**: header `x-api-key`, the Anthropic API key.
   - **`Telegram account`**: the bot token.

6. **Workflows:** `./import_workflows.sh`
   Copies `../workflows/*.json` into n8n. With `TELEGRAM_CHAT_ID` set in `config.env` the chat ID is
   filled in; otherwise replace `VUL-HIER-JE-TELEGRAM-CHAT-ID-IN` in the three Telegram nodes by hand.
   Run `Handmatige test` once (see "Testing" in the main README), then activate both workflows.

7. **Stop the local n8n** so the payslip is not processed twice:
   `docker-compose down` in the repo root (and `systemctl --user disable podman-restart.service` if
   nothing else uses it).

## Update n8n

Pick a version from https://github.com/n8n-io/n8n/releases, set `N8N_VERSION` in `config.env`, then:

```bash
./backup.sh        # recommended: n8n migrates its database on start
./deploy.sh
```

Roll back by setting the old version and restoring the backup taken before the update (below).

## Update the workflows

After changing `workflows/*.json` in git:

```bash
./import_workflows.sh
```

This **overwrites** the workflows with the same ID in n8n, including edits made in the n8n editor, and
leaves them inactive. Activate them again in n8n.

## Everyday commands

```bash
./logs.sh                          # follow the n8n log
./backup.sh                        # download the n8n data to deploy/backups/
RESET_PASSWORD=1 ./setup_n8n.sh    # new Caddy login
```

For containers, disk and memory of the whole VPS, use `./status.sh` in the GPXDock deploy directory.

## Restore a backup

This **replaces** all n8n data (workflows, credentials, execution history).

```bash
scp deploy/backups/n8n-<date>.tar.gz deploy@<ip>:/tmp/n8n.tar.gz
ssh deploy@<ip> "cd /opt/apps/n8n && docker compose stop n8n && \
    docker run --rm -v n8n_n8n-data:/data -v /tmp:/in alpine \
      sh -c 'find /data -mindepth 1 -delete && tar xzf /in/n8n.tar.gz -C / data' && \
    tar xzf /tmp/n8n.tar.gz -O backup/.env > .env && rm /tmp/n8n.tar.gz"
./deploy.sh
```

The archive also holds `.env` with the encryption key that belongs to that data; the restore puts it back
too. Keep the archives as safe as a password: together they open every stored credential.

## Troubleshooting

- **Browser shows a certificate error.** Caddy could not get a certificate yet. Check DNS
  (`dig +short n8n.proeftuin.tech`), then `ssh deploy@<ip> docker logs caddy`.
- **`setup_n8n.sh` says Caddy is not running.** Run `./02_setup_proxy.sh` in the GPXDock deploy directory.
- **Gmail sign-in says `redirect_uri_mismatch`.** The VPS redirect URI is missing in the Google OAuth client
  (step 5).
- **"Credentials could not be decrypted" after a restore.** `.env` and the data volume come from different
  backups. Restore both from the same archive.
- **No Telegram messages.** Are both workflows active? Check the executions in n8n and `./logs.sh`.

## Not done yet

- Scheduled off-site backups and monitoring (same as GPXDock).
- Blocking repeated failed logins on the Caddy basic auth. Caddy itself does not; the options are in
  "Not done yet" in `GPXDock/GPXDock.Web/deploy/README.md`, since Caddy is set up there.
