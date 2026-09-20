# lib/common.sh — shared helpers (sourced by cyberai and all lib/*.sh)

# ── logging ──────────────────────────────────────────────────
_c() { [ -t 1 ] && printf '%s' "$1" || true; }
RED=$(_c $'\033[31m'); GRN=$(_c $'\033[32m'); YLW=$(_c $'\033[33m'); BLU=$(_c $'\033[34m'); RST=$(_c $'\033[0m')
log()  { printf '%s[cyberai]%s %s\n' "$BLU" "$RST" "$*"; }
ok()   { printf '%s[ ok ]%s %s\n'  "$GRN" "$RST" "$*"; }
warn() { printf '%s[warn]%s %s\n'  "$YLW" "$RST" "$*" >&2; }
err()  { printf '%s[fail]%s %s\n'  "$RED" "$RST" "$*" >&2; }
die()  { err "$*"; exit 1; }

# ── env loading ──────────────────────────────────────────────
load_env() {
  local envf="$CYBERAI_HOME/.cyberai.env"
  if [ ! -f "$envf" ]; then
    warn ".cyberai.env not found — using .cyberai.env.example defaults."
    warn "Run: cp .cyberai.env.example .cyberai.env  (then edit CYBERAI_ROOT if needed)"
    envf="$CYBERAI_HOME/.cyberai.env.example"
  fi
  # shellcheck disable=SC1090
  set -a; source "$envf"; set +a
  : "${CYBERAI_ROOT:?CYBERAI_ROOT unset}"
}

# ── yaml (needs yq) ──────────────────────────────────────────
have() { command -v "$1" >/dev/null 2>&1; }
yq_get() { # yq_get <file> <expr>
  have yq || die "yq not installed (run: cyberai host-setup)"
  yq -r "$2" "$1"
}
platform() { yq_get "$CYBERAI_HOME/config/platform.yml" "$1"; }

# ── VirtualBox helpers ───────────────────────────────────────
vbox()      { VBoxManage "$@"; }
vm_exists() { VBoxManage list vms | grep -q "\"$1\""; }
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

require_off() { vm_running "$1" && die "VM '$1' is running; stop it first (cyberai stop $1)"; return 0; }

# host free RAM in MB
host_free_mb() { awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo; }
