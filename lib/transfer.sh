# lib/transfer.sh — controlled host<->VM file transfer (no permanent shared folder).

transfer_dispatch() { local dir="${1:?in|out}"; shift || true
  case "$dir" in in) transfer_in "$@";; out) transfer_out "$@";; *) die "usage: cyberai transfer in|out <vm> <file>";; esac; }

_vmname() { local n="$1"; vm_exists "$(platform .vm_names.clone_prefix)$n" && echo "$(platform .vm_names.clone_prefix)$n" || echo "$n"; }

transfer_in() { # host -> guest, via transient read-only shared folder (auto-mounted)
  local vm file ip
  vm="$(_vmname "${1:?vm}")"; file="${2:?file}"
  [ -f "$file" ] || die "no such file: $file"
  vm_exists "$vm" || die "no such VM: $vm"
  vm_running "$vm" || die "$vm is not running — start it first (cyberai start)"
  mkdir -p "$CYBERAI_TRANSFER"; cp -f "$file" "$CYBERAI_TRANSFER/"
  VBoxManage sharedfolder add "$vm" --name cyberai_xfer --hostpath "$CYBERAI_TRANSFER" --readonly --transient 2>/dev/null || true
  ip=$(vm_wait_ip "$vm" 1 120) || { warn "No AI-plane IP yet — mount manually: sudo mount -t vboxsf -o ro cyberai_xfer /mnt"; return 0; }
  local rc out
  out=$(ssh -i "$CYBERAI_SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o BatchMode=yes -o ConnectTimeout=10 "${CYBERAI_VM_USER}@$ip" \
      "if mountpoint -q /mnt && grep -q cyberai_xfer /proc/mounts; then echo 'already mounted'; \
       elif sudo mount -t vboxsf -o ro cyberai_xfer /mnt; then echo 'mounted'; fi" 2>&1); rc=$?
  if [ "$out" = "mounted" ] || [ "$out" = "already mounted" ]; then
    ok "Mounted in guest at /mnt — file: /mnt/$(basename "$file") ($out)"
  else
    warn "Could not auto-mount (guest additions missing?). Machine-local. Try: sudo mount -t vboxsf -o ro cyberai_xfer /mnt"
  fi
  warn "Remove when done: VBoxManage sharedfolder remove $vm --name cyberai_xfer --transient"
}

transfer_out() { # guest -> host, via guestcontrol copyfrom
  local vm src; vm="$(_vmname "${1:?vm}")"; src="${2:?/guest/path}"
  mkdir -p "$CYBERAI_TRANSFER"
  VBoxManage guestcontrol "$vm" --username "$CYBERAI_VM_USER" --password "$CYBERAI_VM_PASS" \
    copyfrom --target-directory "$CYBERAI_TRANSFER" "$src"
  ok "Copied $src -> $CYBERAI_TRANSFER/"
}
