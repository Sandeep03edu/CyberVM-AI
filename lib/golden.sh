# lib/golden.sh — provision the golden image with Ansible over SSH.

golden_dispatch() { local sub="${1:-}"; shift || true
  case "$sub" in
    build)  golden_build "$@" ;;
    verify) golden_verify "$@" ;;
    *) die "usage: cyberai golden build|verify" ;;
  esac; }

_golden_ip() { # boot golden, return an IP that actually accepts SSH (provisioning ready)
  local vm="$1" ip=""
  vm_running "$vm" || VBoxManage startvm "$vm" --type headless >/dev/null 2>&1
  # Re-poll the guest property each pass: it may hold a STALE IP from the previous
  # boot until guest additions republish on the current network.
  for _ in $(seq 1 90); do
    ip=$(vm_wait_ip "$vm" 1 2) || { sleep 2; continue; }
    ssh -i "$CYBERAI_SSH_KEY" -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=3 \
        -o ServerAliveInterval=5 -o ServerAliveCountMax=3 \
        "${CYBERAI_VM_USER}@$ip" true >/dev/null 2>&1 && { echo "$ip"; return 0; }
    sleep 2
  done
  return 1
}

_write_inventory() { # <ip>
  local inv="$CYBERAI_HOME/factory/ansible/inventory/golden.ini"
  cat > "$inv" <<INV
[golden]
$1 ansible_user=${CYBERAI_VM_USER} ansible_ssh_private_key_file=${CYBERAI_SSH_KEY} ansible_python_interpreter=/usr/bin/python3 ansible_ssh_common_args='-o StrictHostKeyChecking=no'
INV
  echo "$inv"
}

golden_build() {
  local base golden snap
  base="$(platform .vm_names.base)"; golden="$(platform .vm_names.golden)"
  vm_exists "$base" || die "Base image missing — run: cyberai base import"
  if vm_exists "$golden"; then warn "$golden exists; re-provisioning in place."; else
    log "Full-cloning $base -> $golden …"
    VBoxManage clonevm "$base" --snapshot "$(platform .snapshots.base)" \
      --options link --name "$golden" --register 2>/dev/null \
    || VBoxManage clonevm "$base" --name "$golden" --register
  fi
  # Give golden internet for provisioning (NAT) + AI plane (NIC2)
  require_off "$golden"
  source "$CYBERAI_HOME/lib/net.sh"; net_apply "$golden" nat

  local ip; ip=$(_golden_ip "$golden") || die "No IP from golden VM."
  ok "Golden reachable at $ip"
  local inv; inv=$(_write_inventory "$ip")

  log "Running Ansible provisioning playbook…"
  ( cd "$CYBERAI_HOME/factory/ansible" && \
    ansible-galaxy collection install -r requirements.yml >/dev/null && \
    ansible-playbook -i "$inv" playbooks/golden.yml )

  log "Cleaning apt caches + shutting down…"
  ssh -i "$CYBERAI_SSH_KEY" -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=10 \
      -o ServerAliveInterval=5 -o ServerAliveCountMax=3 "${CYBERAI_VM_USER}@$ip" \
      "sudo apt-get clean && sudo rm -rf /var/lib/apt/lists/*" || true
  VBoxManage controlvm "$golden" acpipowerbutton; sleep 8
  for _ in $(seq 1 30); do vm_running "$golden" || break; sleep 2; done

  snap="$(platform .snapshots.golden)-$(date +%Y.%m.%d)"
  VBoxManage snapshot "$golden" take "$snap" --description "provisioned golden image"
  echo "$snap" > "$CYBERAI_HOME/.cyberai.golden-snap"
  # host-side manifest
  cat > "$CYBERAI_IMAGES/golden/manifest.json" <<M
{ "snapshot": "$snap", "kali": "$(platform .kali.release)",
  "built": "$(date -Iseconds)", "git_sha": "$(git -C "$CYBERAI_HOME" rev-parse --short HEAD 2>/dev/null || echo n/a)" }
M
  ok "Golden built. Snapshot: $snap"
}

golden_verify() {
  local golden ip; golden="$(platform .vm_names.golden)"
  vm_exists "$golden" || die "No golden VM."
  ip=$(_golden_ip "$golden") || die "No IP."
  local inv; inv=$(_write_inventory "$ip")
  log "Ansible check-mode (expect: no changes)…"
  ( cd "$CYBERAI_HOME/factory/ansible" && ansible-playbook -i "$inv" playbooks/golden.yml --check ) || warn "check-mode reported changes."
  log "SSH smoke tests…"
  ssh -i "$CYBERAI_SSH_KEY" -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=10 \
      "${CYBERAI_VM_USER}@$ip" '
    set -e
    nmap --version | head -1
    ls ~/.BurpSuite/bapps 2>/dev/null && echo "burp bapps present" || echo "no bapps yet"
    command -v opencode && opencode --version || echo "opencode missing"
    curl -fsm3 http://'"$CYBERAI_HOST_IP"':'"$CYBERAI_OLLAMA_PORT"'/api/tags >/dev/null && echo "ollama reachable from guest" || echo "ollama unreachable"
  '
  VBoxManage controlvm "$golden" acpipowerbutton 2>/dev/null || true
  ok "Verify complete."
}
