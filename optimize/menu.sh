#!/usr/bin/env bash
# Zynr.Cloud -- System Optimizer sub-menu (pterodactyl-installer style)

menu_optimize() {
  while true; do
    clear

    print_brake 70
    output "Zynr.Cloud v${ZYNR_VERSION} -- System Optimizer"
    output ""
    output "Running ${OS} ${OS_VER}"
    print_brake 70

    output ""
    output "-- CPU --"
    output "[1]  CPU Governor and Frequency Scaling"
    output "[2]  Intel Tuning   (pstate / turbo / HWP / C-states)"
    output "[3]  AMD Tuning     (pstate / boost / prefetch)"
    output "[4]  IRQ Balancing and CPU Affinity"
    output ""
    output "-- MEMORY --"
    output "[5]  ZRAM           (compressed swap in RAM)"
    output "[6]  ZSWAP          (compressed swap cache)"
    output "[7]  Huge Pages     (2MB static / 1GB / THP)"
    output "[8]  VM Sysctl      (swappiness / dirty / cache)"
    output ""
    output "-- KERNEL --"
    output "[9]  Network        (BBR / TCP buffers / CAKE / offload)"
    output "[10] I/O Scheduler  (NVMe / SSD / HDD aware)"
    output "[11] Kernel Sysctl  (scheduler / fs / security)"
    output "[12] KSM            (Kernel Same-page Merging for VMs)"
    output "[13] OOM Killer Tuning"
    output "[14] CPU Mitigations  (Spectre / Meltdown -- read warning)"
    output ""
    output "-- TOOLS --"
    output "[15] Auto Full-Optimize  (recommended for VPS/game servers)"
    output "[16] Live System Stats   (before/after benchmark)"
    output "[17] Restore Defaults    (revert all changes)"
    output ""
    output "[0] Back to Main Menu"
    echo ""
    echo -n "* Input 0-17: "
    read -r CHOICE
    echo ""

    case "$CHOICE" in
      1)  opt_cpu_governor ;;
      2)  opt_intel ;;
      3)  opt_amd ;;
      4)  opt_irq ;;
      5)  opt_zram ;;
      6)  opt_zswap ;;
      7)  opt_hugepages ;;
      8)  opt_vm_sysctl ;;
      9)  opt_network ;;
      10) opt_io_scheduler ;;
      11) opt_kernel_sysctl ;;
      12) opt_ksm ;;
      13) opt_oom ;;
      14) opt_mitigations ;;
      15) opt_auto_full ;;
      16) opt_stats ;;
      17) opt_restore ;;
      0)  return ;;
      *)
        echo -e "* ${COLOR_RED}ERROR${COLOR_NC}: Invalid option '$CHOICE'" 1>&2
        echo ""
        sleep 1
        ;;
    esac
  done
}
