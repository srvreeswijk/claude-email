#!/usr/bin/env bash
# Shared helpers for the deploy scripts. Sourced by them, not run directly.
# Same approach as GPXDock/GPXDock.Web/deploy/lib.sh, which also set up the VPS.
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$DEPLOY_DIR")"
APP_DIR=/opt/apps/n8n

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }

[[ -f "$DEPLOY_DIR/config.env" ]] ||
    die "deploy/config.env not found. Copy deploy/config.env.example to deploy/config.env and fill it in."
# shellcheck source=config.env.example
source "$DEPLOY_DIR/config.env"

: "${VPS_HOST:?missing in config.env}" "${VPS_USER:?missing in config.env}"
: "${N8N_HOST:?missing in config.env}" "${N8N_VERSION:?missing in config.env}"
VPS_SSH_PORT="${VPS_SSH_PORT:-22}"
SSH_OPTS=(-p "$VPS_SSH_PORT" -o StrictHostKeyChecking=accept-new)

# Run a command on the VPS as VPS_USER: vps "docker ps"
# Arguments are expanded locally on purpose (SC2029).
# shellcheck disable=SC2029
vps() { ssh "${SSH_OPTS[@]}" "$VPS_USER@$VPS_HOST" "$@"; }

# Same, with a terminal (for 'logs -f').
vps_tty() { ssh -t "${SSH_OPTS[@]}" "$VPS_USER@$VPS_HOST" "$@"; }

# Copy local files to a directory on the VPS: vps_copy file1 file2 /opt/apps/x/
vps_copy() {
    local dest="${*: -1}"
    scp -q -P "$VPS_SSH_PORT" -o StrictHostKeyChecking=accept-new "${@:1:$#-1}" "$VPS_USER@$VPS_HOST:$dest"
}

# Stop early when the shared Caddy (installed from the GPXDock repo) is not running.
require_caddy() {
    vps "docker inspect -f '{{.State.Running}}' caddy 2>/dev/null | grep -q true" ||
        die "Caddy is not running on the VPS. Run ./02_setup_proxy.sh in GPXDock/GPXDock.Web/deploy first."
}

# Copy the values that come from config.env into the n8n .env on the VPS,
# so a change in config.env takes effect on the next setup or deploy.
sync_n8n_env() {
    vps "sed -i -e 's|^N8N_HOST=.*|N8N_HOST=$N8N_HOST|' -e 's|^N8N_VERSION=.*|N8N_VERSION=$N8N_VERSION|' $APP_DIR/.env"
}

# Wait until n8n answers its health check (asked from inside the Caddy container,
# so it tests the same network path Caddy uses).
wait_for_n8n() {
    info "Waiting for n8n to become healthy"
    for _ in $(seq 1 45); do
        if vps "docker exec caddy wget -qO- http://n8n:5678/healthz" >/dev/null 2>&1; then
            info "n8n is healthy: https://$N8N_HOST"
            return 0
        fi
        sleep 2
    done
    die "n8n did not become healthy within 90s. Check: ./logs.sh"
}
