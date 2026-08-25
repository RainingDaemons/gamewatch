#!/usr/bin/env bash
set -euo pipefail
# sync-service-target.sh — run as root on EACH service LXC (necesse or playit).
#
# What it does:
#   1. Detects this LXC's own IPv4 via `hostname -I`.
#   2. Reads the LOCAL /etc/systemd/system/health-agent.service to figure out
#      which service this is, based on its Environment= vars:
#        - HEALTH_PORT=14159 / HEALTH_PROCESS=necesse  -> service id "necesse"
#        - HEALTH_MODE=playit                          -> service id "playit"
#   3. Builds the target URL: http://<ip>:9101/health
#   4. Writes/updates that target directly into status.db's `services` table
#      for the matching row (necesse|playit) — no SSH involved. Assumes
#      status.db is reachable at STATUS_DB_PATH from this host (same path
#      it's mounted/shared at, or set STATUS_DB_PATH if it differs).
#   5. Restarts local health-agent so the SERVICE_URL env var (informational)
#      is also refreshed.
#
# Run this any time an LXC's IP changes, instead of hand-editing status.db.

HEALTH_PORT="9101"
HEALTH_PATH="/health"
AGENT_SERVICE_FILE="/etc/systemd/system/health-agent.service"
STATUS_DB_PATH="${STATUS_DB_PATH:-/opt/status-page/data/status.db}"

if [[ $EUID -ne 0 ]]; then
  echo "error: run as root" >&2
  exit 1
fi

if [[ ! -f "$AGENT_SERVICE_FILE" ]]; then
  echo "error: $AGENT_SERVICE_FILE not found on this host" >&2
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

# --- 1. Detect this LXC's own IPv4 -----------------------------------------
IP="$(hostname -I | tr ' ' '\n' | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' | head -n1 || true)"
if [[ -z "$IP" ]]; then
  echo "error: could not detect an IPv4 address from 'hostname -I'" >&2
  exit 1
fi
echo "detected local IPv4: $IP"

# --- 2. Infer service id from health-agent.service vars ---------------------
if grep -q '^Environment=HEALTH_MODE=playit' "$AGENT_SERVICE_FILE"; then
  SERVICE_ID="playit"
elif grep -q '^Environment=HEALTH_PROCESS=necesse' "$AGENT_SERVICE_FILE" \
  || grep -q '^Environment=HEALTH_PORT=14159' "$AGENT_SERVICE_FILE"; then
  SERVICE_ID="necesse"
else
  echo "error: could not infer service id from $AGENT_SERVICE_FILE — expected either" >&2
  echo "  Environment=HEALTH_MODE=playit" >&2
  echo "or" >&2
  echo "  Environment=HEALTH_PROCESS=necesse / Environment=HEALTH_PORT=14159" >&2
  exit 1
fi
echo "service id: $SERVICE_ID"

TARGET_URL="http://${IP}:${HEALTH_PORT}${HEALTH_PATH}"
echo "target URL: $TARGET_URL"

# --- 3. Update status.db directly -------------------------------------------
cp "$STATUS_DB_PATH" "${STATUS_DB_PATH}.bak.$(date +%Y%m%d%H%M%S)"
echo "backed up status.db"

sqlite3 "$STATUS_DB_PATH" \
  "UPDATE services SET target = '${TARGET_URL}' WHERE id = '${SERVICE_ID}';"

echo "updated row:"
sqlite3 "$STATUS_DB_PATH" "SELECT * FROM services WHERE id='${SERVICE_ID}';"

# --- 4. Update SERVICE_URL in health-agent.service and restart -------------
cp "$AGENT_SERVICE_FILE" "${AGENT_SERVICE_FILE}.bak.$(date +%Y%m%d%H%M%S)"
if grep -q '^Environment=SERVICE_URL=' "$AGENT_SERVICE_FILE"; then
  sed -i "s|^Environment=SERVICE_URL=.*|Environment=SERVICE_URL=${IP}:${HEALTH_PORT}${HEALTH_PATH}|" "$AGENT_SERVICE_FILE"
else
  sed -i "/^\[Service\]/a Environment=SERVICE_URL=${IP}:${HEALTH_PORT}${HEALTH_PATH}" "$AGENT_SERVICE_FILE"
fi
systemctl daemon-reload
systemctl restart health-agent
echo "updated and restarted local health-agent"

echo
echo "Done. Verify with:"
echo "  sqlite3 \"$STATUS_DB_PATH\" \"SELECT checked_at, healthy, latency_ms FROM checks WHERE service_id='${SERVICE_ID}' ORDER BY checked_at DESC LIMIT 5;\""