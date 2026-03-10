#!/usr/bin/env bash
# Zynr.Cloud -- Egg Registry (200+ eggs: browse, bulk import, custom URL)

menu_eggs() {
  panel_installed || { error "Panel must be installed to import eggs."; }
  while true; do
    clear

    print_brake 70
    output "Zynr.Cloud -- Eggs Manager  (200+ eggs)"
    print_brake 70

    output ""
    output "[1] Browse and install by category"
    output "[2] List all available eggs"
    output "[3] Install all eggs in a category"
    output "[4] Import from custom URL"
    output ""
    output "[0] Back"
    echo ""
    echo -n "* Input 0-4: "
    read -r c
    echo ""

    case "$c" in
      1) eggs_browse_category ;;
      2) eggs_list_all ;;
      3) eggs_bulk_install ;;
      4) eggs_custom_url ;;
      0) return ;;
      *)
        echo -e "* ${COLOR_RED}ERROR${COLOR_NC}: Invalid option '$c'" 1>&2
        sleep 1 ;;
    esac
  done
}

_egg_categories() {
  local cats=()
  for key in "${!EGG_NESTS[@]}"; do
    cats+=("${EGG_NESTS[$key]}")
  done
  printf '%s\n' "${cats[@]}" | sort -u
}

eggs_browse_category() {
  print_brake 70; output "Browse Eggs by Category"; print_brake 70; echo ""
  local -a cat_list; mapfile -t cat_list < <(_egg_categories)
  local i=1 cat_map=()
  for cat in "${cat_list[@]}"; do
    output "[${i}] ${cat}"
    cat_map+=("$cat")
    ((i++))
  done
  echo ""
  echo -n "* Select category: "; read -r sel
  [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#cat_map[@]} )) || {
    p_warning "Invalid selection."
    echo -n "* Press ENTER..."; read -r _; return
  }
  local chosen_cat="${cat_map[$((sel-1))]}"
  eggs_list_category "$chosen_cat"
}

eggs_list_category() {
  local cat="$1"
  print_brake 70; output "Eggs: ${cat}"; print_brake 70; echo ""
  local -a keys labels
  for key in "${!EGG_NESTS[@]}"; do
    [[ "${EGG_NESTS[$key]}" == "$cat" ]] || continue
    keys+=("$key")
    labels+=("${EGG_LABELS[$key]}")
  done
  local ms_args=()
  local count=${#keys[@]}
  for (( i=0; i<count; i++ )); do
    ms_args+=("${keys[$i]}" "${labels[$i]}")
  done
  multi_select "Select eggs to import (comma-separated, A=all)" "${ms_args[@]}"
  [[ ${#SELECTED_ITEMS[@]} -eq 0 ]] && { echo -n "* Press ENTER..."; read -r _; return; }
  echo -n "* Import ${#SELECTED_ITEMS[@]} egg(s) into Panel? [y/N]: "; read -r _c
  [[ "$_c" =~ ^[Yy] ]] || { echo -n "* Press ENTER..."; read -r _; return; }
  for key in "${SELECTED_ITEMS[@]}"; do
    egg_import_single "$key"
  done
  p_success "Egg import complete."
  echo -n "* Press ENTER..."; read -r _; echo ""
}

eggs_list_all() {
  print_brake 70; output "All Available Eggs"; print_brake 70; echo ""
  for key in $(echo "${!EGG_LABELS[@]}" | tr ' ' '\n' | sort); do
    printf "  %-25s [%-12s]  %s\n" "$key" "${EGG_NESTS[$key]}" "${EGG_LABELS[$key]}"
  done | less
}

egg_import_single() {
  local key="$1"
  local url="${EGG_URLS[$key]}"
  local label="${EGG_LABELS[$key]:-$key}"
  [[ -z "$url" ]] && { p_warning "No URL registered for egg key: ${key}"; return; }
  output "Importing: ${label}..."
  local tmp; tmp=$(mktemp /tmp/egg_XXXXXX.json)
  curl -fsSLo "$tmp" "$url" || { p_warning "Download failed for ${label}"; rm -f "$tmp"; return; }
  cd /var/www/pterodactyl
  php artisan p:egg:import --path="$tmp" 2>/dev/null && output "* [OK] ${label}" \
    || php artisan pterodactyl:egg:import --path="$tmp" 2>/dev/null && output "* [OK] ${label}" \
    || p_warning "Import failed for ${label} (check Panel logs)"
  rm -f "$tmp"
}

eggs_bulk_install() {
  print_brake 70; output "Bulk Install -- Entire Category"; print_brake 70; echo ""
  local -a cat_list; mapfile -t cat_list < <(_egg_categories)
  local i=1 cat_map=()
  for cat in "${cat_list[@]}"; do
    output "[${i}] ${cat}"
    cat_map+=("$cat")
    ((i++))
  done
  echo ""
  echo -n "* Select category to bulk-install: "; read -r sel
  [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#cat_map[@]} )) || {
    p_warning "Invalid."
    echo -n "* Press ENTER..."; read -r _; return
  }
  local cat="${cat_map[$((sel-1))]}"
  local count=0
  for key in "${!EGG_NESTS[@]}"; do
    [[ "${EGG_NESTS[$key]}" == "$cat" ]] || continue
    ((count++))
  done
  echo -n "* Import ALL ${count} eggs in '${cat}'? [y/N]: "; read -r _c
  [[ "$_c" =~ ^[Yy] ]] || { echo -n "* Press ENTER..."; read -r _; return; }
  for key in "${!EGG_NESTS[@]}"; do
    [[ "${EGG_NESTS[$key]}" == "$cat" ]] && egg_import_single "$key"
  done
  p_success "Bulk import for '${cat}' complete."
  echo -n "* Press ENTER..."; read -r _; echo ""
}

eggs_custom_url() {
  print_brake 70; output "Import Egg from Custom URL"; print_brake 70; echo ""
  echo -n "* Egg JSON URL: "; read -r url
  [[ -z "$url" ]] && { echo -n "* Press ENTER..."; read -r _; return; }
  local tmp; tmp=$(mktemp /tmp/egg_custom_XXXXXX.json)
  output "Downloading egg from ${url}..."
  curl -fsSLo "$tmp" "$url" || { p_error "Download failed."; rm -f "$tmp"; return; }
  cd /var/www/pterodactyl
  php artisan p:egg:import --path="$tmp" 2>/dev/null \
    || php artisan pterodactyl:egg:import --path="$tmp" 2>/dev/null \
    || { p_error "Import failed. Verify the JSON is a valid Pterodactyl egg."; rm -f "$tmp"; return; }
  rm -f "$tmp"
  p_success "Custom egg imported!"
  echo -n "* Press ENTER..."; read -r _; echo ""
}
