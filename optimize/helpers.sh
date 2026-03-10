#!/usr/bin/env bash
# Zynr.Cloud -- Optimization helpers (backup, sysctl, cpufreq)
# Sourced by install.sh
# ================================================================
#  HELPERS -- backup & sysctl apply
# ================================================================
_backup_init() {
  mkdir -p "$BACKUP_DIR"
  output "Backup directory: ${BACKUP_DIR}"
}

_sysctl_set() {
  # _sysctl_set key value comment
  local key="$1" val="$2" comment="${3:-}"
  [[ -n "$comment" ]] && echo "# ${comment}" >> "$SYSCTL_FILE"
  echo "${key} = ${val}" >> "$SYSCTL_FILE"
  sysctl -w "${key}=${val}" &>/dev/null || true
}

_sysctl_header() {
  mkdir -p "$(dirname "$SYSCTL_FILE")"
  echo ""                                        >> "$SYSCTL_FILE"
  echo "# -- $* --$(_rep - 30))"    >> "$SYSCTL_FILE"
}

_cpufreq_write() {
  # Write to all CPU cpufreq files safely
  local file="$1" val="$2"
  for f in /sys/devices/system/cpu/cpu*/cpufreq/${file}; do
    [[ -f "$f" ]] && echo "$val" > "$f" 2>/dev/null || true
  done
}

_persist_cpufreq() {
  # Make cpufreq settings survive reboot via udev rule
  local gov="$1"
  cat > /etc/udev/rules.d/99-zynr-cpufreq.rules <<UDEV
# Zynr.Cloud -- CPU governor on boot
ACTION=="add", SUBSYSTEM=="cpu", ATTR{cpufreq/scaling_governor}="${gov}"
UDEV
  # Also write to /etc/default/cpufrequtils if available
  if [[ -f /etc/default/cpufrequtils ]]; then
    sed -i "s/^GOVERNOR=.*/GOVERNOR=\"${gov}\"/" /etc/default/cpufrequtils
  else
    echo "GOVERNOR=\"${gov}\"" > /etc/default/cpufrequtils 2>/dev/null || true
  fi
}

# ================================================================
#  [1] CPU GOVERNOR & FREQUENCY SCALING
# ================================================================
