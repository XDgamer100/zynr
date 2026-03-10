#!/usr/bin/env bash
# Zynr.Cloud -- Uninstall (Panel / Wings / All)
# Sourced by install.sh
# ================================================================
#  UNINSTALL
# ================================================================
menu_uninstall() {
  print_brake 70; output "Uninstall"; print_brake 70; echo ""
  p_warning "WARNING: These actions are PERMANENT and cannot be undone!"
  output "[1] Uninstall Panel only"
  output "[2] Uninstall Wings only"
  output "[3] Uninstall EVERYTHING  (Panel + Wings + DB)"
  output ""
  output "[0] Back"
  echo -n "* Input 0-3: "; read -r c
  case "$c" in
    1) _uninstall_panel ;;
    2) _uninstall_wings ;;
    3) _uninstall_all ;;
    0) return ;;
  esac
}

_do_rm_panel() {
  output "Removing Panel files..."
  systemctl disable --now pteroq 2>/dev/null || true
  rm -f /etc/systemd/system/pteroq.service
  systemctl disable --now nginx php8.3-fpm 2>/dev/null || true
  rm -f /etc/nginx/sites-enabled/pterodactyl.conf \
        /etc/nginx/sites-available/pterodactyl.conf
  rm -rf /var/www/pterodactyl
  systemctl reload nginx 2>/dev/null || true
  output "Panel files removed."
}

_do_rm_wings() {
  output "Removing Wings..."
  systemctl disable --now wings 2>/dev/null || true
  rm -f /etc/systemd/system/wings.service /usr/local/bin/wings
  rm -rf /etc/pterodactyl /var/lib/pterodactyl/tmp /var/log/pterodactyl
  systemctl daemon-reload
  output "Wings removed."
}

_uninstall_panel() {
  print_brake 70; output "Uninstall Panel"; print_brake 70; echo ""
  panel_installed || { p_warning "Panel does not appear to be installed."; echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }
  { echo -n "* ${RED}Permanently remove Pterodactyl Panel?${NC} [y/N]: "; read -r _c; [[ "$_c" =~ ^[Yy] ]]; } || { echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }
  local bdir="/var/pterodactyl-backups/panel-uninstall-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$bdir"
  output "Backing up .env to ${bdir}/..."
  cp /var/www/pterodactyl/.env "$bdir/.env.bak" 2>/dev/null || true
  _do_rm_panel
  p_success "Panel uninstalled. Backup: ${bdir}/.env.bak"; echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

_uninstall_wings() {
  print_brake 70; output "Uninstall Wings"; print_brake 70; echo ""
  wings_installed || { p_warning "Wings does not appear to be installed."; echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }
  { echo -n "* ${RED}Permanently remove Wings?${NC} [y/N]: "; read -r _c; [[ "$_c" =~ ^[Yy] ]]; } || { echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }
  local bdir="/var/pterodactyl-backups/wings-uninstall-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$bdir"
  cp /etc/pterodactyl/config.yml "$bdir/config.yml.bak" 2>/dev/null || true
  _do_rm_wings
  p_success "Wings uninstalled. Backup: ${bdir}/config.yml.bak"; echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

_uninstall_all() {
  print_brake 70; output "Uninstall Everything"; print_brake 70; echo ""
      p_warning "This will remove: Panel, Wings, MariaDB, Redis, Nginx, PHP and ALL data."
    p_warning "All game server data managed by Wings will be LOST.${NC}\n"
  { echo -n "* ${RED}Are you ABSOLUTELY sure?${NC} [y/N]: "; read -r _c; [[ "$_c" =~ ^[Yy] ]]; } || { echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }
  { echo -n "* ${RED}SECOND CONFIRMATION: Delete EVERYTHING?${NC} [y/N]: "; read -r _c; [[ "$_c" =~ ^[Yy] ]]; } || { echo -n "* Press ENTER to continue..."; read -r _; echo ""; return; }
  panel_installed && _do_rm_panel
  wings_installed && _do_rm_wings
  output "Dropping Pterodactyl database..."
  mysql -e "DROP DATABASE IF EXISTS pterodactyl; DROP USER IF EXISTS 'pterodactyl'@'localhost';" \
    2>/dev/null || true
  output "Removing packages..."
  apt-get remove --purge -y \
    php8.3 php8.3-{fpm,cli,mysql,mbstring,xml,curl,zip,bcmath,gd,tokenizer,intl} \
    nginx mariadb-server redis-server composer 2>/dev/null || true
  apt-get autoremove -y 2>/dev/null || true
  output "Removing Docker..."
  systemctl disable --now docker 2>/dev/null || true
  apt-get remove --purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin \
    docker-compose-plugin 2>/dev/null || true
  rm -rf /var/lib/docker
  p_success "Everything uninstalled. Server is now clean."; echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

# ================================================================
#  BLUEPRINT MANAGER
# ================================================================
blueprint_installed() { [[ -f /var/www/pterodactyl/blueprint.sh ]]; }

