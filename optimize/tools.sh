#!/usr/bin/env bash
# Zynr.Cloud -- Optimization Tools (Auto-Full-Optimize * Stats * Restore)
# Sourced by install.sh

# ================================================================
#  [15] AUTO FULL-OPTIMIZE  (VPS/game server preset)
# ================================================================
opt_auto_full() {
  print_brake 70; output "Auto Full-Optimize -- VPS / Game Server Preset"; print_brake 70; echo ""
  echo -e "  ${CYAN_B}This applies the recommended settings for a VPS running${NC}"
  echo -e "  ${CYAN_B}Pterodactyl + Minecraft/game servers:${NC}"
  echo ""
  echo -e "  ${GREEN_B}[OK]${NC}  CPU governor     -> schedutil"
  echo -e "  ${GREEN_B}[OK]${NC}  Intel/AMD pstate -> active/guided"
  echo -e "  ${GREEN_B}[OK]${NC}  Turbo Boost      -> enabled"
  echo -e "  ${GREEN_B}[OK]${NC}  ZRAM             -> lz4, 50% of RAM"
  echo -e "  ${GREEN_B}[OK]${NC}  ZSWAP            -> lz4 / z3fold, 20%"
  echo -e "  ${GREEN_B}[OK]${NC}  THP              -> madvise"
  echo -e "  ${GREEN_B}[OK]${NC}  vm.swappiness    -> 10"
  echo -e "  ${GREEN_B}[OK]${NC}  TCP BBR + fq"
  echo -e "  ${GREEN_B}[OK]${NC}  TCP buffers      -> auto-sized to RAM"
  echo -e "  ${GREEN_B}[OK]${NC}  UDP buffers      -> game server tuned"
  echo -e "  ${GREEN_B}[OK]${NC}  I/O scheduler    -> per device type"
  echo -e "  ${GREEN_B}[OK]${NC}  FD limits        -> 1M"
  echo -e "  ${GREEN_B}[OK]${NC}  irqbalance       -> enabled"
  echo -e "  ${GREEN_B}[OK]${NC}  RPS/RFS          -> all cores"
  echo -e "  ${GREEN_B}[OK]${NC}  OOM protect      -> services"
  echo ""
  { echo -n "* Apply full auto-optimize? [y/N]: "; read -r _c; [[ "$_c" =~ ^[Yy] ]]; } || { echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }

  _backup_init
  touch "$SYSCTL_FILE"

  steps_init 14

  step_n "CPU governor -> schedutil"
  _cpufreq_write "scaling_governor" "schedutil"
  _persist_cpufreq "schedutil"
  p_success "Governor = schedutil"

  step_n "CPU boost/pstate"
  if [[ "$CPU_VENDOR" == "intel" ]]; then
    echo 0 > /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null || true
    for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
      [[ -f "$f" ]] && echo "balance_performance" > "$f" 2>/dev/null || true
    done
    p_success "Intel: Turbo ON, EPP = balance_performance"
  elif [[ "$CPU_VENDOR" == "amd" ]]; then
    echo 1 > /sys/devices/system/cpu/cpufreq/boost 2>/dev/null || true
    for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
      [[ -f "$f" ]] && echo "balance_performance" > "$f" 2>/dev/null || true
    done
    p_success "AMD: CPB ON, EPP = balance_performance"
  fi

  step_n "ZRAM -> lz4, 50% RAM"
  modprobe zram num_devices=1 2>/dev/null || true; sleep 0.3
  swapoff /dev/zram0 2>/dev/null || true
  echo 0 > /sys/class/zram-control/hot_remove 2>/dev/null || true
  modprobe zram num_devices=1 2>/dev/null || true; sleep 0.3
  local zram_sz=$(( RAM_MB * 512 * 1024 ))
  echo "lz4" > /sys/block/zram0/comp_algorithm 2>/dev/null || true
  echo "$zram_sz" > /sys/block/zram0/disksize
  mkswap /dev/zram0 &>/dev/null; swapon -p 100 /dev/zram0
  p_success "ZRAM active: lz4, $(( RAM_MB/2 ))MB"

  step_n "ZSWAP -> lz4/z3fold, 20%"
  modprobe zswap 2>/dev/null; modprobe z3fold 2>/dev/null || true
  echo Y   > /sys/module/zswap/parameters/enabled 2>/dev/null || true
  echo lz4 > /sys/module/zswap/parameters/compressor 2>/dev/null || true
  echo z3fold > /sys/module/zswap/parameters/zpool 2>/dev/null || true
  echo 20  > /sys/module/zswap/parameters/max_pool_percent 2>/dev/null || true
  _grub_add_param "zswap.enabled=1 zswap.compressor=lz4 zswap.zpool=z3fold"
  p_success "ZSWAP enabled: lz4/z3fold/20%"

  step_n "THP -> madvise"
  echo madvise > /sys/kernel/mm/transparent_hugepage/enabled
  p_success "THP = madvise"

  step_n "VM sysctl"
  _sysctl_header "Auto Full-Optimize"
  _sysctl_set "vm.swappiness"              "10"
  _sysctl_set "vm.vfs_cache_pressure"      "50"
  _sysctl_set "vm.dirty_ratio"             "15"
  _sysctl_set "vm.dirty_background_ratio"  "5"
  _sysctl_set "vm.min_free_kbytes"         "$(( RAM_MB * 1024 / 20 ))"
  _sysctl_set "vm.page-cluster"            "0"
  _sysctl_set "vm.overcommit_memory"       "1"
  _sysctl_set "vm.zone_reclaim_mode"       "0"
  _sysctl_set "vm.watermark_scale_factor"  "200"
  p_success "VM sysctl tuned"

  step_n "Network: BBR + fq"
  modprobe tcp_bbr 2>/dev/null || true
  _sysctl_set "net.core.default_qdisc"          "fq"
  _sysctl_set "net.ipv4.tcp_congestion_control"  "bbr"
  p_success "TCP BBR enabled"

  step_n "Network: buffers + TCP opts"
  local rmem=$(( RAM_MB * 1024 * 1024 / 16 ))
  [[ $rmem -gt 134217728 ]] && rmem=134217728
  _sysctl_set "net.core.rmem_max"                "$rmem"
  _sysctl_set "net.core.wmem_max"                "$rmem"
  _sysctl_set "net.ipv4.tcp_rmem"                "4096 131072 ${rmem}"
  _sysctl_set "net.ipv4.tcp_wmem"                "4096 65536 ${rmem}"
  _sysctl_set "net.core.rmem_max"                "26214400"
  _sysctl_set "net.core.wmem_max"                "26214400"
  _sysctl_set "net.ipv4.tcp_fastopen"            "3"
  _sysctl_set "net.ipv4.tcp_tw_reuse"            "1"
  _sysctl_set "net.ipv4.tcp_fin_timeout"         "15"
  _sysctl_set "net.core.somaxconn"               "65535"
  _sysctl_set "net.core.netdev_max_backlog"       "16384"
  _sysctl_set "net.ipv4.tcp_max_syn_backlog"      "16384"
  _sysctl_set "net.ipv4.udp_rmem_min"            "8192"
  _sysctl_set "net.ipv4.udp_wmem_min"            "8192"
  p_success "Network buffers & TCP opts applied"

  step_n "Kernel sysctl"
  _sysctl_set "kernel.sched_migration_cost_ns"    "5000000"
  _sysctl_set "kernel.sched_autogroup_enabled"    "1"
  _sysctl_set "fs.file-max"                       "2097152"
  _sysctl_set "fs.inotify.max_user_watches"       "524288"
  _sysctl_set "kernel.pid_max"                    "4194304"
  _sysctl_set "kernel.panic"                      "10"
  cat >> /etc/security/limits.conf <<'LIMITS'
# Zynr.Cloud auto-optimize
* soft nofile 1048576
* hard nofile 1048576
LIMITS
  p_success "Kernel sysctl applied"

  step_n "I/O scheduler"
  for dev in /sys/block/nvme*; do
    [[ -d "$dev" ]] && echo "none" > "${dev}/queue/scheduler" 2>/dev/null || true
  done
  for dev in /sys/block/sd* /sys/block/vd*; do
    [[ -d "$dev" ]] || continue
    local rota; rota=$(cat "${dev}/queue/rotational" 2>/dev/null || echo "1")
    [[ "$rota" == "0" ]] && echo "mq-deadline" > "${dev}/queue/scheduler" 2>/dev/null || \
      echo "bfq" > "${dev}/queue/scheduler" 2>/dev/null || true
  done
  systemctl enable fstrim.timer 2>/dev/null || true
  p_success "I/O schedulers set per device type"

  step_n "IRQ balance + RPS"
  apt-get install -y irqbalance -qq && systemctl enable --now irqbalance 2>/dev/null || true
  local cpus_hex; cpus_hex=$(printf '%x' $(( (1 << CPU_CORES) - 1 )))
  for rps in /sys/class/net/*/queues/*/rps_cpus; do
    [[ -f "$rps" ]] && echo "$cpus_hex" > "$rps" 2>/dev/null || true
  done
  p_success "irqbalance running, RPS on all cores"

  step_n "OOM protection"
  for svc in nginx mariadb redis-server; do
    local drop="/etc/systemd/system/${svc}.service.d"
    mkdir -p "$drop"
    printf '[Service]\nOOMScoreAdjust=-500\n' > "${drop}/zynr-oom.conf"
  done
  systemctl daemon-reload
  p_success "OOM protection applied to services"

  step_n "Apply all sysctl"
  sysctl -p "$SYSCTL_FILE" &>/dev/null || true
  p_success "All sysctl values loaded"

  echo ""
  print_brake 70
  p_success "AUTO FULL-OPTIMIZE COMPLETE"
  output "Sysctl saved to: ${SYSCTL_FILE}"
  output "Backup at      : ${BACKUP_DIR}"
  p_warning "Some changes require a reboot to take full effect."
  print_brake 70
  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

# ================================================================
#  [16] LIVE STATS VIEWER
# ================================================================
opt_stats() {
  print_brake 70; output "Live System Stats"; print_brake 70; echo ""
  echo ""

  local gov; gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "unknown")
  local cur_freq; cur_freq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null | awk '{printf "%.0f MHz",$1/1000}' || echo "?")
  local max_freq; max_freq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null | awk '{printf "%.0f MHz",$1/1000}' || echo "?")
  local load; load=$(uptime | grep -oP 'load average: \K.*' || uptime | awk -F'load average:' '{print $2}' | xargs)
  local mem_free; mem_free=$(awk '/MemAvailable/{printf "%.0f MB",$2/1024}' /proc/meminfo)
  local mem_total; mem_total=$(awk '/MemTotal/{printf "%.0f MB",$2/1024}' /proc/meminfo)
  local swap_used; swap_used=$(free -m | awk '/Swap/{print $3}')
  local tcp_cc; tcp_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
  local zram_size="none"
  ls /dev/zram0 &>/dev/null && zram_size=$(lsblk /dev/zram0 -o SIZE -n 2>/dev/null || echo "active")
  local zswap_en; zswap_en=$(cat /sys/module/zswap/parameters/enabled 2>/dev/null || echo "N")

  print_brake 60
  label "  ${BOX_V}  [~]  CPU"            "${CPU_VENDOR^^}  ${CPU_MODEL}"
  label "  ${BOX_V}    Cores"          "${CPU_CORES}  |  Governor: ${gov}"
  label "  ${BOX_V}  [VER]  Freq"           "${cur_freq}  (max ${max_freq})"
  label "  ${BOX_V}  [MON]  Load avg"       "${load}"
  echo ""
  label "  ${BOX_V}    RAM"            "${mem_free} free / ${mem_total} total"
  label "  ${BOX_V}    Swap used"      "${swap_used} MB"
  label "  ${BOX_V}     ZRAM"           "${zram_size}"
  label "  ${BOX_V}  [BAK]  ZSWAP"          "${zswap_en}"
  echo ""
  label "  ${BOX_V}  [WEB]  TCP CC"         "${tcp_cc}"
  label "  ${BOX_V}     Default qdisc"  "$(sysctl -n net.core.default_qdisc 2>/dev/null || echo '?')"
  local iface; iface=$(ip route show default 2>/dev/null | awk '/default/{print $5}' | head -1 || echo "eth0")
  label "  ${BOX_V}    Interface"       "${iface}"
  echo ""
  label "  ${BOX_V}  [CFG]  I/O schedulers" "$(for d in /sys/block/sd* /sys/block/nvme* /sys/block/vd*; do [[ -d "$d" ]] && printf '%s:%s ' "${d##*/}" "$(cat ${d}/queue/scheduler 2>/dev/null|grep -oP '\[\K[^\]]+')"; done)"
  label "  ${BOX_V}  [UPD]  THP"            "$(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null | grep -oP '\[\K[^\]]+' || echo 'unknown')"
  label "  ${BOX_V}    vm.swappiness"  "$(sysctl -n vm.swappiness 2>/dev/null || echo '?')"
  label "  ${BOX_V}  [CFG]  Open FDs"       "$(cat /proc/sys/fs/file-nr 2>/dev/null | awk '{print $1 " / " $3}' || echo '?')"
  print_brake 60
  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

# ================================================================
#  [17] RESTORE DEFAULTS
# ================================================================
opt_restore() {
  print_brake 70; output "Restore Defaults"; print_brake 70; echo ""
  p_warning "This removes Zynr.Cloud sysctl file and restores GRUB/fstab backups."
  { echo -n "* Restore all Zynr.Cloud optimizations to system defaults? [y/N]: "; read -r _c; [[ "$_c" =~ ^[Yy] ]]; } || { echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }

  step "Removing sysctl file..."
  rm -f "$SYSCTL_FILE"
  sysctl --system &>/dev/null || true

  step "Removing ZRAM systemd service..."
  systemctl disable --now zynr-zram 2>/dev/null || true
  swapoff /dev/zram0 2>/dev/null || true
  echo 1 > /sys/class/zram-control/hot_remove 2>/dev/null || true
  rm -f /etc/systemd/system/zynr-zram.service

  step "Disabling ZSWAP..."
  echo N > /sys/module/zswap/parameters/enabled 2>/dev/null || true

  step "Restoring GRUB backup..."
  local latest_bak; latest_bak=$(ls -t /etc/zynr-optimize-backups/*/grub.bak 2>/dev/null | head -1 || echo "")
  if [[ -n "$latest_bak" ]]; then
    cp "$latest_bak" /etc/default/grub
    update-grub &>/dev/null || grub-mkconfig -o /boot/grub/grub.cfg &>/dev/null || true
    p_success "GRUB restored from ${latest_bak}"
  else
    p_warning "No GRUB backup found."
  fi

  step "Removing udev rules..."
  rm -f /etc/udev/rules.d/99-zynr-cpufreq.rules
  rm -f /etc/udev/rules.d/60-zynr-iosched.rules
  udevadm control --reload-rules 2>/dev/null || true

  step "Removing KSM service..."
  systemctl disable --now zynr-ksm 2>/dev/null || true
  echo 0 > /sys/kernel/mm/ksm/run 2>/dev/null || true
  rm -f /etc/systemd/system/zynr-ksm.service

  step "Restoring governor to ondemand..."
  _cpufreq_write "scaling_governor" "ondemand" || true

  step "Resetting THP to madvise (kernel default)..."
  echo madvise > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true

  systemctl daemon-reload
  p_success "All Zynr.Cloud optimizations removed. Reboot recommended."
  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}
