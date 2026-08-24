#!/usr/bin/env bash
set -euo pipefail

# playit_user_setup.sh — run as root on the playit LXC only.
#
# The playit health check needs to:
#   1. switch the health-agent systemd unit to HEALTH_MODE=playit
#   2. grant `nobody` a scoped, passwordless sudo rule so it can run
#      `playit status` (read-only) as root — nothing else.
#
# `playit status` reads from the root-owned socket /run/playit/playitd.sock,
# which the agent (running as User=nobody) cannot access directly.

SERVICE_FILE="/etc/systemd/system/health-agent.service"
AGENT_FILE="/usr/local/bin/health-agent.py"
SUDOERS_FILE="/etc/sudoers.d/health-agent-playit"

if [[ $EUID -ne 0 ]]; then
  echo "error: run as root" >&2
  exit 1
fi

PLAYIT_BIN="$(command -v playit || true)"
if [[ -z "$PLAYIT_BIN" ]]; then
  echo "error: playit binary not found in PATH" >&2
  exit 1
fi
echo "playit binary: $PLAYIT_BIN"

# 1. Switch the agent to playit mode.
if [[ -f "$SERVICE_FILE" ]]; then
  if grep -q '^Environment=HEALTH_MODE=' "$SERVICE_FILE"; then
    sed -i 's|^Environment=HEALTH_MODE=.*|Environment=HEALTH_MODE=playit|' "$SERVICE_FILE"
  else
    echo "Environment=HEALTH_MODE=playit" >> "$SERVICE_FILE"
  fi
  echo "set HEALTH_MODE=playit in $SERVICE_FILE"
else
  echo "warning: $SERVICE_FILE not found — install the health agent first" >&2
fi

# 2. Install the scoped sudo rule (matches the command literally).
cat <<EOF > "$SUDOERS_FILE"
nobody ALL=(root) NOPASSWD: $PLAYIT_BIN status
EOF
chmod 440 "$SUDOERS_FILE"
if command -v visudo >/dev/null 2>&1; then
  visudo -cf "$SUDOERS_FILE"
fi
echo "wrote sudo rule: $SUDOERS_FILE"

# 3. Point PLAYIT_BIN in the agent at the real path, in case it differs.
if [[ -f "$AGENT_FILE" ]]; then
  sed -i "s|^PLAYIT_BIN = .*|PLAYIT_BIN = \"$PLAYIT_BIN\"|" "$AGENT_FILE"
  echo "set PLAYIT_BIN in $AGENT_FILE"
fi

# 4. Reload and restart the agent.
systemctl daemon-reload
systemctl enable -q --now health-agent
systemctl restart health-agent

echo
echo "Done. Verify with:"
echo "  sudo -u nobody sudo -n $PLAYIT_BIN status"
echo "  curl -s localhost:9101/health | python3 -m json.tool"
