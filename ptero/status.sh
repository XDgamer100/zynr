#!/usr/bin/env bash
# Zynr.Cloud -- Status, Logs & Egg Registry helper
# Sourced by install.sh
# ================================================================
#  STATUS & LOGS
# ================================================================
view_status() {
  print_brake 70; output "System Status"; print_brake 70; echo ""
  local RED_DOT="${RED}*${NC}" GRN_DOT="${GREEN}*${NC}" YLW_DOT="${YELLOW}*${NC}"
  _svc_status() {
    local svc="$1" label="$2"
    if systemctl is-active "$svc" &>/dev/null; then
      echo -e "  ${GRN_DOT} ${label} (${CYAN}active${NC})"
    elif systemctl is-enabled "$svc" &>/dev/null; then
      echo -e "  ${YLW_DOT} ${label} (${YELLOW}inactive / enabled${NC})"
    else
      echo -e "  ${RED_DOT} ${label} (${RED}not found${NC})"
    fi
  }
  echo ""; print_brake 70; output "Services"; print_brake 70
  _svc_status nginx          "Nginx Web Server"
  _svc_status php8.3-fpm     "PHP 8.3 FPM"
  _svc_status mariadb        "MariaDB"
  _svc_status redis-server   "Redis"
  _svc_status pteroq         "Pterodactyl Queue Worker"
  _svc_status wings          "Pterodactyl Wings"
  _svc_status docker         "Docker"
  _svc_status cockpit.socket "Cockpit"
  _svc_status fail2ban       "Fail2Ban"
  _svc_status crowdsec       "CrowdSec"

  echo ""; print_brake 70; output "Versions"; print_brake 70
  panel_installed && echo -e "  Panel  : ${CYAN}v$(panel_version)${NC}" \
    || echo -e "  Panel  : ${RED}not installed${NC}"
  wings_installed && echo -e "  Wings  : ${CYAN}v$(wings_version)${NC}" \
    || echo -e "  Wings  : ${RED}not installed${NC}"
  blueprint_installed   && echo -e "  Blueprint: ${CYAN}installed${NC}" \
    || echo -e "  Blueprint: ${RED}not installed${NC}"
  php -v 2>/dev/null | head -1 | sed "s/^/  PHP    : ${CYAN}/" | sed "s/$/${NC}/" || true
  nginx -v 2>&1 | sed "s/^/  Nginx  : ${CYAN}/" | sed "s/$/${NC}/" || true

  echo ""; print_brake 70; output "Resources"; print_brake 70
  echo -e "  CPU    : $(grep -c ^processor /proc/cpuinfo) core(s) -- $(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)"
  local mem_total mem_avail
  mem_total=$(awk '/MemTotal/{printf "%.0f MB",$2/1024}' /proc/meminfo)
  mem_avail=$(awk '/MemAvailable/{printf "%.0f MB",$2/1024}' /proc/meminfo)
  echo -e "  RAM    : ${mem_avail} free / ${mem_total} total"
  df -h / | awk 'NR==2{printf "  Disk   : %s free / %s total (%s used)\n",$4,$2,$5}'

  echo ""; print_brake 70; output "Recent Logs"; print_brake 70
  output "[1] Pterodactyl Panel log"
  output "[2] Wings log"
  output "[3] Nginx error log"
  output "[4] Fail2Ban log"
  output ""
  output "[0] Back"
  echo -n "* View log: "; read -r lc
  case "$lc" in
    1) less +G /var/www/pterodactyl/storage/logs/laravel-"$(date +%Y-%m-%d)".log 2>/dev/null \
         || less +G /var/www/pterodactyl/storage/logs/laravel.log 2>/dev/null \
         || p_warning "No panel log found." ;;
    2) journalctl -u wings -n 100 --no-pager ;;
    3) less +G /var/log/nginx/error.log 2>/dev/null || p_warning "No nginx error log." ;;
    4) less +G /var/log/fail2ban.log 2>/dev/null || p_warning "Fail2Ban log not found." ;;
    0) return ;;
  esac
  echo -n "* Press ENTER to continue..."; read -r _; echo ""
}

# ================================================================
#  EGG REGISTRY  (pelican-eggs / parkervcp)
# ================================================================
# Arrays must be declared before reg() is defined (set -u compatibility)
declare -A EGG_NESTS
declare -A EGG_LABELS
declare -A EGG_URLS
PELICAN_BASE="https://raw.githubusercontent.com/pelican-eggs/eggs/master"
PARKERVCP_BASE="https://raw.githubusercontent.com/parkervcp/eggs/master"

reg() {
  local key="${1:-}" meta="${2:-}"
  # meta format:  "Category|Display Name|URL"
  EGG_NESTS["$key"]="${meta%%|*}"
  local rest="${meta#*|}"
  EGG_LABELS["$key"]="${rest%%|*}"
  EGG_URLS["$key"]="${rest##*|}"
}

# -- Chatbots -------------------------------------------------
reg "chatbot_discord_py"   "Chatbots|Discord.py Bot|${PELICAN_BASE}/chatbots/discord/discordpy/egg-discord-py-generic.json"
reg "chatbot_discord_js"   "Chatbots|Discord.js Bot|${PELICAN_BASE}/chatbots/discord/discordjs/egg-discord-js-generic.json"
reg "chatbot_redbot"       "Chatbots|Red-DiscordBot|${PELICAN_BASE}/chatbots/discord/redbot/egg-redbot.json"
reg "chatbot_sinusbot"     "Chatbots|SinusBot (TS3/Discord)|${PELICAN_BASE}/chatbots/sinusbot/egg-sinusbot.json"
reg "chatbot_botpress"     "Chatbots|Botpress|${PELICAN_BASE}/chatbots/botpress/egg-botpress.json"

# -- Databases -------------------------------------------------
reg "db_mongodb"           "Databases|MongoDB|${PELICAN_BASE}/database/mongodb/egg-mongo-d-b.json"
reg "db_redis"             "Databases|Redis|${PELICAN_BASE}/database/redis/egg-redis.json"
reg "db_mysql"             "Databases|MySQL 8|${PELICAN_BASE}/database/mysql/egg-my-s-q-l8.json"
reg "db_mariadb"           "Databases|MariaDB|${PELICAN_BASE}/database/mariadb/egg-maria-d-b.json"
reg "db_postgres"          "Databases|PostgreSQL|${PELICAN_BASE}/database/postgresql/egg-postgresql.json"

# -- Standalone Games -----------------------------------------
reg "game_terraria_tshock" "Standalone Games|Terraria (tShock)|${PELICAN_BASE}/game_eggs/terraria/tshock/egg-terraria-tshock.json"
reg "game_terraria_vanilla" "Standalone Games|Terraria (Vanilla)|${PELICAN_BASE}/game_eggs/terraria/terraria_vanilla/egg-terraria-vanilla.json"
reg "game_factorio"        "Standalone Games|Factorio|${PELICAN_BASE}/game_eggs/factorio/egg-factorio.json"
reg "game_rust"            "Standalone Games|Rust|${PARKERVCP_BASE}/game_eggs/rust/egg-rust.json"
reg "game_unturned"        "Standalone Games|Unturned|${PARKERVCP_BASE}/game_eggs/unturned/egg-unturned.json"
reg "game_stardew"         "Standalone Games|Stardew Valley Together|${PELICAN_BASE}/game_eggs/stardew_valley/egg-stardew-valley.json"
reg "game_7dtd"            "Standalone Games|7 Days to Die|${PARKERVCP_BASE}/game_eggs/7_days_to_die/egg-7-days-to-die.json"
reg "game_conan"           "Standalone Games|Conan Exiles|${PARKERVCP_BASE}/game_eggs/conan_exiles/egg-conan-exiles.json"
reg "game_dayz"            "Standalone Games|DayZ|${PARKERVCP_BASE}/game_eggs/dayz/egg-day-z.json"
reg "game_kf2"             "Standalone Games|Killing Floor 2|${PARKERVCP_BASE}/game_eggs/killing_floor_2/egg-killing-floor-2.json"
reg "game_mordhau"         "Standalone Games|Mordhau|${PARKERVCP_BASE}/game_eggs/mordhau/egg-mordhau.json"
reg "game_palworld"        "Standalone Games|Palworld|${PELICAN_BASE}/game_eggs/palworld/egg-palworld.json"

# -- SteamCMD Games --------------------------------------------
reg "steam_ark"            "SteamCMD Games|ARK: Survival Evolved|${PARKERVCP_BASE}/game_eggs/ark_survival_evolved/egg-ark-survival-evolved.json"
reg "steam_arksae"         "SteamCMD Games|ARK: Survival Ascended|${PELICAN_BASE}/game_eggs/ark_survival_ascended/egg-ark-survival-ascended.json"
reg "steam_gmod"           "SteamCMD Games|Garry's Mod|${PARKERVCP_BASE}/game_eggs/gmod/egg-gmod.json"
reg "steam_css"            "SteamCMD Games|Counter-Strike: Source|${PARKERVCP_BASE}/game_eggs/counter_strike_source/egg-cs-source.json"
reg "steam_csgo"           "SteamCMD Games|CS:GO|${PARKERVCP_BASE}/game_eggs/counter_strike_global_offensive/egg-counter-strike-global-offensive.json"
reg "steam_cs2"            "SteamCMD Games|Counter-Strike 2|${PELICAN_BASE}/game_eggs/counter_strike_2/egg-counter-strike2.json"
reg "steam_hl2dm"          "SteamCMD Games|HL2: Deathmatch|${PARKERVCP_BASE}/game_eggs/hl2dm/egg-hl2-dm.json"
reg "steam_tf2"            "SteamCMD Games|Team Fortress 2|${PARKERVCP_BASE}/game_eggs/tf2/egg-tf2.json"
reg "steam_left4dead2"     "SteamCMD Games|Left 4 Dead 2|${PARKERVCP_BASE}/game_eggs/left_4_dead_2/egg-left-4-dead-2.json"
reg "steam_insurgency"     "SteamCMD Games|Insurgency: Sandstorm|${PARKERVCP_BASE}/game_eggs/insurgency_sandstorm/egg-insurgency-sandstorm.json"
reg "steam_arma3"          "SteamCMD Games|ARMA 3|${PARKERVCP_BASE}/game_eggs/arma3/egg-arma3.json"
reg "steam_squad"          "SteamCMD Games|Squad|${PARKERVCP_BASE}/game_eggs/squad/egg-squad.json"
reg "steam_valheim"        "SteamCMD Games|Valheim|${PARKERVCP_BASE}/game_eggs/valheim/egg-valheim.json"
reg "steam_satisfactory"   "SteamCMD Games|Satisfactory|${PARKERVCP_BASE}/game_eggs/satisfactory/egg-satisfactory.json"
reg "steam_vrising"        "SteamCMD Games|V Rising|${PELICAN_BASE}/game_eggs/v_rising/egg-v-rising.json"
reg "steam_enshrouded"     "SteamCMD Games|Enshrouded|${PELICAN_BASE}/game_eggs/enshrouded/egg-enshrouded.json"

# -- Languages / Runtimes -------------------------------------
reg "lang_nodejs"          "Languages|Node.js (generic)|${PELICAN_BASE}/langs/nodejs/egg-node-js-generic.json"
reg "lang_nodejs18"        "Languages|Node.js 18|${PELICAN_BASE}/langs/nodejs/egg-node-j-s18.json"
reg "lang_nodejs20"        "Languages|Node.js 20|${PELICAN_BASE}/langs/nodejs/egg-node-j-s20.json"
reg "lang_python"          "Languages|Python (generic)|${PELICAN_BASE}/langs/python/egg-python-generic.json"
reg "lang_java17"          "Languages|Java 17 (generic)|${PELICAN_BASE}/langs/java/egg-java17.json"
reg "lang_java21"          "Languages|Java 21 (generic)|${PELICAN_BASE}/langs/java/egg-java21.json"
reg "lang_go"              "Languages|Go (generic)|${PELICAN_BASE}/langs/go/egg-go-generic.json"
reg "lang_rust"            "Languages|Rust (generic)|${PELICAN_BASE}/langs/rust/egg-rust-generic.json"
reg "lang_dotnet"          "Languages|.NET Core (generic)|${PELICAN_BASE}/langs/dotnet/egg-dot-net-generic.json"
reg "lang_elixir"          "Languages|Elixir (generic)|${PELICAN_BASE}/langs/elixir/egg-elixir-generic.json"
reg "lang_deno"            "Languages|Deno|${PELICAN_BASE}/langs/deno/egg-deno.json"
reg "lang_bun"             "Languages|Bun|${PELICAN_BASE}/langs/bun/egg-bun.json"

# -- Minecraft ------------------------------------------------
reg "mc_paper"             "Minecraft|Paper|${PELICAN_BASE}/minecraft/java/paper/egg-paper.json"
reg "mc_purpur"            "Minecraft|Purpur|${PELICAN_BASE}/minecraft/java/purpur/egg-purpur.json"
reg "mc_folia"             "Minecraft|Folia|${PELICAN_BASE}/minecraft/java/folia/egg-folia.json"
reg "mc_spigot"            "Minecraft|Spigot|${PELICAN_BASE}/minecraft/java/spigot/egg-spigot.json"
reg "mc_vanilla"           "Minecraft|Vanilla|${PELICAN_BASE}/minecraft/java/vanilla/egg-vanilla.json"
reg "mc_forge"             "Minecraft|Forge (1.20+)|${PELICAN_BASE}/minecraft/java/forge/egg-forge.json"
reg "mc_neoforge"          "Minecraft|NeoForge|${PELICAN_BASE}/minecraft/java/neoforge/egg-neo-forge.json"
reg "mc_fabric"            "Minecraft|Fabric|${PELICAN_BASE}/minecraft/java/fabric/egg-fabric.json"
reg "mc_quilt"             "Minecraft|Quilt|${PELICAN_BASE}/minecraft/java/quilt/egg-quilt.json"
reg "mc_sponge"            "Minecraft|SpongeVanilla|${PELICAN_BASE}/minecraft/java/sponge/egg-spongevanilla.json"
reg "mc_bungeecord"        "Minecraft|BungeeCord|${PELICAN_BASE}/minecraft/java/bungeecord/egg-bungeecord.json"
reg "mc_velocity"          "Minecraft|Velocity|${PELICAN_BASE}/minecraft/java/velocity/egg-velocity.json"
reg "mc_waterfall"         "Minecraft|Waterfall|${PELICAN_BASE}/minecraft/java/waterfall/egg-waterfall.json"
reg "mc_bedrock"           "Minecraft|Bedrock (BDS)|${PELICAN_BASE}/minecraft/bedrock/egg-bedrock.json"
reg "mc_geyser"            "Minecraft|GeyserMC Standalone|${PELICAN_BASE}/minecraft/java/geyser/egg-geyser-standalone.json"
reg "mc_limbo"             "Minecraft|Limbo|${PELICAN_BASE}/minecraft/java/limbo/egg-limbo.json"
reg "mc_mohist"            "Minecraft|Mohist (Forge+Bukkit)|${PELICAN_BASE}/minecraft/java/mohist/egg-mohist.json"
reg "mc_magma"             "Minecraft|Magma (Forge+Paper)|${PELICAN_BASE}/minecraft/java/magma/egg-magma.json"
reg "mc_arclight"          "Minecraft|Arclight|${PELICAN_BASE}/minecraft/java/arclight/egg-arclight.json"
reg "mc_pufferfish"        "Minecraft|Pufferfish|${PELICAN_BASE}/minecraft/java/pufferfish/egg-pufferfish.json"

# -- Storage --------------------------------------------------
reg "storage_minio"        "Storage|MinIO|${PELICAN_BASE}/storage/minio/egg-minio.json"
reg "storage_filebrowser"  "Storage|File Browser|${PELICAN_BASE}/storage/filebrowser/egg-filebrowser.json"
reg "storage_syncthing"    "Storage|Syncthing|${PELICAN_BASE}/storage/syncthing/egg-syncthing.json"
reg "storage_nextcloud"    "Storage|Nextcloud|${PELICAN_BASE}/storage/nextcloud/egg-nextcloud.json"

# -- Voice -----------------------------------------------------
reg "voice_teamspeak3"     "Voice|TeamSpeak 3|${PELICAN_BASE}/voice_servers/teamspeak3/egg-teamspeak3.json"
reg "voice_mumble"         "Voice|Mumble|${PELICAN_BASE}/voice_servers/mumble/egg-mumble.json"

# -- Software -------------------------------------------------
reg "sw_gitea"             "Software|Gitea|${PELICAN_BASE}/software/gitea/egg-gitea.json"
reg "sw_ghost"             "Software|Ghost Blog|${PELICAN_BASE}/software/ghost/egg-ghost.json"
reg "sw_wordpress"         "Software|WordPress (PHP)|${PELICAN_BASE}/software/wordpress/egg-wordpress.json"
reg "sw_uptime_kuma"       "Software|Uptime Kuma|${PELICAN_BASE}/software/uptime_kuma/egg-uptime-kuma.json"
reg "sw_vaultwarden"       "Software|Vaultwarden|${PELICAN_BASE}/software/vaultwarden/egg-vaultwarden.json"
reg "sw_grafana"           "Software|Grafana|${PELICAN_BASE}/software/grafana/egg-grafana.json"
reg "sw_prometheus"        "Software|Prometheus|${PELICAN_BASE}/software/prometheus/egg-prometheus.json"
reg "sw_jitsi"             "Software|Jitsi Meet|${PELICAN_BASE}/software/jitsi/egg-jitsi-meet.json"
reg "sw_meilisearch"       "Software|MeiliSearch|${PELICAN_BASE}/software/meilisearch/egg-meilisearch.json"
reg "sw_code_server"       "Software|code-server (VSCode)|${PELICAN_BASE}/software/code_server/egg-code-server.json"

# ================================================================
#  EGG MENU  (browse, bulk install, single import)
# ================================================================
