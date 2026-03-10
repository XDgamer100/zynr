#!/usr/bin/env bash
# Zynr.Cloud -- Pterodactyl sub-menu (pterodactyl-installer style UI)

menu_ptero() {
  while true; do
    clear

    local pi=0 wi=0
    panel_installed 2>/dev/null && pi=1 || true
    wings_installed 2>/dev/null && wi=1 || true

    print_brake 70
    output "Zynr.Cloud @ v${ZYNR_VERSION} -- Pterodactyl Manager"
    output ""
    output "Running ${OS} ${OS_VER}"
    output "Panel installed: $([ "$pi" = "1" ] && echo "yes" || echo "no")  |  Wings installed: $([ "$wi" = "1" ] && echo "yes" || echo "no")"
    print_brake 70

    output ""
    output "-- INSTALLATION --"
    output "[1] Install Panel"
    output "[2] Install Wings"
    output "[3] Install Panel + Wings (same machine)"
    output ""
    output "-- UPDATES --"
    output "[4] Update Panel"
    output "[5] Update Wings"
    output "[6] Update Panel + Wings"
    output ""
    output "-- MANAGEMENT --"
    output "[7] User Management"
    output "[8] Blueprint Manager"
    output "[9] Eggs Manager  (200+ eggs, browse by category)"
    output ""
    output "-- THEMES & ADDONS --"
    output "[10] Themes & Visual Addons"
    output ""
    output "-- SYSTEM --"
    output "[11] Status & Logs"
    output "[12] Uninstall"
    output ""
    output "[0] Back to Main Menu"
    echo ""
    echo -n "* Input 0-12: "
    read -r CHOICE
    echo ""

    case "$CHOICE" in
      1)  flow_install_panel ;;
      2)  flow_install_wings ;;
      3)  flow_install_both ;;
      4)  flow_update_panel ;;
      5)  flow_update_wings ;;
      6)  flow_update_panel; flow_update_wings ;;
      7)  menu_users ;;
      8)  menu_blueprint ;;
      9)  menu_eggs ;;
      10) menu_themes ;;
      11) view_status ;;
      12) menu_uninstall ;;
      0)  return ;;
      *)
        echo ""
        echo -e "* ${COLOR_RED}ERROR${COLOR_NC}: Invalid option '$CHOICE'" 1>&2
        echo ""
        sleep 1
        ;;
    esac
  done
}
