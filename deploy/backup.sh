#!/usr/bin/env bash
# Download a copy of the n8n data (workflows, credentials, executions) to
# deploy/backups/ on this machine. n8n is stopped for a few seconds meanwhile.
# The archive contains the encryption key, so it opens every stored credential:
# keep it as safe as a password.
source "$(dirname "$0")/lib.sh"

mkdir -p "$DEPLOY_DIR/backups"
file="$DEPLOY_DIR/backups/n8n-$(date +%Y%m%d-%H%M%S).tar.gz"
info "Saving n8n data to $file"
vps "cd $APP_DIR && docker compose stop -t 30 n8n >/dev/null"
vps "set -o pipefail; docker run --rm -v n8n_n8n-data:/data:ro -v $APP_DIR/.env:/backup/.env:ro \
    alpine tar czf - -C / data backup/.env" > "$file" ||
    { rm -f "$file"; vps "cd $APP_DIR && docker compose start n8n"; die "Backup failed."; }
vps "cd $APP_DIR && docker compose start n8n >/dev/null"
chmod 600 "$file"
info "Done ($(du -h "$file" | cut -f1))"
