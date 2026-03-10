#!/usr/bin/env bash
# Zynr.Cloud -- Kernel Optimization (Network * I/O * Sysctl * KSM * OOM * Mitigations)
# Sourced by install.sh
# ================================================================
#  [9] NETWORK PERFORMANCE
# ================================================================
opt_network() {
  print_brake 70; output "Network Performance"; print_brake 70; echo ""
  local _net_opts=(
    "bbr"          "TCP BBR v2        -- Google's congestion control (best for VPS)"
    "cake"         "CAKE qdisc        -- Fair queuing for all connections"
    "tcp_buffers"  "TCP buffer sizes  -- Larger send/recv buffers for throughput"
    "udp_buffers"  "UDP buffer sizes  -- For Minecraft / game servers"
    "offload"      "NIC offload       -- Enable TSO/GSO/GRO hardware offloads"
    "tcp_opts"     "TCP optimizations -- fastopen, timestamps, SACK, ECN"
    "ipv6_tune"    "IPv6 tuning       -- Disable if unused (reduce overhead)"
    "conntrack"    "Conntrack tuning  -- Larger connection tracking table"
    "socket_mem"   "Socket memory     -- Raise wmem/rmem for high-throughput"
  )
  multi_select "Select network optimizations" "${_net_opts[@]}"
  [[ ${#SELECTED_ITEMS[@]} -eq 0 ]] && { echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }
  _sysctl_header "Network Performance"
  touch "$SYSCTL_FILE"

  for opt in "${SELECTED_ITEMS[@]}"; do
    case "$opt" in

      bbr)
        step "Enabling TCP BBR..."
        modprobe tcp_bbr 2>/dev/null || true
        echo "tcp_bbr" >> /etc/modules-load.d/zynr-bbr.conf
        _sysctl_set "net.core.default_qdisc"         "fq"  "Fair queue (pairs with BBR)"
        _sysctl_set "net.ipv4.tcp_congestion_control" "bbr" "BBR congestion control"
        p_success "TCP BBR enabled with fq qdisc." ;;

      cake)
        step "Enabling CAKE qdisc..."
        modprobe sch_cake 2>/dev/null || true
        # Apply to all physical interfaces
        for iface in $(ip -o link show | awk -F: '$2 !~ /lo|veth|br|docker|tun|tap/ {print $2}' | xargs); do
          tc qdisc replace dev "$iface" root cake bandwidth 1Gbit 2>/dev/null || true
        done
        p_success "CAKE applied to physical interfaces." ;;

      tcp_buffers)
        local ram_bytes=$(( RAM_MB * 1024 * 1024 ))
        local rmem=$(( ram_bytes / 16 ))  # 1/16 of RAM
        local wmem=$(( ram_bytes / 16 ))
        [[ $rmem -gt 134217728 ]] && rmem=134217728   # cap at 128MB
        [[ $wmem -gt 134217728 ]] && wmem=134217728
        _sysctl_set "net.core.rmem_max"          "$rmem"       "Max socket receive buffer"
        _sysctl_set "net.core.wmem_max"          "$wmem"       "Max socket send buffer"
        _sysctl_set "net.core.rmem_default"      "262144"      "Default receive buffer"
        _sysctl_set "net.core.wmem_default"      "262144"      "Default send buffer"
        _sysctl_set "net.ipv4.tcp_rmem"          "4096 131072 ${rmem}" "TCP recv: min/default/max"
        _sysctl_set "net.ipv4.tcp_wmem"          "4096 65536 ${wmem}"  "TCP send: min/default/max"
        _sysctl_set "net.ipv4.tcp_mem"           "$(( rmem/4096 )) $(( rmem/2048 )) $(( rmem/1024 ))" "TCP memory pages"
        p_success "TCP buffers enlarged to $((rmem/1024/1024))MB max." ;;

      udp_buffers)
        _sysctl_set "net.core.rmem_max"          "26214400"    "UDP game server recv buffer"
        _sysctl_set "net.core.wmem_max"          "26214400"    "UDP game server send buffer"
        _sysctl_set "net.ipv4.udp_rmem_min"      "8192"        "UDP min recv buffer"
        _sysctl_set "net.ipv4.udp_wmem_min"      "8192"        "UDP min send buffer"
        p_success "UDP buffers tuned for game server traffic." ;;

      offload)
        step "Enabling NIC hardware offloads..."
        for iface in $(ip -o link show | awk -F: '$2 !~ /lo|veth|br|docker|tun|tap/ {print $2}' | xargs); do
          ethtool -K "$iface" tso on gso on gro on 2>/dev/null || true
          ethtool -K "$iface" rx-checksumming on tx-checksumming on 2>/dev/null || true
          ethtool -G "$iface" rx 4096 tx 4096 2>/dev/null || true
        done
        p_success "NIC offloads enabled on all physical interfaces." ;;

      tcp_opts)
        _sysctl_set "net.ipv4.tcp_fastopen"        "3"   "TCP Fast Open (client+server)"
        _sysctl_set "net.ipv4.tcp_timestamps"      "1"   "TCP timestamps"
        _sysctl_set "net.ipv4.tcp_sack"            "1"   "Selective ACK"
        _sysctl_set "net.ipv4.tcp_dsack"           "1"   "Duplicate SACK"
        _sysctl_set "net.ipv4.tcp_fack"            "1"   "Forward ACK"
        _sysctl_set "net.ipv4.tcp_ecn"             "1"   "ECN -- avoid drops via marking"
        _sysctl_set "net.ipv4.tcp_window_scaling"  "1"   "TCP window scaling"
        _sysctl_set "net.ipv4.tcp_low_latency"     "1"   "Prefer low latency over throughput"
        _sysctl_set "net.ipv4.tcp_tw_reuse"        "1"   "Reuse TIME_WAIT sockets"
        _sysctl_set "net.ipv4.tcp_fin_timeout"     "15"  "FIN timeout seconds"
        _sysctl_set "net.ipv4.tcp_keepalive_time"  "300" "Keepalive idle time"
        _sysctl_set "net.ipv4.tcp_keepalive_intvl" "30"  "Keepalive probe interval"
        _sysctl_set "net.ipv4.tcp_keepalive_probes" "5"  "Keepalive probe count"
        p_success "TCP optimizations applied." ;;

      ipv6_tune)
        if { echo -n "* Disable IPv6 completely? (only do this if you don't use IPv6) [y/N]: "; read -r _c; [[ "$_c" =~ ^[Yy] ]]; }; then
          _sysctl_set "net.ipv6.conf.all.disable_ipv6"     "1" "Disable IPv6 globally"
          _sysctl_set "net.ipv6.conf.default.disable_ipv6" "1" "Disable IPv6 default"
          _grub_add_param "ipv6.disable=1"
          p_success "IPv6 disabled."
        else
          _sysctl_set "net.ipv6.conf.all.use_tempaddr"     "2" "IPv6 temporary addresses"
          _sysctl_set "net.ipv6.conf.default.use_tempaddr" "2" "IPv6 temporary addresses default"
          p_success "IPv6 privacy extensions enabled."
        fi ;;

      conntrack)
        local ct_max=$(( CPU_CORES * 65536 ))
        _sysctl_set "net.netfilter.nf_conntrack_max"           "$ct_max" "Max conntrack entries"
        _sysctl_set "net.netfilter.nf_conntrack_tcp_timeout_established" "1800" "TCP established timeout"
        _sysctl_set "net.netfilter.nf_conntrack_tcp_timeout_time_wait"   "15"   "TCP TIME_WAIT timeout"
        _sysctl_set "net.netfilter.nf_conntrack_tcp_timeout_syn_recv"    "30"   "TCP SYN_RECV timeout"
        p_success "Conntrack table size = ${ct_max}, timeouts tuned." ;;

      socket_mem)
        _sysctl_set "net.core.somaxconn"          "65535"  "Max listen backlog"
        _sysctl_set "net.core.netdev_max_backlog"  "16384"  "NIC receive queue"
        _sysctl_set "net.ipv4.tcp_max_syn_backlog" "16384"  "Max SYN queue"
        _sysctl_set "net.core.optmem_max"          "65536"  "Socket options memory"
        p_success "Socket memory and backlog raised." ;;
    esac
  done

  sysctl -p "$SYSCTL_FILE" &>/dev/null || true
  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

# ================================================================
#  [10] I/O SCHEDULER & STORAGE
# ================================================================
opt_io_scheduler() {
  print_brake 70; output "I/O Scheduler & Storage"; print_brake 70; echo ""

  # Detect storage types
  echo ""
  local _devs=()
  for dev in /sys/block/sd* /sys/block/nvme* /sys/block/vd*; do
    [[ -d "$dev" ]] || continue
    local name="${dev##*/}"
    local rota; rota=$(cat "${dev}/queue/rotational" 2>/dev/null || echo "?")
    local sched; sched=$(cat "${dev}/queue/scheduler" 2>/dev/null | grep -oP '\[\K[^\]]+' || echo "?")
    local size; size=$(cat "${dev}/size" 2>/dev/null | awk '{printf "%.0f GB",$1*512/1e9}' || echo "?")
    local dtype="HDD"
    [[ "$rota" == "0" ]] && dtype="SSD"
    [[ "$name" =~ nvme ]] && dtype="NVMe"
    output "  ${name}  ${dtype}  ${size}  scheduler=${sched}"
    _devs+=("$name:$dtype")
  done
  echo ""

  local _sched_opts=(
    "nvme_none"     "NVMe -> none/mq-deadline  -- Bypass scheduler (lowest latency)"
    "ssd_mqdl"      "SSD  -> mq-deadline        -- Deadline scheduling for SSDs"
    "hdd_bfq"       "HDD  -> bfq                -- Best For Queuing (fairness + throughput)"
    "readahead"     "Read-ahead tuning          -- Per-device optimal values"
    "io_poll"       "I/O polling                -- For NVMe (reduces interrupt overhead)"
    "trim"          "SSD TRIM / fstrim.timer    -- Weekly TRIM for SSD health"
    "noatime"       "noatime mount option        -- Stop atime writes (faster FS)"
    "writeback"     "Writeback cache            -- ext4 writeback mode"
    "noop_virtio"   "noop for virtual disks     -- VirtIO/cloud disk optimization"
  )
  multi_select "Select I/O optimizations" "${_sched_opts[@]}"
  [[ ${#SELECTED_ITEMS[@]} -eq 0 ]] && { echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }

  # Write udev rules file for persistent scheduler
  local udev_file="/etc/udev/rules.d/60-zynr-iosched.rules"
  echo "# Zynr.Cloud I/O Scheduler rules -- $(date)" > "$udev_file"

  for opt in "${SELECTED_ITEMS[@]}"; do
    case "$opt" in
      nvme_none)
        for dev in /sys/block/nvme*; do
          [[ -d "$dev" ]] || continue
          local n="${dev##*/}"
          echo "none" > "${dev}/queue/scheduler" 2>/dev/null || \
            echo "mq-deadline" > "${dev}/queue/scheduler" 2>/dev/null || true
          echo "ACTION==\"add|change\", KERNEL==\"${n}\", ATTR{queue/scheduler}=\"none\"" >> "$udev_file"
        done
        p_success "NVMe scheduler = none (bypass)" ;;

      ssd_mqdl)
        for dev in /sys/block/sd*; do
          [[ -d "$dev" ]] || continue
          local rota; rota=$(cat "${dev}/queue/rotational" 2>/dev/null || echo "1")
          [[ "$rota" == "0" ]] || continue
          local n="${dev##*/}"
          echo "mq-deadline" > "${dev}/queue/scheduler" 2>/dev/null || true
          echo "ACTION==\"add|change\", KERNEL==\"${n}\", ATTR{queue/scheduler}=\"mq-deadline\"" >> "$udev_file"
        done
        p_success "SSD scheduler = mq-deadline" ;;

      hdd_bfq)
        for dev in /sys/block/sd*; do
          [[ -d "$dev" ]] || continue
          local rota; rota=$(cat "${dev}/queue/rotational" 2>/dev/null || echo "0")
          [[ "$rota" == "1" ]] || continue
          local n="${dev##*/}"
          echo "bfq" > "${dev}/queue/scheduler" 2>/dev/null || true
          echo "ACTION==\"add|change\", KERNEL==\"${n}\", ATTR{queue/scheduler}=\"bfq\"" >> "$udev_file"
        done
        p_success "HDD scheduler = bfq" ;;

      readahead)
        for dev in /sys/block/sd* /sys/block/nvme* /sys/block/vd*; do
          [[ -d "$dev" ]] || continue
          local n="${dev##*/}"
          local rota; rota=$(cat "${dev}/queue/rotational" 2>/dev/null || echo "1")
          local ra=256
          [[ "$rota" == "0" ]] && ra=128    # SSD
          [[ "$n" =~ nvme ]]   && ra=64     # NVMe
          blockdev --setra "$ra" "/dev/${n}" 2>/dev/null || true
          echo "$(( ra * 2 ))" > "${dev}/queue/read_ahead_kb" 2>/dev/null || true
        done
        p_success "Read-ahead tuned per device type (NVMe=64, SSD=128, HDD=256)" ;;

      io_poll)
        for dev in /sys/block/nvme*; do
          [[ -d "$dev" ]] || continue
          echo 1 > "${dev}/queue/io_poll" 2>/dev/null || true
          echo 8 > "${dev}/queue/io_poll_delay" 2>/dev/null || true
        done
        p_success "NVMe I/O polling enabled." ;;

      trim)
        systemctl enable fstrim.timer 2>/dev/null || true
        systemctl start fstrim.timer 2>/dev/null || true
        p_success "Weekly fstrim.timer enabled for SSD TRIM." ;;

      noatime)
        p_warning "noatime adds 'noatime' to all ext4/xfs mounts in /etc/fstab."
        { echo -n "* Apply noatime to /etc/fstab? [y/N]: "; read -r _c; [[ "$_c" =~ ^[Yy] ]]; } || break
        cp /etc/fstab "${BACKUP_DIR}/fstab.bak" 2>/dev/null || true
        sed -i -E 's/(ext4|xfs)([ \t]+\()([^)]*)\)/\1\2\3,noatime)/g' /etc/fstab 2>/dev/null || true
        p_success "noatime added to fstab (takes effect on next mount/reboot)" ;;

      writeback)
        for dev in /sys/block/sd* /sys/block/nvme*; do
          [[ -d "$dev" ]] || continue
          echo "writeback" > "${dev}/../data=writeback" 2>/dev/null || true
        done
        # tune2fs approach
        for mp in / /var /home; do
          local dev_path; dev_path=$(findmnt -n -o SOURCE "$mp" 2>/dev/null || echo "")
          [[ -n "$dev_path" ]] && tune2fs -o journal_data_writeback "$dev_path" 2>/dev/null || true
        done
        p_success "ext4 writeback mode applied." ;;

      noop_virtio)
        for dev in /sys/block/vd*; do
          [[ -d "$dev" ]] || continue
          local n="${dev##*/}"
          echo "none" > "${dev}/queue/scheduler" 2>/dev/null || \
            echo "noop" > "${dev}/queue/scheduler" 2>/dev/null || true
          echo "ACTION==\"add|change\", KERNEL==\"${n}\", ATTR{queue/scheduler}=\"none\"" >> "$udev_file"
        done
        p_success "VirtIO disks set to none/noop scheduler." ;;
    esac
  done
  udevadm control --reload-rules 2>/dev/null || true
  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

# ================================================================
#  [11] FULL KERNEL SYSCTL
# ================================================================
opt_kernel_sysctl() {
  print_brake 70; output "Kernel Sysctl -- Full Tune"; print_brake 70; echo ""
  local _ks_opts=(
    "scheduler"   "Scheduler params  -- migration cost, latency, autogroup"
    "fs_limits"   "Filesystem limits -- file-max, inotify, dentry"
    "security"    "Security sysctl   -- ptrace, kptr restrict, dmesg"
    "core_dumps"  "Core dumps        -- Disable for production servers"
    "time_sync"   "Time params       -- NTP sync, hz, clocksource"
    "kernel_misc" "Misc kernel       -- panic timeout, sysrq, coredump"
  )
  multi_select "Select kernel sysctl options" "${_ks_opts[@]}"
  [[ ${#SELECTED_ITEMS[@]} -eq 0 ]] && { echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }
  _sysctl_header "Kernel Sysctl"
  touch "$SYSCTL_FILE"

  for opt in "${SELECTED_ITEMS[@]}"; do
    case "$opt" in
      scheduler)
        _sysctl_set "kernel.sched_migration_cost_ns"  "5000000"  "Avoid migrating tasks too often"
        _sysctl_set "kernel.sched_autogroup_enabled"  "1"        "Group tasks by session"
        _sysctl_set "kernel.sched_min_granularity_ns" "1000000"  "Minimum task run time before preemption"
        _sysctl_set "kernel.sched_wakeup_granularity_ns" "3000000" "Wakeup preemption granularity"
        _sysctl_set "kernel.sched_latency_ns"         "6000000"  "Target latency for all tasks"
        _sysctl_set "kernel.sched_nr_migrate"         "64"       "Tasks migrated per softirq"
        p_success "Scheduler sysctl tuned." ;;
      fs_limits)
        _sysctl_set "fs.file-max"                   "2097152"  "Max open file descriptors"
        _sysctl_set "fs.nr_open"                    "2097152"  "Max FDs per process"
        _sysctl_set "fs.inotify.max_user_watches"   "524288"   "inotify watches (for file watchers)"
        _sysctl_set "fs.inotify.max_user_instances" "512"      "inotify instances per user"
        _sysctl_set "fs.inotify.max_queued_events"  "16384"    "inotify event queue depth"
        _sysctl_set "fs.pipe-max-size"              "4194304"  "Max pipe buffer size"
        _sysctl_set "fs.aio-max-nr"                 "1048576"  "Max async I/O requests"
        # Also update /etc/security/limits.conf
        cat >> /etc/security/limits.conf <<'LIMITS'
# Zynr.Cloud file descriptor limits
*    soft nofile 1048576
*    hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
LIMITS
        p_success "Filesystem limits raised (FD limit = 1M)." ;;
      security)
        _sysctl_set "kernel.kptr_restrict"           "1"   "Hide kernel pointers"
        _sysctl_set "kernel.dmesg_restrict"          "1"   "Restrict dmesg to root"
        _sysctl_set "kernel.yama.ptrace_scope"       "1"   "Restrict ptrace to parent"
        _sysctl_set "kernel.perf_event_paranoid"     "2"   "Restrict perf events"
        _sysctl_set "kernel.randomize_va_space"      "2"   "Full ASLR"
        _sysctl_set "net.ipv4.conf.all.rp_filter"    "1"   "Reverse path filtering"
        _sysctl_set "net.ipv4.conf.all.log_martians" "1"   "Log martian packets"
        p_success "Security sysctl hardened." ;;
      core_dumps)
        _sysctl_set "kernel.core_pattern"   "|/bin/false"  "Disable core dumps"
        _sysctl_set "fs.suid_dumpable"      "0"            "No setuid core dumps"
        ulimit -c 0
        echo "* hard core 0" >> /etc/security/limits.conf
        echo "* soft core 0" >> /etc/security/limits.conf
        p_success "Core dumps disabled." ;;
      time_sync)
        _sysctl_set "kernel.perf_cpu_time_max_percent" "1" "CPU time for perf (low overhead)"
        p_success "Time sync sysctl applied." ;;
      kernel_misc)
        _sysctl_set "kernel.panic"             "10"  "Auto-reboot on kernel panic (seconds)"
        _sysctl_set "kernel.panic_on_oops"     "1"   "Panic on oops"
        _sysctl_set "kernel.sysrq"             "1"   "Allow SysRq keys"
        _sysctl_set "kernel.pid_max"           "4194304" "Max PID value"
        _sysctl_set "kernel.threads-max"       "2097152" "Max threads"
        p_success "Misc kernel sysctl applied." ;;
    esac
  done
  sysctl -p "$SYSCTL_FILE" &>/dev/null || true
  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

# ================================================================
#  [12] KSM -- KERNEL SAME-PAGE MERGING
# ================================================================
opt_ksm() {
  print_brake 70; output "KSM -- Kernel Same-Page Merging"; print_brake 70; echo ""
  output "KSM deduplicates identical memory pages. Best for VPS hosts / many containers."
  echo ""
  [[ -f /sys/kernel/mm/ksm/run ]] || { p_warning "KSM not supported by this kernel."; echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }
  local cur; cur=$(cat /sys/kernel/mm/ksm/run 2>/dev/null)
  label "  KSM current state" "${cur}"
  echo ""

  local _ksm_opts=(
    "enable"     "Enable KSM scanning"
    "aggressive" "Aggressive mode   -- scan more pages/s (more CPU, more savings)"
    "conservative" "Conservative mode -- less CPU, slower savings"
    "disable"    "Disable KSM"
  )
  multi_select "KSM mode" "${_ksm_opts[@]}"
  [[ ${#SELECTED_ITEMS[@]} -eq 0 ]] && { echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }
  local mode="${SELECTED_ITEMS[0]}"

  case "$mode" in
    enable|aggressive)
      echo 1 > /sys/kernel/mm/ksm/run
      local pages_s=300
      [[ "$mode" == "aggressive" ]] && pages_s=2000
      echo "$pages_s"  > /sys/kernel/mm/ksm/pages_to_scan
      echo 20           > /sys/kernel/mm/ksm/sleep_millisecs 2>/dev/null || true
      # Persist via /etc/rc.local or systemd
      cat > /etc/systemd/system/zynr-ksm.service <<KSMSVC
[Unit]
Description=Zynr.Cloud KSM Configuration
After=local-fs.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'echo 1 > /sys/kernel/mm/ksm/run; echo ${pages_s} > /sys/kernel/mm/ksm/pages_to_scan'
[Install]
WantedBy=multi-user.target
KSMSVC
      systemctl daemon-reload; systemctl enable zynr-ksm 2>/dev/null || true
      p_success "KSM enabled -- scanning ${pages_s} pages/s." ;;
    conservative)
      echo 1 > /sys/kernel/mm/ksm/run
      echo 100 > /sys/kernel/mm/ksm/pages_to_scan
      echo 200 > /sys/kernel/mm/ksm/sleep_millisecs 2>/dev/null || true
      p_success "KSM enabled (conservative -- 100 pages/s, 200ms sleep)." ;;
    disable)
      echo 0 > /sys/kernel/mm/ksm/run
      p_success "KSM disabled." ;;
  esac
  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

# ================================================================
#  [13] OOM KILLER TUNING
# ================================================================
opt_oom() {
  print_brake 70; output "OOM Killer Tuning"; print_brake 70; echo ""
  local _oom_opts=(
    "protect_services" "Protect key services (nginx, mysql, redis, wings)"
    "protect_game"     "Protect Minecraft/game server processes"
    "oom_panic"        "Panic on OOM instead of killing (dedicated servers)"
    "oom_dump"         "Enable OOM dump for debugging"
    "overcommit_off"   "Disable memory overcommit (strict allocation)"
  )
  multi_select "OOM killer options" "${_oom_opts[@]}"
  [[ ${#SELECTED_ITEMS[@]} -eq 0 ]] && { echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }

  _oom_protect_pid() {
    local pid="$1" score="$2"
    [[ -f "/proc/${pid}/oom_score_adj" ]] && \
      echo "$score" > "/proc/${pid}/oom_score_adj" 2>/dev/null || true
  }

  for opt in "${SELECTED_ITEMS[@]}"; do
    case "$opt" in
      protect_services)
        for svc in nginx php-fpm mysqld mariadb redis-server wings sshd; do
          local pids
          pids=$(pgrep -x "$svc" 2>/dev/null || true)
          for pid in $pids; do _oom_protect_pid "$pid" -500; done
        done
        # Make persistent via systemd overrides
        for svc in nginx mariadb redis-server; do
          local drop="/etc/systemd/system/${svc}.service.d"
          mkdir -p "$drop"
          printf '[Service]\nOOMScoreAdjust=-500\n' > "${drop}/zynr-oom.conf"
        done
        systemctl daemon-reload
        p_success "OOM score -500 applied to key services." ;;
      protect_game)
        local pids
        pids=$(pgrep -f "java.*minecraft\|java.*server\|java.*spigot\|java.*paper" 2>/dev/null || true)
        for pid in $pids; do _oom_protect_pid "$pid" -800; done
        p_success "OOM score -800 applied to Minecraft/game processes." ;;
      oom_panic)
        _sysctl_set "vm.panic_on_oom" "1" "Panic instead of OOM killing"
        _sysctl_set "kernel.panic"    "10" "Auto-reboot after OOM panic"
        p_success "Panic on OOM enabled (auto-reboot in 10s)." ;;
      oom_dump)
        _sysctl_set "vm.oom_dump_tasks" "1" "Dump task state on OOM"
        p_success "OOM task dump enabled." ;;
      overcommit_off)
        _sysctl_set "vm.overcommit_memory" "2" "No memory overcommit"
        _sysctl_set "vm.overcommit_ratio"  "95" "Overcommit ratio 95%"
        p_success "Memory overcommit disabled." ;;
    esac
  done
  sysctl -p "$SYSCTL_FILE" &>/dev/null || true
  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

# ================================================================
#  [14] CPU MITIGATIONS (Spectre/Meltdown)
# ================================================================
opt_mitigations() {
  print_brake 70; output "CPU Mitigations"; print_brake 70; echo ""
  echo ""
  print_brake 70
  output "SECURITY WARNING"
  output ""
  output "Disabling CPU mitigations improves performance by 5-30%"
  output "but removes protection against Spectre/Meltdown/RIDL/Fallout/MDS/TAA."
  output ""
  output "ONLY disable on bare-metal or single-tenant VPS you control."
  p_warning "DO NOT disable on shared/multi-tenant hosting."
  print_brake 70
  echo ""

  # Show current state
  step "Current mitigation status:"
  grep -r '' /sys/devices/system/cpu/vulnerabilities/ 2>/dev/null | \
    sed 's|/sys/devices/system/cpu/vulnerabilities/||' | \
    sed "s/Mitigation:.*/${YELLOW}&${NC}/" | \
    sed "s/Not affected/${GREEN}&${NC}/" | \
    sed "s/Vulnerable/${RED_B}&${NC}/" | \
    sed 's/^/    /' || echo "    (vulnerability info not available)"
  echo ""

  local _mit_opts=(
    "show_only"       "Show only -- do not change anything"
    "spectre_v1"      "Disable Spectre v1 mitigation    (+ ~1% perf)"
    "spectre_v2"      "Disable Spectre v2 / eIBRS        (+ ~5% perf)"
    "meltdown"        "Disable Meltdown / PTI             (+ ~15% perf on some workloads)"
    "mds"             "Disable MDS / TAA (RIDL/Fallout)   (+ ~3% perf)"
    "all_off"         "Disable ALL mitigations            (max perf, max risk)"
    "all_auto"        "Restore ALL mitigations to auto    (safe default)"
  )
  multi_select "CPU mitigation options (read warning above)" "${_mit_opts[@]}"
  [[ ${#SELECTED_ITEMS[@]} -eq 0 ]] && { echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }

  { echo -n "* ${RED_B}I understand the security risk and confirm this is a trusted system.${NC} [y/N]: "; read -r _c; [[ "$_c" =~ ^[Yy] ]]; } \
    || { output "No changes made."; echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }

  for opt in "${SELECTED_ITEMS[@]}"; do
    case "$opt" in
      show_only)   output "Showing only -- no changes."; continue ;;
      spectre_v1)  _grub_add_param "nospectre_v1" ;;
      spectre_v2)  _grub_add_param "nospectre_v2 noretpoline" ;;
      meltdown)    _grub_add_param "nopti" ;;
      mds)         _grub_add_param "mds=off tsx_async_abort=off" ;;
      all_off)
        _grub_add_param "mitigations=off"
        p_warning "ALL mitigations disabled -- REBOOT REQUIRED." ;;
      all_auto)
        local grub_cfg="/etc/default/grub"
        for m in mitigations nospectre_v1 nospectre_v2 noretpoline nopti mds tsx_async_abort; do
          sed -i "s/ ${m}=[^ \"]*//g; s/ ${m}//g" "$grub_cfg" 2>/dev/null || true
        done
        update-grub &>/dev/null || grub-mkconfig -o /boot/grub/grub.cfg &>/dev/null || true
        p_success "Mitigations restored to auto (safe defaults)." ;;
    esac
    [[ "$opt" != "show_only" && "$opt" != "all_auto" ]] && \
      p_success "${opt} mitigation disabled -- reboot to apply."
  done
  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

