#!/usr/bin/env bash
# ================================================================
# Zynr.Cloud v5.0.0 -- VPS Manager * Core Functions
# Addon: Server setup * Templates * Provisioning * Management
# Sourced by install.sh -- do not run directly.
# ================================================================

# -- VPS Config defaults (override in /etc/.zynr_vps_env) --------
VPS_GATEWAY="165.101.250.1"
VPS_NETMASK="/23"
VPS_STORAGE="vps_data"
VPS_BRIDGE="vmbr0"
VPS_DNS="1.1.1.1 8.8.8.8"
VPS_PROV_LOG="/var/log/vps-provisioning.log"

[[ -f /etc/.zynr_vps_env ]] && source /etc/.zynr_vps_env 2>/dev/null || true

# -- OS -> Template ID map -----------------------------------------
declare -A _VPS_TMPL_ID=([ubuntu22]=9001 [ubuntu24]=9002 [debian12]=9003 [rocky9]=9004)
declare -A _VPS_TMPL_USER=([ubuntu22]="ubuntu" [ubuntu24]="ubuntu" [debian12]="debian" [rocky9]="rocky")
declare -A _VPS_TMPL_URL=(
  [ubuntu22]="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
  [ubuntu24]="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  [debian12]="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
  [rocky9]="https://dl.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2"
)
declare -A _VPS_TMPL_FILE=(
  [ubuntu22]="ubuntu-22.04.img"
  [ubuntu24]="ubuntu-24.04.img"
  [debian12]="debian-12.qcow2"
  [rocky9]="rocky-9.qcow2"
)

_require_proxmox() {
  command -v qm &>/dev/null || error "Proxmox (qm) not found. This node must be a Proxmox VE host."
}

# ================================================================
# 1 -- SERVER SETUP (security * fail2ban * UFW * SSH)
# ================================================================
vps_server_setup() {
  print_brake 70
  output "[SSL] Server Setup -- Security Hardening"
  print_brake 70
  echo ""

  output "This will apply: system update * fail2ban * UFW * SSH hardening * auto-updates"
  { echo -n "* Proceed with full server setup? [y/N]: "; read -r _c; [[ "$_c" =~ ^[Yy] ]]; } || { echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }

  # -- Get alert email ------------------------------------------
  echo ""
  printf " ${CYAN_B}>${NC} ${BOLD}Alert email for security notifications:${NC} "
  read -r SETUP_EMAIL
  [[ -z "$SETUP_EMAIL" ]] && SETUP_EMAIL="root@localhost"

  steps_init 6

  # -- 1: Update ------------------------------------------------
  step_n "System update & essential packages"
  spinner_start "Updating packages..."
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    fail2ban ufw curl wget vim htop net-tools \
    unattended-upgrades apt-listchanges smartmontools lsof ncdu dnsutils
  # Pre-seed postfix to avoid interactive prompts
  echo "postfix postfix/mailname string $(hostname -f 2>/dev/null || echo localhost)" | debconf-set-selections
  echo "postfix postfix/main_mailer_type string 'Internet Site'" | debconf-set-selections
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq mailutils postfix
  spinner_stop; p_success "Packages updated & installed"

  # -- 2: Admin user --------------------------------------------
  step_n "Creating vpsadmin user"
  local ADMIN_PASS
  ADMIN_PASS=$(openssl rand -base64 16)
  if ! id vpsadmin &>/dev/null; then
    local _sudo_grp="sudo"
    getent group wheel &>/dev/null && ! getent group sudo &>/dev/null && _sudo_grp="wheel"
    useradd -m -s /bin/bash -G "$_sudo_grp" vpsadmin
    echo "vpsadmin:${ADMIN_PASS}" | chpasswd
    p_success "User vpsadmin created"
    echo ""
    echo -e " ${YELLOW}${BOX_TL}$(_rep "${BOX_H}" 50)${BOX_TR}${NC}"
    echo -e " ${YELLOW}${BOX_V}  SAVE THIS -- shown only once                    ${BOX_V}${NC}"
    label " ${YELLOW}${BOX_V}  User    " "vpsadmin"
    label " ${YELLOW}${BOX_V}  Password" "$ADMIN_PASS"
    echo -e " ${YELLOW}${BOX_BL}$(_rep "${BOX_H}" 50)${BOX_BR}${NC}"
    echo ""
  else
    p_warning "User vpsadmin already exists -- skipping"
  fi

  # -- 3: SSH hardening -----------------------------------------
  step_n "SSH hardening"
  cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d) 2>/dev/null || true
  cat > /etc/ssh/sshd_config.d/99-zynr-hardening.conf << 'SSHEOF'
PermitRootLogin prohibit-password
PasswordAuthentication yes
PubkeyAuthentication yes
MaxAuthTries 4
LoginGraceTime 30
X11Forwarding no
AllowTcpForwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
Banner /etc/ssh/zynr-clear
SSHEOF
  cat > /etc/ssh/zynr-banner << 'BANEOF'
*************************************************************
  Authorised access only. All activity is monitored.
  Managed by Zynr.Cloud -- github.com/XDgamer100/zynr
*************************************************************
BANEOF
  systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || {
    p_error "Failed to restart SSH service"
    return 1
  }
  p_success "SSH hardened (key-only root login, login banner, timeouts)"

  # -- 4: Fail2ban ----------------------------------------------
  step_n "Fail2ban -- SSH + Proxmox protection"
  cat > /etc/fail2ban/jail.d/zynr.conf << 'F2BEOF'
[DEFAULT]
bantime  = 2h
findtime = 10m
maxretry = 5
backend  = systemd

[sshd]
enabled  = true
port     = ssh
logpath  = %(sshd_log)s

[proxmox]
enabled  = true
port     = https,8006
filter   = proxmox
logpath  = /var/log/daemon.log
maxretry = 5
bantime  = 4h
F2BEOF

  cat > /etc/fail2ban/filter.d/proxmox.conf << 'PFEOF'
[Definition]
failregex = pvedaemon\[.*authentication failure; rhost=<HOST> user=.* msg=.*
ignoreregex =
PFEOF

  systemctl enable fail2ban -q 2>/dev/null || true
  systemctl restart fail2ban
  sleep 2
  systemctl is-active --quiet fail2ban && \
    p_success "Fail2ban running -- SSH + Proxmox panel protected" || \
    p_warning "Fail2ban may not have started -- check: journalctl -u fail2ban"

  # -- 5: UFW --------------------------------------------------
  step_n "UFW Firewall"
  ufw --force reset > /dev/null
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow 22/tcp   comment 'SSH'
  ufw allow 8006/tcp comment 'Proxmox Web UI'
  ufw allow 3128/tcp comment 'Proxmox SPICE'
  ufw allow 80/tcp   comment 'HTTP'
  ufw allow 443/tcp  comment 'HTTPS'
  ufw allow 8892/tcp comment 'Nginx panel'
  # Block amplification abuse ports
  ufw deny 11211/udp comment 'Block memcached amp'
  ufw deny 1900/udp  comment 'Block SSDP amp'
  ufw deny 389/udp   comment 'Block LDAP amp'
  ufw --force enable > /dev/null
  p_success "UFW enabled -- $(ufw status | grep -c ALLOW || echo 0) allow rules active"

  # -- 6: Auto security updates ---------------------------------
  step_n "Automatic security updates"
  cat > /etc/apt/apt.conf.d/50unattended-upgrades << UEOF
Unattended-Upgrade::Allowed-Origins {
  "\${distro_id}:\${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Mail "${SETUP_EMAIL}";
UEOF
  cat > /etc/apt/apt.conf.d/20auto-upgrades << 'AUEOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
AUEOF
  p_success "Auto security updates enabled -> alerts to $SETUP_EMAIL"

  # -- Done ----------------------------------------------------
  echo ""

  p_success "Server hardening complete!"
  echo ""
  detail "Next: run Template Builder [2] to create VM templates"
  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

# ================================================================
# 2 -- TEMPLATE BUILDER
# ================================================================
vps_template_builder() {
  _require_proxmox
  print_brake 70
  output "[PKG] Template Builder -- Cloud-Init VM Templates"
  print_brake 70
  echo ""

  local IMG_DIR="/var/lib/vz/images/templates"
  mkdir -p "$IMG_DIR"

  # Check storage
  if ! pvesh get /storage/"$VPS_STORAGE" &>/dev/null 2>&1; then
    p_warning "Storage '$VPS_STORAGE' not found. Available:"
    pvesm status 2>/dev/null || true
    echo ""
    printf " ${CYAN_B}>${NC} ${BOLD}Enter storage name to use:${NC} "
    read -r VPS_STORAGE
  fi

  echo ""
  echo -e " Select which templates to create:"
  echo ""
  multi_select "VM Templates" \
    ubuntu22 "Ubuntu 22.04 LTS  (ID 9001) -- recommended" \
    ubuntu24 "Ubuntu 24.04 LTS  (ID 9002)" \
    debian12 "Debian 12 Bookworm (ID 9003)" \
    rocky9   "Rocky Linux 9     (ID 9004)"

  [[ ${#SELECTED_ITEMS[@]} -eq 0 ]] && { p_warning "Nothing selected."; echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }

  local total=${#SELECTED_ITEMS[@]}
  steps_init $total

  for OS_KEY in "${SELECTED_ITEMS[@]}"; do
    local VMID="${_VPS_TMPL_ID[$OS_KEY]}"
    local URL="${_VPS_TMPL_URL[$OS_KEY]}"
    local FILE="${_VPS_TMPL_FILE[$OS_KEY]}"
    local IMG_PATH="$IMG_DIR/$FILE"

    step_n "Building $OS_KEY template (VM $VMID)"

    if qm status "$VMID" &>/dev/null 2>&1; then
      p_warning "VM $VMID already exists -- skipping"
      continue
    fi

    # Download
    if [[ -f "$IMG_PATH" ]]; then
      detail "Image already downloaded: $FILE"
    else
      spinner_start "Downloading $OS_KEY image..."
      wget -q -O "$IMG_PATH" "$URL"
      spinner_stop
      p_success "Downloaded: $FILE ($(du -sh "$IMG_PATH" | cut -f1))"
    fi

    # Inject guest agent
    if command -v virt-customize &>/dev/null; then
      spinner_start "Injecting qemu-guest-agent..."
      virt-customize -a "$IMG_PATH" \
        --install qemu-guest-agent \
        --truncate /etc/machine-id \
        --run-command 'systemctl enable qemu-guest-agent' \
        --quiet 2>/dev/null || true
      spinner_stop
      p_success "Guest agent injected"
    else
      p_warning "virt-customize not found -- install libguestfs-tools for guest agent injection"
    fi

    # Create VM + import disk
    spinner_start "Creating VM $VMID..."
    qm create "$VMID" \
      --name "${OS_KEY}-template" \
      --memory 1024 --balloon 512 --cores 1 \
      --cpu host --net0 "virtio,bridge=${VPS_BRIDGE}" \
      --ostype l26 --agent enabled=1 --onboot 0 --tablet 0

    qm importdisk "$VMID" "$IMG_PATH" "$VPS_STORAGE" --format qcow2 > /dev/null

    qm set "$VMID" \
      --scsihw virtio-scsi-pci \
      --scsi0 "${VPS_STORAGE}:vm-${VMID}-disk-0,discard=on,iothread=1" \
      --ide2  "${VPS_STORAGE}:cloudinit" \
      --boot  "order=scsi0" \
      --serial0 socket --vga serial0 \
      --ipconfig0 ip=dhcp \
      --nameserver "$VPS_DNS" \
      --searchdomain local

    qm template "$VMID"
    spinner_stop
    p_success "Template $VMID ($OS_KEY) is READY"
  done

  echo ""

  output "Templates available:"
  qm list 2>/dev/null | grep -E "90(0[1-4])" || true
  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

# ================================================================
# 3 -- PROVISION VPS
# ================================================================
vps_provision() {
  _require_proxmox
  print_brake 70
  output "[>>] Provision New Client VPS"
  print_brake 70
  echo ""

  # -- Collect inputs -------------------------------------------
  echo ""
  printf " ${CYAN_B}>${NC} ${BOLD}VM ID         (e.g. 201):${NC} "; read -r VMID
  printf " ${CYAN_B}>${NC} ${BOLD}Hostname      (e.g. rahul-vps):${NC} "; read -r VHOSTNAME
  printf " ${CYAN_B}>${NC} ${BOLD}IP Address    (e.g. 165.101.251.81):${NC} "; read -r VIP

  echo ""
  echo -e " ${BOLD}Plan:${NC}"
  
  
  
  
  
  
  
  
  
  echo ""
  printf " ${CYAN_B}>${NC} ${BOLD}Plan [1-9]:${NC} "; read -r PLAN_CHOICE

  case "$PLAN_CHOICE" in
    1) VRAM=2;  VDISK=50  ;;
    2) VRAM=4;  VDISK=80  ;;
    3) VRAM=8;  VDISK=100 ;;
    4) VRAM=16; VDISK=150 ;;
    5) VRAM=24; VDISK=200 ;;
    6) VRAM=32; VDISK=300 ;;
    7) VRAM=48; VDISK=350 ;;
    8) VRAM=64; VDISK=400 ;;
    9)
      printf " ${CYAN_B}>${NC} RAM GB: "; read -r VRAM
      printf " ${CYAN_B}>${NC} Disk GB: "; read -r VDISK
      ;;
    *) p_warning "Invalid plan"; echo -n "* Press ENTER to continue..."; read -r _; echo ""; return ;;
  esac

  echo ""
  echo -e " ${BOLD}OS:${NC}"
  
  
  
  
  printf " ${CYAN_B}>${NC} ${BOLD}OS [1-4]:${NC} "; read -r OS_CHOICE
  case "$OS_CHOICE" in
    1) VOS="ubuntu22" ;;
    2) VOS="ubuntu24" ;;
    3) VOS="debian12" ;;
    4) VOS="rocky9"   ;;
    *) VOS="ubuntu22" ;;
  esac

  echo ""
  printf " ${CYAN_B}>${NC} ${BOLD}Password for VM (or leave blank to auto-generate):${NC} "
  read -r VPASS
  [[ -z "$VPASS" ]] && VPASS=$(openssl rand -base64 12)

  local VMID_N="${_VPS_TMPL_ID[$VOS]}"
  local VM_USER="${_VPS_TMPL_USER[$VOS]}"
  local RAM_MB=$(( VRAM * 1024 ))
  local BALLOON=$(( RAM_MB / 2 ))

  # -- Validate -------------------------------------------------
  [[ ! "$VMID" =~ ^[0-9]+$ ]] && { error "VMID must be a number"; }
  qm status "$VMID" &>/dev/null 2>&1  && { error "VM $VMID already exists!"; }
  ! qm status "$VMID_N" &>/dev/null 2>&1 && { error "Template $VMID_N not found -- run Template Builder first"; }

  # -- Confirm --------------------------------------------------
  echo ""
  echo -e " ${GREEN_B}${BOX_TL}$(_rep "${BOX_H}" $_W)${BOX_TR}${NC}"
  printf " ${GREEN_B}${BOX_V}${NC}  ${BOLD}%-20s${NC} %-36s ${GREEN_B}${BOX_V}${NC}\n" "VM ID:"      "$VMID"
  printf " ${GREEN_B}${BOX_V}${NC}  ${BOLD}%-20s${NC} %-36s ${GREEN_B}${BOX_V}${NC}\n" "Hostname:"   "$VHOSTNAME"
  printf " ${GREEN_B}${BOX_V}${NC}  ${BOLD}%-20s${NC} %-36s ${GREEN_B}${BOX_V}${NC}\n" "OS:"         "$VOS (template $VMID_N)"
  printf " ${GREEN_B}${BOX_V}${NC}  ${BOLD}%-20s${NC} %-36s ${GREEN_B}${BOX_V}${NC}\n" "RAM / Disk:" "${VRAM}GB / ${VDISK}GB"
  printf " ${GREEN_B}${BOX_V}${NC}  ${BOLD}%-20s${NC} %-36s ${GREEN_B}${BOX_V}${NC}\n" "IP:"         "${VIP}${VPS_NETMASK}"
  printf " ${GREEN_B}${BOX_V}${NC}  ${BOLD}%-20s${NC} %-36s ${GREEN_B}${BOX_V}${NC}\n" "SSH User:"   "$VM_USER"
  printf " ${GREEN_B}${BOX_V}${NC}  ${BOLD}%-20s${NC} %-36s ${GREEN_B}${BOX_V}${NC}\n" "Password:"   "$VPASS"
  echo -e " ${GREEN_B}${BOX_BL}$(_rep "${BOX_H}" $_W)${BOX_BR}${NC}"
  echo ""
  { echo -n "* Create this VPS now? [y/N]: "; read -r _c; [[ "$_c" =~ ^[Yy] ]]; } || { echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }

  steps_init 5
  local T_START=$(date +%s)

  step_n "Cloning template $VMID_N -> VM $VMID"
  spinner_start "Cloning..."
  qm clone "$VMID_N" "$VMID" --name "$VHOSTNAME" --full true \
    --storage "$VPS_STORAGE" --format qcow2
  spinner_stop; p_success "Cloned"

  step_n "Setting CPU & RAM"
  qm set "$VMID" --cores 4 --vcpus 4 --cpu host \
    --memory "$RAM_MB" --balloon "$BALLOON"
  p_success "${VRAM}GB RAM configured"

  step_n "Resizing disk to ${VDISK}GB"
  spinner_start "Resizing..."
  qm resize "$VMID" scsi0 "${VDISK}G"
  spinner_stop; p_success "Disk resized"

  step_n "Cloud-init network & credentials"
  qm set "$VMID" \
    --ipconfig0  "ip=${VIP}${VPS_NETMASK},gw=${VPS_GATEWAY}" \
    --nameserver "$VPS_DNS" \
    --ciuser     "$VM_USER" \
    --cipassword "$VPASS" \
    --citype     nocloud \
    --onboot 1 --agent enabled=1 \
    --description "Client: $VHOSTNAME | IP: $VIP | OS: $VOS | Created: $(date '+%Y-%m-%d')"
  p_success "Network and credentials set"

  step_n "Starting VM"
  qm start "$VMID"
  p_success "VM started"

  # Wait for boot
  echo ""
  printf " ${DIM}Waiting for cloud-init boot"
  for i in $(seq 1 18); do sleep 5; printf "."; done
  echo "${NC}"

  local T_END=$(date +%s)
  local ELAPSED=$(( T_END - T_START ))
  echo "$(date '+%Y-%m-%d %H:%M:%S')  CREATED VMID=$VMID HOSTNAME=$VHOSTNAME IP=$VIP OS=$VOS RAM=${VRAM}GB DISK=${VDISK}GB TIME=${ELAPSED}s" \
    >> "$VPS_PROV_LOG"

  # -- Client credentials card ----------------------------------
  echo ""
  print_brake 70
  p_success "VPS READY -- SEND TO CLIENT"
  print_brake 70
  output ""
  output "Hostname    : $VHOSTNAME"
  output "IP Address  : $VIP"
  output "SSH Command : ssh ${VM_USER}@${VIP}"
  output "Username    : $VM_USER"
  output "Password    : $VPASS"
  output "OS          : $VOS"
  output "RAM / Disk  : ${VRAM}GB / ${VDISK}GB NVMe ZFS"
  output "Provisioned : ${ELAPSED}s"
  print_brake 70
  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

# ================================================================
# 4 -- LIST VMs
# ================================================================
vps_list() {
  _require_proxmox
  print_brake 70
  output "[LOG] All VMs -- Status Overview"
  print_brake 70
  echo ""

  echo ""
  printf " ${CYAN_B}%-8s %-22s %-12s %-10s %-10s${NC}\n" \
    "VM ID" "Name" "Status" "RAM(MB)" "IP"

  while IFS= read -r line; do
    local VMID NAME STATUS MEM
    VMID=$(echo "$line" | awk '{print $1}')
    NAME=$(echo "$line" | awk '{print $2}')
    STATUS=$(echo "$line" | awk '{print $3}')
    MEM=$(echo "$line" | awk '{print $4}')

    # Get IP from description or guest agent
    local IP="--"
    IP=$(qm config "$VMID" 2>/dev/null | grep -oP '(?<=ip=)[0-9.]+' | head -1 || echo "--")

    local STATUS_CLR="$DIM"
    [[ "$STATUS" == "running" ]] && STATUS_CLR="$GREEN_B"
    [[ "$STATUS" == "stopped" ]] && STATUS_CLR="$RED"

    printf " %-8s %-22s ${STATUS_CLR}%-12s${NC} %-10s %-10s\n" \
      "$VMID" "$NAME" "$STATUS" "$MEM" "$IP"
  done < <(qm list 2>/dev/null | grep -v VMID | grep -v "template")

  echo ""

  output "$(qm list 2>/dev/null | grep -c " running " || echo 0) running VMs"
  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

# ================================================================
# 5 -- DELETE VPS
# ================================================================
vps_delete() {
  _require_proxmox
  print_brake 70
  output "[DEL]  Delete VPS"
  print_brake 70
  echo ""

  vps_list

  echo ""
  printf " ${CYAN_B}>${NC} ${BOLD}VM ID to delete (0 to cancel):${NC} "
  read -r DEL_ID
  [[ "$DEL_ID" == "0" || -z "$DEL_ID" ]] && return

  ! qm status "$DEL_ID" &>/dev/null 2>&1 && { p_warning "VM $DEL_ID not found."; echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }

  local DEL_NAME; DEL_NAME=$(qm config "$DEL_ID" 2>/dev/null | grep "^name:" | awk '{print $2}')

  echo ""
  echo -e " ${RED_B}[!]  WARNING: This will permanently destroy VM $DEL_ID ($DEL_NAME)${NC}"
  echo -e " ${RED_B}   All data will be lost. This cannot be undone.${NC}"
  echo ""
  { echo -n "* Confirm delete VM $DEL_ID ($DEL_NAME)? [y/N]: "; read -r _c; [[ "$_c" =~ ^[Yy] ]]; } || { echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }

  spinner_start "Stopping VM $DEL_ID..."
  qm stop "$DEL_ID" 2>/dev/null || true
  sleep 3
  spinner_stop

  spinner_start "Destroying VM $DEL_ID..."
  qm destroy "$DEL_ID" --purge 1
  spinner_stop

  p_success "VM $DEL_ID ($DEL_NAME) deleted and storage reclaimed"
  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

# ================================================================
# 6 -- LIVE RESOURCE USAGE
# ================================================================
vps_resources() {
  _require_proxmox
  print_brake 70
  output "[MON] Live Resource Usage"
  print_brake 70
  echo ""

  # -- RAM ------------------------------------------------------
  local TOTAL USED AVAIL PCT
  TOTAL=$(free -m | awk '/^Mem:/{print $2}')
  USED=$(free -m  | awk '/^Mem:/{print $3}')
  AVAIL=$(free -m | awk '/^Mem:/{print $7}')
  PCT=$(( USED * 100 / TOTAL ))

  local BAR_FILL=$(( PCT * 40 / 100 ))
  local BAR="${GREEN_B}$(_rep "#" "$BAR_FILL")${DIM}$(_rep "." "$(( 40 - BAR_FILL  ))")${NC}"

  echo ""
  echo -e " ${BOLD}RAM${NC}"
  printf "  %b  ${BOLD}%d%%${NC} used  (${USED}MB / ${TOTAL}MB * ${AVAIL}MB free)\n" "$BAR" "$PCT"

  # -- CPU ------------------------------------------------------
  LOAD15=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $3}' | tr -d ' ')
  local NCPU; NCPU=$(nproc)
  local CPU_PCT; CPU_PCT=$(echo "$LOAD15 $NCPU" | awk '{printf "%d", ($1/$2)*100}')
  local CBAR_FILL=$(( CPU_PCT * 40 / 100 ))
  local CBAR="${CYAN_B}$(_rep "#" "$CBAR_FILL")${DIM}$(_rep "." "$(( 40 - CBAR_FILL  ))")${NC}"

  echo ""
  echo -e " ${BOLD}CPU${NC} (${NCPU} vCPU)"
  printf "  %b  ${BOLD}%d%%${NC} (15-min load: %s)\n" "$CBAR" "$CPU_PCT" "$LOAD15"

  # -- ZFS ------------------------------------------------------
  echo ""
  echo -e " ${BOLD}ZFS -- $VPS_STORAGE${NC}"
  if command -v zpool &>/dev/null && zpool list "$VPS_STORAGE" &>/dev/null; then
    local ZFS_HEALTH ZFS_ALLOC ZFS_FREE ZFS_CAP ZFS_FRAG
    ZFS_HEALTH=$(zpool list -H -o health "$VPS_STORAGE")
    ZFS_ALLOC=$(zpool list -H -o alloc "$VPS_STORAGE")
    ZFS_FREE=$(zpool list -H -o free "$VPS_STORAGE")
    ZFS_CAP=$(zpool list -H -o cap "$VPS_STORAGE" | tr -d '%')
    ZFS_FRAG=$(zpool list -H -o frag "$VPS_STORAGE")
    local HEALTH_CLR="$GREEN_B"
    [[ "$ZFS_HEALTH" != "ONLINE" ]] && HEALTH_CLR="$RED_B"
    printf "  Health: ${HEALTH_CLR}%s${NC}   Used: %s   Free: %s   Frag: %s   Cap: %s%%\n" \
      "$ZFS_HEALTH" "$ZFS_ALLOC" "$ZFS_FREE" "$ZFS_FRAG" "$ZFS_CAP"
  else
    detail "ZFS pool '$VPS_STORAGE' not found"
  fi

  # -- Per-VM RAM usage -----------------------------------------
  echo ""
  echo -e " ${BOLD}Per-VM RAM (running only)${NC}"

  qm list 2>/dev/null | grep " running " | grep -v VMID | while read -r line; do
    local VID VNAME VRAM_MB
    VID=$(echo "$line" | awk '{print $1}')
    VNAME=$(echo "$line" | awk '{print $2}')
    VRAM_MB=$(echo "$line" | awk '{print $4}')
    printf "  VM %-6s %-22s ${WHITE}%s MB${NC}\n" "$VID" "$VNAME" "$VRAM_MB"
  done

  # -- Disk usage -----------------------------------------------
  echo ""
  echo -e " ${BOLD}Disk Usage${NC}"

  df -h --output=source,size,used,avail,pcent,target 2>/dev/null | tail -n +2 | \
  while IFS= read -r line; do
    local PCT_D; PCT_D=$(echo "$line" | awk '{print $5}' | tr -d '%')
    local MNT; MNT=$(echo "$line" | awk '{print $6}')
    [[ "$MNT" == /snap/* || "$MNT" == /sys/* || "$MNT" == /proc/* ]] && continue
    local CLR="$NC"
    [[ ${PCT_D:-0} -ge 90 ]] && CLR="$RED_B"
    [[ ${PCT_D:-0} -ge 75 && ${PCT_D:-0} -lt 90 ]] && CLR="$YELLOW"
    printf "  ${CLR}%s${NC}\n" "$line"
  done

  echo ""
  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}
