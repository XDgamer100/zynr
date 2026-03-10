#!/usr/bin/env bash
# Zynr.Cloud -- Extra Panels (Paymenter, FOSSBilling, cPanel, VirtPanel)
# Sourced by install.sh
menu_extra_panels() {
  print_brake 70; output "Additional Panels"; print_brake 70; echo ""
  echo -e "  Install extra hosting / billing / VPS control panels.\n"
  multi_select "Select panels to install" "${_extra_panels[@]}"
  local sel=("${SELECTED_ITEMS[@]}")
  [[ ${#sel[@]} -eq 0 ]] && { output "No panels selected."; echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }
  { echo -n "* Install ${#sel[@]} panel(s)? [y/N]: "; read -r _c; [[ "$_c" =~ ^[Yy] ]]; } || { echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }
  for key in "${sel[@]}"; do
    case "$key" in
      paymenter)   _install_paymenter ;;
      fossbilling) _install_fossbilling ;;
      cpanel)      _install_cpanel ;;
      virtualizor) _install_virtualizor ;;
      virtfusion)  _install_virtfusion ;;
    esac
  done
  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

_install_paymenter() {
  print_brake 70; output "Installing Paymenter"; print_brake 70; echo ""
  local domain email db_pass
  read -rp "  Domain for Paymenter (e.g. billing.example.com): " domain
  read -rp "  Admin e-mail: " email
  db_pass=$(openssl rand -base64 20 | tr -dc 'A-Za-z0-9' | head -c 20)
  apt-get install -y php8.3 php8.3-{cli,fpm,mysql,mbstring,xml,curl,zip,bcmath,intl} \
    mariadb-server nginx curl unzip git redis-server --no-install-recommends
  mysql -e "CREATE DATABASE IF NOT EXISTS paymenter;"
  mysql -e "CREATE USER IF NOT EXISTS 'paymenter'@'localhost' IDENTIFIED BY '${db_pass}';"
  mysql -e "GRANT ALL ON paymenter.* TO 'paymenter'@'localhost'; FLUSH PRIVILEGES;"
  mkdir -p /var/www/paymenter
  curl -fsSLo /tmp/paymenter.zip \
    "$(curl -fsSL https://api.github.com/repos/paymenter/paymenter/releases/latest \
       | grep browser_download_url | grep '\.zip' | head -1 | cut -d'"' -f4)"
  unzip -q /tmp/paymenter.zip -d /var/www/paymenter; rm -f /tmp/paymenter.zip
  cd /var/www/paymenter
  composer install --no-dev --optimize-autoloader --no-interaction 2>/dev/null
  cp .env.example .env
  sed -i "s|APP_URL=.*|APP_URL=https://${domain}|" .env
  sed -i "s|DB_DATABASE=.*|DB_DATABASE=paymenter|;s|DB_USERNAME=.*|DB_USERNAME=paymenter|;s|DB_PASSWORD=.*|DB_PASSWORD=${db_pass}|" .env
  php artisan key:generate --force
  php artisan migrate --force
  php artisan db:seed --force
  chown -R www-data:www-data /var/www/paymenter
  # Nginx vhost
  cat > /etc/nginx/sites-available/paymenter.conf <<NGINX
server {
  listen 80; server_name ${domain};
  root /var/www/paymenter/public;
  index index.php;
  location / { try_files \$uri \$uri/ /index.php?\$query_string; }
  location ~ \.php$ {
    fastcgi_pass unix:/run/php/php8.3-fpm.sock;
    fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
    include fastcgi_params;
  }
}
NGINX
  ln -sf /etc/nginx/sites-available/paymenter.conf /etc/nginx/sites-enabled/
  nginx -t && systemctl reload nginx
  PAY_DOMAIN="$domain"
  p_success "Paymenter installed -> http://${domain}"
}

_install_fossbilling() {
  print_brake 70; output "Installing FOSSBilling"; print_brake 70; echo ""
  local domain db_pass
  read -rp "  Domain for FOSSBilling (e.g. billing.example.com): " domain
  db_pass=$(openssl rand -base64 20 | tr -dc 'A-Za-z0-9' | head -c 20)
  apt-get install -y php8.3 php8.3-{cli,fpm,mysql,mbstring,xml,curl,zip,intl,gd,pdo} \
    mariadb-server nginx curl unzip --no-install-recommends
  mysql -e "CREATE DATABASE IF NOT EXISTS fossbilling;"
  mysql -e "CREATE USER IF NOT EXISTS 'fossbilling'@'localhost' IDENTIFIED BY '${db_pass}';"
  mysql -e "GRANT ALL ON fossbilling.* TO 'fossbilling'@'localhost'; FLUSH PRIVILEGES;"
  mkdir -p /var/www/fossbilling
  local dl_url; dl_url=$(curl -fsSL \
    "https://api.github.com/repos/FOSSBilling/FOSSBilling/releases/latest" \
    | grep browser_download_url | grep '\.zip' | head -1 | cut -d'"' -f4)
  curl -fsSLo /tmp/fossbilling.zip "$dl_url"
  unzip -q /tmp/fossbilling.zip -d /var/www/fossbilling; rm -f /tmp/fossbilling.zip
  chown -R www-data:www-data /var/www/fossbilling
  cat > /etc/nginx/sites-available/fossbilling.conf <<NGINX
server {
  listen 80; server_name ${domain};
  root /var/www/fossbilling;
  index index.php;
  location / { try_files \$uri \$uri/ /index.php?\$query_string; }
  location ~ \.php$ {
    fastcgi_pass unix:/run/php/php8.3-fpm.sock;
    fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
    include fastcgi_params;
  }
}
NGINX
  ln -sf /etc/nginx/sites-available/fossbilling.conf /etc/nginx/sites-enabled/
  nginx -t && systemctl reload nginx
  FOSS_DOMAIN="$domain"
  p_success "FOSSBilling installed -> http://${domain}  (complete setup in browser)"
}

_install_cpanel() {
  print_brake 70; output "Installing cPanel/WHM"; print_brake 70; echo ""
  p_warning "cPanel/WHM requires a valid license (commercial product)."
  { echo -n "* Proceed with cPanel installation? (This will RESTART your server) [y/N]: "; read -r _c; [[ "$_c" =~ ^[Yy] ]]; } || return
  [[ "$OS_ID" == "ubuntu" ]] || error "cPanel officially supports CentOS/AlmaLinux/CloudLinux -- Ubuntu support is limited."
  output "Downloading cPanel installer..."
  curl -fsSLo /root/latest https://securedownloads.cpanel.net/latest
  chmod +x /root/latest
  output "Running cPanel installer (this takes 15-30 min)..."
  bash /root/latest
  p_success "cPanel installer completed. Access WHM at https://$(hostname -I | awk '{print $1}'):2087"
}

_install_virtualizor() {
  print_brake 70; output "Installing Virtualizor"; print_brake 70; echo ""
  local ip; ip=$(curl -sf https://api.ipify.org || hostname -I | awk '{print $1}')
  output "Downloading Virtualizor installer..."
  wget -q "https://files.virtualizor.com/install.sh" -O /tmp/vz_install.sh
  chmod +x /tmp/vz_install.sh
  output "Running Virtualizor installer..."
  bash /tmp/vz_install.sh 2>&1 | tail -20
  rm -f /tmp/vz_install.sh
  p_success "Virtualizor installed!  ->  https://${ip}:4082  (admin / admin)"
}

_install_virtfusion() {
  print_brake 70; output "Installing VirtFusion"; print_brake 70; echo ""
  local ip; ip=$(curl -sf https://api.ipify.org || hostname -I | awk '{print $1}')
  output "Downloading VirtFusion installer..."
  curl -fsSLo /tmp/vf_install.sh \
    "https://download.virtfusion.net/scripts/install-virtfusion.sh"
  chmod +x /tmp/vf_install.sh
  bash /tmp/vf_install.sh
  rm -f /tmp/vf_install.sh
  p_success "VirtFusion installed!  ->  http://${ip}:1200"
}

# ================================================================
#  DDOS PROTECTION SUITE
# ================================================================
_ddos_components=(
  "ufw"         "UFW  -- Uncomplicated Firewall (port rules)"
  "fail2ban"    "Fail2Ban  -- Brute-force / intrusion auto-ban"
  "crowdsec"    "CrowdSec  -- Collaborative threat intelligence"
  "sysctl"      "Sysctl Hardening  -- Kernel-level TCP/IP tuning"
  "iptables"    "IPTables Rules  -- SYN / UDP / ICMP flood drops"
  "nftables"    "NFTables  -- Modern stateful firewall (Minecraft-aware)"
  "nginx_rate"  "Nginx Rate Limiting  -- Limit req/s per IP"
  "ipset"       "IPSet Blocklists  -- Block known bad IPs"
  "monitor"     "DDoS Auto-Monitor Daemon  -- Live flood detection + auto-ban"
)

# Global: does user run Minecraft?
_MC_PORTS_ENABLED=0

