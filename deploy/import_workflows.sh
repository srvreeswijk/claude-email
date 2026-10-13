#!/usr/bin/env bash
# Import the workflows from ../workflows into n8n on the VPS.
# The workflows have fixed IDs, so this OVERWRITES the same workflows in n8n,
# including edits made in the n8n editor. Afterwards activate them again in n8n.
# TELEGRAM_CHAT_ID from config.env (if set) replaces the chat ID placeholder.
source "$(dirname "$0")/lib.sh"

vps "docker inspect n8n >/dev/null 2>&1" || die "n8n is not running on the VPS. Run ./deploy.sh first."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp "$REPO_DIR"/workflows/*.json "$tmp/"
if [[ -n "${TELEGRAM_CHAT_ID:-}" ]]; then
    sed -i "s/VUL-HIER-JE-TELEGRAM-CHAT-ID-IN/$TELEGRAM_CHAT_ID/g" "$tmp"/*.json
else
    info "TELEGRAM_CHAT_ID is empty: fill in the chat ID in the Telegram nodes in n8n"
fi

info "Importing workflows"
vps "rm -f $APP_DIR/workflows/*.json"
vps_copy "$tmp"/*.json "$APP_DIR/workflows/"
vps "docker exec n8n n8n import:workflow --separate --input=/workflows"
# The files may hold the chat ID; n8n has them now, so they are not needed on disk.
vps "rm -f $APP_DIR/workflows/*.json"
info "Done. Open https://$N8N_HOST and activate both workflows."
