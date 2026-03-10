#!/usr/bin/env bash
# ================================================================
# Zynr.Cloud v5.0.0 -- VPS Manager * Health Check
# Addon: Full server diagnostics + optional email alerts
# Sourced by install.sh -- do not run directly.
# ================================================================

vps_health_check() {
  clear
  print_brake 70; output "  Server Health Check"; print_brake 70

  local REPORT="" ALERTS="" HAS_CRIT=0 HAS_WARN=0
  local NOW; NOW=$(date '+%Y-%m-%d %H:%M:%S')

  _hadd()  { REPORT+="$1\n"; }
  _hcrit() { ALERTS+="[CRIT] CRITICAL: $1\n"; HAS_CRIT=1; _hadd "  [CRIT] CRITICAL: $1"; }
  _hwarn() { ALERTS+="[WARN] WARNING:  $1\n"; HAS_WARN=1;  _hadd "  [WARN] WARNING:  $1"; }
  _hok()   { _hadd "  ${GREEN_B}[OK]${NC}  $1"; }

  # -- RAM ----------------------------------------------------
  _hadd ""
  _hadd " ${CYAN_B}-- RAM ---------------------------------${NC}"
  local TOT USED AVAIL PCT
  TOT=$(free -m  | awk '/^Mem:/{print $2}')
  USED=$(free -m | awk '/^Mem:/{print $3}')
  AVAIL=$(free -m| awk '/^Mem:/{print $7}')
  PCT=$(( USED * 100 / TOT ))
  local SWAP_USED SWAP_TOT SWAP_PCT
  SWAP_TOT=$(free -m  | awk '/^Swap:/{print $2}')
  SWAP_USED=$(free -m | awk '/^Swap:/{print $3}')
  SWAP_PCT=0
  if (( SWAP_TOT > 0 )); then
    SWAP_PCT=$(( SWAP_USED * 100 / SWAP_TOT ))
  fi

  printf "  Total: ${TOT}MB   Used: ${USED}MB (${PCT}%)   Free: ${AVAIL}MB\n"
  printf "  Swap: ${SWAP_USED}/${SWAP_TOT}MB (${SWAP_PCT}%)\n"

  [[ $PCT -ge 90 ]] && _hcrit "RAM at ${PCT}% -- only ${AVAIL}MB free" \
  || { [[ $PCT -ge 80 ]] && _hwarn "RAM at ${PCT}%" || _hok "RAM ${PCT}% used (${AVAIL}MB free)"; }
  [[ $SWAP_PCT -ge 50 ]] && _hwarn "Swap ${SWAP_PCT}% -- VMs may be paging"

  # -- CPU ----------------------------------------------------
  _hadd ""
  _hadd " ${CYAN_B}-- CPU ---------------------------------${NC}"
  local NCPU LOAD15 CPU_PCT
  NCPU=$(nproc)
  LOAD15=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $3}' | tr -d ' ')
  CPU_PCT=$(echo "$LOAD15 $NCPU" | awk '{printf "%d", ($1/$2)*100}')
  _hadd "  vCPUs: $NCPU   15-min load: $LOAD15   (~${CPU_PCT}%)"
  [[ $CPU_PCT -ge 80 ]] && _hwarn "CPU load at ${CPU_PCT}%" || _hok "CPU load ${CPU_PCT}%"

  # -- Disks --------------------------------------------------
  _hadd ""
  _hadd " ${CYAN_B}-- DISKS -------------------------------${NC}"
  while IFS= read -r line; do
    local PCT_D MNT
    PCT_D=$(echo "$line" | awk '{print $5}' | tr -d '%')
    MNT=$(echo "$line" | awk '{print $6}')
    [[ "$MNT" == /snap/* || "$MNT" == /sys/* || "$MNT" == /proc/* ]] && continue
    _hadd "  $line"
    [[ ${PCT_D:-0} -ge 90 ]] && _hcrit "Disk $MNT at ${PCT_D}% full"
    [[ ${PCT_D:-0} -ge 75 && ${PCT_D:-0} -lt 90 ]] && _hwarn "Disk $MNT at ${PCT_D}%"
  done < <(df -h --output=source,size,used,avail,pcent,target 2>/dev/null | tail -n +2)

  # -- ZFS ----------------------------------------------------
  _hadd ""
  _hadd " ${CYAN_B}-- ZFS ---------------------------------${NC}"
  if command -v zpool &>/dev/null && zpool list "$VPS_STORAGE" &>/dev/null 2>&1; then
    local ZH ZA ZF ZC ZFR
    ZH=$(zpool list -H -o health  "$VPS_STORAGE")
    ZA=$(zpool list -H -o alloc   "$VPS_STORAGE")
    ZF=$(zpool list -H -o free    "$VPS_STORAGE")
    ZC=$(zpool list -H -o cap     "$VPS_STORAGE" | tr -d '%')
    ZFR=$(zpool list -H -o frag   "$VPS_STORAGE")
    _hadd "  Health: $ZH   Alloc: $ZA   Free: $ZF   Cap: ${ZC}%   Frag: $ZFR"
    [[ "$ZH" != "ONLINE" ]] && _hcrit "ZFS pool $VPS_STORAGE is $ZH -- check immediately!" \
      || _hok "ZFS pool $VPS_STORAGE healthy (${ZC}% used)"

    # sdb SMART check (known failing disk)
    if command -v smartctl &>/dev/null && [[ -b /dev/sdb ]]; then
      local REALLOC PENDING SHEAL
      REALLOC=$(smartctl -A /dev/sdb 2>/dev/null | awk '/Reallocated_Sector_Ct/{print $NF}')
      PENDING=$(smartctl -A /dev/sdb 2>/dev/null | awk '/Current_Pending_Sector/{print $NF}')
      SHEAL=$(smartctl -H /dev/sdb 2>/dev/null | grep "SMART overall" || true | awk '{print $NF}')
      _hadd "  sdb SMART: $SHEAL   Reallocated: ${REALLOC:-?}   Pending: ${PENDING:-?}"
      [[ "${REALLOC:-0}" -gt 0 || "${PENDING:-0}" -gt 0 ]] && \
        _hcrit "sdb FAILING -- Reallocated=${REALLOC} Pending=${PENDING} -- REPLACE NOW"
    fi
  else
    _hadd "  ZFS not available or pool '$VPS_STORAGE' not found"
  fi

  # -- VMs ----------------------------------------------------
  _hadd ""
  _hadd " ${CYAN_B}-- VMs ---------------------------------${NC}"
  if command -v qm &>/dev/null; then
    local VM_RUN VM_STOP VM_TOT
    VM_RUN=$(qm list  2>/dev/null | grep -c " running " || echo 0)
    VM_STOP=$(qm list 2>/dev/null | grep -c " stopped " || echo 0)
    VM_TOT=$(( VM_RUN + VM_STOP ))
    _hadd "  Total: $VM_TOT   Running: $VM_RUN   Stopped: $VM_STOP"
    _hok "$VM_RUN VMs running"
  else
    _hadd "  Proxmox not available on this node"
  fi

  # -- Services -----------------------------------------------
  _hadd ""
  _hadd " ${CYAN_B}-- KEY SERVICES ------------------------${NC}"
  for SVC in pvedaemon pveproxy fail2ban ssh ufw; do
    if systemctl is-active --quiet "$SVC" 2>/dev/null; then
      _hadd "  ${GREEN_B}[OK]${NC} $SVC: running"
    else
      _hadd "  ${RED_B}[X]${NC} $SVC: NOT RUNNING"
      _hcrit "Service $SVC is DOWN"
    fi
  done

  # -- Fail2ban -----------------------------------------------
  _hadd ""
  _hadd " ${CYAN_B}-- FAIL2BAN ----------------------------${NC}"
  if command -v fail2ban-client &>/dev/null; then
    local SSH_BANS SSH_TOT PVE_BANS
    SSH_BANS=$(fail2ban-client status sshd  2>/dev/null | grep "Currently banned" | awk '{print $NF}')
    SSH_TOT=$(fail2ban-client status sshd   2>/dev/null | grep "Total banned"     | awk '{print $NF}')
    PVE_BANS=$(fail2ban-client status proxmox 2>/dev/null | grep "Currently banned" | awk '{print $NF}' || echo 0)
    _hadd "  SSH banned now: ${SSH_BANS:-0}   SSH total: ${SSH_TOT:-0}   Proxmox: ${PVE_BANS:-0}"
    _hok "fail2ban active -- ${SSH_BANS:-0} IPs currently banned"
  else
    _hwarn "fail2ban not installed"
  fi

  # -- Summary ------------------------------------------------
  _hadd ""
  _hadd " ${CYAN_B}-- SUMMARY -----------------------------${NC}"
  if [[ -n "$ALERTS" ]]; then
    _hadd "$ALERTS"
  else
    _hadd "  ${GREEN_B}[OK]  All checks passed -- server is healthy${NC}"
  fi
  _hadd ""
  _hadd "  Report generated: $NOW"

  # -- Print --------------------------------------------------
  echo -e "$REPORT"
  echo "$REPORT" >> /var/log/vps-health.log 2>/dev/null || true

  # -- Email option -------------------------------------------
  if [[ $HAS_CRIT -eq 1 || $HAS_WARN -eq 1 ]]; then
    echo ""
    p_warning "Issues detected!"
    echo -n "* Send email alert? [y/N]: "; read -r _c
  if [[ "$_c" =~ ^[Yy] ]]; then
      printf " ${CYAN_B}>${NC} Alert email address: "; read -r HEALTH_EMAIL
      if command -v mail &>/dev/null && [[ -n "$HEALTH_EMAIL" ]]; then
        local SUBJ="[CRIT] Zynr VPS Alert -- $(hostname) -- $(date '+%Y-%m-%d %H:%M')"
        [[ $HAS_CRIT -eq 0 ]] && SUBJ="[WARN] Zynr VPS Warning -- $(hostname) -- $(date '+%Y-%m-%d %H:%M')"
        echo -e "$REPORT" | mail -s "$SUBJ" "$HEALTH_EMAIL"
        p_success "Alert sent to $HEALTH_EMAIL"
      else
        p_warning "mail command not available -- install: apt install mailutils"
      fi
    fi
  fi

  # -- Cron setup ---------------------------------------------
  echo ""
  echo -n "* Set up daily health check cron? (runs at 08:00) [y/N]: "; read -r _c
  if [[ "$_c" =~ ^[Yy] ]]; then
    printf " ${CYAN_B}>${NC} Alert email: "; read -r CRON_EMAIL
    cat > /etc/cron.d/zynr-health << CRONEOF
# Zynr.Cloud -- Daily Health Check
0 8 * * * root bash <(curl -fsSL https://raw.githubusercontent.com/XDgamer100/zynr/main/install.sh) --health-only 2>&1 | mail -s "Zynr Health $(hostname) $(date +%Y-%m-%d)" ${CRON_EMAIL:-root}
CRONEOF
    p_success "Daily health cron set -> ${CRON_EMAIL:-root}"
  fi

  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}
