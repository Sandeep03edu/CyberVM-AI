# lib/net.sh — network mode profiles applied via VBoxManage modifyvm.
# NIC1 = internet plane; NIC2 = AI plane (host-only, always on except airgap).

net_apply() { # net_apply <vm> <mode>  (VM must be off)
  local vm="$1" mode="$2" ifn
  ifn="$(cat "$CYBERAI_HOME/.cyberai.netif" 2>/dev/null || echo vboxnet0)"
  case "$mode" in
    offline)  VBoxManage modifyvm "$vm" --nic1 null \
                --nic2 hostonly --host-only-adapter2 "$ifn" ;;
    airgap)   VBoxManage modifyvm "$vm" --nic1 null --nic2 null ;;
    nat)      VBoxManage modifyvm "$vm" --nic1 nat --nat-localhostreachable1 off \
                --nic2 hostonly --host-only-adapter2 "$ifn" ;;
    bridged)  local br; br=$(ip -o route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++)if($i=="dev")print $(i+1)}')
              VBoxManage modifyvm "$vm" --nic1 bridged --bridge-adapter1 "${br:-eth0}" \
                --nic2 hostonly --host-only-adapter2 "$ifn" ;;
    *) die "unknown net mode: $mode (offline|airgap|nat|bridged)" ;;
  esac
}

net_set() { # cyberai net <vm> <mode>
  local vm="${1:?vm}" mode="${2:?mode}"
  vm_exists "$vm" || {
    local px; px="$(platform .vm_names.clone_prefix)"
    vm="$px$vm"
    vm_exists "$vm" || die "no such VM: $1"
  }
  require_off "$vm"
  if [ "$mode" = bridged ]; then
    warn "BRIDGED puts '$vm' directly on your physical LAN (breaks the sandbox)."
    confirm "Enable bridged for $vm?" || die "aborted."
  fi
  net_apply "$vm" "$mode"
  ok "$vm network mode -> $mode"
}
