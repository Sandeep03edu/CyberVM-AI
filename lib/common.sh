# lib/common.sh — shared helpers (sourced by cybervm and all lib/*.sh)

# ── logging ──────────────────────────────────────────────────
_c() { [ -t 1 ] && printf '%s' "$1" || true; }
RED=$(_c $'\033[31m'); GRN=$(_c $'\033[32m'); YLW=$(_c $'\033[33m'); BLU=$(_c $'\033[34m'); RST=$(_c $'\033[0m')
log()  { printf '%s[cybervm]%s %s\n' "$BLU" "$RST" "$*"; }
ok()   { printf '%s[ ok ]%s %s\n'  "$GRN" "$RST" "$*"; }
warn() { printf '%s[warn]%s %s\n'  "$YLW" "$RST" "$*" >&2; }
err()  { printf '%s[fail]%s %s\n'  "$RED" "$RST" "$*" >&2; }
die()  { err "$*"; exit 1; }

# ── env loading ──────────────────────────────────────────────
load_env() {
  local envf="$CYBERVM_HOME/.cybervm.env"
  if [ ! -f "$envf" ]; then
    warn ".cybervm.env not found — using .cybervm.env.example defaults."
    warn "Run: cp .cybervm.env.example .cybervm.env  (then edit CYBERVM_ROOT if needed)"
    envf="$CYBERVM_HOME/.cybervm.env.example"
  fi
  # shellcheck disable=SC1090
  set -a; source "$envf"; set +a
  : "${CYBERVM_ROOT:?CYBERVM_ROOT unset}"
}

# ── yaml (needs yq) ──────────────────────────────────────────
have() { command -v "$1" >/dev/null 2>&1; }
yq_get() { # yq_get <file> <expr>
  have yq || die "yq not installed (run: cybervm host-setup)"
  yq -r "$2" "$1"
}
platform() { yq_get "$CYBERVM_HOME/config/platform.yml" "$1"; }

# ── VirtualBox helpers ───────────────────────────────────────
vbox()      { VBoxManage "$@"; }
vm_exists() { VBoxManage list vms | grep -q "\"$1\""; }

# ── Shared VM host config (clipboard / drag-and-drop) ─────────
# These are HYPERVISOR properties stored in the VM's .vbox — NOT guest settings.
# VirtualBox copies them into a VM only at CLONE time, so a VM that was created
# before the posture changed keeps the old value forever unless we re-apply it.
# Therefore EVERY code path that authors a VM's config must call
# vm_apply_host_config: base import, golden build, and clone.
# Single source of truth: config/platform.yml -> .vm_defaults.*
vm_desired_clipboard()   { platform ".vm_defaults.clipboard_mode"; }
vm_desired_draganddrop() { platform ".vm_defaults.draganddrop_mode"; }

# _vm_cfg <vm> <machinereadable-key>  e.g. _vm_cfg "$vm" clipboard
# Never fails: an unreadable key yields "" so callers stay usable under `set -e`.
_vm_cfg() { VBoxManage showvminfo "$1" --machinereadable 2>/dev/null | sed -n "s/^$2=\"\(.*\)\"/\1/p" || true; }

# _vm_defaults_ok — non-fatal probe (safe inside `if`; `die` would exit the caller)
_vm_defaults_ok() {
  local cb dd; cb="$(vm_desired_clipboard)"; dd="$(vm_desired_draganddrop)"
  [ -n "$cb" ] && [ "$cb" != "null" ] && [ -n "$dd" ] && [ "$dd" != "null" ]
}
_require_vm_defaults() {
  _vm_defaults_ok && return 0
  die "config/platform.yml: .vm_defaults.clipboard_mode / .draganddrop_mode missing or null"
}

# vm_apply_host_config <vm> — idempotent: no-ops when already correct.
vm_apply_host_config() {
  local vm="${1:?vm}" want_cb want_dd cur_cb cur_dd
  vm_exists "$vm" || { warn "vm_apply_host_config: no such VM: $vm"; return 0; }
  _require_vm_defaults
  want_cb="$(vm_desired_clipboard)"; want_dd="$(vm_desired_draganddrop)"
  cur_cb="$(_vm_cfg "$vm" clipboard)"; cur_dd="$(_vm_cfg "$vm" draganddrop)"
  if [ "$cur_cb" = "$want_cb" ] && [ "$cur_dd" = "$want_dd" ]; then return 0; fi
  require_off "$vm"
  log "Applying shared VM config to $vm (clipboard ${cur_cb:-?}->$want_cb, DnD ${cur_dd:-?}->$want_dd)…"
  VBoxManage modifyvm "$vm" --clipboard-mode "$want_cb" --draganddrop "$want_dd" >/dev/null
  ok "$vm shared config applied (clipboard=$want_cb DnD=$want_dd)"
}

# vm_host_config_drift <vm> — read-only. Returns 0 when the VM matches config.
vm_host_config_drift() {
  local vm="${1:?vm}" want_cb want_dd cur_cb cur_dd
  _require_vm_defaults
  want_cb="$(vm_desired_clipboard)"; want_dd="$(vm_desired_draganddrop)"
  cur_cb="$(_vm_cfg "$vm" clipboard)"; cur_dd="$(_vm_cfg "$vm" draganddrop)"
  if [ "$cur_cb" = "$want_cb" ] && [ "$cur_dd" = "$want_dd" ]; then
    printf 'clipboard=%s DnD=%s' "$cur_cb" "$cur_dd"; return 0
  fi
  printf 'clipboard=%s(want %s) DnD=%s(want %s)' "$cur_cb" "$want_cb" "$cur_dd" "$want_dd"; return 1
}

vm_running(){ VBoxManage list runningvms | grep -q "\"$1\""; }
vm_state()  { VBoxManage showvminfo "$1" --machinereadable 2>/dev/null | sed -n 's/^VMState="\(.*\)"/\1/p'; }

# Wait for a guest-additions-reported IPv4 on a given NIC slot (0-based).
vm_wait_ip() { # vm_wait_ip <vm> <slot> [timeout_s]
  local vm="$1" slot="$2" to="${3:-120}" ip=""
  for _ in $(seq 1 "$to"); do
    ip=$(VBoxManage guestproperty get "$vm" "/VirtualBox/GuestInfo/Net/$slot/V4/IP" 2>/dev/null \
          | sed -n 's/^Value: //p')
    [ -n "$ip" ] && [ "$ip" != "No value set!" ] && { echo "$ip"; return 0; }
    sleep 1
  done
  return 1
}

confirm() { # confirm "<prompt>" — returns 0 only on typed 'yes'
  local ans; read -r -p "$1 (type 'yes'): " ans; [ "$ans" = "yes" ]
}

require_off() { vm_running "$1" && die "VM '$1' is running; stop it first (cybervm stop $1)"; return 0; }

# ── host-setup readiness gate ────────────────────────────────
# host-setup writes .cybervm.host-ready ONLY after every step (incl. the KVM/AI
# network) has completed. Downstream commands must not run on a half-set host.
host_setup_done() {
  [ -f "$CYBERVM_HOME/.cybervm.host-ready" ] && [ -s "$CYBERVM_HOME/.cybervm.netif" ]
}
require_host_setup() {
  host_setup_done && return 0
  die "Host not fully configured yet. Run and FINISH: ./cybervm host-setup"
}

# host free RAM in MB
host_free_mb() { awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo; }
