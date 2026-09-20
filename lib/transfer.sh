# lib/transfer.sh — controlled host<->VM file transfer via SCP over the AI plane.
# No shared folders: files go straight between host and guest over SSH.

transfer_dispatch() { local dir="${1:?in|out}"; shift || true
  case "$dir" in in) transfer_in "$@";; out) transfer_out "$@";;
    *) die "usage: cyberai transfer in|out <vm> <file> [dest]";; esac; }

_vmname() { local n="$1"; vm_exists "$(platform .vm_names.clone_prefix)$n" && echo "$(platform .vm_names.clone_prefix)$n" || echo "$n"; }

_gx() { # _gx <vm> [ssh-args...] — resolves the running clone's AI-plane IP
  local vm="$1"; shift
  local ip; ip=$(vm_wait_ip "$vm" 1 120) || { warn "No AI-plane IP yet for $vm; retry shortly."; return 1; }
  command ssh -i "$CYBERAI_SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o BatchMode=yes -o ConnectTimeout=10 "${CYBERAI_VM_USER}@$ip" "$@"
}

transfer_in() { # host -> guest; default dest /mnt (plain root-writable dir)
  local vm="${1:?usage: cyberai transfer in <vm> <file> [guest/dir]}"
  local file="${2:?file}" dest="${3:-/mnt}" ip
  [ -f "$file" ] || die "no such file: $file"
  vm="$(_vmname "$vm")"; vm_exists "$vm" || die "no such VM: $vm"
  vm_running "$vm" || die "$vm is not running — start it first (cyberai start)"
  ip=$(vm_wait_ip "$vm" 1 120) || { warn "No AI-plane IP yet for $vm; retry shortly."; return 0; }

  # Tear down any stale read-only shared-folder mount so /mnt is a normal dir.
  # umount -l: detached even if the guest has /mnt as its CWD (target is busy).
  command ssh -i "$CYBERAI_SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o BatchMode=yes -o ConnectTimeout=10 "${CYBERAI_VM_USER}@$ip" \
    'mountpoint -q /mnt && grep -q vboxsf /proc/mounts && sudo umount -l /mnt' 2>/dev/null || true
  VBoxManage sharedfolder remove "$vm" --name cyberai_xfer --transient 2>/dev/null || true

  local host_name; host_name="$(basename "$file")"
  local tmp=".cyberai-xfer-$$"
  command scp -i "$CYBERAI_SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o BatchMode=yes -o ConnectTimeout=10 "$file" "${CYBERAI_VM_USER}@$ip:/tmp/$tmp" || die "scp to guest failed"
  command ssh -i "$CYBERAI_SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o BatchMode=yes -o ConnectTimeout=10 "${CYBERAI_VM_USER}@$ip" \
    "sudo install -m 0644 /tmp/$tmp '$dest/$host_name' && sudo rm -f /tmp/$tmp" \
    || { err "moving to $dest failed"; return 1; }
  ok "Copied $file -> $vm:$dest/$host_name"
}

transfer_out() { # guest -> host; default dest = current working directory
  local vm="${1:?usage: cyberai transfer out <vm> <guest/file> [host/dest]}"
  local src="${2:?guest file}" dest="${3:-$PWD}" ip
  vm="$(_vmname "$vm")"; vm_exists "$vm" || die "no such VM: $vm"
  vm_running "$vm" || die "$vm is not running — start it first (cyberai start)"
  ip=$(vm_wait_ip "$vm" 1 120) || { warn "No AI-plane IP yet for $vm; retry shortly."; return 0; }

  if [ -d "$dest" ] || [ "${dest%/}" != "$dest" ]; then
    mkdir -p "$dest"; dest="$dest/$(basename "$src")"
  else
    mkdir -p "$(dirname "$dest")"
  fi
  command scp -i "$CYBERAI_SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o BatchMode=yes -o ConnectTimeout=10 "${CYBERAI_VM_USER}@$ip:$src" "$dest" \
    || die "scp from guest failed"
  ok "Copied $vm:$src -> $dest"
}