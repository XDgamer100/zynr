#!/usr/bin/env bash
# Zynr.Cloud -- Pterodactyl Panel & Wings install/update
# Sourced by install.sh
install_dependencies() {
  print_brake 70; output "System Dependencies"; print_brake 70; echo ""
  export DEBIAN_FRONTEND=noninteractive
  step "Updating package lists"
  apt-get update -y
  step "Installing base packages"
  apt-get install -y \
    curl wget git unzip tar jq bc \
    apt-transport-https ca-certificates \
    gnupg gnupg2 lsb-release certbot python3-certbot-nginx \
    nginx ufw openssl cron logrotate

  if ! php -v 2>/dev/null | grep -qE "8\.(1|2|3)"; then
    # Ubuntu 22.04/24.04: use Ondrej PPA (add-apt-repository method, reliable)
    # Debian 12/13: use packages.sury.org direct repo
    mkdir -p /etc/apt/keyrings
    if [[ "$OS" == "ubuntu" ]]; then
      step "Adding PHP PPA (ondrej/php) for Ubuntu ${OS_VER}"
      apt-get install -y software-properties-common 2>/dev/null || true
      LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
    else
      step "Adding PHP repository (Sury) for Debian ${OS_VER}"
      curl -fsSL https://packages.sury.org/php/apt.gpg \
        | gpg --dearmor -o /etc/apt/keyrings/sury-php.gpg
      echo "deb [signed-by=/etc/apt/keyrings/sury-php.gpg] https://packages.sury.org/php/ ${OS_CODENAME} main" \
        > /etc/apt/sources.list.d/sury-php.list
    fi
    apt-get update -y
  fi

  if   apt-cache show php8.3 &>/dev/null 2>&1; then PHP_VER="8.3"
  elif apt-cache show php8.2 &>/dev/null 2>&1; then PHP_VER="8.2"
  else                                               PHP_VER="8.1"
  fi
  export PHP_VER
  echo "PHP_VER=${PHP_VER}" > /etc/.ptero_env; chmod 644 /etc/.ptero_env
  step "Installing PHP ${PHP_VER}"
  apt-get install -y \
    "php${PHP_VER}" "php${PHP_VER}-cli" "php${PHP_VER}-fpm" \
    "php${PHP_VER}-mysql" "php${PHP_VER}-pgsql" "php${PHP_VER}-sqlite3" \
    "php${PHP_VER}-gd" "php${PHP_VER}-curl" "php${PHP_VER}-mbstring" \
    "php${PHP_VER}-xml" "php${PHP_VER}-zip" "php${PHP_VER}-bcmath" \
    "php${PHP_VER}-tokenizer" "php${PHP_VER}-intl" "php${PHP_VER}-readline"

  if ! command -v composer &>/dev/null; then
    step "Installing Composer"
    local expected actual
    expected="$(php -r 'copy("https://composer.github.io/installer.sig","php://stdout");')"
    php -r "copy('https://getcomposer.org/installer','/tmp/composer-setup.php');"
    actual="$(php -r "echo hash_file('sha384','/tmp/composer-setup.php');")"
    [[ "$expected" == "$actual" ]] || { rm -f /tmp/composer-setup.php; error "Composer checksum mismatch."; }
    php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer --quiet
    rm -f /tmp/composer-setup.php
  else
    output "Composer already present ($(composer --version 2>/dev/null | awk '{print $3}'))"
  fi

  step "Installing MariaDB & Redis"
  apt-get install -y mariadb-server mariadb-client
  # Redis: Ubuntu 24.04 ships valkey as drop-in replacement; fall back to redis-server
  if apt-cache show valkey-server &>/dev/null 2>&1; then
    apt-get install -y valkey-server
    systemctl enable --now mariadb || true
    systemctl enable --now valkey-server 2>/dev/null || true
    # Symlink service name for compatibility
    ln -sf /lib/systemd/system/valkey-server.service \
       /etc/systemd/system/redis-server.service 2>/dev/null || true
    systemctl daemon-reload
  else
    apt-get install -y redis-server
    systemctl enable --now mariadb redis-server
  fi
  p_success "Dependencies installed -- PHP ${PHP_VER}"
}

# ================================================================
#  SHARED: DOCKER
# ================================================================
install_docker() {
  if command -v docker &>/dev/null; then
    local dv; dv=$(docker --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "?")
    output "Docker already installed (v${dv}). Skipping."; return 0
  fi
  step "Installing Docker CE"
  export DEBIAN_FRONTEND=noninteractive
  local pkg
  for pkg in docker docker-engine docker.io containerd runc docker-doc docker-compose podman-docker; do
    apt-get remove -y "$pkg" 2>/dev/null || true
  done
  mkdir -p /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/${OS}/gpg" \
    | gpg --dearmor > /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${OS} ${OS_CODENAME} stable
EOF
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker || true
  local dv; dv=$(docker --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "?")
  p_success "Docker CE installed (v${dv})"
}

# ================================================================
#  SSL: Let's Encrypt OR Cloudflare Tunnel
# ================================================================
collect_ssl_method() {
  echo ""
      output "Choose SSL / connection method:"
    output "[1] Lets Encrypt  (Direct HTTPS -- free, requires port 80 open)"
    output "[2] Cloudflare Tunnel  (Zero Trust -- no port forwarding needed)"
  echo ""
  echo -n "* Choice [1/2, default 1]: "; read -r ssl_choice
  case "$ssl_choice" in
    2) SSL_METHOD="cloudflare"; _setup_cloudflare_tunnel ;;
    *) SSL_METHOD="letsencrypt" ;;
  esac
}

_setup_cloudflare_tunnel() {
  step "Installing cloudflared..."
  curl -L --output /tmp/cloudflared.deb \
    https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb >> /dev/null 2>&1
  dpkg -i /tmp/cloudflared.deb >> /dev/null 2>&1; rm -f /tmp/cloudflared.deb
  echo ""
  output "After install, authenticate your tunnel:"
  output "Run: cloudflared tunnel login"
  echo -e "  cloudflared tunnel create my-tunnel"
  echo -e "  cloudflared tunnel route dns my-tunnel ${PANEL_DOMAIN}${NC}"
  echo ""
  echo -n "* Paste Cloudflare Tunnel Token (Enter to skip for now): "; read -r CF_TOKEN
  if [[ -n "$CF_TOKEN" ]]; then
    cloudflared service install "$CF_TOKEN" >> /dev/null 2>&1
    systemctl enable --now cloudflared >> /dev/null 2>&1 || true
    p_success "Cloudflare Tunnel active."
  else
    p_warning "Token skipped -- configure tunnel manually later."
  fi
}

obtain_ssl() {
  local domain="$1" email="$2"
  if [[ "$SSL_METHOD" == "cloudflare" ]]; then
    output "Cloudflare Tunnel mode -- skipping certbot for ${domain}"
    return 0
  fi
  step "Obtaining SSL certificate for ${domain}"
  systemctl stop nginx 2>/dev/null || true
  if ! certbot certonly --standalone --non-interactive --agree-tos \
      --email "$email" -d "$domain"; then
    p_warning "SSL failed for ${domain} -- ensure DNS and port 80 are reachable."
    systemctl start nginx 2>/dev/null || true; return 1
  fi
  systemctl start nginx 2>/dev/null || true
  p_success "SSL certificate obtained for ${domain}"
}

setup_certbot_renewal() {
  [[ "$SSL_METHOD" == "cloudflare" ]] && return 0
  cat > /etc/cron.d/pterodactyl-certbot <<'CRON'
0 3 * * * root certbot renew --quiet --deploy-hook "systemctl reload nginx" >> /var/log/certbot-renew.log 2>&1
CRON
  chmod 644 /etc/cron.d/pterodactyl-certbot
  p_success "Certbot auto-renewal configured (daily 03:00)"
}

# ================================================================
#  SHARED: FIREWALL
# ================================================================
configure_firewall() {
  step "Configuring UFW firewall"
  ufw --force reset        > /dev/null 2>&1
  ufw default deny incoming > /dev/null
  ufw default allow outgoing > /dev/null
  ufw allow ssh       comment 'SSH'
  ufw allow 80/tcp    comment 'HTTP'
  ufw allow 443/tcp   comment 'HTTPS'
  ufw allow 8080/tcp  comment 'Wings HTTP'
  ufw allow 8443/tcp  comment 'Wings HTTPS'
  ufw allow 2022/tcp  comment 'Wings SFTP'
  ufw --force enable
  p_success "Firewall: SSH 22, HTTP 80, HTTPS 443, Wings 8080/8443/2022"
}

# ================================================================
#  SHARED: DATABASE
# ================================================================
setup_database() {
  step "Configuring MariaDB"
  local db_pass; db_pass=$(openssl rand -hex 20)
  mysql -u root <<SQL
CREATE DATABASE IF NOT EXISTS \`pterodactyl\`;
CREATE USER IF NOT EXISTS 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${db_pass}';
GRANT ALL PRIVILEGES ON \`pterodactyl\`.* TO 'pterodactyl'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL
  printf '%s' "$db_pass" > /etc/.ptero_db_pass; chmod 600 /etc/.ptero_db_pass
  p_success "Database 'pterodactyl' configured"
}

# ================================================================
#  PANEL: COLLECT INPUTS
# ================================================================
collect_panel_inputs() {
  print_brake 70; output "Panel Configuration"; print_brake 70; echo ""
  while [[ -z "$PANEL_DOMAIN" ]];  do read -rp  "  Panel domain (e.g. panel.example.com): " PANEL_DOMAIN; done
  while [[ -z "$ADMIN_EMAIL" ]];   do read -rp  "  Admin email: " ADMIN_EMAIL; done
  read -rp "  Admin username [admin]: " ADMIN_USER;  ADMIN_USER="${ADMIN_USER:-admin}"
  while [[ ${#ADMIN_PASS} -lt 8 ]]; do
    read -rsp "  Admin password (min 8 chars): " ADMIN_PASS; echo
    [[ ${#ADMIN_PASS} -lt 8 ]] && p_warning "Password must be at least 8 characters."
  done
  read -rp "  First name [Admin]: " ADMIN_FNAME; ADMIN_FNAME="${ADMIN_FNAME:-Admin}"
  read -rp "  Last name  [User]:  " ADMIN_LNAME; ADMIN_LNAME="${ADMIN_LNAME:-User}"
  read -rp "  Timezone   [UTC]:   " TZ_INPUT;    TZ_INPUT="${TZ_INPUT:-UTC}"
  echo ""; 
  echo -e "  ${BOLD}Review:${NC}"
  echo -e "  Domain   : ${CYAN}${PANEL_DOMAIN}${NC}"
  echo -e "  Email    : ${CYAN}${ADMIN_EMAIL}${NC}"
  echo -e "  Username : ${CYAN}${ADMIN_USER}${NC}"
  echo -e "  Name     : ${CYAN}${ADMIN_FNAME} ${ADMIN_LNAME}${NC}"
  echo -e "  Timezone : ${CYAN}${TZ_INPUT}${NC}"
  echo ""; 
  collect_ssl_method
  { echo -n "* Proceed with installation? [y/N]: "; read -r _c; [[ "$_c" =~ ^[Yy] ]]; } || error "Installation cancelled."
}

# ================================================================
#  PANEL: INSTALL
# ================================================================
do_install_panel() {
  step "Downloading Pterodactyl Panel (latest release)"
  mkdir -p /var/www/pterodactyl; cd /var/www/pterodactyl
  curl -fsSLo panel.tar.gz \
    https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
  tar -xzf panel.tar.gz; rm -f panel.tar.gz
  chmod -R 755 storage/* bootstrap/cache/

  step "Installing Composer dependencies"
  COMPOSER_ALLOW_SUPERUSER=1 composer install \
    --no-dev --optimize-autoloader --no-interaction --quiet

  step "Generating application key & configuring environment"
  cp .env.example .env; php artisan key:generate --force
  php artisan p:environment:setup \
    --author="$ADMIN_EMAIL" --url="https://${PANEL_DOMAIN}" --timezone="$TZ_INPUT" \
    --cache=redis --session=redis --queue=redis \
    --redis-host=127.0.0.1 --redis-pass="" --redis-port=6379 --settings-ui=true

  local db_pass; db_pass=$(cat /etc/.ptero_db_pass)
  php artisan p:environment:database \
    --host=127.0.0.1 --port=3306 --database=pterodactyl \
    --username=pterodactyl --password="$db_pass"

  step "Running database migrations"
  php artisan migrate --seed --force

  step "Creating admin user: ${ADMIN_USER}"
  php artisan p:user:make \
    --email="$ADMIN_EMAIL" --username="$ADMIN_USER" \
    --name-first="$ADMIN_FNAME" --name-last="$ADMIN_LNAME" \
    --password="$ADMIN_PASS" --admin=1

  chown -R www-data:www-data /var/www/pterodactyl
  mkdir -p /var/log/pterodactyl; chown www-data:www-data /var/log/pterodactyl

  cat > /etc/systemd/system/pteroq.service << SERVICE
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service valkey.service mariadb.service
Wants=redis-server.service valkey.service
[Service]
User=www-data
Group=www-data
Restart=always
RestartSec=5s
StartLimitInterval=180
StartLimitBurst=30
ExecStart=/usr/bin/php${PHP_VER} /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3 --max-time=3600
StandardOutput=append:/var/log/pterodactyl/queue.log
StandardError=append:/var/log/pterodactyl/queue.log
[Install]
WantedBy=multi-user.target
SERVICE

  cat > /etc/logrotate.d/pterodactyl << 'LOGROTATE'
/var/log/pterodactyl/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    sharedscripts
    postrotate
        systemctl reload pteroq 2>/dev/null || true
    endscript
}
LOGROTATE

  { crontab -l 2>/dev/null | grep -v 'pterodactyl/artisan schedule:run' || true
    echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1"
  } | crontab -
  systemctl daemon-reload; systemctl enable --now pteroq || true
  p_success "Panel installed"
}

configure_nginx() {
  local ssl_cert ssl_key
  if [[ "$SSL_METHOD" == "cloudflare" ]]; then
    ssl_cert="/etc/ssl/certs/ssl-cert-snakeoil.pem"
    ssl_key="/etc/ssl/private/ssl-cert-snakeoil.key"
  else
    ssl_cert="/etc/letsencrypt/live/${PANEL_DOMAIN}/fullchain.pem"
    ssl_key="/etc/letsencrypt/live/${PANEL_DOMAIN}/privkey.pem"
  fi
  step "Configuring Nginx for ${PANEL_DOMAIN}"
  cat > /etc/nginx/sites-available/pterodactyl.conf << NGINX
server {
    listen 80; listen [::]:80; server_name ${PANEL_DOMAIN};
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl; listen [::]:443 ssl; http2 on;
    server_name ${PANEL_DOMAIN};
    root /var/www/pterodactyl/public; index index.php;
    ssl_certificate     ${ssl_cert};
    ssl_certificate_key ${ssl_key};
    ssl_session_timeout 1d; ssl_session_cache shared:PteroSSL:10m; ssl_session_tickets off;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers off;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    access_log /var/log/nginx/pterodactyl.access.log;
    error_log  /var/log/nginx/pterodactyl.error.log warn;
    client_max_body_size 100m; client_body_timeout 120s; sendfile off;
    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php${PHP_VER}-fpm.sock;
        fastcgi_index index.php; include fastcgi_params;
        fastcgi_param PHP_VALUE      "upload_max_filesize=100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY     "";
        fastcgi_connect_timeout 300; fastcgi_send_timeout 300; fastcgi_read_timeout 300;
    }
    location ~ /\.(?!well-known) { deny all; }
}
NGINX
  ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
  rm -f /etc/nginx/sites-enabled/default
  nginx -t && systemctl enable --now nginx && systemctl restart nginx
  p_success "Nginx configured for ${PANEL_DOMAIN}"
}

flow_install_panel() {
  if panel_installed; then p_warning "Panel already installed. Use [4] to update."; sleep 2; return; fi
  collect_panel_inputs
  install_dependencies
  obtain_ssl "$PANEL_DOMAIN" "$ADMIN_EMAIL"
  setup_database; do_install_panel; configure_nginx
  configure_firewall; setup_certbot_renewal; _print_panel_summary; echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

_print_panel_summary() {
  echo ""
  print_brake 70
  p_success "PANEL INSTALLED SUCCESSFULLY"
  output ""
  output "Panel URL : https://${PANEL_DOMAIN}"
  output "Username  : ${ADMIN_USER}"
  output "Email     : ${ADMIN_EMAIL}"
  output "SSL       : ${SSL_METHOD}"
  print_brake 70
  echo ""
}

# ================================================================
#  WINGS
# ================================================================
collect_wings_inputs() {
  print_brake 70; output "Wings / Node Configuration"; print_brake 70; echo ""
  while [[ -z "$WINGS_DOMAIN" ]]; do echo -n "* Node FQDN (e.g. node1.example.com): "; read -r WINGS_DOMAIN; done
  while [[ -z "$WINGS_EMAIL" ]];  do echo -n "* Email for SSL: "; read -r WINGS_EMAIL; done
  echo ""; 
  output "Node FQDN : ${WINGS_DOMAIN}"
  echo -e "  Email     : ${CYAN}${WINGS_EMAIL}${NC}"; echo ""
  { echo -n "* Proceed with Wings installation? [y/N]: "; read -r _c; [[ "$_c" =~ ^[Yy] ]]; } || error "Installation cancelled."
}

do_install_wings() {
  install_docker
  local arch; arch=$(dpkg --print-architecture 2>/dev/null || uname -m)
  case "$arch" in amd64|x86_64) arch="amd64";; arm64|aarch64) arch="arm64";; *) error "Unsupported CPU: ${arch}";; esac
  step "Downloading Wings binary (latest, ${arch})"
  curl -fsSLo /usr/local/bin/wings \
    "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${arch}"
  chmod 755 /usr/local/bin/wings
  mkdir -p /etc/pterodactyl /var/log/pterodactyl /var/lib/pterodactyl/volumes /var/run/wings
  if [[ ! -s /etc/pterodactyl/config.yml ]]; then
    cat > /etc/pterodactyl/config.yml << 'PLACEHOLDER'
# To activate Wings:
# 1. Panel -> Admin -> Nodes -> Create Node  (FQDN: this server, Port: 8080, SSL: Yes)
# 2. Node -> Configuration tab -> copy YAML
# 3. Paste YAML here, then: systemctl restart wings
PLACEHOLDER
  fi
  cat > /etc/systemd/system/wings.service << 'SERVICE'
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service network-online.target
Requires=docker.service
[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
ExecStart=/usr/local/bin/wings
Restart=on-failure
RestartSec=5s
StartLimitInterval=180
StartLimitBurst=30
StandardOutput=append:/var/log/pterodactyl/wings.log
StandardError=append:/var/log/pterodactyl/wings.log
[Install]
WantedBy=multi-user.target
SERVICE
  systemctl daemon-reload; systemctl enable wings
  p_success "Wings installed -- paste node config into /etc/pterodactyl/config.yml then: systemctl start wings"
}

flow_install_wings() {
  if wings_installed; then p_warning "Wings already installed. Use [5] to update."; sleep 2; return; fi
  collect_wings_inputs
  install_dependencies; obtain_ssl "$WINGS_DOMAIN" "$WINGS_EMAIL"
  do_install_wings; configure_firewall; _print_wings_summary; echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

_print_wings_summary() {
  local wv; wv=$(wings_version)
  echo ""
  print_brake 70
  p_success "WINGS INSTALLED SUCCESSFULLY"
  print_brake 70
  output ""
  output "Wings FQDN : ${WINGS_DOMAIN}"
  output "Version    : v${wv}"
  output "API Port   : 8080 (HTTPS)"
  output "Config     : /etc/pterodactyl/config.yml"
  print_brake 70
  output "Next Steps:"
  output "1. Panel -> Admin -> Nodes -> Create Node"
  output "   FQDN: ${WINGS_DOMAIN}  Port: 8080  SSL: Yes"
  output "2. Node -> Configuration -> copy YAML"
  output "3. Paste into /etc/pterodactyl/config.yml"
  output "4. Run: systemctl start wings"
  print_brake 70
  echo ""
}

flow_install_both() {
  panel_installed && p_warning "Panel already installed -- skipping panel steps."
  wings_installed && p_warning "Wings already installed -- skipping wings steps."
  collect_panel_inputs
  while [[ -z "$WINGS_DOMAIN" ]]; do echo -n "* Wings/Node FQDN: "; read -r WINGS_DOMAIN; done
  WINGS_EMAIL="$ADMIN_EMAIL"; install_dependencies
  if ! panel_installed; then
    obtain_ssl "$PANEL_DOMAIN" "$ADMIN_EMAIL"; setup_database; do_install_panel; configure_nginx
  fi
  if ! wings_installed; then
    [[ "$WINGS_DOMAIN" != "$PANEL_DOMAIN" ]] && obtain_ssl "$WINGS_DOMAIN" "$ADMIN_EMAIL"
    do_install_wings
  fi
  configure_firewall; setup_certbot_renewal; _print_panel_summary; _print_wings_summary; echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

# ================================================================
#  UPDATE PANEL
# ================================================================
flow_update_panel() {
  print_brake 70; output "Update Panel"; print_brake 70; echo ""; panel_installed || error "Panel is not installed."
  local old_ver latest; old_ver=$(panel_version); latest=$(github_latest "pterodactyl/panel")
  output "Installed : v${old_ver}"; output "Available : v${latest}"
  if [[ "$old_ver" == "$latest" ]]; then
    p_success "Panel is up to date (v${old_ver})."
    { echo -n "* Force reinstall anyway? [y/N]: "; read -r _c; [[ "$_c" =~ ^[Yy] ]]; } || { echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }
  else
    { echo -n "* Update Panel v${old_ver} -> v${latest}? [y/N]: "; read -r _c; [[ "$_c" =~ ^[Yy] ]]; } || { echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }
  fi
  local bdir="/var/pterodactyl-backups/panel-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$bdir"; cp /var/www/pterodactyl/.env "$bdir/.env.bak" 2>/dev/null || true
  output "Backup: ${bdir}"
  cd /var/www/pterodactyl; php artisan down --retry=15
  curl -fsSLo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
  tar -xzf panel.tar.gz; rm -f panel.tar.gz; chmod -R 755 storage/* bootstrap/cache/
  COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader --no-interaction --quiet
  php artisan migrate --force; php artisan view:clear; php artisan config:clear
  php artisan route:clear; php artisan optimize
  chown -R www-data:www-data /var/www/pterodactyl
  php artisan up; systemctl restart pteroq nginx
  p_success "Panel updated: v${old_ver} -> v$(panel_version)"; echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

# ================================================================
#  UPDATE WINGS
# ================================================================
flow_update_wings() {
  print_brake 70; output "Update Wings"; print_brake 70; echo ""; wings_installed || error "Wings is not installed."
  local old_ver latest; old_ver=$(wings_version); latest=$(github_latest "pterodactyl/wings")
  output "Installed : v${old_ver}"; output "Available : v${latest}"
  if [[ "$old_ver" == "$latest" ]]; then
    p_success "Wings is up to date (v${old_ver})."
    { echo -n "* Force reinstall anyway? [y/N]: "; read -r _c; [[ "$_c" =~ ^[Yy] ]]; } || { echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }
  else
    { echo -n "* Update Wings v${old_ver} -> v${latest}? [y/N]: "; read -r _c; [[ "$_c" =~ ^[Yy] ]]; } || { echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }
  fi
  local bdir="/var/pterodactyl-backups/wings-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$bdir"; cp /usr/local/bin/wings "$bdir/wings.bak"
  local arch; arch=$(dpkg --print-architecture 2>/dev/null || echo "amd64")
  [[ "$arch" == "aarch64" ]] && arch="arm64"
  systemctl stop wings 2>/dev/null || true
  curl -fsSLo /usr/local/bin/wings \
    "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${arch}"
  chmod 755 /usr/local/bin/wings; systemctl start wings
  p_success "Wings updated: v${old_ver} -> v$(wings_version)"; echo -n "* Press ENTER to continue..."; read -r _; echo ""
}
