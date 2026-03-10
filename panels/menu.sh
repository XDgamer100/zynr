#!/usr/bin/env bash
# Zynr.Cloud -- Control Panels sub-menu (pterodactyl-installer style)

menu_panels() {
  while true; do
    clear

    print_brake 70
    output "Zynr.Cloud v${ZYNR_VERSION} -- Control Panels"
    output ""
    output "Running ${OS} ${OS_VER}"
    print_brake 70

    output ""
    output "-- WEB-BASED MANAGEMENT --"
    output "[1] Cockpit           (web server manager, port 9090)"
    output ""
    output "-- BILLING & HOSTING PANELS --"
    output "[2] Paymenter         (open-source billing panel)"
    output "[3] FOSSBilling       (free billing and automation)"
    output "[4] cPanel            (traditional hosting panel)"
    output ""
    output "-- VPS / VM PANELS --"
    output "[5] Virtualizor       (VPS control panel)"
    output "[6] VirtFusion        (VPS platform)"
    output "[7] Install ALL above  (multi-install)"
    output ""
    output "[0] Back to Main Menu"
    echo ""
    echo -n "* Input 0-7: "
    read -r CHOICE
    echo ""

    case "$CHOICE" in
      1) menu_cockpit ;;
      2) _install_paymenter ;;
      3) _install_fossbilling ;;
      4) _install_cpanel ;;
      5) _install_virtualizor ;;
      6) _install_virtfusion ;;
      7) menu_extra_panels ;;
      0) return ;;
      *)
        echo -e "* ${COLOR_RED}ERROR${COLOR_NC}: Invalid option '$CHOICE'" 1>&2
        echo ""
        sleep 1
        ;;
    esac
  done
}
