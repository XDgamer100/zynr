#!/usr/bin/env bash
# Zynr.Cloud -- Pterodactyl Themes & Visual Addons

menu_themes() {
  while true; do
    clear

    print_brake 70
    output "Zynr.Cloud -- Pterodactyl Themes and Addons"
    print_brake 70

    output ""
    output "[1] HyperV1 Theme  (Premium -- License Required)"
    output ""
    output "[0] Back"
    echo ""
    echo -n "* Input 0-1: "
    read -r CHOICE
    echo ""

    case "$CHOICE" in
      1) _theme_hyperv1 ;;
      0) return ;;
      *)
        echo -e "* ${COLOR_RED}ERROR${COLOR_NC}: Invalid option '$CHOICE'" 1>&2
        sleep 1 ;;
    esac
  done
}

_theme_hyperv1() {
  clear
  echo ""
  print_brake 70
  output "HyperV1 Theme Manager"
  output ""
  output "Install, upgrade, or restore the HyperV1 Pterodactyl theme."
  print_brake 70
  echo ""
  output "-- REQUIREMENTS --"
  output "* Panel must be installed at /var/www/pterodactyl"
  output "* Remove any existing installer.sh before running"
  output "* Script must run as root"
  echo ""

  print_brake 70
  output "LICENSE REQUIRED"
  output ""
  output "HyperV1 is a PREMIUM theme. You must purchase a license"
  output "before using it on a production server."
  output ""
  output "* discord.gg/99XJuwpV9w"
  output "* Join -> open a ticket -> purchase license"
  print_brake 70
  echo ""

  panel_installed || {
    p_error "Pterodactyl Panel is not installed. Install it first (option 1 in Pterodactyl menu)."
    echo -n "* Press ENTER to continue..."; read -r _; return
  }

  echo -n "* Continue with HyperV1 installer? [y/N]: "; read -r _c
  [[ "$_c" =~ ^[Yy] ]] || return

  print_brake 70
  output "HyperV1 Install / Update Options"
  print_brake 70
  echo ""
  output "[1] Install HyperV1 (fresh install)"
  output "[2] Update HyperV1 (existing install)"
  output "[3] Restore Pterodactyl defaults (remove theme)"
  output ""
  output "[0] Cancel"
  echo ""
  echo -n "* Input 0-3: "; read -r HV_CHOICE; echo ""

  local INSTALLER_URL="https://raw.githubusercontent.com/HyperV1-Installer/installer/main/installer.sh"
  local RESTORE_URL="https://raw.githubusercontent.com/HyperV1-Installer/installer/main/restore.sh"

  case "$HV_CHOICE" in
    1|2)
      output "Downloading HyperV1 installer..."
      local tmp; tmp=$(mktemp /tmp/hyperv1_XXXXXX.sh)
      if curl -fsSLo "$tmp" "$INSTALLER_URL"; then
        chmod +x "$tmp"
        bash "$tmp"
        rm -f "$tmp"
        p_success "HyperV1 operation complete."
      else
        p_error "Failed to download HyperV1 installer. Check your connection and the URL."
      fi
      ;;
    3)
      output "Downloading restore script..."
      local tmp; tmp=$(mktemp /tmp/hyperv1_restore_XXXXXX.sh)
      if curl -fsSLo "$tmp" "$RESTORE_URL"; then
        chmod +x "$tmp"
        bash "$tmp"
        rm -f "$tmp"
        p_success "Pterodactyl defaults restored."
      else
        p_error "Failed to download restore script."
      fi
      ;;
    0) return ;;
    *)
      p_error "Invalid option."
      ;;
  esac

  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}
