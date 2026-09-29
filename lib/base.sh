# lib/base.sh — create the CyberVM-Kali-Base VM from the verified .7z (.vbox+.vdi).

base_dispatch() { local sub="${1:-}"; shift || true
  case "$sub" in import) base_import "$@";; *) die "usage: cybervm base import";; esac; }

base_import() {
  local base_name; base_name="$(platform .vm_names.base)"
  vm_exists "$base_name" && { warn "$base_name already exists."; return 0; }

  local arc="$CYBERVM_DOWNLOADS/kali/$(platform .kali.archive)"
  [ -f "$arc" ] || die "Kali archive missing: $arc"
  log "Verifying Kali archive checksum…"
  echo "$(platform .kali.sha256)  $arc" | sha256sum -c - || die "Checksum mismatch — do NOT import."
  ok "Checksum verified."

  local dest="$CYBERVM_IMAGES/base"
  mkdir -p "$dest"
  log "Extracting archive to $dest …"
  7z x -y -o"$dest" "$arc" >/dev/null
  local vbox; vbox=$(find "$dest" -name '*.vbox' | head -1)
  [ -n "$vbox" ] || die "No .vbox found after extraction (unexpected archive layout)."

  log "Registering VM (.vbox+.vdi -> registervm, NOT import)…"
  VBoxManage registervm "$vbox"
  local orig; orig=$(VBoxManage list vms | awk -F\" '/'"$(basename "${vbox%.vbox}")"'/{print $2; exit}')
  [ -z "$orig" ] && orig=$(basename "${vbox%.vbox}")
  [ "$orig" != "$base_name" ] && VBoxManage modifyvm "$orig" --name "$base_name"

  _base_harden "$base_name"
  _base_bootstrap_ssh "$base_name"
  VBoxManage snapshot "$base_name" take "$(platform .snapshots.base)" --description "clean verified official image"
  ok "Base image ready: $base_name (snapshot $(platform .snapshots.base))."
}

_base_harden() { local vm="$1"
  log "Hardening base VM (sandbox defaults)…"
  VBoxManage modifyvm "$vm" \
    --audio-enabled off --usb-ohci off --usb-ehci off --usb-xhci off \
    --nic1 nat --nat-localhostreachable1 off \
    --nic2 hostonly --host-only-adapter2 "$(cat "$CYBERVM_HOME/.cybervm.netif" 2>/dev/null || echo vboxnet0)"
  # clipboard + DnD come from config/platform.yml (.vm_defaults) — never hardcoded
  vm_apply_host_config "$vm"
  ok "Base configured: clipboard/DnD per config; no audio/USB; NAT loopback off; NIC2 on AI plane."
}

_base_bootstrap_ssh() { local vm="$1"
  log "Bootstrapping SSH into base via Guest Additions (headless)…"
  VBoxManage startvm "$vm" --type headless
  local ip; ip=$(vm_wait_ip "$vm" 1 180) || { warn "No NIC2 IP; is Guest Additions running? Enable SSH manually."; return 0; }
  local u="$CYBERVM_VM_USER" p="$CYBERVM_VM_PASS" pub; pub=$(cat "${CYBERVM_SSH_KEY}.pub")
  local gc="VBoxManage guestcontrol $vm --username $u --password $p"
  $gc run --exe /bin/bash -- -c "echo '$p' | sudo -S systemctl enable --now ssh" || true
  $gc run --exe /bin/bash -- -c "mkdir -p ~/.ssh && echo '$pub' >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
  $gc run --exe /bin/bash -- -c "echo '$p' | sudo -S bash -c 'echo \"$u ALL=(ALL) NOPASSWD:ALL\" > /etc/sudoers.d/cybervm'"
  ok "SSH bootstrapped. Test: ssh -i $CYBERVM_SSH_KEY $u@$ip true"
  VBoxManage controlvm "$vm" acpipowerbutton 2>/dev/null || true
}
