#!/usr/bin/env bash
# Zynr.Cloud -- Pterodactyl User Management

menu_users() {
  panel_installed || { error "Panel is not installed."; }
  while true; do
    clear

    print_brake 70
    output "Zynr.Cloud -- User Management"
    print_brake 70

    output ""
    output "[1] Create user"
    output "[2] List users"
    output "[3] Delete user"
    output "[4] Change password"
    output "[5] Toggle admin"
    output ""
    output "[0] Back"
    echo ""
    echo -n "* Input 0-5: "
    read -r c
    echo ""

    case "$c" in
      1) user_create ;;
      2) user_list ;;
      3) user_delete ;;
      4) user_change_password ;;
      5) user_set_admin ;;
      0) return ;;
      *)
        echo -e "* ${COLOR_RED}ERROR${COLOR_NC}: Invalid option '$c'" 1>&2
        sleep 1 ;;
    esac
  done
}

user_create() {
  print_brake 70
  output "Create User"
  print_brake 70
  echo ""
  local uname email pass fname lname
  echo -n "* Username     : "; read -r uname
  echo -n "* Email        : "; read -r email
  echo -n "* Password     : "; read -rs pass; echo
  echo -n "* First name   : "; read -r fname
  echo -n "* Last name    : "; read -r lname
  local admin_flag="--no-admin"
  echo -n "* Grant admin access? [y/N]: "; read -r _adm
  [[ "$_adm" =~ ^[Yy] ]] && admin_flag="--admin"
  cd /var/www/pterodactyl
  php artisan p:user:make \
    --username="$uname" --email="$email" \
    --name-first="$fname" --name-last="$lname" \
    --password="$pass" "$admin_flag"
  echo ""
  p_success "User '${uname}' created."
  echo -n "* Press ENTER to continue..."; read -r _
  echo ""
}

user_list() {
  print_brake 70
  output "User List"
  print_brake 70
  echo ""
  cd /var/www/pterodactyl
  php artisan tinker --execute="
    \Pterodactyl\Models\User::all(['id','username','email','root_admin','created_at'])
    ->each(fn(\$u) => printf(\"%-5s %-20s %-30s %s\n\",\$u->id,\$u->username,\$u->email,\$u->root_admin?'[ADMIN]':''));
  " 2>/dev/null || \
  mysql -u pterodactyl -p"${DB_PASS:-}" pterodactyl \
    -e "SELECT id,username,email,root_admin,created_at FROM users;" 2>/dev/null
  echo ""
  echo -n "* Press ENTER to continue..."; read -r _
  echo ""
}

user_delete() {
  print_brake 70
  output "Delete User"
  print_brake 70
  echo ""
  user_list
  local uid
  echo -n "* Enter user ID to delete: "; read -r uid
  echo -n "* Delete user ID ${uid}? This cannot be undone. [y/N]: "; read -r _c
  [[ "$_c" =~ ^[Yy] ]] || { echo -n "* Press ENTER to continue..."; read -r _; return; }
  cd /var/www/pterodactyl
  php artisan p:user:delete --user="$uid"
  p_success "User ${uid} deleted."
  echo -n "* Press ENTER to continue..."; read -r _
  echo ""
}

user_change_password() {
  print_brake 70
  output "Change Password"
  print_brake 70
  echo ""
  user_list
  local email pass
  echo -n "* Enter user e-mail: "; read -r email
  echo -n "* New password: "; read -rs pass; echo
  cd /var/www/pterodactyl
  php artisan tinker --execute="
    \$u = \Pterodactyl\Models\User::where('email','${email}')->firstOrFail();
    \$u->password = \Illuminate\Support\Facades\Hash::make('${pass}');
    \$u->save(); echo 'Password updated for '.\$u->username.PHP_EOL;
  "
  p_success "Password updated."
  echo -n "* Press ENTER to continue..."; read -r _
  echo ""
}

user_set_admin() {
  print_brake 70
  output "Toggle Admin"
  print_brake 70
  echo ""
  user_list
  local email
  echo -n "* Enter user e-mail: "; read -r email
  echo -n "* Grant admin to ${email}? n=revoke [y/N]: "; read -r _ans
  local flag=1
  [[ "$_ans" =~ ^[Yy] ]] || flag=0
  cd /var/www/pterodactyl
  php artisan tinker --execute="
    \$u = \Pterodactyl\Models\User::where('email','${email}')->firstOrFail();
    \$u->root_admin = ${flag}; \$u->save();
    echo 'Admin status set to ${flag} for '.\$u->username.PHP_EOL;
  "
  p_success "Admin status updated for ${email}."
  echo -n "* Press ENTER to continue..."; read -r _
  echo ""
}
