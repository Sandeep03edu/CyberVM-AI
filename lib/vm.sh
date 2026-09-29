# lib/vm.sh — disposable VM lifecycle (linked clones of the golden snapshot).

vm_dispatch() { local action="$1"; shift || true
  case "$action" in
    new)      vm_new "$@" ;;
    resize)   vm_resize "$@" ;;
    start)    vm_start "$@" ;;
    stop)     vm_stop "$@" ;;
    snapshot) vm_snapshot "$@" ;;
    restore)  vm_restore "$@" ;;
    destroy)  vm_destroy "$@" ;;
    list)     vm_list "$@" ;;
    *) die "unknown vm action: $action" ;;
  esac; }

_clone_name() { echo "$(platform .vm_names.clone_prefix)$1"; }
_is_protected() { local n="$1"; [ "$n" = "$(platform .vm_names.base)" ] || [ "$n" = "$(platform .vm_names.golden)" ]; }

# ── per-clone CPU / memory ──────────────────────────────────
# Sizing is a .vbox property, applied at clone time and by `cybervm resize`. The
# golden image is therefore never modified and a single golden serves every
# clone. Names/sizes live in config/platform.yml -> resource_profiles.

_host_total_mb() { awk '/MemTotal/{print int($2/1024)}' /proc/meminfo; }
_resource_profiles() { platform '.resource_profiles | keys | .[]' | tr '\n' ' '; }

# Numeric .vbox keys (memory, cpus) are printed WITHOUT quotes by
# --machinereadable, so _vm_cfg's quoted pattern cannot see them.
_vm_cfg_num() { VBoxManage showvminfo "$1" --machinereadable 2>/dev/null | sed -n "s/^$2=//p" | head -1; }

# yq prints the literal string "null" for a missing key. That is NOT empty, so a
# plain -z test would wave a typo'd profile through and hand `modifyvm` the
# string "null". Normalise it away.
_yaml_str() { local v; v="$(platform "$1")"; [ "$v" = "null" ] && v=""; printf '%s' "$v"; }

# Pure: prints MB on stdout, returns 1 on bad input. It must NOT call die,
# because it runs inside a command substitution where `exit` would only leave
# the subshell - the caller would then see an empty string and silently fall
# back to the default profile. The caller turns rc!=0 into the error.
_ram_to_mb() { # a bare number means GB; MB must be explicit (8192M)
  local v="${1,,}" n
  case "$v" in ''|*[!0-9gmb]*) return 1 ;; esac
  case "$v" in
    *mb|*m) n="${v%%[gm]*}"
            case "$n" in ''|*[!0-9]*) return 1 ;; esac
            echo "$n"; return 0 ;;
  esac
  n="${v%%[gm]*}"
  case "$n" in ''|*[!0-9]*) return 1 ;; esac
  echo $((n * 1024))
}

_check_ram_mb() {
  case "$1" in ''|*[!0-9]*) die "invalid --ram: '$1'";; esac
  [ "$1" -ge 2048 ] || die "--ram must be at least 2048MB (got ${1}MB)."
  local tot; tot="$(_host_total_mb)"
  [ "$1" -le "$tot" ] || die "--ram ${1}MB exceeds host physical RAM (${tot}MB)."
}

_check_cpus() {
  case "$1" in ''|*[!0-9]*) die "invalid --cpus: '$1'";; esac
  [ "$1" -ge 1 ] || die "--cpus must be >= 1 (got $1)."
  local n; n="$(nproc)"
  [ "$1" -le "$n" ] || die "--cpus $1 exceeds host logical CPUs (${n})."
}

# _resolve_resources <default|explicit> <current_ram_mb> [args...]
# Sets _RES_RAM / _RES_CPUS / _RES_SRC.
#   default  : falls back to config default_profile (used by `cybervm new`)
#   explicit : at least one of --ram/--cpus required and nothing is defaulted
#              off the current VM (used by `cybervm resize`)
# Precedence: explicit flags > --profile > default_profile.
# NOTE: this announces its own decisions via log() on stdout, so call it
# directly - never in a command substitution, or the notice lands in your value.
_RES_RAM=; _RES_CPUS=; _RES_SRC=
_resolve_resources() {
  local policy="$1" cur="$2"; shift 2
  local profile="" ram="" cpus="" want_explicit=false
  while [ $# -gt 0 ]; do
    case "$1" in
      --profile)
        [ -n "${2:-}" ] || die "--profile needs a value (one of: $(_resource_profiles))"
        profile="$2"; shift 2 ;;
      --ram)
        [ -n "${2:-}" ] || die "--ram needs a value (e.g. 12, 12G or 12288M)"
        ram="$(_ram_to_mb "$2")" \
          || die "invalid --ram value: '$2' (use 12, 12G or 12288M)"
        shift 2 ;;
      --cpus)
        [ -n "${2:-}" ] || die "--cpus needs a value"
        cpus="$2"; shift 2 ;;
      --net)
        die "there is no --net on this command - a new clone is always offline. Use 'cybervm start <name> --net <mode>' or 'cybervm net <name> <mode>'." ;;
      *)
        die "unknown option: '$1' (valid: --profile P, --ram GB, --cpus N)" ;;
    esac
  done

  if [ "$policy" = "explicit" ]; then
    [ -z "$profile" ] || die "cybervm resize takes --ram/--cpus only, not --profile."
    want_explicit=true
  fi

  # An explicit flag alongside --profile is ambiguous; ask rather than guess.
  if [ -n "$profile" ] && { [ -n "$ram" ] || [ -n "$cpus" ]; }; then
    die "--profile cannot be combined with --ram/--cpus - pick one."
  fi

  if [ "$want_explicit" = true ] && [ -z "$ram" ] && [ -z "$cpus" ]; then
    die "nothing to change: pass --ram GB and/or --cpus N (there is no default here, because a profile default would silently overwrite this VM's current sizing)."
  fi

  if [ -n "$ram" ] || [ -n "$cpus" ]; then
    if [ -z "$ram" ]; then
      # --cpus only: keep the VM's current RAM when resizing; on `new` fall back
      # to the default profile's RAM so `--cpus 8` does what it looks like
      # rather than failing on a missing --ram.
      ram="$cur"
      if [ -z "$ram" ]; then
        local dp; dp="$(_yaml_str .default_profile)"
        ram="$(_yaml_str ".resource_profiles.$dp.ram_mb")"
        [ -n "$ram" ] || die "config: default_profile '$dp' has no ram_mb in config/platform.yml"
      fi
    fi
    _check_ram_mb "$ram"
    if [ -n "$cpus" ]; then
      _check_cpus "$cpus"
    else
      # Same 1:2 ratio the profiles are built on, so `--ram 12` and
      # `--profile balanced` cannot disagree. Always announced, never silent.
      cpus=$((ram / 1024 / 2)); [ "$cpus" -ge 2 ] || cpus=2
      _check_cpus "$cpus"
      log "no --cpus given -> $cpus vCPU from ${ram}MB (1:2 ratio, same rule as the profiles)"
    fi
    _RES_SRC="explicit"
  else
    profile="${profile:-$(platform .default_profile)}"
    ram="$(_yaml_str ".resource_profiles.$profile.ram_mb")"
    cpus="$(_yaml_str ".resource_profiles.$profile.cpus")"
    if [ -z "$ram" ] || [ -z "$cpus" ]; then
      die "unknown profile '$profile' (config resource_profiles has: $(_resource_profiles))"
    fi
    _check_ram_mb "$ram"; _check_cpus "$cpus"
    _RES_SRC="profile $profile"
  fi
  _RES_RAM="$ram"; _RES_CPUS="$cpus"
}

vm_new() {
  local name="${1:?usage: cybervm new <name> [--profile P] [--ram GB] [--cpus N]}"; shift || true
  _resolve_resources default "" "$@"
  local golden snap vm
  golden="$(platform .vm_names.golden)"; vm="$(_clone_name "$name")"
  vm_exists "$vm" && die "$vm already exists."
  snap="$(cat "$CYBERVM_HOME/.cybervm.golden-snap" 2>/dev/null)"
  [ -z "$snap" ] && snap=$(VBoxManage snapshot "$golden" list --machinereadable 2>/dev/null | sed -n 's/^SnapshotUUID[^=]*="\([^"]*\)"/\1/p' | tail -1)
  [ -z "$snap" ] && die "No golden snapshot — run: cybervm golden build"

  log "Linked-cloning $golden@$snap -> $vm ($_RES_RAM MB / $_RES_CPUS vCPU, $_RES_SRC)…"
  VBoxManage clonevm "$golden" --snapshot "$snap" --options link --name "$vm" \
    --basefolder "$CYBERVM_LABS" --register
  VBoxManage modifyvm "$vm" --memory "$_RES_RAM" --cpus "$_RES_CPUS"
  # clipboard/DnD are already baked into the golden snapshot, but a clone must
  # never inherit a stale posture if golden's config drifted after its snapshot
  # was taken. Apply before the 'clean' snapshot so it is recorded too.
  vm_apply_host_config "$vm"
  source "$CYBERVM_HOME/lib/net.sh"; net_apply "$vm" offline
  VBoxManage snapshot "$vm" take clean --description "fresh clone"
  ok "Created $vm (${_RES_RAM}MB/${_RES_CPUS}vCPU from $_RES_SRC; net: offline). Start: cybervm start $name"
}

# Change RAM/vCPU on an existing clone. Both are inert .vbox fields, so this is
# instant and cannot touch the guest disk. The VM must be off - VirtualBox
# cannot change these while a guest is running.
vm_resize() {
  local name="${1:?usage: cybervm resize <name> [--ram GB] [--cpus N]}"; shift || true
  local vm; vm="$(_clone_name "$name")"; vm_exists "$vm" || vm="$name"
  vm_exists "$vm" || die "no such VM: $name"
  _is_protected "$vm" && die "refusing to resize protected VM: $vm (base/golden are not clones; edit config/platform.yml and run 'cybervm golden build')"
  local cur; cur="$(_vm_cfg_num "$vm" memory)"
  [ -n "$cur" ] || die "could not read current memory of $vm"
  require_off "$vm"
  _resolve_resources explicit "$cur" "$@"
  local was="was ${cur}MB/$(_vm_cfg_num "$vm" cpus)vCPU"
  VBoxManage modifyvm "$vm" --memory "$_RES_RAM" --cpus "$_RES_CPUS"
  ok "$vm resized: $was -> ${_RES_RAM}MB/${_RES_CPUS}vCPU"
}


vm_start() {
  local name="${1:?vm}"; shift || true
  local vm; vm="$(_clone_name "$name")"; vm_exists "$vm" || vm="$name"
  vm_exists "$vm" || die "no such VM: $name"
  local mode="" type="gui"
  while [ $# -gt 0 ]; do case "$1" in
    --net) mode="$2"; shift 2;; --headless) type="headless"; shift;; *) die "unknown option for 'cybervm start': $1 (valid: --net offline|airgap|nat|bridged, --headless)";; esac; done
  # RAM guard
  local need free; need=$(_vm_cfg_num "$vm" memory)
  free=$(host_free_mb)
  if [ $((free - need)) -lt "$CYBERVM_HOST_RESERVE_MB" ]; then
    die "Not enough host RAM: free ${free}MB, VM needs ${need}MB, reserve ${CYBERVM_HOST_RESERVE_MB}MB."
  fi
  require_off "$vm"
  # Only touch the network when --net was given; otherwise keep the VM's stored
  # config (e.g. the mode persisted by `cybervm net`).
  [ -n "$mode" ] && net_apply_wrap "$vm" "$mode"
  VBoxManage startvm "$vm" --type "$type"
  ok "$vm started (net=${mode:-stored})."
}
net_apply_wrap() { source "$CYBERVM_HOME/lib/net.sh"; net_apply "$1" "$2"; }

vm_stop()    { local vm; vm="$(_clone_name "${1:?vm}")"; vm_exists "$vm" || vm="$1"; VBoxManage controlvm "$vm" acpipowerbutton && ok "$vm shutting down."; }
vm_snapshot(){ local vm; vm="$(_clone_name "${1:?vm}")"; VBoxManage snapshot "$vm" take "${2:?tag}" && ok "snapshot $2 on $vm"; }
vm_restore() { local vm; vm="$(_clone_name "${1:?vm}")"; require_off "$vm"; VBoxManage snapshot "$vm" restore "${2:?tag}" && ok "restored $2 on $vm"; }

# Raw unregister + delete. Deliberately has NO confirmation and NO protected-VM
# guard: `golden reset` must be able to replace the golden itself. Anything
# user-facing should call vm_destroy instead, which adds both checks.
_vm_unregister() { local vm="$1"
  vm_running "$vm" && { VBoxManage controlvm "$vm" poweroff >/dev/null 2>&1; sleep 3; }
  VBoxManage unregistervm "$vm" --delete
}

vm_destroy() {
  local name="${1:?vm}"; local vm; vm="$(_clone_name "$name")"; vm_exists "$vm" || vm="$name"
  _is_protected "$vm" && die "refusing to destroy protected VM: $vm"
  vm_exists "$vm" || die "no such VM: $name"
  warn "This permanently deletes $vm and its disks."
  confirm "Destroy $vm?" || die "aborted."
  _vm_unregister "$vm"
  ok "Destroyed $vm."
}

# Every registered VM belonging to this project: base/golden, plus clones that
# live under the labs/ or images/ folders. Shared by `vm list` and `doctor` so
# the listing and the RAM figures can never disagree about what counts as ours.
_cybervm_vms() {
  VBoxManage list vms | sed -n 's/^"\([^"]*\).*/\1/p' | while read -r n; do
    local cfg; cfg="$(_vm_cfg "$n" CfgFile)"
    case "$n" in
      CyberVM-Kali-*|kali-*) echo "$n" ;;                       # base/golden + legacy clones
      *) # Unprefixed clones are identified by living under our own roots. Both
         # roots must actually be set: an empty $CYBERVM_LABS would make the
         # pattern below degenerate to "/*" and claim every VM on the host.
         [ -n "$CYBERVM_LABS" ] && [ -n "$CYBERVM_IMAGES" ] || continue
         case "$cfg" in
           "$CYBERVM_LABS"/*|"$CYBERVM_IMAGES"/*) echo "$n" ;;
         esac ;;
    esac
  done
}

# RAM configured across RUNNING clones. vm_start's guard compares *free* memory
# against a VM's *full* allocation, so this total is what predicts whether a
# second or third VM will be refused - surface it before it bites.
_clone_ram_allocated_mb() {
  local total=0 n mem
  while read -r n; do
    [ -n "$n" ] || continue
    [ "$(vm_state "$n")" = "running" ] || continue
    mem="$(_vm_cfg_num "$n" memory)"
    [ -n "$mem" ] || continue
    total=$((total + mem))
  done < <(_cybervm_vms)
  echo "$total"
}

vm_list() {
  printf '%-28s %-12s %-9s %-7s %s\n' "VM" "STATE" "RAM" "CPU" "KIND"
  _cybervm_vms | while read -r n; do
    [ -n "$n" ] || continue
    local mem cpus
    mem="$(_vm_cfg_num "$n" memory)"; cpus="$(_vm_cfg_num "$n" cpus)"
    printf '%-28s %-12s %-9s %-7s %s\n' "$n" "$(vm_state "$n")" \
      "${mem:+${mem}MB}" "${cpus:+${cpus}v}" \
      "$(_is_protected "$n" && echo protected || echo clone)"
  done
}
