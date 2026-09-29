#!/usr/bin/env bash
# lib/local-llm-remove.sh — revert 'cybervm ai tune'.
#
# Reverting is deletion, not restoration: the tuning lives in a systemd DROP-IN
# (/etc/systemd/system/ollama.service.d/cybervm-llm-tune.conf) that only overrides
# the base ollama.service. Removing the drop-in + reloading makes systemd fall
# back to the base unit exactly (CPUQuota gone, Nice=0, KEEP_ALIVE=5m, CONTEXT=8192).
# Only the runtime settings that are NOT in the unit (CPU governor, swappiness)
# are restored from the state file that setup recorded.
#
# Called as: cybervm ai untune
set -euo pipefail

: "${CYBERVM_HOME:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/common.sh
source "$CYBERVM_HOME/lib/common.sh"

DROPIN_DIR=/etc/systemd/system/ollama.service.d
DROPIN="$DROPIN_DIR/cybervm-llm-tune.conf"
STATE="$CYBERVM_HOME/config/ai/.llm-tune.state"

changed=0

# 1) Delete the drop-in — this alone reverts CPUQuota/Nice/keep_alive/context.
if [ -f "$DROPIN" ]; then
  log "Removing Ollama tuning drop-in…"
  sudo rm -f "$DROPIN"
  sudo rmdir "$DROPIN_DIR" 2>/dev/null || true   # tidy up if now empty
  sudo systemctl daemon-reload
  sudo systemctl restart ollama
  ok "Drop-in removed; base ollama.service restored."
  changed=1
else
  log "No tuning drop-in present (nothing to remove)."
fi

# 2) Restore runtime settings that setup changed (governor, swappiness).
if [ -f "$STATE" ]; then
  # shellcheck disable=SC1090
  source "$STATE" 2>/dev/null || true

  if [ -n "${GOVERNOR_PREV:-}" ]; then
    if command -v cpupower >/dev/null 2>&1; then
      sudo cpupower frequency-set -g "$GOVERNOR_PREV" >/dev/null \
        && { ok "CPU governor restored -> ${GOVERNOR_PREV}"; changed=1; } \
        || warn "failed to restore governor"
    else
      warn "cpupower missing; cannot restore governor to ${GOVERNOR_PREV}"
    fi
  fi

  if [ -n "${SWAPPINESS_PREV:-}" ]; then
    sudo sysctl -q vm.swappiness="$SWAPPINESS_PREV" \
      && { ok "vm.swappiness restored -> ${SWAPPINESS_PREV}"; changed=1; } \
      || warn "failed to restore swappiness"
  fi

  rm -f "$STATE"
fi

if [ "$changed" = 1 ]; then
  ok "Ollama untuned. Verify: systemctl show ollama -p CPUQuota,Nice,Environment"
else
  log "Nothing to revert (Ollama was not tuned)."
fi
