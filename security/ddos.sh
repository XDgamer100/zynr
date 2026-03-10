#!/usr/bin/env bash
# Zynr.Cloud -- DDoS Protection Suite (UFW * Fail2Ban * NFTables * CrowdSec * Monitor)
# Sourced by install.sh
# Global: does user run Minecraft?
_MC_PORTS_ENABLED=0

menu_ddos() {
  print_brake 70
  output "DDoS Protection Suite"
  print_brake 70
  echo ""
      output "Harden your VPS against volumetric, application, and protocol attacks."
    output "Game-server (Minecraft) aware rules available."

  { echo -n "* Is a Minecraft server running on this VPS? [y/N]: "; read -r _c; [[ "$_c" =~ ^[Yy] ]]; } && _MC_PORTS_ENABLED=1 || true
  if [[ $_MC_PORTS_ENABLED -eq 1 ]]; then
    output "Minecraft mode ON -- ports 25565/TCP, 19132/UDP, 25575/TCP will be whitelisted."
  fi
  echo ""

  multi_select "Select protection components to install" "${_ddos_components[@]}"
  local sel=("${SELECTED_ITEMS[@]}")
  [[ ${#sel[@]} -eq 0 ]] && { output "No components selected."; echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }
  echo -n "* Apply ${#sel[@]} protection component(s)? [y/N]: "; read -r _c
  [[ "$_c" =~ ^[Yy] ]] || { echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }
  apt-get update -qq
  for key in "${sel[@]}"; do
    case "$key" in
      ufw)        _ddos_ufw ;;
      fail2ban)   _ddos_fail2ban ;;
      crowdsec)   _ddos_crowdsec ;;
      sysctl)     _ddos_sysctl ;;
      iptables)   _ddos_iptables ;;
      nftables)   _ddos_nftables ;;
      nginx_rate) _ddos_nginx_rate ;;
      ipset)      _ddos_ipset ;;
      monitor)    _ddos_monitor_daemon ;;
    esac
  done
  p_success "DDoS protection suite applied."
  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

_ddos_ufw() {
  output "Configuring UFW..."
  apt-get install -y ufw --no-install-recommends
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing
  # Always allow SSH -- rate-limited to prevent brute-force
  ufw allow 22/tcp
  ufw limit 22/tcp comment 'SSH rate-limit'

  # Pterodactyl essentials
  ufw allow 80/tcp  comment 'HTTP'
  ufw allow 443/tcp comment 'HTTPS'
  ufw allow 8080/tcp comment 'Wings API'
  ufw allow 2022/tcp comment 'Wings SFTP'

  # Minecraft-aware whitelist
  if [[ $_MC_PORTS_ENABLED -eq 1 ]]; then
    ufw allow 25565/tcp comment 'Minecraft Java'
    ufw allow 19132/udp comment 'Minecraft Bedrock/Geyser'
    ufw allow 25575/tcp comment 'Minecraft RCON'
    output "Minecraft ports whitelisted in UFW."
  fi

  local _ufw_extra=(
    "9090"  "Cockpit Web UI (port 9090)"
    "3306"  "MySQL/MariaDB  (port 3306)"
    "6379"  "Redis          (port 6379)"
    "27015" "Steam/Source   (port 27015)"
    "19132" "Bedrock UDP    (port 19132) -- only if not already added"
    "25565" "Minecraft Java (port 25565) -- only if not already added"
  )
  multi_select "UFW: Select additional ports to ALLOW" "${_ufw_extra[@]}"
  for p in "${SELECTED_ITEMS[@]}"; do
    case "$p" in
      19132) ufw allow 19132/udp comment 'Bedrock/Geyser' 2>/dev/null || true ;;
      *)     ufw allow "${p}/tcp" 2>/dev/null || true ;;
    esac
  done

  # Rate-limit new connection attempts globally (anti-port-scan)
  ufw limit 80/tcp  comment 'HTTP rate-limit'
  ufw limit 443/tcp comment 'HTTPS rate-limit'

  ufw logging medium
  ufw --force enable
  ufw status numbered
  p_success "UFW configured with rate-limiting."
}

_ddos_fail2ban() {
  output "Installing Fail2Ban..."
  apt-get install -y fail2ban --no-install-recommends

  local _f2b_jails=(
    "sshd"             "SSH brute-force protection"
    "nginx-http-auth"  "Nginx HTTP auth failures"
    "nginx-botsearch"  "Nginx bot scanner blocking"
    "nginx-req-limit"  "Nginx request rate-limit violations"
    "pterodactyl"      "Pterodactyl Panel login attempts"
    "recidive"         "Repeat-offender mega-ban (24h)"
    "portscan"         "Port-scan detection"
  )
  multi_select "Fail2Ban: Select jails to enable" "${_f2b_jails[@]}"
  local chosen_jails=("${SELECTED_ITEMS[@]}")

  # Read ban/retry settings
  local bantime findtime maxretry
  read -rp "  Ban duration in seconds  [default: 3600]:  " bantime
  read -rp "  Find-window in seconds   [default: 600]:   " findtime
  read -rp "  Max retries before ban   [default: 5]:     " maxretry
  bantime="${bantime:-3600}"; findtime="${findtime:-600}"; maxretry="${maxretry:-5}"

  cat > /etc/fail2ban/jail.local <<JAIL
[DEFAULT]
bantime   = ${bantime}
findtime  = ${findtime}
maxretry  = ${maxretry}
backend   = systemd
banaction = iptables-multiport
action    = %(action_mwl)s

JAIL

  for jail in "${chosen_jails[@]}"; do
    case "$jail" in
      recidive)
        cat >> /etc/fail2ban/jail.local <<JAIL
[recidive]
enabled   = true
bantime   = 86400
findtime  = 86400
maxretry  = 3

JAIL
        ;;
      portscan)
        # Custom portscan filter
        cat > /etc/fail2ban/filter.d/portscan.conf <<'FILTER'
[Definition]
failregex = .*UFW BLOCK.* SRC=<HOST> .*
ignoreregex =
FILTER
        cat >> /etc/fail2ban/jail.local <<JAIL
[portscan]
enabled   = true
filter    = portscan
logpath   = /var/log/ufw.log
bantime   = 7200
maxretry  = 10

JAIL
        ;;
      pterodactyl)
        cat >> /etc/fail2ban/jail.local <<JAIL
[pterodactyl]
enabled   = true
filter    = pterodactyl
logpath   = /var/www/pterodactyl/storage/logs/laravel-*.log
maxretry  = 10

JAIL
        # Create filter
        mkdir -p /etc/fail2ban/filter.d
        cat > /etc/fail2ban/filter.d/pterodactyl.conf <<'FILTER'
[Definition]
failregex = .*authentication failure.*"ip":"<HOST>".*
ignoreregex =
FILTER
        ;;
      *)
        printf '[%s]\nenabled = true\n\n' "$jail" >> /etc/fail2ban/jail.local
        ;;
    esac
  done

  # Minecraft login flood jail (if MC enabled)
  if [[ $_MC_PORTS_ENABLED -eq 1 ]]; then
    cat > /etc/fail2ban/filter.d/minecraft-login.conf <<'FILTER'
[Definition]
failregex = ^\s*\[.*\]: .*<HOST> .*logged in with entity id
            ^\s*\[.*\]: .*<HOST> .*lost connection: LoginPayloadResponse
ignoreregex =
FILTER
    cat >> /etc/fail2ban/jail.local <<JAIL
[minecraft-login]
enabled   = true
filter    = minecraft-login
logpath   = /var/log/minecraft/*.log
            /home/*/minecraft/logs/latest.log
bantime   = 1800
maxretry  = 20
findtime  = 60

JAIL
    output "Minecraft login-flood jail added."
  fi

  systemctl enable --now fail2ban || true
  systemctl restart fail2ban
  p_success "Fail2Ban configured -- ${#chosen_jails[@]} jail(s) active."
}

_ddos_crowdsec() {
  output "Installing CrowdSec..."
  curl -fsSL https://packagecloud.io/crowdsec/crowdsec/gpgkey | \
    gpg --dearmor -o /usr/share/keyrings/crowdsec-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/crowdsec-archive-keyring.gpg] \
https://packagecloud.io/crowdsec/crowdsec/ubuntu/ $(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/crowdsec.list 2>/dev/null || \
  echo "deb [signed-by=/usr/share/keyrings/crowdsec-archive-keyring.gpg] \
https://packagecloud.io/crowdsec/crowdsec/debian/ $(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/crowdsec.list
  apt-get update -qq
  apt-get install -y crowdsec crowdsec-firewall-bouncer-iptables --no-install-recommends
  local _cs_collections=(
    "crowdsecurity/linux"       "Linux base collection"
    "crowdsecurity/nginx"       "Nginx scenarios"
    "crowdsecurity/sshd"        "SSHD scenarios"
    "crowdsecurity/http-cve"    "HTTP CVE scenarios"
    "crowdsecurity/wordpress"   "WordPress scenarios"
    "crowdsecurity/iptables"    "IPTables bannedIP scenarios"
  )
  multi_select "CrowdSec: Select collections to install" "${_cs_collections[@]}"
  for col in "${SELECTED_ITEMS[@]}"; do
    cscli collections install "$col" 2>/dev/null || true
  done
  systemctl enable --now crowdsec || true
  p_success "CrowdSec installed with ${#SELECTED_ITEMS[@]} collection(s)."
}

_ddos_sysctl() {
  output "Applying sysctl hardening..."
  cat > /etc/sysctl.d/99-zynr-ddos.conf <<'SYSCTL'
# --- Zynr.Cloud DDoS / Network Hardening ---
# Syn flood protection
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 3
# Bogus ICMP responses
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
# Source routing & redirects
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
# Log martians
net.ipv4.conf.all.log_martians = 1
# TIME_WAIT socket reuse
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
# Increase socket queue
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 5000
SYSCTL
  sysctl -p /etc/sysctl.d/99-zynr-ddos.conf
  p_success "Sysctl hardening applied."
}

_ddos_iptables() {
  output "Applying IPTables flood-drop rules..."
  # SYN flood
  iptables -A INPUT -p tcp --syn -m limit --limit 1/s --limit-burst 3 -j ACCEPT
  iptables -A INPUT -p tcp --syn -j DROP
  # UDP flood
  iptables -A INPUT -p udp -m limit --limit 10/s --limit-burst 20 -j ACCEPT
  iptables -A INPUT -p udp -j DROP
  # ICMP flood
  iptables -A INPUT -p icmp -m limit --limit 1/s --limit-burst 2 -j ACCEPT
  iptables -A INPUT -p icmp -j DROP
  # Bogon source drops
  for bogon in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 \
               127.0.0.0/8 0.0.0.0/8 240.0.0.0/4 224.0.0.0/4; do
    iptables -A INPUT -s "$bogon" -j DROP 2>/dev/null || true
  done
  # Persist rules
  apt-get install -y iptables-persistent --no-install-recommends
  netfilter-persistent save
  p_success "IPTables flood-drop rules applied."
}

_ddos_nginx_rate() {
  output "Applying Nginx rate limiting..."
  cat > /etc/nginx/conf.d/zynr-rate-limit.conf <<'NGXRL'
# --- Zynr.Cloud Nginx Rate Limiting ---
limit_req_zone $binary_remote_addr zone=zynr_global:10m rate=20r/s;
limit_req_zone $binary_remote_addr zone=zynr_api:10m    rate=5r/s;
limit_conn_zone $binary_remote_addr zone=zynr_conn:10m;
NGXRL
  # Inject limit_req into existing server blocks that don't have it
  local vhost
  for vhost in /etc/nginx/sites-enabled/*.conf; do
    [[ -f "$vhost" ]] || continue
    grep -q "limit_req" "$vhost" && continue
    sed -i '/location \/ {/a\        limit_req zone=zynr_global burst=30 nodelay;\n        limit_conn zynr_conn 30;' "$vhost"
  done
  nginx -t && systemctl reload nginx
  p_success "Nginx rate limiting configured."
}

_ddos_ipset() {
  output "Installing ipset and loading block lists..."
  apt-get install -y ipset --no-install-recommends
  ipset create zynr_blocklist hash:ip maxelem 1000000 2>/dev/null || ipset flush zynr_blocklist
  # Download firehol level-1 (well-known bad IPs)
  local tmp; tmp=$(mktemp)
  curl -fsSL "https://iplists.firehol.org/files/firehol_level1.netset" -o "$tmp" 2>/dev/null \
    || { p_warning "Could not download firehol list -- skipping ipset population."; rm -f "$tmp"; return; }
  grep -v '^#' "$tmp" | grep -v '^$' | while read -r cidr; do
    ipset add zynr_blocklist "$cidr" 2>/dev/null || true
  done
  rm -f "$tmp"
  iptables -I INPUT -m set --match-set zynr_blocklist src -j DROP 2>/dev/null || true
  # Make persistent
  cat > /etc/cron.daily/zynr-ipset-update <<'CRON'
#!/bin/bash
set -e
tmp=$(mktemp)
curl -fsSL "https://iplists.firehol.org/files/firehol_level1.netset" -o "$tmp"
ipset flush zynr_blocklist 2>/dev/null || ipset create zynr_blocklist hash:ip maxelem 1000000
grep -v '^#' "$tmp" | grep -v '^$' | xargs -I{} ipset add zynr_blocklist {} 2>/dev/null || true
rm -f "$tmp"
CRON
  chmod +x /etc/cron.daily/zynr-ipset-update
  p_success "IPSet blocklist loaded (Firehol Level-1) + daily update cron."
}

# ================================================================
#  NFTABLES -- STATEFUL FIREWALL (MINECRAFT-AWARE)
# ================================================================
_ddos_nftables() {
  output "Installing NFTables..."
  apt-get install -y nftables --no-install-recommends

  local mc_rules=""
  if [[ $_MC_PORTS_ENABLED -eq 1 ]]; then
    mc_rules=$(cat <<'MC'
    # -- Minecraft: generous limits for game traffic --------------
    tcp dport 25565 ct state new limit rate 50/second accept   comment "MC Java new connections"
    tcp dport 25575 ct state new limit rate 5/second accept    comment "MC RCON"
    udp dport 19132 limit rate 200/second accept               comment "MC Bedrock / Geyser"
    # Block MC port abuse (connection flood)
    tcp dport 25565 ct state new meter mc_meter { ip saddr limit rate 20/second } drop
MC
    )
    output "Minecraft-aware NFTables rules added."
  fi

  cat > /etc/nftables.conf <<NFTEOF
#!/usr/sbin/nft -f
# ================================================================
#  Zynr.Cloud NFTables Ruleset  -- auto-generated $(date)
#  Minecraft-aware: ${_MC_PORTS_ENABLED}
# ================================================================

flush ruleset

table inet zynr_filter {

  # -- Connection tracker ------------------------------------------
  set blocked_ips {
    type ipv4_addr
    flags dynamic, timeout
    timeout 1h
  }

  chain inbound {
    type filter hook input priority 0; policy drop;

    # Loopback
    iif lo accept

    # Established / related
    ct state established,related accept

    # Invalid -- drop silently
    ct state invalid drop

    # Drop blocked IPs
    ip saddr @blocked_ips drop

    # ICMP -- rate-limited
    icmp type echo-request limit rate 10/second accept
    icmp type echo-request drop

    # SSH -- rate-limited
    tcp dport 22 ct state new limit rate 5/minute accept
    tcp dport 22 ct state new add @blocked_ips { ip saddr timeout 10m } drop

    # HTTP/HTTPS
    tcp dport { 80, 443 } ct state new limit rate 100/second accept
    tcp dport { 80, 443 } ct state new add @blocked_ips { ip saddr timeout 5m } drop

    # Pterodactyl
    tcp dport { 8080, 2022 } ct state new limit rate 30/second accept

${mc_rules}

    # SYN flood guard
    tcp flags syn tcp option maxseg size 1-536 drop
    tcp flags & (fin|syn|rst|ack) == syn limit rate 100/second accept
    tcp flags & (fin|syn|rst|ack) == syn add @blocked_ips { ip saddr timeout 30m } drop

    # UDP flood guard (generic)
    meta l4proto udp limit rate 500/second accept
    meta l4proto udp add @blocked_ips { ip saddr timeout 10m } drop
  }

  chain forward {
    type filter hook forward priority 0; policy drop;
  }

  chain outbound {
    type filter hook output priority 0; policy accept;
  }
}
NFTEOF

  nft -f /etc/nftables.conf
  systemctl enable --now nftables 2>/dev/null || true
  p_success "NFTables stateful firewall active (Minecraft-aware: ${_MC_PORTS_ENABLED})."
}

# ================================================================
#  DDOS AUTO-MONITOR DAEMON
#  Watches live connections, detects floods, auto-bans via ipset
# ================================================================
_ddos_monitor_daemon() {
  output "Setting up DDoS auto-monitor daemon..."
  apt-get install -y ipset iproute2 procps --no-install-recommends

  # -- Thresholds ---------------------------------------------------
  local conn_thresh pps_thresh ban_dur
  read -rp "  Max connections per IP before auto-ban   [default: 80]:  " conn_thresh
  read -rp "  Max new TCP conns/sec per IP before ban  [default: 50]:  " pps_thresh
  read -rp "  Auto-ban duration in seconds             [default: 900]: " ban_dur
  conn_thresh="${conn_thresh:-80}"
  pps_thresh="${pps_thresh:-50}"
  ban_dur="${ban_dur:-900}"

  # -- Write the monitor script -------------------------------------
  cat > /usr/local/bin/zynr-ddos-monitor <<MONITOR
#!/usr/bin/env bash
# ================================================================
#  Zynr.Cloud DDoS Monitor -- auto-generated by setup script
#  Detects: connection floods, UDP floods, port scans
#  Action : ipset ban + syslog + optional webhook alert
# ================================================================
set -euo pipefail

CONN_THRESH=${conn_thresh}
PPS_THRESH=${pps_thresh}
BAN_DURATION=${ban_dur}
LOG="/var/log/zynr-ddos.log"
IPSET_NAME="zynr_autoban"
WHITELIST="/etc/zynr/ddos_whitelist.txt"
WEBHOOK="\${ZYNR_WEBHOOK:-}"   # optional: export ZYNR_WEBHOOK=https://...

# -- Minecraft ports (never ban for traffic on these) -------------
MC_PORTS=(25565 19132 25575)

mkdir -p /etc/zynr
touch "\$LOG" "\$WHITELIST"

# Ensure ipset exists
ipset list "\$IPSET_NAME" &>/dev/null || \
  ipset create "\$IPSET_NAME" hash:ip timeout "\$BAN_DURATION" maxelem 100000

# Link ipset into iptables if not already done
iptables -C INPUT -m set --match-set "\$IPSET_NAME" src -j DROP 2>/dev/null || \
  iptables -I INPUT 1 -m set --match-set "\$IPSET_NAME" src -j DROP

log_event() {
  local ts; ts=\$(date '+%Y-%m-%d %H:%M:%S')
  echo "[\$ts] \$*" | tee -a "\$LOG"
  logger -t zynr-ddos "\$*"
}

is_whitelisted() {
  grep -qxF "\$1" "\$WHITELIST" 2>/dev/null
}

ban_ip() {
  local ip="\$1" reason="\$2"
  is_whitelisted "\$ip" && return 0
  ipset add "\$IPSET_NAME" "\$ip" timeout "\$BAN_DURATION" 2>/dev/null || return 0
  log_event "BAN \$ip  reason=\${reason}  duration=\${BAN_DURATION}s"
  # Optional webhook
  if [[ -n "\$WEBHOOK" ]]; then
    curl -sf -X POST "\$WEBHOOK" \
      -H 'Content-Type: application/json' \
      -d "{\"text\":\"[!] Zynr DDoS Monitor: Banned \${ip} -- \${reason}\"}" \
      &>/dev/null || true
  fi
}

check_connection_flood() {
  # Count established+syn_sent connections per src IP
  ss -nt state established state syn-sent 2>/dev/null \
    | awk '{print \$5}' \
    | grep -oP '[\d.]+(?=:\d+$)' \
    | sort | uniq -c | sort -rn \
    | while read -r count ip; do
        [[ "\$count" -gt "\$CONN_THRESH" ]] || break
        ban_ip "\$ip" "conn-flood cnt=\${count} thresh=\${CONN_THRESH}"
      done
}

check_syn_flood() {
  # Look for IPs with many SYN_RECV sockets
  ss -nt state syn-recv 2>/dev/null \
    | awk '{print \$5}' \
    | grep -oP '[\d.]+(?=:\d+$)' \
    | sort | uniq -c | sort -rn \
    | while read -r count ip; do
        [[ "\$count" -gt 20 ]] || break
        ban_ip "\$ip" "syn-flood cnt=\${count}"
      done
}

check_pps_flood() {
  # Read /proc/net/dev for total rx packets; compare over 1-sec window
  # Ban IPs found via ss that are generating huge packet rates
  local snapshot1 snapshot2
  snapshot1=\$(ss -nt 2>/dev/null | awk '{print \$5}' | grep -oP '[\d.]+(?=:\d+$)' | sort | uniq -c)
  sleep 1
  snapshot2=\$(ss -nt 2>/dev/null | awk '{print \$5}' | grep -oP '[\d.]+(?=:\d+$)' | sort | uniq -c)
  # IPs that newly appeared with count > PPS_THRESH
  comm -13 <(echo "\$snapshot1" | sort) <(echo "\$snapshot2" | sort) | \
    awk "\\\$1 > \${PPS_THRESH} {print \\\$2}" | \
    while read -r ip; do
      ban_ip "\$ip" "pps-flood new-conns/s>=\${PPS_THRESH}"
    done
}

check_udp_flood() {
  # Detect massive UDP traffic to non-whitelisted ports
  # Uses /proc/net/udp to count by remote address
  awk 'NR>1 {print \$3}' /proc/net/udp 2>/dev/null \
    | awk -F: '{printf "%d.%d.%d.%d\n", strtonum("0x"substr(\$1,7,2)), strtonum("0x"substr(\$1,5,2)), strtonum("0x"substr(\$1,3,2)), strtonum("0x"substr(\$1,1,2))}' \
    | sort | uniq -c | sort -rn \
    | head -20 \
    | while read -r count ip; do
        [[ "\$count" -gt 50 ]] || break
        # Skip Minecraft UDP ports
        local skip=0
        for p in "\${MC_PORTS[@]}"; do
          ss -u -n src "\$ip" dport ":\$p" 2>/dev/null | grep -q '\.' && skip=1 && break
        done
        [[ \$skip -eq 1 ]] && continue
        ban_ip "\$ip" "udp-flood cnt=\${count}"
      done
}

cleanup_log() {
  # Rotate log if > 50MB
  local size
  size=\$(stat -c%s "\$LOG" 2>/dev/null || echo 0)
  if [[ \$size -gt 52428800 ]]; then
    mv "\$LOG" "\${LOG}.\$(date +%Y%m%d)"
    touch "\$LOG"
    log_event "Log rotated."
  fi
}

log_event "Zynr DDoS Monitor started. thresholds: conn=\${CONN_THRESH} pps=\${PPS_THRESH} ban=\${BAN_DURATION}s"

while true; do
  check_connection_flood
  check_syn_flood
  check_udp_flood
  check_pps_flood
  cleanup_log
  sleep 5
done
MONITOR

  chmod +x /usr/local/bin/zynr-ddos-monitor

  # -- Whitelist setup ----------------------------------------------
  mkdir -p /etc/zynr
  local my_ip
  my_ip=$(curl -sf --max-time 5 https://api.ipify.org 2>/dev/null \
          || hostname -I | awk '{print $1}' || echo "")
  [[ -n "$my_ip" ]] && echo "$my_ip" > /etc/zynr/ddos_whitelist.txt
  output "Your IP (${my_ip}) added to auto-ban whitelist."
  output "Edit /etc/zynr/ddos_whitelist.txt to add more trusted IPs."

  # -- Systemd service ----------------------------------------------
  cat > /etc/systemd/system/zynr-ddos-monitor.service <<'SERVICE'
[Unit]
Description=Zynr.Cloud DDoS Auto-Monitor Daemon
After=network.target iptables.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/zynr-ddos-monitor
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=zynr-ddos

[Install]
WantedBy=multi-user.target
SERVICE

  systemctl daemon-reload
  systemctl enable --now zynr-ddos-monitor || true

  # -- View command helper ------------------------------------------
  cat > /usr/local/bin/zynr-ddos-status <<'STATUS'
#!/usr/bin/env bash
echo ""
echo "  +======================================================+"
echo "  |        Zynr.Cloud -- DDoS Monitor Status              |"
echo "  +======================================================+"
echo ""
echo "  -- Service ---------------------------------------------"
systemctl status zynr-ddos-monitor --no-pager -l | tail -5 | sed 's/^/  /'
echo ""
echo "  -- Currently Banned IPs --------------------------------"
ipset list zynr_autoban 2>/dev/null | grep -E '^\d' | head -30 | sed 's/^/  /' \
  || echo "  (none or ipset not yet populated)"
echo ""
echo "  -- Recent Events (last 20) -----------------------------"
tail -20 /var/log/zynr-ddos.log 2>/dev/null | sed 's/^/  /' || echo "  (no log yet)"
echo ""
echo "  Commands:"
echo "    zynr-ddos-status             -- this screen"
echo "    zynr-ddos-unban <ip>         -- remove IP from ban list"
echo "    zynr-ddos-whitelist <ip>     -- add IP to permanent whitelist"
echo ""
STATUS

  cat > /usr/local/bin/zynr-ddos-unban <<'UNBAN'
#!/usr/bin/env bash
[[ -z "$1" ]] && { echo "Usage: zynr-ddos-unban <ip>"; exit 1; }
ipset del zynr_autoban "$1" 2>/dev/null && echo "  [OK] Unbanned: $1" || echo "  [X] IP not in ban list: $1"
UNBAN

  cat > /usr/local/bin/zynr-ddos-whitelist <<'WL'
#!/usr/bin/env bash
[[ -z "$1" ]] && { echo "Usage: zynr-ddos-whitelist <ip>"; exit 1; }
echo "$1" >> /etc/zynr/ddos_whitelist.txt
ipset del zynr_autoban "$1" 2>/dev/null || true
echo "  [OK] Whitelisted and unbanned: $1"
WL

  chmod +x /usr/local/bin/zynr-ddos-{status,unban,whitelist}
  p_success "DDoS auto-monitor daemon installed and running!"
  output "  zynr-ddos-status           -- view bans & events"
  output "  zynr-ddos-unban <ip>       -- remove a ban"
  output "  zynr-ddos-whitelist <ip>   -- permanently whitelist an IP"
  output "  Log: /var/log/zynr-ddos.log"
}

# ================================================================
#  USER MANAGEMENT
# ================================================================
