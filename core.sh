#!/usr/bin/env bash
# ================================================================
#  Zynr.Cloud v5.1.1  --  Core: Colors * Helpers * Detection
#  Sourced by install.sh; do not run directly.
# ================================================================

set -Eeuo pipefail

# -- Pterodactyl-style output helpers (defined FIRST so _on_err can use them)
COLOR_YELLOW='\033[1;33m'
COLOR_GREEN='\033[0;32m'
COLOR_RED='\033[0;31m'
COLOR_NC='\033[0m'

output()    { echo -e "* $1"; }
p_success() { echo ""; echo -e "* ${COLOR_GREEN}SUCCESS${COLOR_NC}: $1"; echo ""; }
p_error()   { echo ""; echo -e "* ${COLOR_RED}ERROR${COLOR_NC}: $1" 1>&2; echo ""; }
p_warning() { echo ""; echo -e "* ${COLOR_YELLOW}WARNING${COLOR_NC}: $1"; echo ""; }
print_brake() {
  for ((n = 0; n < $1; n++)); do echo -n "#"; done
  echo ""
}

trap '_on_err $LINENO' ERR
_on_err() {
  spinner_stop 2>/dev/null || true
  echo "" >&2
  print_brake 70 >&2
  echo "* ERROR: Unexpected error on line $1" >&2
  echo "* Check the output above for details." >&2
  print_brake 70 >&2
  echo "" >&2
  exit 1
}

# -- Colours ------------------------------------------------------
readonly RED='\033[0;31m'
readonly RED_B='\033[1;31m'
readonly GREEN='\033[0;32m'
readonly GREEN_B='\033[1;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly CYAN_B='\033[1;36m'
readonly BLUE='\033[0;34m'
readonly BLUE_B='\033[1;34m'
readonly MAGENTA='\033[0;35m'
readonly MAGENTA_B='\033[1;35m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly ITALIC='\033[3m'
readonly UNDER='\033[4m'
readonly WHITE='\033[1;37m'
readonly GRAY='\033[0;37m'
readonly NC='\033[0m'

# Box-drawing constants
readonly BOX_TL='+' BOX_TR='+' BOX_BL='+' BOX_BR='+'
readonly BOX_H='-'  BOX_V='|'
readonly BOX_ML='+' BOX_MR='+'
readonly LN_H='-'   LN_V='|'   LN_TL='+' LN_TR='+' LN_BL='+' LN_BR='+'
readonly TICK="${GREEN_B}[+]${NC}"
readonly CROSS="${RED_B}[!]${NC}"
readonly ARROW="${CYAN_B}>${NC}"
readonly BULLET="${CYAN}*${NC}"

# (output/p_success/p_error/p_warning/print_brake defined above, before trap)

# -- Global state -------------------------------------------------
OS=""; OS_VER=""; OS_CODENAME=""
PHP_VER="8.3"
PANEL_DOMAIN=""; ADMIN_EMAIL=""; ADMIN_USER=""
ADMIN_PASS=""; ADMIN_FNAME=""; ADMIN_LNAME=""
TZ_INPUT="UTC"
WINGS_DOMAIN=""; WINGS_EMAIL=""
SSL_METHOD="letsencrypt"
CF_TOKEN=""
PAY_DOMAIN=""; FOSS_DOMAIN=""

[[ -f /etc/.ptero_env ]] && source /etc/.ptero_env 2>/dev/null || true

# -- Output helpers ------------------------------------------------
_W=64   # box inner width

# Safe char repeat: _rep CHAR COUNT  (avoids printf flag issues with - chars)
_rep() {
  local char="$1" n="${2:-0}" out="" i=0
  while (( i < n )); do out="${out}${char}"; (( i++ )); done
  printf '%s' "$out"
}

info()    { echo -e "* $*"; }
warn()    { echo -e "* WARNING: $*"; }
error()   { echo -e "\n* ERROR: $*\n" >&2; exit 1; }
success() { echo -e "* $*"; }
step()    { echo -e "\n  ${CYAN_B}  >  ${BOLD}$*${NC}"; }
detail()  { echo -e "  ${DIM}     $*${NC}"; }
label()   { printf "  ${GRAY}%-22s${NC} ${WHITE}%s${NC}\n" "$1" "$2"; }

divider() {
  echo -e "  ${DIM}$(_rep "${LN_H}" $_W)${NC}"
}

thin_divider() {
  echo -e "  ${DIM}$(_rep - $_W)${NC}"
}

section() {
  local title="$*"
  local inner=$(( _W - 2 ))
  echo ""
  echo -e "  ${CYAN_B}${LN_TL}$(_rep "${BOX_H}" $_W)${LN_TR}${NC}"
  printf  "  ${CYAN_B}${LN_V}${NC}  ${BOLD}${WHITE}%-${inner}s${NC}${CYAN_B}${LN_V}${NC}\n" " $title"
  echo -e "  ${CYAN_B}${LN_BL}$(_rep "${BOX_H}" $_W)${LN_BR}${NC}"
  echo ""
}

header_box() {
  # Double-line box for major titles
  local title="$*"
  local inner=$(( _W - 2 ))
  echo ""
  echo -e "  ${MAGENTA_B}${BOX_TL}$(_rep "${BOX_H}" $_W)${BOX_TR}${NC}"
  printf  "  ${MAGENTA_B}${BOX_V}${NC}  ${BOLD}${WHITE}%-${inner}s${NC}${MAGENTA_B}${BOX_V}${NC}\n" " $title"
  echo -e "  ${MAGENTA_B}${BOX_BL}$(_rep "${BOX_H}" $_W)${BOX_BR}${NC}"
  echo ""
}

confirm() {
  local msg="${1:-Continue?}" ans
  echo ""
  printf "  ${CYAN_B}?${NC}  ${BOLD}%s${NC} ${DIM}[y/N]${NC}: " "$msg"
  read -r ans
  [[ "$ans" =~ ^[Yy](es)?$ ]]
}

press_enter() {
  echo ""
  printf "  ${DIM}${ITALIC}Press ENTER to continue...${NC}"
  read -r _
  echo ""
}

# -- Spinner -------------------------------------------------------
_SPIN_PID=0
spinner_start() {
  local msg="${1:-Working}"
  local frames=('|' '/' '-' '\\' '|' '/' '-' '\\' '|' '/')
  (
    local i=0
    while true; do
      printf "\r  ${CYAN_B}%s${NC}  ${BOLD}%s${NC}   " "${frames[$i]}" "$msg"
      i=$(( (i+1) % ${#frames[@]} ))
      sleep 0.1
    done
  ) &
  _SPIN_PID=$!
  disown "$_SPIN_PID" 2>/dev/null || true
}

spinner_stop() {
  if [[ $_SPIN_PID -ne 0 ]]; then
    kill "$_SPIN_PID" 2>/dev/null || true
    wait "$_SPIN_PID" 2>/dev/null || true
    _SPIN_PID=0
    printf "\r\033[2K"  # clear spinner line
  fi
}

# -- Step counter --------------------------------------------------
_STEP_TOTAL=0
_STEP_CUR=0
steps_init() { _STEP_TOTAL="${1:-0}"; _STEP_CUR=0; }
step_n() {
  (( _STEP_CUR++ )) || true
  local pct=0
  [[ $_STEP_TOTAL -gt 0 ]] && pct=$(( _STEP_CUR * 100 / _STEP_TOTAL ))
  local filled=$(( pct * 30 / 100 ))
  local bar="${GREEN_B}$(_rep "#" "$filled")${DIM}$(_rep "." "$(( _W - filled ))")${NC}"
  echo ""
  echo -e "  ${CYAN_B}[${_STEP_CUR}/${_STEP_TOTAL}]${NC} ${BOLD}$*${NC}"
  echo -e "  ${bar} ${DIM}${pct}%${NC}"
}

# -- Badge helpers -------------------------------------------------
badge_ok()  { printf "${GREEN_B}%-12s${NC}" " [READY]  "; }
badge_no()  { printf "${RED}%-12s${NC}"     " [ABSENT] "; }
badge_up()  { printf "${YELLOW}%-12s${NC}"  " [UPDATE] "; }

# -- Preconditions -------------------------------------------------
require_root()        { [[ $EUID -eq 0 ]] || error "This script must run as root. Try: sudo bash $0"; }
panel_installed()     { [[ -f /var/www/pterodactyl/artisan ]]; }
wings_installed()     { [[ -f /usr/local/bin/wings ]]; }
blueprint_installed() { [[ -f /var/www/pterodactyl/blueprint.json ]]; }

# -- Version queries -----------------------------------------------
panel_version() {
  panel_installed || { echo "---"; return; }
  cd /var/www/pterodactyl
  php artisan --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "?"
}
wings_version() {
  wings_installed || { echo "---"; return; }
  /usr/local/bin/wings --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "?"
}
blueprint_version() {
  blueprint_installed || { echo "---"; return; }
  jq -r '.version' /var/www/pterodactyl/blueprint.json 2>/dev/null || echo "?"
}
github_latest() {
  curl -fsSL "https://api.github.com/repos/$1/releases/latest" 2>/dev/null \
    | grep '"tag_name"' | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "unknown"
}

# ================================================================
#  MULTI-SELECT HELPER  (used by Cockpit, Panels, DDoS, Blueprint)
#  Usage: multi_select "Title" KEY1 "label1"  KEY2 "label2" ...
#  Result stored in global array: SELECTED_ITEMS
# ================================================================
SELECTED_ITEMS=()

multi_select() {
  local title="$1"; shift
  local -a keys=() labels=()
  while [[ $# -ge 2 ]]; do keys+=("$1"); labels+=("$2"); shift 2; done
  local count=${#keys[@]}
  SELECTED_ITEMS=()

  local inner=$(( _W - 2 ))
  echo ""
  echo -e "  ${BLUE_B}${LN_TL}$(_rep "${BOX_H}" $_W)${LN_TR}${NC}"
  printf  "  ${BLUE_B}${LN_V}${NC}  ${BOLD}${WHITE}%-${inner}s${NC}${BLUE_B}${LN_V}${NC}\n" " =  $title"
  echo -e "  ${BLUE_B}${BOX_ML}$(_rep "${LN_H}" $_W)${BOX_MR}${NC}"
  echo ""

  local i
  for i in "${!keys[@]}"; do
    printf "  ${BLUE_B}  %2d${NC}  ${DIM}[ ]${NC}  ${WHITE}%s${NC}\n" "$((i+1))" "${labels[$i]}"
  done
  local all_n=$(( count + 1 ))
  echo ""
  printf "  ${GREEN_B}  %2d${NC}  ${GREEN}[x]${NC}  ${GREEN_B}%s${NC}\n" "$all_n" "Select ALL"
  printf "  ${RED}   0${NC}  ${RED}[ ]${NC}  ${RED}%s${NC}\n" "Skip / None"
  echo ""
  echo -e "  ${BLUE_B}${LN_BL}$(_rep "${LN_H}" $_W)${LN_BR}${NC}"
  echo ""
  printf "  ${CYAN_B}>${NC}  ${BOLD}Pick (comma-separated, e.g. ${DIM}1,3,5${NC}${BOLD} or ${DIM}${all_n}${NC}${BOLD} for all):${NC} "
  read -r raw

  IFS=',' read -ra tokens <<< "$raw"
  for t in "${tokens[@]}"; do
    t=$(echo "$t" | tr -d ' ')
    if   [[ "$t" == "$all_n" ]]; then SELECTED_ITEMS=("${keys[@]}"); return
    elif [[ "$t" == "0"      ]]; then SELECTED_ITEMS=(); return
    elif [[ "$t" =~ ^[0-9]+$ ]] && (( t >= 1 && t <= count )); then
      SELECTED_ITEMS+=("${keys[$((t-1))]}")
    fi
  done

  # Echo back selections
  if [[ ${#SELECTED_ITEMS[@]} -gt 0 ]]; then
    echo ""
    echo -e "  ${GREEN_B}Selected:${NC}"
    for item in "${SELECTED_ITEMS[@]}"; do
      local idx
      for idx in "${!keys[@]}"; do
        [[ "${keys[$idx]}" == "$item" ]] && \
          echo -e "    ${GREEN_B}[+]${NC}  ${labels[$idx]}" && break
      done
    done
    echo ""
  fi
}

is_selected() {
  local needle="$1"
  for item in "${SELECTED_ITEMS[@]}"; do [[ "$item" == "$needle" ]] && return 0; done
  return 1
}

# ================================================================
#  OS DETECTION
# ================================================================
detect_os() {
  [[ -f /etc/os-release ]] || error "/etc/os-release not found."
  source /etc/os-release
  OS="${ID:-}"; OS_VER="${VERSION_ID:-}"
  # VERSION_CODENAME is in /etc/os-release on modern systems; no need for lsb_release
  OS_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
  # Fallback: parse codename from VERSION field e.g. 12 (bookworm)
  if [[ -z "$OS_CODENAME" ]]; then
    OS_CODENAME=$(grep -oE '(jammy|noble|bookworm|trixie|focal|bullseye|buster)' /etc/os-release | head -1)
    [[ -z "$OS_CODENAME" ]] && error "Unable to detect OS codename."
  fi
  fi
  if [[ -z "$OS_CODENAME" ]]; then
    # Last resort: known version-to-codename map
    case "${OS_VER:-}" in
      22.04) OS_CODENAME="jammy" ;;
      24.04) OS_CODENAME="noble" ;;
      12)    OS_CODENAME="bookworm" ;;
      13)    OS_CODENAME="trixie" ;;
    esac
  fi
  case "$OS" in
    ubuntu) case "$OS_VER" in
      22.04) output "Ubuntu 22.04 LTS (Jammy) -- supported" ;;
      24.04) output "Ubuntu 24.04 LTS (Noble) -- supported" ;;
      20.04) p_warning "Ubuntu 20.04 LTS -- EOL. Upgrade recommended." ;;
      *)     error "Unsupported Ubuntu ${OS_VER}. Requires 22.04 or 24.04." ;;
    esac ;;
    debian) case "$OS_VER" in
      12) output "Debian 12 (Bookworm) -- supported" ;;
      13) output "Debian 13 (Trixie)   -- supported" ;;
      11) p_warning "Debian 11 -- EOL. Upgrade recommended." ;;
      *)  error "Unsupported Debian ${OS_VER}. Requires 12 or 13." ;;
    esac ;;
    *) error "Unsupported OS: '${OS}'." ;;
  esac
}

# ================================================================
#  BANNER
# ================================================================
banner() {
  clear
  echo ""
  printf "${CYAN_B}${BOLD}%s${NC}\n" "  +================================================================+"
  printf "${CYAN_B}${BOLD}%s${NC}\n" "  |                                                                |"
  printf "${CYAN_B}${BOLD}%s${NC}\n" "  |      ZZZZZ  Y   Y  N   N  RRRR      CCCC  L    IIIII         |"
  printf "${CYAN_B}${BOLD}%s${NC}\n" "  |          Z   Y Y   NN  N  R   R    C       L      I           |"
  printf "${CYAN_B}${BOLD}%s${NC}\n" "  |         Z     Y    N N N  RRRR     C       L      I           |"
  printf "${CYAN_B}${BOLD}%s${NC}\n" "  |        Z      Y    N  NN  R  R     C       L      I           |"
  printf "${CYAN_B}${BOLD}%s${NC}\n" "  |      ZZZZZ    Y    N   N  R   R     CCCC  LLLL  IIIII         |"
  printf "${CYAN_B}${BOLD}%s${NC}\n" "  |                                                                |"
  printf "${CYAN_B}${BOLD}  |${NC}${WHITE}${BOLD}      All-in-One Server Manager  v5.1.0  --  zynr.cloud      ${CYAN_B}${BOLD}|${NC}\n"
  printf "${CYAN_B}${BOLD}%s${NC}\n" "  +================================================================+"
  echo ""

  # System info row
  local ip os_str uptime_str date_str
  ip=$(curl -sf --max-time 3 https://api.ipify.org 2>/dev/null \
       || hostname -I 2>/dev/null | awk '{print $1}' || echo "N/A")
  os_str="${OS:-unknown} ${OS_VER:-}"
  uptime_str=$(uptime -p 2>/dev/null | sed 's/up //' || echo "N/A")
  date_str=$(date '+%Y-%m-%d  %H:%M %Z')

  echo -e "  ${CYAN_B}+$(_rep - $_W)+${NC}"
  printf "  ${CYAN_B}|${NC}  Host    : ${WHITE}%-51s${CYAN_B}|${NC}\n"  "$(hostname)"
  printf "  ${CYAN_B}|${NC}  IP      : ${WHITE}%-51s${CYAN_B}|${NC}\n"  "$ip"
  printf "  ${CYAN_B}|${NC}  OS      : ${WHITE}%-51s${CYAN_B}|${NC}\n"  "$os_str"
  printf "  ${CYAN_B}|${NC}  Uptime  : ${WHITE}%-51s${CYAN_B}|${NC}\n"  "$uptime_str"
  printf "  ${CYAN_B}|${NC}  Date    : ${WHITE}%-51s${CYAN_B}|${NC}\n"  "$date_str"
  echo -e "  ${CYAN_B}+$(_rep - $_W)+${NC}"

  # Install status row
  local pv wv bv
  pv=$(panel_version 2>/dev/null || echo "---")
  wv=$(wings_version 2>/dev/null || echo "---")
  bv=$(blueprint_version 2>/dev/null || echo "---")

  local ps="[--]" ws="[--]" bs="[--]"
  panel_installed     2>/dev/null && ps="${GREEN_B}[OK]${NC}" || ps="${DIM}[--]${NC}"
  wings_installed     2>/dev/null && ws="${GREEN_B}[OK]${NC}" || ws="${DIM}[--]${NC}"
  blueprint_installed 2>/dev/null && bs="${GREEN_B}[OK]${NC}" || bs="${DIM}[--]${NC}"

  printf "  ${CYAN_B}|${NC}  Panel     : %b  v%-10s  Wings    : %b  v%-10s  ${CYAN_B}|${NC}\n" "$ps" "$pv" "$ws" "$wv"
  printf "  ${CYAN_B}|${NC}  Blueprint : %b  v%-10s%30s${CYAN_B}|${NC}\n" "$bs" "$bv" ""
  echo -e "  ${CYAN_B}+$(_rep - $_W)+${NC}"
  echo ""
}

# ================================================================
#  MAIN MENU
# ================================================================
_menu_item() {
  # _menu_item  NUM  LABEL  [FLAG]
  local num="${1:-}" label="${2:-}" flag="${3:-}"
  local badge=""
  [[ "$flag" == "1" ]] && badge="  ${GREEN_B}[READY]${NC}" || true
  printf "    ${CYAN_B}[%-2s]${NC}  %-52s%b\n" "$num" "$label" "$badge"
}


# -- Optimization globals ------------------------------------------
CPU_VENDOR=""
CPU_MODEL=""
CPU_CORES=0
RAM_MB=0
BACKUP_DIR="/etc/zynr-backups/$(date +%Y%m%d-%H%M%S)"
SYSCTL_FILE="/etc/sysctl.d/99-zynr.conf"

detect_cpu() {
  CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs)
  CPU_CORES=$(nproc --all)
  if grep -qi "GenuineIntel" /proc/cpuinfo; then
    CPU_VENDOR="intel"
  elif grep -qi "AuthenticAMD" /proc/cpuinfo; then
    CPU_VENDOR="amd"
  else
    CPU_VENDOR="unknown"
  fi
  RAM_MB=$(awk '/MemTotal/{printf "%.0f",$2/1024}' /proc/meminfo)
}

# ================================================================
#  BANNER

_opt_item() {
  printf "    ${MAGENTA_B}%-4s${NC}  %s  %-42s\n" "[$1]" "$2" "$3"
}
