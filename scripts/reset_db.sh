#!/usr/bin/env bash
set -euo pipefail

# clean_panel.sh — clear the status.db check history.
#
# Useful right after you've set up the Necesse and playit health agents:
# up until the daemons were actually running, the status page has been
# recording "down" rows. Wiping the `checks` table resets the uptime
# counters so the panel reflects real uptime from this point onward.

DB_PATH="${STATUS_DB_PATH:-/opt/status-page/data/status.db}"
SERVICE="status-page"

if [[ $EUID -ne 0 ]]; then
  echo "error: run as root" >&2
  exit 1
fi

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "error: sqlite3 not found — install it first (apt-get install -y sqlite3)" >&2
  exit 1
fi

if [[ ! -f "$DB_PATH" ]]; then
  echo "error: $DB_PATH not found" >&2
  exit 1
fi

echo "stopping $SERVICE..."
systemctl stop "$SERVICE"

before="$(sqlite3 "$DB_PATH" 'SELECT COUNT(*) FROM checks;')"
echo "deleting $before check rows..."
sqlite3 "$DB_PATH" "DELETE FROM checks; DELETE FROM sqlite_sequence WHERE name = 'checks';"

echo "starting $SERVICE..."
systemctl start "$SERVICE"

after="$(sqlite3 "$DB_PATH" 'SELECT COUNT(*) FROM checks;')"
echo "done: checks table now has $after rows"
