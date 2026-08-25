#!/usr/bin/env bash
set -euo pipefail
# sync-service-target.sh — run as root on the necesse-status (panel) host.
#
# What it does:
#   1. Reads NECESSE_HEALTH_URL and PLAYIT_HEALTH_URL from config.toml.
#   2. Updates the matching rows (id='necesse', id='playit') in status.db's
#      `services` table with those URLs — backing up the DB first.
#   3. Optionally restarts the status-page service so the panel re-polls
#      with the corrected targets immediately.
#
# This is the config.toml -> status.db sync step: config.toml is the
# source of truth for where each service's health-agent actually lives;
# this script makes sure status.db agrees with it, instead of drifting
# out of sync the way the playit row did before (stale IP left over from
# an earlier config).
#
# Run this any time config.toml changes (e.g. an LXC's IP changes and you
# update the URL there), instead of hand-editing status.db.

CONFIG_PATH="${CONFIG_PATH:-/opt/status-page/config.toml}"
STATUS_DB_PATH="${STATUS_DB_PATH:-/opt/status-page/data/status.db}"
SERVICE_NAME="${SERVICE_NAME:-status-page}"

if [[ $EUID -ne 0 ]]; then
  echo "error: run as root" >&2
  exit 1
fi

if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "error: config.toml not found at $CONFIG_PATH — set CONFIG_PATH if it lives elsewhere" >&2
  exit 1
fi

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "error: sqlite3 not found — install it (apt install sqlite3)" >&2
  exit 1
fi

if [[ ! -f "$STATUS_DB_PATH" ]]; then
  echo "error: status.db not found at $STATUS_DB_PATH — set STATUS_DB_PATH if it lives elsewhere" >&2
  exit 1
fi

# --- 1. Read URLs from config.toml ------------------------------------------
# Expects lines like: NECESSE_HEALTH_URL="http://192.168.100.228:9101/health"
extract_toml_value() {
  local key="$1"
  grep -E "^${key}[[:space:]]*=" "$CONFIG_PATH" \
    | head -n1 \
    | sed -E "s/^${key}[[:space:]]*=[[:space:]]*\"([^\"]*)\".*/\1/"
}

NECESSE_URL="$(extract_toml_value NECESSE_HEALTH_URL)"
PLAYIT_URL="$(extract_toml_value PLAYIT_HEALTH_URL)"

if [[ -z "$NECESSE_URL" ]]; then
  echo "error: NECESSE_HEALTH_URL not found in $CONFIG_PATH" >&2
  exit 1
fi
if [[ -z "$PLAYIT_URL" ]]; then
  echo "error: PLAYIT_HEALTH_URL not found in $CONFIG_PATH" >&2
  exit 1
fi

echo "config.toml says:"
echo "  necesse -> $NECESSE_URL"
echo "  playit  -> $PLAYIT_URL"

# --- 2. Update status.db -----------------------------------------------------
cp "$STATUS_DB_PATH" "${STATUS_DB_PATH}.bak.$(date +%Y%m%d%H%M%S)"
echo "backed up status.db"

sqlite3 "$STATUS_DB_PATH" <<SQL
UPDATE services SET target = '${NECESSE_URL}' WHERE id = 'necesse';
UPDATE services SET target = '${PLAYIT_URL}'  WHERE id = 'playit';
SQL

echo
echo "rows after sync:"
sqlite3 "$STATUS_DB_PATH" "SELECT * FROM services;"

# --- 3. Optionally restart the panel -----------------------------------------
echo
read -r -p "Restart ${SERVICE_NAME} now so the panel re-polls immediately? [y/N] " REPLY
if [[ "$REPLY" =~ ^[Yy]$ ]]; then
  systemctl restart "$SERVICE_NAME"
  systemctl status "$SERVICE_NAME" --no-pager
else
  echo "skipped restart — status.db is fixed either way, panel picks it up"
  echo "on its normal poll interval (or sooner if it re-reads services per check)."
fi

echo
echo "Done. Verify with:"
echo "  sqlite3 \"$STATUS_DB_PATH\" \"SELECT service_id, checked_at, healthy, latency_ms FROM checks ORDER BY checked_at DESC LIMIT 10;\""