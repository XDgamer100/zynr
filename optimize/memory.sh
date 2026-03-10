#!/usr/bin/env bash
# Zynr.Cloud -- Memory Optimization (ZRAM * ZSWAP * HugePages * VM sysctl)
# Sourced by install.sh
# ================================================================
#  [5] ZRAM -- Compressed Swap in RAM
# ================================================================
opt_zram() {
  print_brake 70; output "ZRAM -- Compressed Swap in RAM"; print_brake 70; echo ""
  output "RAM: ${RAM_MB} MB  |  ZRAM turns part of your RAM into ultra-fast compressed swap."
  echo ""

  local cur_zram="none"
  ls /dev/zram0 &>/dev/null 2>&1 && cur_zram="active ($(lsblk /dev/zram0 -o SIZE -n 2>/dev/null || echo '?'))"
  label "  Current ZRAM" "${cur_zram}"
  echo ""

  # Compression algorithm
  local _algos=(
    "lz4"      "lz4      -- Fastest (best for gaming / game servers) * recommended"
    "zstd"     "zstd     -- Best compression ratio, slightly slower"
    "lzo"      "lzo      -- Good balance of speed and ratio"
    "lzo-rle"  "lzo-rle  -- lzo with run-length encoding (slight improvement)"
  )
  multi_select "Select ZRAM compression algorithm" "${_algos[@]}"
  local algo="${SELECTED_ITEMS[0]:-lz4}"

  # Size
  local zram_pct
  echo ""
  read -rp "  ZRAM size as % of total RAM [default: 50]: " zram_pct
  zram_pct="${zram_pct:-50}"
  local zram_mb=$(( RAM_MB * zram_pct / 100 ))
  output "ZRAM will be ${zram_mb} MB (${zram_pct}% of ${RAM_MB} MB)"

  { echo -n "* Configure ZRAM with ${algo} / ${zram_mb}MB? [y/N]: "; read -r _c; [[ "$_c" =~ ^[Yy] ]]; } || { echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }

  spinner_start "Configuring ZRAM..."

  # Remove existing ZRAM
  swapoff /dev/zram0 2>/dev/null || true
  echo 0 > /sys/class/zram-control/hot_remove 2>/dev/null || true

  # Use zram-config tool on Ubuntu, or manual on Debian
  if apt-cache show zram-config &>/dev/null 2>&1 && [[ "$OS" == "ubuntu" ]]; then
    apt-get install -y zram-config -qq
    spinner_stop
    # Override zram-config defaults
    local zram_cfg="/usr/bin/init-zram-swapping"
    if [[ -f "$zram_cfg" ]]; then
      sed -i "s/mem=\$(awk.*/mem=$(( zram_mb * 1024 * 1024 ))/" "$zram_cfg" 2>/dev/null || true
    fi
    systemctl enable --now zram-config 2>/dev/null || true
  else
    # Manual setup using zram kernel module
    modprobe zram num_devices=1 2>/dev/null || true
    sleep 0.5

    # Set compression algo
    if [[ -f /sys/block/zram0/comp_algorithm ]]; then
      echo "$algo" > /sys/block/zram0/comp_algorithm 2>/dev/null || \
        p_warning "Algorithm '${algo}' not supported, using default."
    fi

    # Set size
    echo "$(( zram_mb * 1024 * 1024 ))" > /sys/block/zram0/disksize
    mkswap /dev/zram0
    swapon -p 100 /dev/zram0   # priority 100 = prefer over disk swap
    spinner_stop
  fi

  spinner_stop

  # Make persistent via systemd unit
  cat > /etc/systemd/system/zynr-zram.service <<SVCEOF
[Unit]
Description=Zynr.Cloud ZRAM Swap -- ${algo} ${zram_mb}MB
After=local-fs.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c ' \
  modprobe zram num_devices=1 2>/dev/null || true; \
  sleep 0.3; \
  echo "${algo}" > /sys/block/zram0/comp_algorithm 2>/dev/null || true; \
  echo "${zram_mb}M" > /sys/block/zram0/disksize; \
  mkswap /dev/zram0; \
  swapon -p 100 /dev/zram0'
ExecStop=/bin/bash -c 'swapoff /dev/zram0 2>/dev/null; \
  echo 1 > /sys/class/zram-control/hot_remove 2>/dev/null || true'

[Install]
WantedBy=multi-user.target
SVCEOF
  systemctl daemon-reload
  systemctl enable zynr-zram 2>/dev/null || true

  # Tune swappiness low since ZRAM is fast
  _sysctl_set "vm.swappiness" "10" "Low swappiness -- prefer ZRAM"
  _sysctl_set "vm.page-cluster" "0" "Single pages for ZRAM efficiency"

  p_success "ZRAM configured: algo=${algo}  size=${zram_mb}MB  priority=100"
  swapon --show 2>/dev/null | sed 's/^/  /'
  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

# ================================================================
#  [6] ZSWAP -- Compressed Swap Cache
# ================================================================
opt_zswap() {
  print_brake 70; output "ZSWAP -- Compressed Swap Cache"; print_brake 70; echo ""
  output "ZSWAP keeps recently evicted pages compressed in RAM before they hit disk swap."
  echo ""

  local cur_enabled; cur_enabled=$(cat /sys/module/zswap/parameters/enabled 2>/dev/null || echo "N")
  local cur_pool;    cur_pool=$(cat    /sys/module/zswap/parameters/zpool 2>/dev/null || echo "unknown")
  local cur_comp;    cur_comp=$(cat    /sys/module/zswap/parameters/compressor 2>/dev/null || echo "unknown")
  local cur_pct;     cur_pct=$(cat     /sys/module/zswap/parameters/max_pool_percent 2>/dev/null || echo "?")
  label "  ZSWAP enabled"   "${cur_enabled}"
  label "  Compressor"      "${cur_comp}"
  label "  Zpool"           "${cur_pool}"
  label "  Max pool %"      "${cur_pct}%"
  echo ""

  local _comp_opts=(
    "lz4"     "lz4      -- Fastest  (recommended for game servers)"
    "zstd"    "zstd     -- Best compression"
    "lzo-rle" "lzo-rle  -- Good balance"
  )
  local _pool_opts=(
    "z3fold"   "z3fold    -- 3 compressed pages per pool page (best density)"
    "zbud"     "zbud      -- 2 pages per entry (stable/conservative)"
    "zsmalloc" "zsmalloc  -- Variable size (good for many small pages)"
  )
  multi_select "ZSWAP: Select compressor" "${_comp_opts[@]}"
  local zswap_comp="${SELECTED_ITEMS[0]:-lz4}"
  multi_select "ZSWAP: Select zpool allocator" "${_pool_opts[@]}"
  local zswap_pool="${SELECTED_ITEMS[0]:-z3fold}"

  local zswap_pct
  read -rp "  Max pool % of RAM [default: 20]: " zswap_pct
  zswap_pct="${zswap_pct:-20}"

  { echo -n "* Enable ZSWAP: compressor=${zswap_comp} pool=${zswap_pool} max=${zswap_pct}%? [y/N]: "; read -r _c; [[ "$_c" =~ ^[Yy] ]]; } || { echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }

  spinner_start "Enabling ZSWAP..."
  modprobe zswap 2>/dev/null || true
  modprobe "$zswap_pool" 2>/dev/null || true

  # Runtime
  echo Y          > /sys/module/zswap/parameters/enabled         2>/dev/null || true
  echo "$zswap_comp" > /sys/module/zswap/parameters/compressor   2>/dev/null || true
  echo "$zswap_pool" > /sys/module/zswap/parameters/zpool        2>/dev/null || true
  echo "$zswap_pct"  > /sys/module/zswap/parameters/max_pool_percent 2>/dev/null || true
  spinner_stop

  # Persist via GRUB
  _grub_add_param "zswap.enabled=1 zswap.compressor=${zswap_comp} zswap.zpool=${zswap_pool} zswap.max_pool_percent=${zswap_pct}"

  # Also persist via /etc/modules-load.d
  echo "$zswap_pool" > /etc/modules-load.d/zynr-zswap.conf

  p_success "ZSWAP enabled: ${zswap_comp} / ${zswap_pool} / max ${zswap_pct}%"
  cat /sys/kernel/debug/zswap/pool_total_size 2>/dev/null \
    | awk '{printf "  Pool size: %.1f MB\n", $1/1048576}' || true
  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

# ================================================================
#  [7] HUGE PAGES
# ================================================================
opt_hugepages() {
  print_brake 70; output "Huge Pages"; print_brake 70; echo ""
  local _hp_opts=(
    "thp_always"   "THP = always      -- Auto huge pages for all allocations"
    "thp_madvise"  "THP = madvise     -- Only where app requests (recommended)"
    "thp_never"    "THP = never       -- Disable THP (best for Java/databases)"
    "static_2mb"   "Static 2MB pages  -- Pre-allocate for databases / JVMs"
    "static_1gb"   "Static 1GB pages  -- For high-memory workloads (Postgres/Redis)"
    "khugepaged"   "khugepaged tuning  -- Faster THP promotion"
  )
  multi_select "Huge Pages options" "${_hp_opts[@]}"
  [[ ${#SELECTED_ITEMS[@]} -eq 0 ]] && { echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }

  for opt in "${SELECTED_ITEMS[@]}"; do
    case "$opt" in
      thp_always)
        echo always > /sys/kernel/mm/transparent_hugepage/enabled
        echo always > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null || true
        _grub_add_param "transparent_hugepage=always"
        p_success "THP = always" ;;
      thp_madvise)
        echo madvise > /sys/kernel/mm/transparent_hugepage/enabled
        echo defer+madvise > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null || true
        p_success "THP = madvise (recommended)" ;;
      thp_never)
        echo never > /sys/kernel/mm/transparent_hugepage/enabled
        _grub_add_param "transparent_hugepage=never"
        p_success "THP disabled" ;;
      static_2mb)
        local hp_count
        read -rp "  Number of 2MB huge pages [default: 512]: " hp_count
        hp_count="${hp_count:-512}"
        _sysctl_set "vm.nr_hugepages" "$hp_count" "Static 2MB huge pages"
        _sysctl_set "vm.hugetlb_shm_group" "0" "Allow any group to use huge pages"
        p_success "${hp_count} x 2MB huge pages allocated." ;;
      static_1gb)
        local hp1g_count
        read -rp "  Number of 1GB huge pages [default: 4]: " hp1g_count
        hp1g_count="${hp1g_count:-4}"
        _grub_add_param "hugepagesz=1G hugepages=${hp1g_count} default_hugepagesz=1G"
        p_success "${hp1g_count} x 1GB huge pages -- GRUB updated, reboot required." ;;
      khugepaged)
        echo 100  > /sys/kernel/mm/transparent_hugepage/khugepaged/scan_sleep_millisecs
        echo 10   > /sys/kernel/mm/transparent_hugepage/khugepaged/alloc_sleep_millisecs
        p_success "khugepaged scan interval reduced for faster THP promotion." ;;
    esac
  done
  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

# ================================================================
#  [8] VM / MEMORY SYSCTL
# ================================================================
opt_vm_sysctl() {
  print_brake 70; output "VM / Memory Sysctl Tuning"; print_brake 70; echo ""
  local _vm_opts=(
    "swappiness"     "vm.swappiness          -- How aggressively to swap (lower = less)"
    "vfs_pressure"   "vm.vfs_cache_pressure  -- How fast to reclaim dentries/inodes"
    "dirty_ratio"    "vm.dirty_ratio/bg       -- Write-back thresholds"
    "min_free"       "vm.min_free_kbytes      -- Emergency memory reserve"
    "overcommit"     "vm.overcommit_memory    -- Memory overcommit policy"
    "watermark"      "vm.watermark_scale       -- Memory reclaim aggressiveness"
    "compaction"     "vm.compaction_proactiveness -- Proactive memory compaction"
    "oom_score"      "vm.oom_score_adj          -- OOM protection for key processes"
    "zone_reclaim"   "vm.zone_reclaim_mode       -- NUMA zone reclaim"
  )
  multi_select "Select VM sysctl tunings" "${_vm_opts[@]}"
  [[ ${#SELECTED_ITEMS[@]} -eq 0 ]] && { echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }
  _sysctl_header "VM / Memory"
  touch "$SYSCTL_FILE"

  for opt in "${SELECTED_ITEMS[@]}"; do
    case "$opt" in
      swappiness)
        local val
        echo "  Recommended: 10 (server/game), 30 (general), 60 (desktop)"
        read -rp "  vm.swappiness [default: 10]: " val; val="${val:-10}"
        _sysctl_set "vm.swappiness" "$val" "Swap reluctance (0=never, 100=aggressive)"
        p_success "vm.swappiness = ${val}" ;;
      vfs_pressure)
        local val
        echo "  100 = default, 50 = cache-friendly (recommended for servers)"
        read -rp "  vm.vfs_cache_pressure [default: 50]: " val; val="${val:-50}"
        _sysctl_set "vm.vfs_cache_pressure" "$val" "VFS cache pressure"
        p_success "vm.vfs_cache_pressure = ${val}" ;;
      dirty_ratio)
        _sysctl_set "vm.dirty_ratio"            "15"  "Max dirty pages before write (% of RAM)"
        _sysctl_set "vm.dirty_background_ratio" "5"   "Background writeback threshold"
        _sysctl_set "vm.dirty_expire_centisecs" "1500" "Age of dirty pages before writeback"
        _sysctl_set "vm.dirty_writeback_centisecs" "500" "Writeback interval"
        p_success "Dirty page ratios tuned (15%/5%)" ;;
      min_free)
        local val
        local recommended=$(( RAM_MB * 1024 / 20 ))   # 5% of RAM in kB
        read -rp "  vm.min_free_kbytes [default: ${recommended}]: " val; val="${val:-$recommended}"
        _sysctl_set "vm.min_free_kbytes" "$val" "Minimum free memory reserve"
        p_success "vm.min_free_kbytes = ${val}" ;;
      overcommit)
        echo "  0=heuristic (default)  1=always (JVM/gaming)  2=never (strict)"
        local val; read -rp "  vm.overcommit_memory [default: 1]: " val; val="${val:-1}"
        _sysctl_set "vm.overcommit_memory" "$val" "Memory overcommit policy"
        [[ "$val" == "2" ]] && _sysctl_set "vm.overcommit_ratio" "95" "Overcommit ratio %"
        p_success "vm.overcommit_memory = ${val}" ;;
      watermark)
        _sysctl_set "vm.watermark_scale_factor" "200" "Watermark scaling (higher = earlier reclaim)"
        p_success "vm.watermark_scale_factor = 200" ;;
      compaction)
        _sysctl_set "vm.compaction_proactiveness" "20" "Proactive compaction (0=off, 100=max)"
        p_success "vm.compaction_proactiveness = 20" ;;
      oom_score)
        step "Setting OOM protection for critical processes..."
        for proc in nginx php-fpm8.3 mysqld redis-server wings; do
          for pid_file in /proc/*/comm; do
            local pname; pname=$(cat "$pid_file" 2>/dev/null || echo "")
            [[ "$pname" == "$proc" ]] && {
              local pid="${pid_file%/comm}"; pid="${pid##*/}"
              echo -500 > "/proc/${pid}/oom_score_adj" 2>/dev/null || true
            }
          done
        done
        p_success "OOM score -500 set for critical server processes." ;;
      zone_reclaim)
        _sysctl_set "vm.zone_reclaim_mode" "0" "0=no zone reclaim (best for single-socket)"
        p_success "vm.zone_reclaim_mode = 0 (better for single-socket servers)" ;;
    esac
  done

  sysctl -p "$SYSCTL_FILE" &>/dev/null || true
  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

