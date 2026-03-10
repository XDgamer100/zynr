#!/usr/bin/env bash
# ================================================================
#  Zynr.Cloud v5.1.1 -- All-in-One Server Management & Optimization
#
#    bash <(curl -fsSL https://raw.githubusercontent.com/XDgamer100/zynr/main/install.sh)
#
#  Supports: Ubuntu 22.04 / 24.04  |  Debian 12 / 13
# ================================================================

set -Eeuo pipefail

# -- Repo config --------------------------------------------------
REPO_RAW="https://raw.githubusercontent.com/XDgamer100/zynr/main"
ZYNR_TMP="/tmp/zynr-$$"
ZYNR_VERSION="5.1.1"

_cleanup() { rm -rf "$ZYNR_TMP" 2>/dev/null || true; }
trap _cleanup EXIT

# Bootstrap colours & helpers (available BEFORE any module is sourced)
RED='\033[1;31m'; GREEN='\033[1;32m'; CYAN='\033[1;36m'
BOLD='\033[1m';   NC='\033[0m';       DIM='\033[2m'
_die()      { echo -e "\n* ERROR: $*\n" >&2; exit 1; }
_info()     { echo -e "* $*"; }
_ok()       { echo -e "* $*"; }
# Stub print_brake / output so they work before core.sh is sourced.
# core.sh will redefine them (same behaviour) after it loads.
print_brake() { local _i=0; while (( _i < ${1:-70} )); do printf '#'; ((_i++)); done; printf '\n'; }
output()      { echo -e "* $1"; }
p_success()   { echo ""; echo -e "* SUCCESS: $1"; echo ""; }
p_warning()   { echo ""; echo -e "* WARNING: $1"; echo ""; }
p_error()     { echo ""; echo -e "* ERROR: $1" 1>&2; echo ""; }

[[ "$EUID" -eq 0 ]] || _die "Run as root:  sudo bash <(curl -fsSL ${REPO_RAW}/install.sh)"
command -v curl &>/dev/null || _die "curl is required but not installed."

# -- Module list (load order matters -- core must be first) --------
_MODULES=(
  "core.sh"

  "ptero/menu.sh"
  "ptero/panel.sh"
  "ptero/users.sh"
  "ptero/blueprint.sh"
  "ptero/eggs.sh"
  "ptero/status.sh"
  "ptero/uninstall.sh"
  "ptero/themes.sh"

  "panels/menu.sh"
  "panels/cockpit.sh"
  "panels/extras.sh"

  "security/menu.sh"
  "security/ddos.sh"

  "cloud/menu.sh"
  "cloud/cloud.sh"

  "optimize/menu.sh"
  "optimize/helpers.sh"
  "optimize/cpu.sh"
  "optimize/memory.sh"
  "optimize/kernel.sh"
  "optimize/tools.sh"

  "vps/menu.sh"
  "vps/vps.sh"
  "backup/backup.sh"
  "monitoring/health.sh"
)

# -- Load modules (local or remote) ------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"

_load_modules() {
  local use_local=0
  [[ -f "${SCRIPT_DIR}/core.sh" ]] && use_local=1

  if [[ "$use_local" -eq 1 ]]; then
    _info "Loading modules from local repo..."
    for mod in "${_MODULES[@]}"; do
      local path="${SCRIPT_DIR}/${mod}"
      [[ -f "$path" ]] || _die "Missing module: $path"
      source "$path"
    done
    _ok "All ${#_MODULES[@]} modules loaded (local)"
  else
    mkdir -p "${ZYNR_TMP}"/{ptero,panels,security,cloud,optimize,vps,backup,monitoring}

    # Download core.sh first so print_brake/output are available
    local _core_url="${REPO_RAW}/core.sh"
    local _core_dest="${ZYNR_TMP}/core.sh"
    printf "* [ 1/%2d]  %-42s" "${#_MODULES[@]}" "core.sh"
    if curl -fsSL "$_core_url" -o "$_core_dest" 2>/dev/null; then
      echo "[OK]"
    else
      echo "[FAIL]"
      _die "Failed to download: ${_core_url}"
    fi
    source "$_core_dest"

    echo ""
    print_brake 70
    output "Zynr.Cloud v${ZYNR_VERSION} -- downloading modules..."
    print_brake 70
    echo ""

    local total="${#_MODULES[@]}" idx=0
    for mod in "${_MODULES[@]}"; do
      (( idx++ )) || true
      [[ "$mod" == "core.sh" ]] && continue   # already loaded above
      local url="${REPO_RAW}/${mod}"
      local dest="${ZYNR_TMP}/${mod}"
      printf "* [%2d/%2d]  %-42s" "$idx" "$total" "$mod"
      if curl -fsSL "$url" -o "$dest" 2>/dev/null; then
        echo "[OK]"
      else
        echo "[FAIL]"
        _die "Failed to download: $url"
      fi
      source "$dest"
    done
    echo ""
    _ok "All ${total} modules loaded"
  fi
}

# -- Lightweight OS check -----------------------------------------
_check_os() {
  [[ -f /etc/os-release ]] || _die "/etc/os-release not found."
  local os_id ver
  os_id=$(grep -oP '(?<=^ID=).+' /etc/os-release | tr -d '"')
  ver=$(grep   -oP '(?<=^VERSION_ID=).+' /etc/os-release | tr -d '"')
  case "$os_id" in
    ubuntu) [[ "$ver" =~ ^(22\.04|24\.04)$ ]] || \
      echo "* WARNING: Ubuntu ${ver} -- tested on 22.04 / 24.04 only." ;;
    debian) [[ "$ver" =~ ^(12|13)$ ]] || \
      echo "* WARNING: Debian ${ver} -- tested on 12 / 13 only." ;;
    *) echo "* WARNING: Unsupported OS '${os_id}' -- continuing anyway." ;;
  esac
}

# -- Splash screen ------------------------------------------------
_splash() {
  # No-op: welcome banner printed inside main_menu via print_brake style
  true
}

# -- Main unified menu (pterodactyl-installer style) ---------------
main_menu() {
  while true; do
    clear

    local pi=0 wi=0
    panel_installed 2>/dev/null && pi=1 || true
    wings_installed 2>/dev/null && wi=1 || true
    local p_status="not installed" w_status="not installed"
    [[ $pi -eq 1 ]] && p_status="installed"
    [[ $wi -eq 1 ]] && w_status="installed"

    print_brake 70
    output "Zynr.Cloud v${ZYNR_VERSION} -- All-in-One Server Manager"
    output ""
    output "Copyright (C) 2024 - 2026, Zynr.Cloud"
    output "https://github.com/XDgamer100/zynr"
    output ""
    output "Running ${OS:-?} ${OS_VER:-}"
    output "Pterodactyl Panel: ${p_status}  |  Wings: ${w_status}"
    print_brake 70

    output ""
    output "What would you like to do?"
    output ""
    output "[1] Pterodactyl & Wings   (panel, wings, users, eggs, themes)"
    output "[2] Control Panels        (Cockpit, Paymenter, cPanel)"
    output "[3] Security & DDoS       (UFW, Fail2Ban, CrowdSec)"
    output "[4] Cloud Tools           (Root SSH enabler for Azure/GCP/AWS)"
    output "[5] System Optimizer      (CPU, RAM, ZRAM, kernel tuning)"
    output "[6] VPS Manager           (Proxmox, templates, backups)"
    output ""
    output "[0] Exit"
    echo ""
    echo -n "* Input 0-6: "
    read -r CHOICE
    echo ""

    case "$CHOICE" in
      1) menu_ptero ;;
      2) menu_panels ;;
      3) menu_security ;;
      4) menu_cloud ;;
      5) detect_cpu 2>/dev/null || true; menu_optimize ;;
      6) menu_vps ;;
      0)
        output "Goodbye. https://zynr.cloud"
        echo ""
        exit 0 ;;
      *)
        echo ""
        echo -e "* ${COLOR_RED}ERROR${COLOR_NC}: Invalid option '$CHOICE'" 1>&2
        echo ""
        sleep 1
        ;;
    esac
  done
}

# -- Entry point --------------------------------------------------
_check_os
_load_modules
detect_os
main_menu
