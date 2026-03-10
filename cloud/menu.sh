#!/usr/bin/env bash
# Zynr.Cloud -- Cloud Tools sub-menu (pterodactyl-installer style)

menu_cloud() {
  while true; do
    clear

    print_brake 70
    output "Zynr.Cloud v${ZYNR_VERSION} -- Cloud Root Enabler"
    output ""
    output "Running ${OS} ${OS_VER}"
    output ""
    output "Cloud providers disable root SSH by default."
    output "These tools safely re-enable it per-provider."
    print_brake 70

    output ""
    output "[1] Auto-detect provider and enable root SSH"
    output "[2] Manual root SSH setup  (any provider)"
    output "[3] Harden SSH  (key-only, disable password auth)"
    output "[4] SSH Status  (show current config and sessions)"
    output ""
    output "-- SUPPORTED PROVIDERS --"
    output "* Azure       : patches sshd_config.d/50-cloud-init.conf"
    output "* GCP         : disables google-guest-agent"
    output "* AWS         : patches sshd_config, fixes default user"
    output "* Hetzner / Vultr / DigitalOcean : standard sshd patch"
    output ""
    output "[0] Back to Main Menu"
    echo ""
    echo -n "* Input 0-4: "
    read -r CHOICE
    echo ""

    case "$CHOICE" in
      1) cloud_root_auto ;;
      2) cloud_root_manual ;;
      3) cloud_harden_ssh ;;
      4) cloud_ssh_status ;;
      0) return ;;
      *)
        echo -e "* ${COLOR_RED}ERROR${COLOR_NC}: Invalid option '$CHOICE'" 1>&2
        echo ""
        sleep 1
        ;;
    esac
  done
}
