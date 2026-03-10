#!/usr/bin/env bash
# Zynr.Cloud -- Cockpit + Addons
# Sourced by install.sh
# ================================================================
#  COCKPIT + ADDONS
# ================================================================
_cockpit_addons=(
  "files"          "Cockpit Files (File Browser)"
  "podman"         "Cockpit Podman (Container Manager)"
  "networkmanager" "Cockpit NetworkManager (Network UI)"
  "storaged"       "Cockpit Storaged / Storage UI"
  "machines"       "Cockpit Machines (VM Manager)"
  "pcp"            "Cockpit PCP (Performance Metrics)"
  "sosreport"      "Cockpit Sosreport (Diagnostic Report)"
  "kdump"          "Cockpit Kdump (Crash Dump)"
  "selinux"        "Cockpit SELinux (Policy Manager)"
)

menu_cockpit() {
  panel_installed || { p_warning "Pterodactyl Panel should be installed first."; echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }
  print_brake 70; output "Cockpit + Addons"; print_brake 70; echo ""
  output "Cockpit is a web-based server management UI (CPU, RAM, storage, networking, systemd)."
  echo -e "  It will be installed with the addons you select below.\n"
  multi_select "Select Cockpit addons to install (or 0 to cancel)" "${_cockpit_addons[@]}"
  local selected_addons=("${SELECTED_ITEMS[@]}")
  [[ ${#selected_addons[@]} -eq 0 ]] && { output "No addons selected -- installing base Cockpit only."; }
  { echo -n "* Install Cockpit${#selected_addons[@]:+ and ${#selected_addons[@]} addon(s)}? [y/N]: "; read -r _c; [[ "$_c" =~ ^[Yy] ]]; } || { echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }
  _do_install_cockpit "${selected_addons[@]}"
  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

_do_install_cockpit() {
  local addons=("$@")
  output "Installing Cockpit base..."
  apt-get update -qq
  apt-get install -y cockpit --no-install-recommends
  local pkg
  for key in "${addons[@]}"; do
    case "$key" in
      files)          pkg="cockpit-files" ;;
      podman)         pkg="cockpit-podman" ;;
      networkmanager) pkg="cockpit-networkmanager" ;;
      storaged)       pkg="cockpit-storaged" ;;
      machines)       pkg="cockpit-machines" ;;
      pcp)            pkg="cockpit-pcp" ;;
      sosreport)      pkg="cockpit-sosreport" ;;
      kdump)          pkg="cockpit-kdump" ;;
      selinux)        pkg="cockpit-selinux" ;;
      *)              p_warning "Unknown addon: $key"; continue ;;
    esac
    output "Installing ${pkg}..."
    apt-get install -y "$pkg" --no-install-recommends 2>/dev/null \
      || p_warning "Package ${pkg} not found in repos -- skipping."
  done
  systemctl enable --now cockpit.socket 2>/dev/null || true
  configure_firewall_port 9090
  local ip; ip=$(curl -sf https://api.ipify.org || hostname -I | awk '{print $1}')
  p_success "Cockpit installed!  ->  http://${ip}:9090"
}

configure_firewall_port() {
  local port="$1"
  if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
    ufw allow "$port/tcp" &>/dev/null || true
  fi
}

# ================================================================
#  ADDITIONAL PANELS
# ================================================================
_extra_panels=(
  "paymenter"   "Paymenter  (Open-source billing panel)"
  "fossbilling" "FOSSBilling (Open-source billing panel)"
  "cpanel"      "cPanel/WHM  (Requires cPanel license)"
  "virtualizor" "Virtualizor (VPS control panel)"
  "virtfusion"  "VirtFusion  (VPS platform)"
)

