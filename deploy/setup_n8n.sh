#!/usr/bin/env bash
# Step 3: one-time setup of n8n on the VPS: .env with a generated encryption key,
# and the Caddy site with a login in front of n8n.
# Safe to run again. RESET_PASSWORD=1 ./setup_n8n.sh sets a new login password.
source "$(dirname "$0")/lib.sh"
[[ -t 0 ]] || die "This script asks for a password; run it in a terminal."
require_caddy

info "Copying compose.yml to $APP_DIR"
vps "mkdir -p $APP_DIR/workflows"
vps_copy "$DEPLOY_DIR/n8n/compose.yml" "$APP_DIR/"

if ! vps "test -f $APP_DIR/.env"; then
    info "Creating $APP_DIR/.env with a generated encryption key"
    vps "umask 077 && cat > $APP_DIR/.env" <<ENV
N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
N8N_HOST=$N8N_HOST
N8N_VERSION=$N8N_VERSION
ENV
fi
sync_n8n_env

# The login is stored as a bcrypt hash in $APP_DIR/basicauth ("user hash").
if [[ "${RESET_PASSWORD:-0}" == 1 ]] || ! vps "test -f $APP_DIR/basicauth"; then
    info "Caddy basic auth for https://$N8N_HOST (like htpasswd: the browser asks for it before n8n opens)."
    info "Choose a new user name and password. Not your ssh login. Only a bcrypt hash is stored on the VPS."
    read -rp "Basic auth user name for https://$N8N_HOST: " auth_user
    read -rsp "Basic auth password for https://$N8N_HOST (input hidden): " auth_password; echo
    [[ -n "$auth_user" && -n "$auth_password" ]] || die "User name and password may not be empty."
    # Caddy reads the password from stdin, so it never shows up in a process list.
    auth_hash="$(printf '%s\n' "$auth_password" | vps "docker exec -i caddy caddy hash-password")"
    printf '%s %s\n' "$auth_user" "$auth_hash" | vps "umask 077 && cat > $APP_DIR/basicauth"
fi
read -r auth_user auth_hash < <(vps "cat $APP_DIR/basicauth")

info "Writing Caddy site for https://$N8N_HOST"
site="$(<"$DEPLOY_DIR/n8n/site.caddy.template")"
site="${site//__HOST__/$N8N_HOST}"
site="${site//__USER__/$auth_user}"
site="${site//__HASH__/$auth_hash}"
printf '%s\n' "$site" | vps "cat > /opt/apps/caddy/etc/sites/n8n.caddy"
vps "docker exec -w /etc/caddy caddy caddy reload --config /etc/caddy/Caddyfile"

info "n8n is set up. Next: ./deploy.sh"
