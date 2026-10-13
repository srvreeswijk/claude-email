#!/usr/bin/env bash
# Follow the n8n log on the VPS (Ctrl+C to stop).
source "$(dirname "$0")/lib.sh"
vps_tty "cd $APP_DIR && docker compose logs -f --tail=100 n8n"
