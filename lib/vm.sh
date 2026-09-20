# lib/vm.sh — disposable VM lifecycle (linked clones of the golden snapshot).

vm_dispatch() { local action="$1"; shift || true
  case "$action" in
    new)      vm_new "$@" ;;
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

vm_new() {
  local name="${1:?usage: cyberai new <name> [--profile lite|standard|heavy]}"; shift || true
  local profile="$(platform .default_profile)"
  [ "${1:-}" = "--profile" ] && { profile="$2"; shift 2; }
  local golden snap vm ram cpus
  golden="$(platform .vm_names.golden)"; vm="$(_clone_name "$name")"
  vm_exists "$vm" && die "$vm already exists."
  snap="$(cat "$CYBERAI_HOME/.cyberai.golden-snap" 2>/dev/null)"
  [ -z "$snap" ] && snap=$(VBoxManage snapshot "$golden" list --machinereadable 2>/dev/null | sed -n 's/^SnapshotUUID[^=]*="\([^"]*\)"/\1/p' | tail -1)
  [ -z "$snap" ] && die "No golden snapshot — run: cyberai golden build"
  ram="$(platform ".resource_profiles.$profile.ram_mb")"; cpus="$(platform ".resource_profiles.$profile.cpus")"

  log "Linked-cloning $golden@$snap -> $vm (profile $profile: ${ram}MB/${cpus}vCPU)…"
  VBoxManage clonevm "$golden" --snapshot "$snap" --options link --name "$vm" \
    --basefolder "$CYBERAI_LABS" --register
  VBoxManage modifyvm "$vm" --memory "$ram" --cpus "$cpus"
  source "$CYBERAI_HOME/lib/net.sh"; net_apply "$vm" offline
  VBoxManage snapshot "$vm" take clean --description "fresh clone"
  ok "Created $vm (default net: offline). Start: cyberai start $name --net offline"
}

vm_start() {
  local name="${1:?vm}"; shift || true
  local vm; vm="$(_clone_name "$name")"; vm_exists "$vm" || vm="$name"
  vm_exists "$vm" || die "no such VM: $name"
  local mode="" type="gui"
  while [ $# -gt 0 ]; do case "$1" in
    --net) mode="$2"; shift 2;; --headless) type="headless"; shift;; *) shift;; esac; done
  # RAM guard
  local need free; need=$(VBoxManage showvminfo "$vm" --machinereadable | sed -n 's/^memory=//p')
  free=$(host_free_mb)
  if [ $((free - need)) -lt "$CYBERAI_HOST_RESERVE_MB" ]; then
    die "Not enough host RAM: free ${free}MB, VM needs ${need}MB, reserve ${CYBERAI_HOST_RESERVE_MB}MB."
  fi
  require_off "$vm"
  # Only touch the network when --net was given; otherwise keep the VM's stored
  # config (e.g. the mode persisted by `cyberai net`).
  [ -n "$mode" ] && net_apply_wrap "$vm" "$mode"
  VBoxManage startvm "$vm" --type "$type"
  ok "$vm started (net=${mode:-stored})."
}
net_apply_wrap() { source "$CYBERAI_HOME/lib/net.sh"; net_apply "$1" "$2"; }

vm_stop()    { local vm; vm="$(_clone_name "${1:?vm}")"; vm_exists "$vm" || vm="$1"; VBoxManage controlvm "$vm" acpipowerbutton && ok "$vm shutting down."; }
vm_snapshot(){ local vm; vm="$(_clone_name "${1:?vm}")"; VBoxManage snapshot "$vm" take "${2:?tag}" && ok "snapshot $2 on $vm"; }
vm_restore() { local vm; vm="$(_clone_name "${1:?vm}")"; require_off "$vm"; VBoxManage snapshot "$vm" restore "${2:?tag}" && ok "restored $2 on $vm"; }

vm_destroy() {
  local name="${1:?vm}"; local vm; vm="$(_clone_name "$name")"; vm_exists "$vm" || vm="$name"
  _is_protected "$vm" && die "refusing to destroy protected VM: $vm"
  vm_exists "$vm" || die "no such VM: $name"
  warn "This permanently deletes $vm and its disks."
  confirm "Destroy $vm?" || die "aborted."
  vm_running "$vm" && { VBoxManage controlvm "$vm" poweroff; sleep 3; }
  VBoxManage unregistervm "$vm" --delete
  ok "Destroyed $vm."
}

vm_list() {
  printf '%-28s %-12s %s\n' "VM" "STATE" "KIND"
  VBoxManage list vms | sed -n 's/^"\([^"]*\).*/\1/p' | while read -r n; do
    local cfg; cfg=$(VBoxManage showvminfo "$n" --machinereadable 2>/dev/null | sed -n 's/^CfgFile="\(.*\)"/\1/p')
    case "$n" in
      CyberAI-Kali-*|kali-*) : ;;                              # base/golden + legacy clones
      *) case "$cfg" in                                       # unprefixed clones live under labs
           "$CYBERAI_LABS"/*|"$CYBERAI_IMAGES"/*) : ;;
           *) continue ;;
         esac ;;
    esac
    printf '%-28s %-12s %s\n' "$n" "$(vm_state "$n")" \
      "$(_is_protected "$n" && echo protected || echo clone)"
  done
}
