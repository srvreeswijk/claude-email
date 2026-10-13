#!/usr/bin/env bash
# Start or update n8n on the VPS with N8N_VERSION from config.env.
# Pulls the image, restarts n8n and waits for the health check.
source "$(dirname "$0")/lib.sh"

vps "test -f $APP_DIR/.env" || die "n8n is not set up on the VPS yet. Run ./setup_n8n.sh first."

info "Deploying n8n $N8N_VERSION to $VPS_HOST"
vps_copy "$DEPLOY_DIR/n8n/compose.yml" "$APP_DIR/"
sync_n8n_env
vps "cd $APP_DIR && docker compose pull -q && docker compose up -d --remove-orphans"
wait_for_n8n

info "Removing unused images"
vps "docker image prune -f" >/dev/null
