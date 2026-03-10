#!/usr/bin/env bash
# Zynr.Cloud -- VPS Manager sub-menu (pterodactyl-installer style)

menu_vps() {
  while true; do
    clear

    local vm_count="?" running="0" zfs_free="N/A"
    if command -v qm &>/dev/null; then
      vm_count=$(qm list 2>/dev/null | grep -v VMID | grep -vc "template" 2>/dev/null || echo "?")
      running=$(qm list 2>/dev/null | grep -c " running " 2>/dev/null || echo "0")
      command -v zpool &>/dev/null && zfs_free=$(zpool list -H -o free vps_data 2>/dev/null || echo "N/A")
    fi

    print_brake 70
    output "Zynr.Cloud v${ZYNR_VERSION} -- VPS Manager (Proxmox)"
    output ""
    if command -v qm &>/dev/null; then
      output "VMs: ${vm_count}  |  Running: ${running}  |  ZFS Free: ${zfs_free}"
    else
      output "WARNING: Proxmox not detected on this node."
    fi
    output "Running ${OS} ${OS_VER}"
    print_brake 70

    output ""
    output "[1] Server Setup       (security / fail2ban / UFW / SSH)"
    output "[2] Template Builder   (Ubuntu 22/24 / Debian 12 / Rocky 9)"
    output "[3] Provision VPS      (new client VM, interactive, ~60s)"
    output "[4] List All VMs       (status / IP / RAM / disk per VM)"
    output "[5] Delete VPS         (stop, destroy, and purge a VM)"
    output "[6] Live Resources     (RAM / CPU / ZFS / per-VM usage)"
    output "[7] Backup Manager     (PBS / snapshots / vzdump / cron)"
    output "[8] Health Check       (full diagnostics and email alert)"
    output ""
    output "[0] Back to Main Menu"
    echo ""
    echo -n "* Input 0-8: "
    read -r C
    echo ""

    case "$C" in
      1) vps_server_setup     ;;
      2) vps_template_builder ;;
      3) vps_provision        ;;
      4) vps_list             ;;
      5) vps_delete           ;;
      6) vps_resources        ;;
      7) menu_backup          ;;
      8) vps_health_check     ;;
      0) return               ;;
      *)
        echo -e "* ${COLOR_RED}ERROR${COLOR_NC}: Invalid option '$C'" 1>&2
        echo ""
        sleep 1
        ;;
    esac
  done
}
