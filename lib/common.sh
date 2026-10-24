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

# ── Realtime host skills share (vboxsf) ──────────────────────
# Like clipboard/DnD above, a shared folder is a per-VM .vbox property copied into
# a clone only at clone time, so EVERY authoring path (clone, and any re-attach)
# must call vm_apply_skills_share. The host folder (CYBERVM_SKILLS_HOST, the
# AgenticSkills repo) is mounted read-only by default at /media/sf_<name> in the
# guest; golden bakes the two client symlinks that point there.
# _vm_share_path <vm> <share-name> — the host path currently mapped to that share, or "".
# --machinereadable emits SharedFolderNameMachineMappingN / SharedFolderPathMachineMappingN
# pairs keyed by the same N; join them and print the path whose name matches.
_vm_share_path() {
  VBoxManage showvminfo "$1" --machinereadable 2>/dev/null \
    | awk -F'"' -v n="$2" '
        /^SharedFolderNameMachineMapping[0-9]+=/ { i=$0; sub(/=.*/,"",i); sub(/^SharedFolderNameMachineMapping/,"",i); names[i]=$2 }
        /^SharedFolderPathMachineMapping[0-9]+=/ { i=$0; sub(/=.*/,"",i); sub(/^SharedFolderPathMachineMapping/,"",i); paths[i]=$2 }
        END { for (k in names) if (names[k]==n) print paths[k] }'
}

# _vm_share_writable <vm> <share-name> — "true"/"false" from the .vbox, or "" if no such share.
# The writable/autoMount flags are not in --machinereadable, so read the CfgFile XML.
# IMPORTANT: this runs under `set -euo pipefail` (the cybervm CLI). A grep with no
# match exits 1, and under pipefail that 1 propagates out of ANY pipeline it sits
# in — including a `$(...)` assignment — killing the whole script right here on a
# fresh VM that has no SharedFolder yet. A single awk pass never does that (awk
# exits 0 whether or not a pattern matched), so use awk, not grep|grep|head|sed,
# and keep the explicit `|| true` belt-and-suspenders like _vm_cfg above.
_vm_share_writable() {
  local cfg; cfg="$(VBoxManage showvminfo "$1" --machinereadable 2>/dev/null | sed -n 's/^CfgFile="\(.*\)"/\1/p' || true)"
  [ -n "$cfg" ] && [ -f "$cfg" ] || { echo ""; return 0; }
  awk -v n="$2" '
    match($0, /<SharedFolder[^>]*>/) {
      line = substr($0, RSTART, RLENGTH)
      if (line ~ ("name=\"" n "\"") && match(line, /writable="[a-zA-Z]*"/)) {
        w = substr(line, RSTART, RLENGTH); sub(/writable="/,"",w); sub(/"$/,"",w)
        print w; exit
      }
    }
  ' "$cfg" || true
}

# vm_apply_skills_share <vm> — idempotent: (re)attach the skills share if missing/wrong.
# Never blocks VM creation: a missing config or host path only warns.
vm_apply_skills_share() {
  local vm="${1:?vm}" name hostpath cur; local ro=()
  vm_exists "$vm" || { warn "vm_apply_skills_share: no such VM: $vm"; return 0; }
  hostpath="${CYBERVM_SKILLS_HOST:-}"
  name="${CYBERVM_SKILLS_SHARE_NAME:-AgenticSkills}"
  if [ -z "$hostpath" ]; then
    warn "CYBERVM_SKILLS_HOST unset — skipping skills share for $vm"; return 0
  fi
  if [ ! -d "$hostpath" ]; then
    warn "skills host path not found ($hostpath) — skipping skills share for $vm"; return 0
  fi
  cur="$(_vm_share_path "$vm" "$name")"
  local want_w cur_w; want_w="true"; [ "${CYBERVM_SKILLS_READONLY:-1}" = "1" ] && want_w="false"
  cur_w="$(_vm_share_writable "$vm" "$name")"
  [ "$cur" = "$hostpath" ] && [ "$cur_w" = "$want_w" ] && return 0   # already correct (path + RO)
  require_off "$vm"
  [ -n "$cur" ] && { VBoxManage sharedfolder remove "$vm" --name "$name" 2>/dev/null || true; }
  [ "${CYBERVM_SKILLS_READONLY:-1}" = "1" ] && ro=(--readonly)
  log "Attaching skills share to $vm ($name -> $hostpath, ro=${CYBERVM_SKILLS_READONLY:-1})…"
  VBoxManage sharedfolder add "$vm" --name "$name" --hostpath "$hostpath" --automount "${ro[@]}"
  ok "$vm skills share attached ($name -> /media/sf_$name)"
}

# vm_skills_share_drift <vm> — read-only. Returns 0 when the share matches config.
vm_skills_share_drift() {
  local vm="${1:?vm}" name hostpath cur
  name="${CYBERVM_SKILLS_SHARE_NAME:-AgenticSkills}"; hostpath="${CYBERVM_SKILLS_HOST:-}"
  cur="$(_vm_share_path "$vm" "$name")"
  if [ -n "$cur" ] && [ "$cur" = "$hostpath" ]; then
    printf '%s -> %s' "$name" "$cur"; return 0
  fi
  printf '%s -> %s (want %s)' "$name" "${cur:-<none>}" "${hostpath:-<unset>}"; return 1
}

# ── Realtime host PLUGINS share (vboxsf) — same story as skills above ───────
# Twin of vm_apply_skills_share/vm_skills_share_drift, reading CYBERVM_PLUGINS_* instead.
# Reuses the same generic _vm_share_path/_vm_share_writable helpers (parametrized by share
# name already). Unlike skills, Claude Code plugins are never auto-discovered from a
# directory, so this share exists only so a plugin's bundled MCP server scripts (wired
# via config/mcp/servers.yml) can actually reach their command on disk at guest runtime.
vm_apply_plugins_share() {
  local vm="${1:?vm}" name hostpath cur; local ro=()
  vm_exists "$vm" || { warn "vm_apply_plugins_share: no such VM: $vm"; return 0; }
  hostpath="${CYBERVM_PLUGINS_HOST:-}"
  name="${CYBERVM_PLUGINS_SHARE_NAME:-AgenticPlugins}"
  if [ -z "$hostpath" ]; then
    warn "CYBERVM_PLUGINS_HOST unset — skipping plugins share for $vm"; return 0
  fi
  if [ ! -d "$hostpath" ]; then
    warn "plugins host path not found ($hostpath) — skipping plugins share for $vm"; return 0
  fi
  cur="$(_vm_share_path "$vm" "$name")"
  local want_w cur_w; want_w="true"; [ "${CYBERVM_PLUGINS_READONLY:-1}" = "1" ] && want_w="false"
  cur_w="$(_vm_share_writable "$vm" "$name")"
  [ "$cur" = "$hostpath" ] && [ "$cur_w" = "$want_w" ] && return 0   # already correct (path + RO)
  require_off "$vm"
  [ -n "$cur" ] && { VBoxManage sharedfolder remove "$vm" --name "$name" 2>/dev/null || true; }
  [ "${CYBERVM_PLUGINS_READONLY:-1}" = "1" ] && ro=(--readonly)
  log "Attaching plugins share to $vm ($name -> $hostpath, ro=${CYBERVM_PLUGINS_READONLY:-1})…"
  VBoxManage sharedfolder add "$vm" --name "$name" --hostpath "$hostpath" --automount "${ro[@]}"
  ok "$vm plugins share attached ($name -> /media/sf_$name)"
}

# vm_plugins_share_drift <vm> — read-only. Returns 0 when the share matches config.
vm_plugins_share_drift() {
  local vm="${1:?vm}" name hostpath cur
  name="${CYBERVM_PLUGINS_SHARE_NAME:-AgenticPlugins}"; hostpath="${CYBERVM_PLUGINS_HOST:-}"
  cur="$(_vm_share_path "$vm" "$name")"
  if [ -n "$cur" ] && [ "$cur" = "$hostpath" ]; then
    printf '%s -> %s' "$name" "$cur"; return 0
  fi
  printf '%s -> %s (want %s)' "$name" "${cur:-<none>}" "${hostpath:-<unset>}"; return 1
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

# vm_shutdown <vm> [seconds-per-attempt] — clean shutdown that is actually verified.
# The ACPI power button alone is not enough: a logged-in Kali desktop ignores it,
# so the VM stays up while the caller believes it is off. Press the button, wait,
# then ask the guest to power itself off (guest control works in every net mode).
# Returns 1 if the VM is still running; callers decide whether that is fatal.
_vm_wait_off() { local i; for i in $(seq 1 "$2"); do vm_running "$1" || return 0; sleep 1; done; return 1; }
vm_shutdown() {
  local vm="${1:?vm}" t="${2:-30}"
  vm_running "$vm" || return 0
  VBoxManage controlvm "$vm" acpipowerbutton >/dev/null 2>&1 || true
  _vm_wait_off "$vm" "$t" && return 0
  log "$vm ignored the power button — asking the guest to power off…"
  VBoxManage guestcontrol "$vm" --username "$CYBERVM_VM_USER" --password "$CYBERVM_VM_PASS" \
    run --exe /bin/bash -- -c "echo '$CYBERVM_VM_PASS' | sudo -S poweroff" >/dev/null 2>&1 || true
  _vm_wait_off "$vm" "$t"
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

# ── AI plane (host-only adapter) ─────────────────────────────
# VirtualBox remembers the adapter's address, but after a host reboot the kernel
# interface comes back DOWN with no address until a VM attaches to it. Nothing
# can bind CYBERVM_HOST_IP in that window, so Ollama fails at boot. Re-apply the
# address and revive Ollama before any command that needs the plane.
ai_plane_if()   { cat "$CYBERVM_HOME/.cybervm.netif" 2>/dev/null; }
ai_plane_live() { ip -4 -o addr show dev "$1" 2>/dev/null | grep -qF " ${CYBERVM_HOST_IP}/"; }
ensure_ai_plane() {
  local ifn; ifn="$(ai_plane_if || true)"; [ -n "$ifn" ] || return 0
  if ! ai_plane_live "$ifn"; then
    log "AI plane: bringing up $ifn (${CYBERVM_HOST_IP})…"
    VBoxManage hostonlyif ipconfig "$ifn" --ip "$CYBERVM_HOST_IP" --netmask 255.255.255.0 \
      || die "could not configure $ifn — re-run: cybervm host-setup"
  fi
  if ! systemctl is-active --quiet ollama; then
    log "AI plane: Ollama is not running — restarting it (sudo)…"
    sudo systemctl reset-failed ollama 2>/dev/null || true
    sudo systemctl restart ollama || warn "Ollama did not start — see: journalctl -u ollama -n 20"
  fi
}

# host free RAM in MB
host_free_mb() { awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo; }
