#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts.org
# Author: RainingDaemons
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/RainingDaemons/necesse-status

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y curl git ca-certificates build-essential python3 sqlite3
msg_ok "Installed Dependencies"

msg_info "Installing Node.js 22 LTS"
$STD bash -c "$(curl -fsSL https://deb.nodesource.com/setup_22.x)"
$STD apt-get install -y nodejs
msg_ok "Installed Node.js"

msg_info "Installing pnpm"
$STD npm install -g pnpm@10
msg_ok "Installed pnpm"

msg_info "Cloning Status Page"
$STD git clone https://github.com/RainingDaemons/necesse-status.git /opt/status-page
msg_ok "Cloned Status Page"

msg_info "Installing Dependencies"
$STD pnpm --dir /opt/status-page install --frozen-lockfile
msg_ok "Installed Dependencies"

msg_info "Building Status Page"
$STD pnpm --dir /opt/status-page build
msg_ok "Built Status Page"

msg_info "Creating Data Directory"
$STD mkdir -p /opt/status-page/data
$STD chown -R www-data:www-data /opt/status-page/data
msg_ok "Created Data Directory"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/status-page.service
[Unit]
Description=Status Page SvelteKit App
After=network.target

[Service]
Type=simple
Environment=NODE_ENV=production
Environment=PORT=3000
Environment=STATUS_DB_PATH=/opt/status-page/data/status.db
Environment=STATUS_CONFIG_PATH=/opt/status-page/config.toml
WorkingDirectory=/opt/status-page
ExecStart=/usr/bin/node build/index.js
Restart=always
User=www-data
Group=www-data

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now status-page
msg_ok "Created Service"

msg_info "Creating DB Backup Service"
$STD install -m 755 backup_db.py /opt/status-page/backup_db.py
$STD install -m 644 backup.service backup.timer /etc/systemd/system/
$STD systemctl daemon-reload
$STD systemctl enable --now backup.timer
msg_ok "Created DB Backup Service"

motd_ssh

# Point the in-container "update" command at this repository
eval "$(declare -f customize | sed 's#https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct#https://raw.githubusercontent.com/RainingDaemons/necesse-status/main#g')"
customize
cleanup_lxc
