# lib/host.sh — one-shot, idempotent host preparation (any x86-64 Ubuntu/Debian).

host_setup() {
  log "CyberAI host-setup starting (idempotent; safe to re-run)."
  _host_preflight
  _host_apt
  _host_ssh_key
  _host_ollama
  _host_network
  _host_ufw
  _host_secrets_stub
  _host_models
  ok "host-setup complete. Run: ./cyberai doctor"
}

_host_preflight() {
  log "Preflight checks…"
  grep -qE '(vmx|svm)' /proc/cpuinfo || die "No hardware virtualization (VT-x) in /proc/cpuinfo — enable it in BIOS."
  local total_mb; total_mb=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)
  [ "$total_mb" -ge 16000 ] || warn "RAM ${total_mb}MB is low; 32GB recommended."
  # KVM/VBox coexistence: if kvm modules hold VMX exclusively, VBox VMs fail to start.
  if lsmod | grep -q '^kvm_intel' && [ ! -e /etc/modprobe.d/kvm-cyberai.conf ]; then
    warn "KVM modules loaded. If VirtualBox VMs fail to start, run:"
    warn "  echo 'options kvm enable_virt_at_load=0' | sudo tee /etc/modprobe.d/kvm-cyberai.conf && sudo update-initramfs -u"
  fi
  have VBoxManage || die "VirtualBox not installed. Install virtualbox-7.2 from Oracle's repo, then re-run."
  ok "Preflight OK (VT-x present, VirtualBox present)."
}

_host_apt() {
  log "Installing host dependencies via apt (sudo)…"
  sudo apt-get update -qq
  sudo apt-get install -y -qq jq p7zip-full sshpass ufw curl wget rsync python3-pip pipx docker.io docker-compose-v2 >/dev/null
  # yq (mikefarah) — static binary if not present
  if ! have yq; then
    local yq_url="https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64"
    sudo wget -qO /usr/local/bin/yq "$yq_url" && sudo chmod +x /usr/local/bin/yq
  fi
  # ansible-core via pipx (pinned, user-scoped)
  if ! have ansible-playbook; then
    pipx install --quiet ansible-core || pip install --user ansible-core
    pipx ensurepath >/dev/null 2>&1 || true
  fi
  sudo systemctl enable --now docker >/dev/null 2>&1 || true
  ok "Dependencies installed (yq, jq, ansible-core, docker, 7z, sshpass, ufw)."
}

_host_ssh_key() {
  local kdir; kdir="$(dirname "$CYBERAI_SSH_KEY")"
  mkdir -p "$kdir"; chmod 700 "$kdir"
  if [ ! -f "$CYBERAI_SSH_KEY" ]; then
    ssh-keygen -t ed25519 -N '' -C 'cyberai-provisioning' -f "$CYBERAI_SSH_KEY" >/dev/null
    ok "Generated provisioning SSH key: $CYBERAI_SSH_KEY"
  else
    ok "Provisioning SSH key present."
  fi
}

_host_ollama() {
  local ver url; ver="$(platform .ollama.version)"; url="$(platform .ollama.url)"
  if have ollama && ollama --version 2>/dev/null | grep -q "${ver#v}"; then
    ok "Ollama ${ver} already installed."
  else
    log "Installing Ollama ${ver} (pinned tarball, sha256-checked if set)…"
    local tmp; tmp="$(mktemp -d)"
    wget -qO "$tmp/ollama.tgz" "$url"
    local want; want="$(platform .ollama.sha256)"
    if [ -n "$want" ] && [ "$want" != "null" ]; then
      echo "$want  $tmp/ollama.tgz" | sha256sum -c - || die "Ollama tarball checksum mismatch!"
    else
      warn "config/platform.yml ollama.sha256 empty — skipping checksum (set it for reproducible builds)."
    fi
    sudo tar -C /usr -xzf "$tmp/ollama.tgz"
    rm -rf "$tmp"
    id ollama >/dev/null 2>&1 || sudo useradd -r -s /bin/false -U -m -d /usr/share/ollama ollama
  fi
  # systemd unit + override binding to the private host-only IP
  sudo tee /etc/systemd/system/ollama.service >/dev/null <<UNIT
[Unit]
Description=Ollama (CyberAI)
After=network-online.target
[Service]
ExecStart=/usr/bin/ollama serve
User=ollama
Group=ollama
Restart=always
Environment="OLLAMA_HOST=${CYBERAI_HOST_IP}:${CYBERAI_OLLAMA_PORT}"
Environment="OLLAMA_MODELS=${CYBERAI_MODELS}/ollama"
Environment="OLLAMA_KEEP_ALIVE=5m"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_NUM_PARALLEL=1"
Environment="OLLAMA_CONTEXT_LENGTH=8192"
Environment="OLLAMA_FLASH_ATTENTION=1"
Environment="OLLAMA_KV_CACHE_TYPE=q8_0"
[Install]
WantedBy=multi-user.target
UNIT
  sudo mkdir -p "${CYBERAI_MODELS}/ollama"
  sudo chown -R ollama:ollama "${CYBERAI_MODELS}/ollama" 2>/dev/null || true
  # allow the 'ollama' user to traverse into the models dir (may be under $HOME)
  sudo setfacl -m u:ollama:rx "$CYBERAI_ROOT" "$CYBERAI_MODELS" 2>/dev/null || true
  sudo systemctl daemon-reload
  sudo systemctl enable --now ollama >/dev/null 2>&1 || true
  ok "Ollama service bound to ${CYBERAI_HOST_IP}:${CYBERAI_OLLAMA_PORT}."
}

_host_network() {
  log "Ensuring host-only network '${CYBERAI_NET_NAME}' (${CYBERAI_HOST_IP})…"
  # Find (or create) a hostonly IF with our IP.
  local ifn
  ifn=$(VBoxManage list hostonlyifs | awk -v ip="$CYBERAI_HOST_IP" '
    /^Name:/{n=$2} /^IPAddress:/{if($2==ip) print n}')
  if [ -z "$ifn" ]; then
    ifn=$(VBoxManage hostonlyif create 2>/dev/null | sed -n "s/.*'\(.*\)'.*/\1/p")
    [ -z "$ifn" ] && ifn=$(VBoxManage list hostonlyifs | awk '/^Name:/{n=$2} END{print n}')
    VBoxManage hostonlyif ipconfig "$ifn" --ip "$CYBERAI_HOST_IP" --netmask 255.255.255.0
  fi
  echo "$ifn" > "$CYBERAI_HOME/.cyberai.netif"
  # DHCP for the clones
  VBoxManage dhcpserver add --interface "$ifn" \
    --server-ip "$CYBERAI_HOST_IP" --netmask 255.255.255.0 \
    --lower-ip "$CYBERAI_DHCP_LOWER" --upper-ip "$CYBERAI_DHCP_UPPER" --enable 2>/dev/null \
  || VBoxManage dhcpserver modify --interface "$ifn" --enable 2>/dev/null || true
  ok "Host-only interface: $ifn ($CYBERAI_HOST_IP), DHCP ${CYBERAI_DHCP_LOWER}-${CYBERAI_DHCP_UPPER}."
}

_host_ufw() {
  log "Configuring ufw for the AI plane (allow only Ollama + RAG from ${CYBERAI_NET_CIDR})…"
  sudo ufw allow from "$CYBERAI_NET_CIDR" to "$CYBERAI_HOST_IP" port "$CYBERAI_OLLAMA_PORT" proto tcp >/dev/null 2>&1 || true
  sudo ufw allow from "$CYBERAI_NET_CIDR" to "$CYBERAI_HOST_IP" port "$CYBERAI_RAG_PORT" proto tcp    >/dev/null 2>&1 || true
  sudo ufw --force enable >/dev/null 2>&1 || true
  ok "ufw rules applied (transfer port ${CYBERAI_TRANSFER_PORT} opened on demand)."
}

_host_secrets_stub() {
  mkdir -p "$(dirname "$CYBERAI_SECRETS")"
  if [ ! -f "$CYBERAI_SECRETS" ]; then
    cat > "$CYBERAI_SECRETS" <<SEC
# CyberAI cloud API keys — NEVER commit, NEVER bake into images.
# Uncomment + fill only what you use.
#ANTHROPIC_API_KEY=
#OPENAI_API_KEY=
#DEEPSEEK_API_KEY=
#OPENROUTER_API_KEY=
SEC
    chmod 600 "$CYBERAI_SECRETS"
    ok "Created secrets file: $CYBERAI_SECRETS (chmod 600)."
  else
    ok "Secrets file present."
  fi
}

_host_models() {
  log "Pulling models from config/ai/models.yml (may take a while)…"
  local m
  while read -r m; do
    [ -z "$m" ] && continue
    OLLAMA_HOST="${CYBERAI_HOST_IP}:${CYBERAI_OLLAMA_PORT}" ollama pull "$m" || warn "pull failed: $m"
  done < <(yq_get "$CYBERAI_HOME/config/ai/models.yml" '.chat[], .embedding[]')
  ok "Model pulls attempted."
}
