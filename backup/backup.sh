#!/usr/bin/env bash
# ================================================================
# Zynr.Cloud v5.0.0 -- VPS Manager * Backup Module
# Addon: PBS setup * VM snapshots * vzdump backups
# Sourced by install.sh -- do not run directly.
# ================================================================

menu_backup() {
  while true; do
    clear

    local pbs_status="not installed"
    local backup_storage="--"
    command -v proxmox-backup-client &>/dev/null && pbs_status="installed"
    [[ -d /mnt/pve/backup ]] && backup_storage=$(df -h /mnt/pve/backup 2>/dev/null | tail -1 | awk '{print $4" free of "$2}')

    print_brake 70
    output "Zynr.Cloud -- Backup Manager"
    output ""
    output "PBS: ${pbs_status}   Backup drive: ${backup_storage}"
    print_brake 70

    output ""
    output "[1] Setup PBS           (Proxmox Backup Server on backup drive)"
    output "[2] Snapshot VM         (instant ZFS snapshot of a VM)"
    output "[3] vzdump Backup       (full VM backup to backup storage)"
    output "[4] Restore Snapshot    (roll back a VM to a snapshot)"
    output "[5] List Snapshots      (all snapshots per VM)"
    output "[6] Delete Snapshot     (free up space)"
    output "[7] Auto-backup Cron    (daily backup schedule)"
    output ""
    output "[0] Back to VPS Menu"
    echo ""
    echo -n "* Input 0-7: "
    read -r C
    echo ""

    case "$C" in
      1) backup_setup_pbs    ;;
      2) backup_snapshot     ;;
      3) backup_vzdump       ;;
      4) backup_restore      ;;
      5) backup_list         ;;
      6) backup_delete       ;;
      7) backup_cron         ;;
      0) return              ;;
      *)
        echo -e "* ${COLOR_RED}ERROR${COLOR_NC}: Invalid option" 1>&2
        sleep 1 ;;
    esac
  done
}

# -- 1: Setup PBS ------------------------------------------------
backup_setup_pbs() {
  print_brake 70
  output "Proxmox Backup Server Setup"
  print_brake 70

  output "PBS will be installed on this node and use the backup drive at /mnt/pve/backup"
  output "Backup drive: $(df -h /mnt/pve/backup 2>/dev/null | tail -1 | awk '{print $2" total, "$4" free"}' || echo 'not mounted')"
  echo ""
  echo -n "* Install Proxmox Backup Server? [y/N]: "; read -r _c
  [[ "$_c" =~ ^[Yy] ]] || { echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }

  steps_init 4

  step_n "Add PBS repo"
  echo "deb http://download.proxmox.com/debian/pbs "${OS_CODENAME}" pbs-no-subscription" \
    > /etc/apt/sources.list.d/pbs.list 2>/dev/null || true
  spinner_start "Updating repos..."
  apt-get update -qq
  spinner_stop; p_success "PBS repo added"

  step_n "Install proxmox-backup-server"
  spinner_start "Installing (~300MB)..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq proxmox-backup-server
  spinner_stop; p_success "PBS installed"

  step_n "Create datastore on backup drive"
  if [[ -d /mnt/pve/backup ]]; then
    proxmox-backup-manager datastore create main /mnt/pve/backup 2>/dev/null || \
      detail "Datastore may already exist"
    p_success "Datastore 'main' created at /mnt/pve/backup"
  else
    p_warning "/mnt/pve/backup not found -- mount your backup drive first"
  fi

  step_n "Enable PBS service"
  systemctl enable proxmox-backup --quiet 2>/dev/null || true
  systemctl start proxmox-backup
  p_success "PBS running on https://$(hostname -I | awk '{print $1}'):8007"

  echo ""

  output "Access PBS web UI: https://$(hostname -I | awk '{print $1}'):8007"
  output "Login: root / your root password"
  output "Add this PBS as storage in Proxmox: Datacenter -> Storage -> Add -> Proxmox Backup Server"
  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

# -- 2: Snapshot VM ----------------------------------------------
backup_snapshot() {
  _require_proxmox
  print_brake 70
  output " VM Snapshot"
  print_brake 70

  vps_list

  echo ""
  printf " ${CYAN_B}>${NC} VM ID to snapshot: "; read -r SNAP_ID
  [[ -z "$SNAP_ID" ]] && return

  ! qm status "$SNAP_ID" &>/dev/null && { p_warning "VM $SNAP_ID not found."; echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }

  local DEFAULT_NAME="snap-$(date +%Y%m%d-%H%M)"
  printf " ${CYAN_B}>${NC} Snapshot name [${DEFAULT_NAME}]: "; read -r SNAP_NAME
  [[ -z "$SNAP_NAME" ]] && SNAP_NAME="$DEFAULT_NAME"

  printf " ${CYAN_B}>${NC} Description (optional): "; read -r SNAP_DESC

  spinner_start "Creating snapshot $SNAP_NAME for VM $SNAP_ID..."
  qm snapshot "$SNAP_ID" "$SNAP_NAME" --description "${SNAP_DESC:-Zynr snapshot}" --vmstate 0
  spinner_stop
  p_success "Snapshot '$SNAP_NAME' created for VM $SNAP_ID"
  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

# -- 3: vzdump backup --------------------------------------------
backup_vzdump() {
  _require_proxmox
  print_brake 70
  output "[PKG] vzdump Backup"
  print_brake 70

  vps_list

  echo ""
  printf " ${CYAN_B}>${NC} VM ID to backup (or 'all'): "; read -r BK_ID

  local BK_STORAGE="backup"
  printf " ${CYAN_B}>${NC} Storage target [${BK_STORAGE}]: "; read -r BK_STORAGE_IN
  [[ -n "$BK_STORAGE_IN" ]] && BK_STORAGE="$BK_STORAGE_IN"

  echo ""
  echo -e " ${BOLD}Compression:${NC}"
  
  
  
  printf " ${CYAN_B}>${NC} [1-3]: "; read -r COMP_CHOICE
  case "$COMP_CHOICE" in
    2) COMP="gzip" ;; 3) COMP="0" ;; *) COMP="zstd" ;;
  esac

  echo ""
  echo -n "* Start backup of VM $BK_ID to storage '$BK_STORAGE'? [y/N]: "; read -r _c
  [[ "$_c" =~ ^[Yy] ]] || { echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }

  if [[ "$BK_ID" == "all" ]]; then
    spinner_start "Backing up all VMs..."
    vzdump --all --storage "$BK_STORAGE" --compress "$COMP" --mode snapshot
  else
    spinner_start "Backing up VM $BK_ID..."
    vzdump "$BK_ID" --storage "$BK_STORAGE" --compress "$COMP" --mode snapshot
  fi
  spinner_stop
  p_success "Backup complete -> stored in $BK_STORAGE"
  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

# -- 4: Restore snapshot -----------------------------------------
backup_restore() {
  _require_proxmox
  print_brake 70
  output "[UPD] Restore VM Snapshot"
  print_brake 70

  echo ""
  printf " ${CYAN_B}>${NC} VM ID to restore: "; read -r REST_ID
  [[ -z "$REST_ID" ]] && return

  ! qm status "$REST_ID" &>/dev/null && { p_warning "VM $REST_ID not found."; echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }

  echo ""
  output "Available snapshots for VM $REST_ID:"
  qm listsnapshot "$REST_ID" 2>/dev/null
  echo ""

  printf " ${CYAN_B}>${NC} Snapshot name to restore: "; read -r REST_SNAP
  [[ -z "$REST_SNAP" ]] && return

  echo ""
  echo -e " ${YELLOW}[!]  This will roll back VM $REST_ID to snapshot '$REST_SNAP'${NC}"
  echo -e " ${YELLOW}   Any changes since that snapshot will be LOST.${NC}"
  echo -n "* Confirm rollback? [y/N]: "; read -r _c
  [[ "$_c" =~ ^[Yy] ]] || { echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }

  # Stop VM if running
  qm status "$REST_ID" 2>/dev/null | grep -q "running" && {
    spinner_start "Stopping VM $REST_ID..."
    qm stop "$REST_ID"
    sleep 3
    spinner_stop
  }

  spinner_start "Restoring snapshot '$REST_SNAP'..."
  qm rollback "$REST_ID" "$REST_SNAP"
  spinner_stop
  p_success "VM $REST_ID restored to snapshot '$REST_SNAP'"

  { echo -n "* Start VM $REST_ID now? [y/N]: "; read -r _c; [[ "$_c" =~ ^[Yy] ]]; } && qm start "$REST_ID" && p_success "VM $REST_ID started"
  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

# -- 5: List snapshots -------------------------------------------
backup_list() {
  _require_proxmox
  print_brake 70
  output "[LOG] VM Snapshots"
  print_brake 70

  echo ""
  printf " ${CYAN_B}>${NC} VM ID (or 'all'): "; read -r LS_ID

  if [[ "$LS_ID" == "all" ]]; then
    qm list 2>/dev/null | grep -v VMID | while read -r line; do
      local VID; VID=$(echo "$line" | awk '{print $1}')
      local SNAPS; SNAPS=$(qm listsnapshot "$VID" 2>/dev/null | grep -vc "current" || echo 0)
      [[ $SNAPS -gt 0 ]] && {
        echo ""
        echo -e " ${BOLD}VM $VID -- $(echo "$line" | awk '{print $2}')${NC}"
        qm listsnapshot "$VID" 2>/dev/null
      }
    done
  else
    qm listsnapshot "$LS_ID" 2>/dev/null || p_warning "No snapshots found for VM $LS_ID"
  fi

  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

# -- 6: Delete snapshot ------------------------------------------
backup_delete() {
  _require_proxmox
  print_brake 70
  output "[DEL]  Delete Snapshot"
  print_brake 70

  printf " ${CYAN_B}>${NC} VM ID: "; read -r DS_ID
  [[ -z "$DS_ID" ]] && return
  echo ""
  qm listsnapshot "$DS_ID" 2>/dev/null
  echo ""
  printf " ${CYAN_B}>${NC} Snapshot name to delete: "; read -r DS_SNAP
  [[ -z "$DS_SNAP" ]] && return

  echo -n "* Delete snapshot '$DS_SNAP' from VM $DS_ID? [y/N]: "; read -r _c
  [[ "$_c" =~ ^[Yy] ]] || { echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }
  spinner_start "Deleting..."
  qm delsnapshot "$DS_ID" "$DS_SNAP"
  spinner_stop
  p_success "Snapshot '$DS_SNAP' deleted"
  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

# -- 7: Auto-backup cron -----------------------------------------
backup_cron() {
  print_brake 70
  output " Automated Backup Schedule"
  print_brake 70

  output "This creates a daily cron job to backup all running VMs"
  echo ""

  printf " ${CYAN_B}>${NC} Backup time (hour, 0-23) [default: 2]: "; read -r BK_HOUR
  [[ -z "$BK_HOUR" ]] && BK_HOUR=2

  printf " ${CYAN_B}>${NC} Storage target [backup]: "; read -r BK_ST
  [[ -z "$BK_ST" ]] && BK_ST="backup"

  printf " ${CYAN_B}>${NC} Keep last N backups [7]: "; read -r BK_KEEP
  [[ -z "$BK_KEEP" ]] && BK_KEEP=7

  cat > /etc/cron.d/zynr-backup << CRONEOF
# Zynr.Cloud -- Daily VPS Backup (generated by Zynr)
0 ${BK_HOUR} * * * root vzdump --all --storage ${BK_ST} --compress zstd --mode snapshot --maxfiles ${BK_KEEP} >> /var/log/zynr-backup.log 2>&1
CRONEOF

  p_success "Cron job created: daily at ${BK_HOUR}:00 -> storage '$BK_ST' * keep last $BK_KEEP"
  detail "Log: /var/log/zynr-backup.log"
  detail "Edit: /etc/cron.d/zynr-backup"
  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}
