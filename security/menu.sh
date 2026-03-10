#!/usr/bin/env bash
# Zynr.Cloud -- Security & DDoS Protection sub-menu (pterodactyl-installer style)

menu_security() {
  while true; do
    clear

    print_brake 70
    output "Zynr.Cloud v${ZYNR_VERSION} -- Security and DDoS Protection"
    output ""
    output "Running ${OS} ${OS_VER}"
    print_brake 70

    output ""
    output "[1] Full DDoS Protection Suite  (multi-select install)"
    output ""
    output "-- QUICK INSTALL --"
    output "[2] UFW Firewall          (port rules and rate limits)"
    output "[3] Fail2Ban              (brute-force / login flood ban)"
    output "[4] NFTables              (stateful firewall, Minecraft-aware)"
    output "[5] CrowdSec              (collaborative threat intelligence)"
    output "[6] IPSet Blocklists      (known bad IP lists)"
    output "[7] DDoS Monitor Daemon   (flood detect and auto-ban)"
    output "[8] Kernel Sysctl         (TCP/IP flood hardening)"
    output "[9] Nginx Rate Limiting   (HTTP req/s per IP)"
    output ""
    output "[0] Back to Main Menu"
    echo ""
    echo -n "* Input 0-9: "
    read -r CHOICE
    echo ""

    case "$CHOICE" in
      1) menu_ddos ;;
      2) _ddos_ufw ;;
      3) _ddos_fail2ban ;;
      4) _ddos_nftables ;;
      5) _ddos_crowdsec ;;
      6) _ddos_ipset ;;
      7) _ddos_monitor_daemon ;;
      8) _ddos_sysctl ;;
      9) _ddos_nginx_rate ;;
      0) return ;;
      *)
        echo -e "* ${COLOR_RED}ERROR${COLOR_NC}: Invalid option '$CHOICE'" 1>&2
        echo ""
        sleep 1
        ;;
    esac
  done
}
