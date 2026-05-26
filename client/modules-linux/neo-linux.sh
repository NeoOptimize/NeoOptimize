#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-SystemDiagnostics}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_DIR="$ROOT_DIR/reports/linux"
AUDIT_DIR="$ROOT_DIR/reports/linux/audit"
APPLY_MODE="${NEO_APPLY:-0}"
APPROVAL_TOKEN="${NEO_LINUX_APPROVAL:-}"
mkdir -p "$REPORT_DIR"
mkdir -p "$AUDIT_DIR"

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

report_file() {
  printf '%s/%s_%s.log' "$REPORT_DIR" "$(timestamp | tr ':T' '--')" "$1"
}

run_cmd() {
  local label="$1"
  shift
  {
    printf '\n== %s ==\n' "$label"
    "$@" 2>&1 || true
  }
}

safety_log() {
  local level="$1"
  local message="$2"
  printf '%s [%s] %s\n' "$(timestamp)" "$level" "$message" >>"$AUDIT_DIR/safety.log"
}

is_denied_command() {
  local command="$1"
  local denied=(
    'rm[[:space:]]+-rf[[:space:]]+/'
    'mkfs([.[:space:]]|$)'
    'dd[[:space:]].*of=/dev/'
    'tune2fs[[:space:]].*-O[[:space:]]+\^has_journal'
    'fsck[[:space:]].*-y'
    'update-grub'
    'grub-mkconfig'
    'mitigations=off'
    'noibrs'
    'systemctl[[:space:]]+(disable|mask|stop)[[:space:]]+NetworkManager'
    'swapoff[[:space:]]+-a'
    '>[[:space:]]*/sys/power/state'
    '>[[:space:]]*/proc/sys/kernel/'
    '>[[:space:]]*/sys/block/'
    'hdparm[[:space:]]'
    'blockdev[[:space:]]+--set'
    'tc[[:space:]]+qdisc[[:space:]]+(add|replace|del)'
    'ethtool[[:space:]]+-K'
    'cpupower[[:space:]]+frequency-set'
  )
  for pattern in "${denied[@]}"; do
    if [[ "$command" =~ $pattern ]]; then
      return 0
    fi
  done
  return 1
}

is_allowed_write_command() {
  local command="$1"
  case "$command" in
    "sudo -n apt-get autoclean") return 0 ;;
    "sudo -n journalctl --vacuum-time=14d") return 0 ;;
    "find /tmp -mindepth 1 -maxdepth 1 -mtime +3 -print -delete") return 0 ;;
    *) return 1 ;;
  esac
}

require_write_approval() {
  local label="$1"
  local command="$2"

  if is_denied_command "$command"; then
    safety_log "DENY" "$label :: $command"
    printf '[DENY] %s blocked by NeoOptimize Linux safety policy.\n' "$label"
    return 1
  fi

  if ! is_allowed_write_command "$command"; then
    safety_log "DENY" "$label :: not in write allowlist :: $command"
    printf '[DENY] %s is not in the Linux write allowlist.\n' "$label"
    return 1
  fi

  if [[ "$APPLY_MODE" != "1" || "$APPROVAL_TOKEN" != "I_APPROVE_SAFE_LINUX_CLEANUP" ]]; then
    safety_log "SKIP" "$label :: approval missing :: $command"
    printf '[SKIP] %s requires NEO_APPLY=1 and NEO_LINUX_APPROVAL=I_APPROVE_SAFE_LINUX_CLEANUP.\n' "$label"
    return 1
  fi

  safety_log "ALLOW" "$label :: $command"
  return 0
}

safe_write_cmd() {
  local label="$1"
  local command="$2"
  {
    printf '\n== %s ==\n' "$label"
    if require_write_approval "$label" "$command"; then
      bash -c "$command" 2>&1 || true
    fi
  }
}

write_header() {
  local title="$1"
  printf 'NeoOptimize Linux Module: %s\n' "$title"
  printf 'Generated: %s\n' "$(timestamp)"
  printf 'Host: %s\n' "$(hostname 2>/dev/null || printf unknown)"
  printf 'Kernel: %s\n\n' "$(uname -srmo 2>/dev/null || uname -a)"
}

system_diagnostics() {
  local out
  out="$(report_file system_diagnostics)"
  {
    write_header "SystemDiagnostics"
    run_cmd "OS release" cat /etc/os-release
    run_cmd "Uptime" uptime
    run_cmd "Memory" free -h
    run_cmd "Swap" swapon --show
    run_cmd "CPU top" sh -c "ps -eo pid,comm,pcpu,pmem,rss,args --sort=-pcpu | head -20"
    run_cmd "RAM top" sh -c "ps -eo pid,comm,rss,pcpu,pmem,args --sort=-rss | head -20"
    run_cmd "Disk usage" df -hT
    run_cmd "Failed systemd units" systemctl --failed --no-pager
    run_cmd "NetworkManager status" systemctl status NetworkManager --no-pager
    run_cmd "UFW status" ufw status verbose
    run_cmd "Recent critical journal" journalctl -p 0..3 -n 120 --no-pager
  } >"$out"
  printf 'Linux diagnostics report: %s\n' "$out"
}

network_diagnose() {
  local out
  out="$(report_file network)"
  {
    write_header "Network"
    run_cmd "NetworkManager enabled" systemctl is-enabled NetworkManager
    run_cmd "NetworkManager active" systemctl is-active NetworkManager
    run_cmd "NetworkManager devices" nmcli device status
    run_cmd "Connections" nmcli connection show
    run_cmd "IP addresses" ip -br address
    run_cmd "Routes" ip route
    run_cmd "DNS" resolvectl status
    run_cmd "Ping gateway" sh -c "ip route | awk '/default/ {print \$3; exit}' | xargs -r -I{} ping -c 3 -W 2 {}"
    run_cmd "Ping public DNS" ping -c 3 -W 2 1.1.1.1
  } >"$out"
  printf 'Linux network report: %s\n' "$out"
}

deep_scan() {
  local out
  out="$(report_file deep_scan)"
  {
    write_header "DeepScan"
    run_cmd "Boot errors" journalctl -b -p 0..4 --no-pager
    run_cmd "OOM events" journalctl -k --grep='Out of memory|oom-killer|Killed process' --no-pager
    run_cmd "Package audit" sh -c "command -v apt >/dev/null && apt list --upgradable 2>/dev/null || true"
    run_cmd "Open listening ports" sh -c "command -v ss >/dev/null && ss -tulpen || netstat -tulpen"
    run_cmd "SMART summary" sh -c "command -v smartctl >/dev/null && for d in /dev/sd? /dev/nvme?n?; do [ -e \"\$d\" ] && sudo -n smartctl -H \"\$d\"; done || true"
  } >"$out"
  printf 'Linux deep scan report: %s\n' "$out"
}

cleaner() {
  local out
  out="$(report_file cleaner)"
  {
    write_header "Cleaner"
    printf 'Mode: %s\n\n' "${NEO_APPLY:-dry-run}"
    run_cmd "APT cache estimate" sh -c "du -sh /var/cache/apt/archives 2>/dev/null || true"
    run_cmd "Journal disk usage" journalctl --disk-usage
    run_cmd "User cache estimate" sh -c "du -sh \"$HOME/.cache\" 2>/dev/null || true"
    if [[ "${NEO_APPLY:-0}" == "1" ]]; then
      safe_write_cmd "APT autoclean" "sudo -n apt-get autoclean"
      safe_write_cmd "Journal vacuum 14 days" "sudo -n journalctl --vacuum-time=14d"
      safe_write_cmd "Temp cleanup" "find /tmp -mindepth 1 -maxdepth 1 -mtime +3 -print -delete"
    else
      printf '\nDry-run only. Safe cleanup apply additionally requires NEO_LINUX_APPROVAL=I_APPROVE_SAFE_LINUX_CLEANUP.\n'
    fi
  } >"$out"
  printf 'Linux cleaner report: %s\n' "$out"
}

integrity_scan() {
  local out
  out="$(report_file integrity)"
  {
    write_header "IntegrityScan"
    run_cmd "dpkg audit" sh -c "command -v dpkg >/dev/null && dpkg --audit || true"
    run_cmd "debsums changed files" sh -c "command -v debsums >/dev/null && sudo -n debsums -s || true"
    run_cmd "Failed services" systemctl --failed --no-pager
    run_cmd "Kernel errors" journalctl -k -p 0..3 -n 200 --no-pager
  } >"$out"
  printf 'Linux integrity report: %s\n' "$out"
}

power_audit() {
  local out
  out="$(report_file power)"
  {
    write_header "Power"
    run_cmd "Power profile" sh -c "command -v powerprofilesctl >/dev/null && powerprofilesctl get || true"
    run_cmd "CPU governor" sh -c "grep -H . /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null | head -32 || true"
    run_cmd "Thermal zones" sh -c "for z in /sys/class/thermal/thermal_zone*; do [ -r \"\$z/temp\" ] && printf '%s ' \"\$z\" && cat \"\$z/temp\"; done"
  } >"$out"
  printf 'Linux power report: %s\n' "$out"
}

privacy_review() {
  local out
  out="$(report_file privacy)"
  {
    write_header "Privacy"
    run_cmd "Recent logins" last -n 20
    run_cmd "Listening sockets" sh -c "command -v ss >/dev/null && ss -tulpen || netstat -tulpen"
    run_cmd "Autostart entries" sh -c "find \"$HOME/.config/autostart\" /etc/xdg/autostart -maxdepth 1 -type f -name '*.desktop' -print 2>/dev/null || true"
    run_cmd "Browser cache estimate" sh -c "du -sh \"$HOME/.cache/mozilla\" \"$HOME/.cache/google-chrome\" \"$HOME/.cache/chromium\" 2>/dev/null || true"
    run_cmd "User services" systemctl --user list-units --type=service --state=running --no-pager
  } >"$out"
  printf 'Linux privacy report: %s\n' "$out"
}

update_manager() {
  local out
  out="$(report_file update)"
  {
    write_header "NeoUpdate"
    run_cmd "Current package updates" sh -c "command -v apt >/dev/null && apt list --upgradable 2>/dev/null || true"
    run_cmd "NeoOptimize package files" sh -c "find . -maxdepth 2 -type f \\( -name 'NeoOptimize*' -o -name '*.sha256' \\) -print"
    run_cmd "NeoOptimize local hashes" sh -c "find . -maxdepth 2 -type f \\( -name 'NeoOptimize' -o -name '*.ps1' -o -name '*.sh' \\) -print0 | xargs -0 sha256sum 2>/dev/null | head -80"
    printf '\nPolicy: update install requires signed artifact and SHA-256 verification.\n'
  } >"$out"
  printf 'Linux update report: %s\n' "$out"
}

script_forge() {
  local out
  out="$(report_file script_forge)"
  {
    write_header "AIScriptForge"
    printf 'Mode: read-only draft.\n\n'
    printf 'Suggested safe Linux command drafts:\n'
    printf '  - systemctl is-enabled NetworkManager && systemctl is-active NetworkManager\n'
    printf '  - free -h && swapon --show\n'
    printf '  - journalctl -p 0..3 -n 120 --no-pager\n'
    printf '  - df -hT && systemctl --failed --no-pager\n'
    printf '\nDenied categories remain blocked by Linux safety policy.\n'
  } >"$out"
  printf 'Linux script forge report: %s\n' "$out"
}

local_ai_setup() {
  local out
  out="$(report_file local_ai)"
  {
    write_header "LocalAISetup"
    run_cmd "Ollama binary" sh -c "command -v ollama || true"
    run_cmd "Ollama service" sh -c "systemctl --user status ollama --no-pager || systemctl status ollama --no-pager || true"
    run_cmd "Ollama models" sh -c "command -v ollama >/dev/null && ollama list || true"
    printf '\nRecommended local models: neo-light:latest for daily use, neo:latest for deeper reasoning when RAM allows.\n'
    printf 'Policy: model install is explicit operator action; no silent download from Linux module.\n'
  } >"$out"
  printf 'Linux local AI report: %s\n' "$out"
}

ai_plan() {
  local out
  out="$(report_file ai_plan)"
  {
    write_header "AIPlan"
    system_diagnostics
    printf '\nRecommended safe Linux care plan:\n'
    printf '1. Stabilize NetworkManager boot enablement before any network tuning.\n'
    printf '2. Keep zram/swap configured before running browser, VM, and local model workloads together.\n'
    printf '3. Run cleaner in dry-run first; apply only apt autoclean, journal vacuum, and old /tmp cleanup.\n'
    printf '4. Kernel, bootloader, filesystem repair, NetworkManager disable/mask/stop, block-device tuning, and power-state writes are deny-by-default.\n'
    printf '5. Write actions require signed/approved operation path; current Linux module only allows safe cleanup with explicit approval token.\n'
  } >"$out"
  printf 'Linux AI plan report: %s\n' "$out"
}

safety_policy() {
  local out
  out="$(report_file safety_policy)"
  {
    write_header "SafetyPolicy"
    printf 'Default mode: read-only diagnostics.\n'
    printf 'Write gate: NEO_APPLY=1 plus NEO_LINUX_APPROVAL=I_APPROVE_SAFE_LINUX_CLEANUP.\n'
    printf 'Write allowlist:\n'
    printf '  - sudo -n apt-get autoclean\n'
    printf '  - sudo -n journalctl --vacuum-time=14d\n'
    printf '  - find /tmp -mindepth 1 -maxdepth 1 -mtime +3 -print -delete\n'
    printf 'Deny-by-default categories:\n'
    printf '  - bootloader/grub mutation\n'
    printf '  - filesystem destructive repair or journal removal\n'
    printf '  - NetworkManager disable/mask/stop\n'
    printf '  - block-device/kernel/sysfs/procfs tuning\n'
    printf '  - power-state writes\n'
    printf '  - rm -rf root-class destructive deletion\n'
    printf '\nAudit log: %s/safety.log\n' "$AUDIT_DIR"
  } >"$out"
  printf 'Linux safety policy report: %s\n' "$out"
}

case "$ACTION" in
  Dashboard|Collect|SystemDiagnostics|WindowsDoctor|WindowsErrorFix|SystemRepair)
    system_diagnostics
    ;;
  Cleaner|CleanAll|Maintenance|SmartOptimize|SmartBooster)
    cleaner
    ;;
  Privacy|Apps)
    privacy_review
    ;;
  DeepScan|ThreatMonitor)
    deep_scan
    ;;
  Network)
    network_diagnose
    ;;
  Power)
    power_audit
    ;;
  IntegrityScan|Security|Autoimmune)
    integrity_scan
    ;;
  LinuxSafety|Policy)
    safety_policy
    ;;
  AIPlan|NEOAgentic)
    ai_plan
    ;;
  AIScriptForge|AIInteractive|AICatalog)
    script_forge
    ;;
  LocalAISetup|AIProviders|AIEnvironment)
    local_ai_setup
    ;;
  NeoUpdate)
    update_manager
    ;;
  *)
    system_diagnostics
    ;;
esac
