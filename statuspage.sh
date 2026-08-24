#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts.org
# Author: RainingDaemons
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/RainingDaemons/necesse-status

APP="Status Page"
var_tags="${var_tags:-monitoring;status}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-5}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

# Fetch the installer from this repository instead of the community-scripts repo
eval "$(declare -f build_container | sed 's#https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/install#https://raw.githubusercontent.com/RainingDaemons/necesse-status/main/install#g')"

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/status-page/.git ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating ${APP}"
  cd /opt/status-page
  git pull
  pnpm install --frozen-lockfile
  pnpm build
  systemctl restart status-page
  msg_ok "Updated ${APP}"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Status page: ${BGN}http://${IP}:3000${CL}"
