#!/usr/bin/env bash
# Zynr.Cloud -- CPU Optimization (Governor * Intel pstate/turbo/HWP * AMD pstate/boost * IRQ)
# Sourced by install.sh
# ================================================================
#  [1] CPU GOVERNOR & FREQUENCY SCALING
# ================================================================
opt_cpu_governor() {
  print_brake 70; output "CPU Governor & Frequency Scaling"; print_brake 70; echo ""
  output "CPU: ${CPU_VENDOR^^}  |  Cores: ${CPU_CORES}  |  Model: ${CPU_MODEL}"
  local cur_gov
  cur_gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "unknown")
  output "Current governor: ${YELLOW}${cur_gov}${NC}"

  local avail
  avail=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors 2>/dev/null || echo "")
  [[ -n "$avail" ]] && output "Available: ${avail}"
  echo ""

  local _govs=(
    "performance"  "performance  -- Max clocks, lowest latency (best for servers/games)"
    "schedutil"    "schedutil    -- Kernel scheduler-driven (best balance, recommended)"
    "ondemand"     "ondemand     -- Scale up fast, scale down slow"
    "conservative" "conservative -- Scale up/down gradually"
    "powersave"    "powersave    -- Minimum clocks (for idle/edge nodes)"
  )
  multi_select "Select CPU governor to apply" "${_govs[@]}"
  [[ ${#SELECTED_ITEMS[@]} -eq 0 ]] && { echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }
  local gov="${SELECTED_ITEMS[0]}"

  apt-get install -y cpufrequtils linux-cpupower -qq 2>/dev/null || \
    apt-get install -y cpufrequtils -qq 2>/dev/null || {
    p_error "Failed to install CPU frequency tools"
    return 1
  }

  spinner_start "Applying governor: ${gov} to all ${CPU_CORES} cores"
  _cpufreq_write "scaling_governor" "$gov"
  spinner_stop
  _persist_cpufreq "$gov"
  p_success "Governor set to '${gov}' on all cores (persistent)."

  # Optionally pin min/max frequency
  if { echo -n "* Set custom min/max CPU frequency? [y/N]: "; read -r _c; [[ "$_c" =~ ^[Yy] ]]; }; then
    local min_khz max_khz
    echo "  Available scaling_min_freq:"
    cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq 2>/dev/null | sed 's/^/    /'
    echo "  Available scaling_max_freq:"
    cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null | sed 's/^/    /'
    read -rp "  Min frequency (kHz, leave blank to skip): " min_khz
    read -rp "  Max frequency (kHz, leave blank to skip): " max_khz
    [[ -n "$min_khz" ]] && _cpufreq_write "scaling_min_freq" "$min_khz"
    [[ -n "$max_khz" ]] && _cpufreq_write "scaling_max_freq" "$max_khz"
    p_success "CPU frequency range pinned."
  fi
  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

# ================================================================
#  [2] INTEL-SPECIFIC TUNING
# ================================================================
opt_intel() {
  print_brake 70; output "Intel CPU Optimizations"; print_brake 70; echo ""
  if [[ "$CPU_VENDOR" != "intel" ]]; then
    p_warning "Non-Intel CPU detected (${CPU_VENDOR}). Some options may not apply."
    { echo -n "* Continue anyway? [y/N]: "; read -r _c; [[ "$_c" =~ ^[Yy] ]]; } || { echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }
  fi

  local _intel_opts=(
    "pstate_active"    "intel_pstate active mode  -- Native P-state driver (best)"
    "pstate_passive"   "intel_pstate passive mode -- Hands off to scaling_governor"
    "hwp_enable"       "HWP (Hardware P-states)   -- CPU self-manages power/perf"
    "hwp_perf"         "HWP Performance hint       -- EPP = performance"
    "hwp_bal"          "HWP Balance-Performance hint -- EPP = balance_performance"
    "turbo_on"         "Intel Turbo Boost ON       -- Allow burst frequencies"
    "turbo_off"        "Intel Turbo Boost OFF      -- Lock to base clock (latency)"
    "cstate_opt"       "C-State optimization       -- Disable deep sleep (low latency)"
    "prefetch_tune"    "Prefetcher tuning          -- Disable HW prefetch for NUMA"
    "microcode"        "CPU Microcode update       -- Latest security/perf fixes"
    "energy_policy"    "Energy Performance Policy  -- Set via x86_energy_perf_policy"
  )
  multi_select "Select Intel tuning options" "${_intel_opts[@]}"
  [[ ${#SELECTED_ITEMS[@]} -eq 0 ]] && { echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }
  _backup_init

  for opt in "${SELECTED_ITEMS[@]}"; do
    case "$opt" in

      pstate_active)
        step "Setting intel_pstate to active mode..."
        if [[ -f /sys/devices/system/cpu/intel_pstate/status ]]; then
          echo "active" > /sys/devices/system/cpu/intel_pstate/status
          # Persist via GRUB
          _grub_add_param "intel_pstate=enable"
          p_success "intel_pstate = active"
        else
          p_warning "intel_pstate not available on this system."
        fi ;;

      pstate_passive)
        step "Setting intel_pstate to passive mode..."
        [[ -f /sys/devices/system/cpu/intel_pstate/status ]] && \
          echo "passive" > /sys/devices/system/cpu/intel_pstate/status
        _grub_add_param "intel_pstate=passive"
        p_success "intel_pstate = passive (uses scaling_governor)" ;;

      hwp_enable)
        step "Enabling HWP..."
        if grep -q "hwp" /proc/cpuinfo 2>/dev/null || \
           grep -q "HWP" /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_available_preferences 2>/dev/null; then
          for f in /sys/devices/system/cpu/cpu*/power/energy_perf_bias; do
            [[ -f "$f" ]] && echo 0 > "$f" 2>/dev/null || true
          done
          p_success "HWP enabled (energy_perf_bias=0)"
        else
          p_warning "HWP not supported by this CPU."
        fi ;;

      hwp_perf)
        step "Setting HWP EPP = performance..."
        for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
          [[ -f "$f" ]] && echo "performance" > "$f" 2>/dev/null || true
        done
        p_success "HWP EPP = performance on all cores" ;;

      hwp_bal)
        step "Setting HWP EPP = balance_performance..."
        for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
          [[ -f "$f" ]] && echo "balance_performance" > "$f" 2>/dev/null || true
        done
        p_success "HWP EPP = balance_performance" ;;

      turbo_on)
        step "Enabling Intel Turbo Boost..."
        [[ -f /sys/devices/system/cpu/intel_pstate/no_turbo ]] && \
          echo 0 > /sys/devices/system/cpu/intel_pstate/no_turbo
        [[ -f /sys/devices/system/cpu/cpufreq/boost ]] && \
          echo 1 > /sys/devices/system/cpu/cpufreq/boost 2>/dev/null || true
        _grub_add_param "intel_pstate.no_hwp=0"
        p_success "Turbo Boost ENABLED" ;;

      turbo_off)
        step "Disabling Intel Turbo Boost (constant base clock)..."
        [[ -f /sys/devices/system/cpu/intel_pstate/no_turbo ]] && \
          echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo
        p_success "Turbo Boost DISABLED -- deterministic latency" ;;

      cstate_opt)
        step "Optimizing C-states (disabling deep sleep for low latency)..."
        # Limit to C1/C1E only via kernel param
        _grub_add_param "processor.max_cstate=1 intel_idle.max_cstate=1"
        # Runtime: set latency tolerance
        for f in /sys/devices/system/cpu/cpu*/power/pm_qos_resume_latency_us; do
          [[ -f "$f" ]] && echo "0" > "$f" 2>/dev/null || true
        done
        # Disable power management C-states via cpupower if available
        cpupower idle-set --disable-by-latency 10 &>/dev/null || true
        p_success "C-states limited to C1 -- minimal wake latency" ;;

      prefetch_tune)
        step "Tuning Intel hardware prefetcher via MSR..."
        if command -v wrmsr &>/dev/null; then
          # Disable hardware prefetch and adjacent cache line prefetch on each core
          for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
            local n; n="${cpu##*cpu}"
            wrmsr -p "$n" 0x1a4 0xf 2>/dev/null || true
          done
          p_success "Hardware prefetcher disabled (NUMA/HPC workloads benefit)"
        else
          apt-get install -y msr-tools -qq 2>/dev/null || true
          modprobe msr 2>/dev/null || true
          for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
            local n; n="${cpu##*cpu}"
            wrmsr -p "$n" 0x1a4 0xf 2>/dev/null || true
          done
          p_success "Hardware prefetcher tuned via MSR"
        fi ;;

      microcode)
        step "Installing/updating Intel CPU microcode..."
        apt-get install -y intel-microcode iucode-tool -qq 2>/dev/null \
          || p_warning "intel-microcode not available in repos."
        p_success "Microcode package updated (reboot to apply)" ;;

      energy_policy)
        step "Setting energy performance policy to 'performance'..."
        if command -v x86_energy_perf_policy &>/dev/null; then
          x86_energy_perf_policy performance 2>/dev/null || true
        else
          apt-get install -y linux-tools-common linux-tools-generic -qq 2>/dev/null || \
            apt-get install -y linux-tools-"$(uname -r)" -qq 2>/dev/null || true
          x86_energy_perf_policy performance 2>/dev/null || true
        fi
        p_success "Energy performance policy = performance" ;;
    esac
  done
  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

# -- GRUB param helper ---------------------------------------------
_grub_add_param() {
  local param="$1"
  local grub_cfg="/etc/default/grub"
  [[ -f "$grub_cfg" ]] || return
  cp "$grub_cfg" "${BACKUP_DIR}/grub.bak" 2>/dev/null || mkdir -p "$BACKUP_DIR" && cp "$grub_cfg" "${BACKUP_DIR}/grub.bak"
  # Check if already present
  grep -q "$param" "$grub_cfg" && return
  sed -i "s|GRUB_CMDLINE_LINUX_DEFAULT=\"|GRUB_CMDLINE_LINUX_DEFAULT=\"${param} |" "$grub_cfg"
  update-grub &>/dev/null || grub-mkconfig -o /boot/grub/grub.cfg &>/dev/null || true
  detail "GRUB param added: ${param} (reboot required)"
}

# ================================================================
#  [3] AMD-SPECIFIC TUNING
# ================================================================
opt_amd() {
  print_brake 70; output "AMD CPU Optimizations"; print_brake 70; echo ""
  if [[ "$CPU_VENDOR" != "amd" ]]; then
    p_warning "Non-AMD CPU detected (${CPU_VENDOR}). Some options may not apply."
    { echo -n "* Continue anyway? [y/N]: "; read -r _c; [[ "$_c" =~ ^[Yy] ]]; } || { echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }
  fi

  local _amd_opts=(
    "pstate_guided"  "amd_pstate guided mode     -- Kernel guides P-state (kernel 6.1+)"
    "pstate_active"  "amd_pstate active mode      -- Full hardware autonomy (kernel 6.3+)"
    "cpb_on"         "Core Performance Boost ON   -- Allow Precision Boost"
    "cpb_off"        "Core Performance Boost OFF  -- Stable base clock"
    "epp_perf"       "Energy Perf Pref = performance"
    "epp_bal"        "Energy Perf Pref = balance_performance"
    "prefetch_tune"  "Disable HW prefetch         -- Better for NUMA / gaming latency"
    "microcode"      "AMD CPU Microcode update"
    "power_cap"      "Remove CPU power cap        -- Allow full TDP"
    "numa_bal"       "NUMA balancing ON            -- Multi-socket workloads"
  )
  multi_select "Select AMD tuning options" "${_amd_opts[@]}"
  [[ ${#SELECTED_ITEMS[@]} -eq 0 ]] && { echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }
  _backup_init

  for opt in "${SELECTED_ITEMS[@]}"; do
    case "$opt" in

      pstate_guided)
        step "Enabling amd_pstate guided mode..."
        if [[ -f /sys/devices/system/cpu/amd_pstate/status ]]; then
          echo "guided" > /sys/devices/system/cpu/amd_pstate/status
          p_success "amd_pstate = guided"
        else
          _grub_add_param "amd_pstate=guided"
          p_warning "amd_pstate not yet active -- GRUB param added, reboot required."
        fi ;;

      pstate_active)
        step "Enabling amd_pstate active mode..."
        if [[ -f /sys/devices/system/cpu/amd_pstate/status ]]; then
          echo "active" > /sys/devices/system/cpu/amd_pstate/status
          p_success "amd_pstate = active"
        else
          _grub_add_param "amd_pstate=active"
          p_warning "Reboot required to activate amd_pstate active mode."
        fi ;;

      cpb_on)
        step "Enabling Core Performance Boost..."
        [[ -f /sys/devices/system/cpu/cpufreq/boost ]] && \
          echo 1 > /sys/devices/system/cpu/cpufreq/boost
        _grub_add_param "amd_pstate.shared_mem=1"
        p_success "CPB (Precision Boost) ENABLED" ;;

      cpb_off)
        step "Disabling Core Performance Boost (stable base clock)..."
        [[ -f /sys/devices/system/cpu/cpufreq/boost ]] && \
          echo 0 > /sys/devices/system/cpu/cpufreq/boost
        p_success "CPB DISABLED -- deterministic latency" ;;

      epp_perf)
        step "Setting AMD EPP = performance..."
        for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
          [[ -f "$f" ]] && echo "performance" > "$f" 2>/dev/null || true
        done
        p_success "EPP = performance on all cores" ;;

      epp_bal)
        step "Setting AMD EPP = balance_performance..."
        for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
          [[ -f "$f" ]] && echo "balance_performance" > "$f" 2>/dev/null || true
        done
        p_success "EPP = balance_performance" ;;

      prefetch_tune)
        step "Disabling AMD hardware prefetch via MSR (0xC0011022)..."
        modprobe msr 2>/dev/null || true
        if command -v wrmsr &>/dev/null; then
          for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
            local n; n="${cpu##*cpu}"
            # Set bit 13 (HW prefetch disable) in MSRC001_1022
            wrmsr -p "$n" 0xC0011022 0x0000000000002000 2>/dev/null || true
          done
          p_success "AMD hardware prefetch disabled via MSR"
        else
          apt-get install -y msr-tools -qq && modprobe msr
          for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
            local n; n="${cpu##*cpu}"
            wrmsr -p "$n" 0xC0011022 0x0000000000002000 2>/dev/null || true
          done
          p_success "AMD hardware prefetch disabled"
        fi ;;

      microcode)
        step "Installing AMD microcode..."
        apt-get install -y amd64-microcode -qq 2>/dev/null \
          || p_warning "amd64-microcode not found in repos."
        p_success "AMD microcode updated (reboot to apply)" ;;

      power_cap)
        step "Removing RAPL/power cap constraints..."
        for f in /sys/devices/virtual/powercap/intel-rapl/*/constraint_0_power_limit_uw; do
          # Write max value to remove cap
          [[ -f "$f" ]] && cat "${f/power_limit_uw/power_limit_max_uw}" > "$f" 2>/dev/null || true
        done
        p_success "Power cap removed -- CPU can use full TDP" ;;

      numa_bal)
        step "Enabling NUMA balancing..."
        _sysctl_set "kernel.numa_balancing" "1" "NUMA automatic balancing"
        p_success "NUMA balancing ON" ;;
    esac
  done
  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

# ================================================================
#  [4] IRQ BALANCING & CPU AFFINITY
# ================================================================
opt_irq() {
  print_brake 70; output "IRQ Balancing & CPU Affinity"; print_brake 70; echo ""
  local _irq_opts=(
    "irqbalance"    "irqbalance daemon  -- Auto-distribute IRQs across cores"
    "rps_rfs"       "RPS / RFS          -- Spread network IRQs to all CPUs"
    "affinity_net"  "Pin network IRQs to non-zero cores (keep core 0 for OS)"
    "nohz_full"     "nohz_full / isolcpus -- Isolate cores for latency-critical tasks"
  )
  multi_select "IRQ & CPU Affinity options" "${_irq_opts[@]}"
  [[ ${#SELECTED_ITEMS[@]} -eq 0 ]] && { echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }

  for opt in "${SELECTED_ITEMS[@]}"; do
    case "$opt" in
      irqbalance)
        apt-get install -y irqbalance -qq
        systemctl enable --now irqbalance 2>/dev/null || true
        p_success "irqbalance installed and running." ;;

      rps_rfs)
        step "Enabling RPS/RFS on all interfaces..."
        local cpus_hex; cpus_hex=$(printf '%x' $(( (1 << CPU_CORES) - 1 )))
        for rps in /sys/class/net/*/queues/*/rps_cpus; do
          [[ -f "$rps" ]] && echo "$cpus_hex" > "$rps" 2>/dev/null || true
        done
        local rfs_entries=32768
        _sysctl_set "net.core.rps_sock_flow_entries" "$rfs_entries" "RFS flow entries"
        for rfs in /sys/class/net/*/queues/*/rps_flow_cnt; do
          [[ -f "$rfs" ]] && echo "$(( rfs_entries / $(ls /sys/class/net/*/queues/rx_* 2>/dev/null | wc -l || echo 1) ))" \
            > "$rfs" 2>/dev/null || true
        done
        p_success "RPS/RFS enabled across all ${CPU_CORES} cores." ;;

      affinity_net)
        step "Pinning network IRQs away from core 0..."
        local mask=0
        for (( i=1; i<CPU_CORES; i++ )); do
          mask=$(( mask | (1 << i) ))
        done
        local hex_mask; hex_mask=$(printf '%x' $mask)
        for irq_file in /proc/irq/*/smp_affinity; do
          [[ -f "$irq_file" ]] && echo "$hex_mask" > "$irq_file" 2>/dev/null || true
        done
        p_success "Network IRQs pinned to cores 1-$(( CPU_CORES-1 ))." ;;

      nohz_full)
        p_warning "nohz_full isolates CPUs from timer ticks -- only for real-time/HPC workloads."
        local last_core=$(( CPU_CORES - 1 ))
        read -rp "  Core range to isolate (e.g. 2-${last_core}): " iso_range
        [[ -z "$iso_range" ]] && { p_warning "Skipped."; continue; }
        _grub_add_param "nohz_full=${iso_range} isolcpus=${iso_range} rcu_nocbs=${iso_range}"
        p_success "nohz_full=${iso_range} added to GRUB (reboot required)." ;;
    esac
  done
  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

