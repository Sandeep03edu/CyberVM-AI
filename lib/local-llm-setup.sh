#!/usr/bin/env bash
# lib/local-llm-setup.sh — apply coexistence-friendly tuning to the host Ollama
# service via a systemd drop-in (+ optional CPU governor / swappiness).
#
# The drop-in ONLY layers on top of the base /etc/systemd/system/ollama.service
# written by host-setup; it never edits that file. Reverting is therefore just a
# matter of deleting the drop-in (see lib/local-llm-remove.sh — cybervm ai untune).
#
# Called as: cybervm ai tune [options]
set -euo pipefail

: "${CYBERVM_HOME:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/common.sh
source "$CYBERVM_HOME/lib/common.sh"

DROPIN_DIR=/etc/systemd/system/ollama.service.d
DROPIN="$DROPIN_DIR/cybervm-llm-tune.conf"
STATE="$CYBERVM_HOME/config/ai/.llm-tune.state"

# ── defaults (coexistence-first: leave headroom for a VM running in parallel) ──
CPU_QUOTA=500        # percent-of-one-core; 500 = up to ~5 cores, ever
NICE=10              # higher = Ollama yields the CPU to VM/interactive work
KEEPALIVE=2m         # unload idle model to free ~2 GB RAM
CONTEXT=4096         # lighter prompt-eval + RAM than the base unit's 8192
SET_GOV=0            # --governor: opt-in (more speed, more heat/power)
SWAPPINESS=""        # --swappiness N: opt-in

usage() {
  cat <<U
Usage: cybervm ai tune [options]

  Applies a REVERSIBLE systemd drop-in so the host Ollama cannot monopolise the
  machine while a VM runs in parallel. Revert everything with: cybervm ai untune

Options (all optional; defaults shown):
  --cpu-quota PCT   Max CPU Ollama may use, percent-of-one-core (default ${CPU_QUOTA} = ~5 cores)
  --nice N          Scheduler niceness, higher yields more (default ${NICE})
  --keepalive DUR   Unload idle model after DUR to free RAM (default ${KEEPALIVE})
  --context N       Default context length (default ${CONTEXT}; base unit uses 8192)
  --governor        Also set CPU governor to 'performance' (faster; more heat/power)
  --swappiness N    Also set vm.swappiness=N (e.g. 10 to avoid swapping)
  -h, --help        Show this help
U
}

while [ $# -gt 0 ]; do
  case "$1" in
    --cpu-quota)  CPU_QUOTA="${2:?--cpu-quota needs a value}"; shift 2 ;;
    --nice)       NICE="${2:?--nice needs a value}"; shift 2 ;;
    --keepalive)  KEEPALIVE="${2:?--keepalive needs a value}"; shift 2 ;;
    --context)    CONTEXT="${2:?--context needs a value}"; shift 2 ;;
    --governor)   SET_GOV=1; shift ;;
    --swappiness) SWAPPINESS="${2:?--swappiness needs a value}"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    *) die "unknown option: $1 (see: cybervm ai tune --help)" ;;
  esac
done

command -v systemctl >/dev/null 2>&1 || die "systemctl not found — this tunes a systemd-managed Ollama."
systemctl list-unit-files ollama.service >/dev/null 2>&1 \
  || die "ollama.service not found — run: cybervm host-setup"

log "Writing Ollama tuning drop-in (CPUQuota=${CPU_QUOTA}%, Nice=${NICE}, keep_alive=${KEEPALIVE}, context=${CONTEXT})…"
sudo install -d "$DROPIN_DIR"
sudo tee "$DROPIN" >/dev/null <<CONF
# Managed by 'cybervm ai tune' (lib/local-llm-setup.sh).
# This is a drop-in override; delete it to revert (cybervm ai untune).
[Service]
CPUQuota=${CPU_QUOTA}%
Nice=${NICE}
Environment="OLLAMA_KEEP_ALIVE=${KEEPALIVE}"
Environment="OLLAMA_CONTEXT_LENGTH=${CONTEXT}"
CONF

sudo systemctl daemon-reload
sudo systemctl restart ollama
ok "Drop-in applied and ollama restarted."

# ── runtime (non-file) settings: record prior value ONCE so untune can restore ──
mkdir -p "$(dirname "$STATE")"
touch "$STATE"
record_prev() { grep -q "^$1=" "$STATE" 2>/dev/null || printf '%s=%s\n' "$1" "$2" >> "$STATE"; }

if [ "$SET_GOV" = 1 ]; then
  if command -v cpupower >/dev/null 2>&1; then
    cur=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo unknown)
    [ "$cur" != performance ] && record_prev GOVERNOR_PREV "$cur"
    sudo cpupower frequency-set -g performance >/dev/null \
      && ok "CPU governor -> performance (was ${cur})" \
      || warn "failed to set governor"
  else
    warn "cpupower not installed; skipping --governor (apt install linux-cpupower)"
  fi
fi

if [ -n "$SWAPPINESS" ]; then
  prev=$(cat /proc/sys/vm/swappiness 2>/dev/null || echo 60)
  record_prev SWAPPINESS_PREV "$prev"
  sudo sysctl -q vm.swappiness="$SWAPPINESS" \
    && ok "vm.swappiness=${SWAPPINESS} (was ${prev})" \
    || warn "failed to set swappiness"
fi

# drop an empty state file if nothing runtime was changed (keeps untune simple)
[ -s "$STATE" ] || rm -f "$STATE"

ok "Ollama tuned. Verify: systemctl show ollama -p CPUQuota,Nice,Environment"
ok "Revert anytime:      cybervm ai untune"
