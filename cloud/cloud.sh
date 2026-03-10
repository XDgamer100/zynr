#!/usr/bin/env bash
# Zynr.Cloud -- Cloud Root Enabler (Azure * GCP * AWS * Hetzner * Vultr)
# Sourced by install.sh
#  Cloud VPS providers (Azure, GCP, DigitalOcean) disable root login
#  by default. This section enables it safely on VMs you own.
# ================================================================
menu_cloud_tools() {
  while true; do
    clear

    print_brake 70
    output "Zynr.Cloud -- Cloud Root Enabler"
    output ""
    output "Enable root SSH on cloud VPS providers (Azure, GCP, DigitalOcean)"
    output "that disable it by default."
    print_brake 70

    output ""
    output "[1] Enable Root SSH  (auto-detect provider)"
    output "[2] Enable Root SSH  (manual / any VPS)"
    output "[3] Harden SSH Config  (keys-only, disable password)"
    output "[4] Show current SSH status"
    output ""
    output "[0] Back"
    echo ""
    echo -n "* Input 0-4: "
    read -r c
    echo ""

    case "$c" in
      1) cloud_root_auto ;;
      2) cloud_root_manual ;;
      3) cloud_harden_ssh ;;
      4) cloud_ssh_status ;;
      0) return ;;
      *)
        echo -e "* ${COLOR_RED}ERROR${COLOR_NC}: Invalid option" 1>&2
        sleep 1 ;;
    esac
  done
}

# -- Detect which cloud provider we're on -------------------------
_detect_cloud_provider() {
  local dmi_vendor="" dmi_product="" provider="unknown" default_user="root"

  dmi_vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || echo "")
  dmi_product=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "")

  if curl -sf --max-time 2 -H "Metadata: true" \
       "http://169.254.169.254/metadata/instance?api-version=2021-02-01" \
       &>/dev/null; then
    provider="azure"; default_user="azureuser"
  elif curl -sf --max-time 2 \
       "http://metadata.google.internal/computeMetadata/v1/" \
       -H "Metadata-Flavor: Google" &>/dev/null; then
    provider="gcp"; default_user=$(whoami)
  elif curl -sf --max-time 2 \
       "http://169.254.169.254/latest/meta-data/instance-id" &>/dev/null; then
    provider="aws"; default_user="ubuntu"
  elif [[ "$dmi_vendor" == *"DigitalOcean"* ]]; then
    provider="digitalocean"; default_user="root"
  elif [[ "$dmi_product" == *"Hetzner"* ]] || \
       curl -sf --max-time 2 "http://169.254.169.254/hetzner/v1/metadata" &>/dev/null; then
    provider="hetzner"; default_user="root"
  elif [[ "$dmi_vendor" == *"Vultr"* ]]; then
    provider="vultr"; default_user="root"
  fi

  echo "${provider}:${default_user}"
}

cloud_root_auto() {
  print_brake 70
  output "Auto-Detect Cloud Provider -- Enable Root SSH"
  print_brake 70
  echo ""

  local detection; detection=$(_detect_cloud_provider)
  local provider="${detection%%:*}"
  local def_user="${detection##*:}"

  echo ""
  output "Detected provider : ${provider}"
    output "Default user      : ${def_user}"
  echo ""

  if [[ "$provider" == "unknown" ]]; then
    p_warning "Could not auto-detect provider. Using manual mode."
    cloud_root_manual; return
  fi

  _do_enable_root_ssh "$def_user" "$provider"
}

cloud_root_manual() {
  print_brake 70
  output "Enable Root SSH -- Manual"
  print_brake 70
  echo ""
  local cur_user provider
  read -rp "  Current (non-root) SSH username [e.g. azureuser, ubuntu]: " cur_user
  read -rp "  Provider label (azure/gcp/aws/other)                    : " provider
  [[ -z "$cur_user" ]] && { p_warning "Username required."; echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }
  _do_enable_root_ssh "$cur_user" "${provider:-manual}"
}

_do_enable_root_ssh() {
  local src_user="$1" provider="$2"

  print_brake 70
  output "Enabling Root SSH  [${provider}]"
  print_brake 70
  echo ""

  # -- 1. Set a root password ---------------------------------------
  echo ""
  output "Step 1/4 -- Set root password"
  echo -e "  ${YELLOW} [!]${NC}  Choose a ${BOLD}strong${NC} password. This will be the root SSH password."
  local rpass rpass2
  while true; do
    read -rsp "  New root password : " rpass; echo
    read -rsp "  Confirm password  : " rpass2; echo
    [[ "$rpass" == "$rpass2" ]] && [[ ${#rpass} -ge 8 ]] && break
    p_warning "Passwords don't match or too short (min 8 chars). Try again."
  done
  echo "root:${rpass}" | chpasswd
  p_success "Root password set."

  # -- 2. Copy authorized_keys from source user ---------------------
  output "Step 2/4 -- Copy SSH keys from ${src_user} -> root"
  local src_home; src_home=$(eval echo "~${src_user}" 2>/dev/null || echo "/home/${src_user}")
  local src_keys="${src_home}/.ssh/authorized_keys"

  if [[ -f "$src_keys" ]]; then
    mkdir -p /root/.ssh
    cp "$src_keys" /root/.ssh/authorized_keys
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/authorized_keys
    p_success "SSH authorized_keys copied from ${src_user}."
  else
    p_warning "No authorized_keys found for ${src_user}. You must add your public key manually:"
    p_warning "  echo 'YOUR_PUBKEY' >> /root/.ssh/authorized_keys"
  fi

  # -- 3. Patch sshd_config -----------------------------------------
  output "Step 3/4 -- Patching /etc/ssh/sshd_config"
  local sshd_cfg="/etc/ssh/sshd_config"
  cp "${sshd_cfg}" "${sshd_cfg}.zynr.bak"

  # Enable root login
  sed -i \
    -e 's/^#*\s*PermitRootLogin.*/PermitRootLogin yes/' \
    -e 's/^#*\s*PasswordAuthentication.*/PasswordAuthentication yes/' \
    "$sshd_cfg"

  # If lines didn't exist, add them
  grep -q "^PermitRootLogin"       "$sshd_cfg" || echo "PermitRootLogin yes"       >> "$sshd_cfg"
  grep -q "^PasswordAuthentication" "$sshd_cfg" || echo "PasswordAuthentication yes" >> "$sshd_cfg"

  # Cloud-provider-specific: remove AllowUsers/DenyUsers that block root
  if [[ "$provider" == "azure" ]]; then
    # Azure injects AllowUsers in /etc/ssh/sshd_config.d/
    local azure_override="/etc/ssh/sshd_config.d/50-cloud-init.conf"
    if [[ -f "$azure_override" ]]; then
      cp "$azure_override" "${azure_override}.zynr.bak"
      sed -i \
        -e 's/^PasswordAuthentication.*/PasswordAuthentication yes/' \
        -e '/^AllowUsers /d' \
        "$azure_override" 2>/dev/null || true
      output "Azure cloud-init SSH override patched."
    fi
    # Also check /etc/ssh/sshd_config.d/
    for f in /etc/ssh/sshd_config.d/*.conf; do
      [[ -f "$f" ]] || continue
      grep -q "AllowUsers" "$f" && \
        sed -i '/^AllowUsers /d' "$f" && \
        output "Removed AllowUsers from $(basename $f)"
    done
  fi

  if [[ "$provider" == "gcp" ]]; then
    # GCP uses google_authorized_keys -- add root to sudoers override
    local gcp_sshd="/etc/ssh/sshd_config.d/60-cloudconfig.conf"
    [[ -f "$gcp_sshd" ]] && {
      cp "$gcp_sshd" "${gcp_sshd}.zynr.bak"
      sed -i -e 's/^PermitRootLogin.*/PermitRootLogin yes/' "$gcp_sshd" 2>/dev/null || true
    }
    # Disable the GCP SSH metadata service that resets sshd_config
    systemctl disable --now google-guest-agent 2>/dev/null || true
    systemctl disable --now google-oslogin-cache.timer 2>/dev/null || true
    output "GCP guest agent disabled to prevent sshd_config reset."
  fi

  # Validate config before restart
  sshd -t || { p_warning "sshd_config test failed -- restoring backup."; \
    cp "${sshd_cfg}.zynr.bak" "$sshd_cfg"; error "SSH config validation failed."; }

  # -- 4. Restart SSH -----------------------------------------------
  output "Step 4/4 -- Restarting SSH daemon"
  systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
  p_success "SSH daemon restarted."

  # -- Summary ------------------------------------------------------
  local my_ip; my_ip=$(curl -sf --max-time 3 https://api.ipify.org || hostname -I | awk '{print $1}')
  echo ""
  p_success "Root SSH Enabled Successfully!"
  printf  "  ${GREEN_B}|${NC}  %-22s ${CYAN_B}%-32s${NC}${GREEN_B}|${NC}\n" "[WEB]  Server IP"     "${my_ip}"
  printf  "  ${GREEN_B}|${NC}  %-22s ${WHITE}%-32s${NC}${GREEN_B}|${NC}\n"  "[USR]  Username"      "root"
  printf  "  ${GREEN_B}|${NC}  %-22s ${WHITE}%-32s${NC}${GREEN_B}|${NC}\n"  "[PRT]  Port"          "22"
  printf  "  ${GREEN_B}|${NC}  %-22s ${WHITE}%-32s${NC}${GREEN_B}|${NC}\n"  "[KEY]  Auth"          "Password + SSH Key"
  printf  "  ${GREEN_B}|${NC}  %-22s ${WHITE}%-32s${NC}${GREEN_B}|${NC}\n"  "[BAK]  SSH Backup"    "${sshd_cfg}.zynr.bak"
  output "Connect with:  ssh root@${my_ip}"
  echo ""
  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

cloud_harden_ssh() {
  print_brake 70
  output "Harden SSH -- Keys Only (Disable Password Auth)"
  print_brake 70
  echo ""
  p_warning "This disables password login. Ensure your SSH key works BEFORE confirming."
  local sshd_cfg="/etc/ssh/sshd_config"

  [[ -f /root/.ssh/authorized_keys ]] || \
    error "No /root/.ssh/authorized_keys found. Add your public key first or you will be locked out!"

  { echo -n "* Disable password auth and enforce keys-only login? [y/N]: "; read -r _c; [[ "$_c" =~ ^[Yy] ]]; } || { echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }

  cp "${sshd_cfg}" "${sshd_cfg}.zynr-harden.bak"

  sed -i \
    -e 's/^#*\s*PermitRootLogin.*/PermitRootLogin prohibit-password/' \
    -e 's/^#*\s*PasswordAuthentication.*/PasswordAuthentication no/' \
    -e 's/^#*\s*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' \
    -e 's/^#*\s*KerberosAuthentication.*/KerberosAuthentication no/' \
    -e 's/^#*\s*GSSAPIAuthentication.*/GSSAPIAuthentication no/' \
    -e 's/^#*\s*UsePAM.*/UsePAM yes/' \
    -e 's/^#*\s*MaxAuthTries.*/MaxAuthTries 3/' \
    -e 's/^#*\s*LoginGraceTime.*/LoginGraceTime 20/' \
    -e 's/^#*\s*X11Forwarding.*/X11Forwarding no/' \
    "$sshd_cfg"

  grep -q "^PermitRootLogin"           "$sshd_cfg" || echo "PermitRootLogin prohibit-password" >> "$sshd_cfg"
  grep -q "^PasswordAuthentication"    "$sshd_cfg" || echo "PasswordAuthentication no"          >> "$sshd_cfg"
  grep -q "^MaxAuthTries"              "$sshd_cfg" || echo "MaxAuthTries 3"                      >> "$sshd_cfg"

  # Patch drop-ins too
  for f in /etc/ssh/sshd_config.d/*.conf; do
    [[ -f "$f" ]] || continue
    sed -i -e 's/^PasswordAuthentication.*/PasswordAuthentication no/' "$f" 2>/dev/null || true
  done

  sshd -t || { p_warning "Config test failed -- restoring backup."; \
    cp "${sshd_cfg}.zynr-harden.bak" "$sshd_cfg"; error "SSH hardening failed."; }

  systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
  p_success "SSH hardened -- password auth disabled, keys-only."
  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

cloud_ssh_status() {
  print_brake 70
  output "SSH Status"
  print_brake 70
  echo ""
  output "-- sshd_config summary --"
  local cfg="/etc/ssh/sshd_config"
  local keys=("PermitRootLogin" "PasswordAuthentication" "PubkeyAuthentication"
               "MaxAuthTries" "LoginGraceTime" "Port" "ListenAddress")
  for k in "${keys[@]}"; do
    local val
    val=$(grep -E "^${k}" "$cfg" 2>/dev/null | tail -1 | awk '{print $2}' || echo "default")
    printf "  %-30s  ${CYAN_B}%s${NC}\n" "$k" "${val:-default}"
  done
  echo ""
  output "-- SSH drop-in configs (/etc/ssh/sshd_config.d/) --"
  ls /etc/ssh/sshd_config.d/*.conf 2>/dev/null | while read -r f; do
    output "$(basename $f)"
    grep -vE '^#|^$' "$f" | sed 's/^/    /'
  done || output "(none)"
  echo ""
  output "-- Active SSH sessions --"
  who | sed 's/^/  /' || true
  echo ""
  output "-- Authorized keys (root) --"
  if [[ -f /root/.ssh/authorized_keys ]]; then
    awk '{print "  " $3 "  " substr($0,1,40)"..."}' /root/.ssh/authorized_keys
  else
    p_warning "No authorized_keys for root"
  fi
  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

# ================================================================
#  ENTRY POINT
# ================================================================
require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    echo ""
    print_brake 70
    echo "* ERROR: ROOT REQUIRED"
    echo "* Please run: sudo bash $0"
    print_brake 70
    echo ""
    exit 1
  fi
}
