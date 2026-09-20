# lib/transfer.sh — controlled host<->VM file transfer (no permanent shared folder).

transfer_dispatch() { local dir="${1:?in|out}"; shift || true
  case "$dir" in in) transfer_in "$@";; out) transfer_out "$@";; *) die "usage: cyberai transfer in|out <vm> <file>";; esac; }

_vmname() { local n="$1"; vm_exists "$(platform .vm_names.clone_prefix)$n" && echo "$(platform .vm_names.clone_prefix)$n" || echo "$n"; }

transfer_in() { # host -> guest, via transient read-only shared folder
  local vm file; vm="$(_vmname "${1:?vm}")"; file="${2:?file}"
  [ -f "$file" ] || die "no such file: $file"
  mkdir -p "$CYBERAI_TRANSFER"; cp -f "$file" "$CYBERAI_TRANSFER/"
  VBoxManage sharedfolder add "$vm" --name cyberai_xfer --hostpath "$CYBERAI_TRANSFER" --readonly --transient 2>/dev/null || true
  ok "Shared (read-only, transient) as 'cyberai_xfer'. In guest: sudo mount -t vboxsf -o ro cyberai_xfer /mnt"
  warn "Remove when done: VBoxManage sharedfolder remove $vm --name cyberai_xfer --transient"
}

transfer_out() { # guest -> host, via guestcontrol copyfrom
  local vm src; vm="$(_vmname "${1:?vm}")"; src="${2:?/guest/path}"
  mkdir -p "$CYBERAI_TRANSFER"
  VBoxManage guestcontrol "$vm" --username "$CYBERAI_VM_USER" --password "$CYBERAI_VM_PASS" \
    copyfrom --target-directory "$CYBERAI_TRANSFER" "$src"
  ok "Copied $src -> $CYBERAI_TRANSFER/"
}
