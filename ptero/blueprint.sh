#!/usr/bin/env bash
# Zynr.Cloud -- Blueprint Framework Manager

blueprint_installed() { [[ -f /var/www/pterodactyl/blueprint.sh ]]; }

menu_blueprint() {
  panel_installed || { error "Panel must be installed first."; }
  while true; do
    clear

    local bp_ver="not installed"
    blueprint_installed && bp_ver=$(cd /var/www/pterodactyl && bash blueprint.sh -version 2>/dev/null | head -1 || echo "installed")

    print_brake 70
    output "Zynr.Cloud -- Blueprint Manager  [${bp_ver}]"
    print_brake 70

    output ""
    output "[1] Install Blueprint"
    output "[2] Install extension  (.blueprint file)"
    output "[3] List installed extensions"
    output "[4] Remove extension"
    output "[5] Update Blueprint"
    output "[6] Uninstall Blueprint"
    output ""
    output "[0] Back"
    echo ""
    echo -n "* Input 0-6: "
    read -r c
    echo ""

    case "$c" in
      1) bp_install ;;
      2) bp_install_ext ;;
      3) bp_list_ext ;;
      4) bp_remove_ext ;;
      5) bp_update ;;
      6) bp_uninstall ;;
      0) return ;;
      *)
        echo -e "* ${COLOR_RED}ERROR${COLOR_NC}: Invalid option '$c'" 1>&2
        sleep 1 ;;
    esac
  done
}

bp_install() {
  print_brake 70; output "Install Blueprint"; print_brake 70; echo ""
  blueprint_installed && { p_warning "Blueprint already installed."; echo -n "* Press ENTER..."; read -r _; return; }
  local latest; latest=$(github_latest "BlueprintFramework/framework")
  output "Installing Blueprint v${latest}..."
  cd /var/www/pterodactyl
  local url="https://github.com/BlueprintFramework/framework/releases/latest/download/blueprint.zip"
  curl -fsSLo /tmp/blueprint.zip "$url"
  unzip -qo /tmp/blueprint.zip -d /var/www/pterodactyl; rm -f /tmp/blueprint.zip
  chmod +x /var/www/pterodactyl/blueprint.sh
  bash /var/www/pterodactyl/blueprint.sh
  p_success "Blueprint installed!"
  echo -n "* Press ENTER..."; read -r _; echo ""
}

bp_install_ext() {
  print_brake 70; output "Install Blueprint Extension"; print_brake 70; echo ""
  blueprint_installed || { error "Blueprint is not installed. Install it first."; }
  output "Provide the path to a .blueprint extension file."
  echo ""
  echo -n "* Path to .blueprint file (or URL): "; read -r src
  local ext_file="/tmp/bp_ext_install.blueprint"
  if [[ "$src" =~ ^https?:// ]]; then
    output "Downloading extension..."
    curl -fsSLo "$ext_file" "$src"
  else
    [[ -f "$src" ]] || { p_error "File not found: ${src}"; echo -n "* Press ENTER..."; read -r _; return; }
    cp "$src" "$ext_file"
  fi
  cd /var/www/pterodactyl
  bash blueprint.sh -install "$ext_file"
  rm -f "$ext_file"
  p_success "Extension installed!"
  echo -n "* Press ENTER..."; read -r _; echo ""
}

bp_list_ext() {
  print_brake 70; output "Installed Blueprint Extensions"; print_brake 70; echo ""
  blueprint_installed || { p_warning "Blueprint is not installed."; echo -n "* Press ENTER..."; read -r _; return; }
  cd /var/www/pterodactyl
  bash blueprint.sh -list 2>/dev/null || \
    ls /var/www/pterodactyl/.blueprint/extensions/ 2>/dev/null || \
    output "No extensions found."
  echo ""
  echo -n "* Press ENTER..."; read -r _; echo ""
}

bp_remove_ext() {
  print_brake 70; output "Remove Blueprint Extension"; print_brake 70; echo ""
  blueprint_installed || { p_warning "Blueprint is not installed."; echo -n "* Press ENTER..."; read -r _; return; }
  bp_list_ext
  echo -n "* Extension ID to remove: "; read -r ext_id
  echo -n "* Remove extension '${ext_id}'? [y/N]: "; read -r _c
  [[ "$_c" =~ ^[Yy] ]] || { echo -n "* Press ENTER..."; read -r _; return; }
  cd /var/www/pterodactyl
  bash blueprint.sh -remove "$ext_id"
  p_success "Extension '${ext_id}' removed."
  echo -n "* Press ENTER..."; read -r _; echo ""
}

bp_update() {
  print_brake 70; output "Update Blueprint"; print_brake 70; echo ""
  blueprint_installed || { error "Blueprint is not installed."; }
  local latest; latest=$(github_latest "BlueprintFramework/framework")
  output "Updating Blueprint to v${latest}..."
  local url="https://github.com/BlueprintFramework/framework/releases/latest/download/blueprint.zip"
  curl -fsSLo /tmp/blueprint.zip "$url"
  cd /var/www/pterodactyl
  unzip -qo /tmp/blueprint.zip; rm -f /tmp/blueprint.zip
  chmod +x blueprint.sh
  bash blueprint.sh -update 2>/dev/null || true
  p_success "Blueprint updated to v${latest}!"
  echo -n "* Press ENTER..."; read -r _; echo ""
}

bp_uninstall() {
  print_brake 70; output "Uninstall Blueprint"; print_brake 70; echo ""
  blueprint_installed || { p_warning "Blueprint is not installed."; echo -n "* Press ENTER..."; read -r _; return; }
  echo -n "* Remove Blueprint and ALL its extensions? [y/N]: "; read -r _c
  [[ "$_c" =~ ^[Yy] ]] || { echo -n "* Press ENTER..."; read -r _; return; }
  cd /var/www/pterodactyl
  bash blueprint.sh -destroy 2>/dev/null || true
  rm -f /var/www/pterodactyl/blueprint.sh
  rm -rf /var/www/pterodactyl/.blueprint
  p_success "Blueprint uninstalled."
  echo -n "* Press ENTER..."; read -r _; echo ""
}
