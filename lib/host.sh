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
  touch "$CYBERAI_HOME/.cyberai.host-ready"
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
  local apt_pkgs=(jq p7zip-full sshpass ufw curl wget rsync python3-pip pipx zstd)
  # Docker engine: only request Ubuntu's docker.io when nothing is already installed.
  # Respects Docker CE (download.docker.com), docker.io, or any future provider.
  if have docker; then
    ok "docker already present ($(docker --version 2>/dev/null | cut -d, -f1)) — skipping docker.io"
  else
    apt_pkgs+=(docker.io)            # clean machines get Docker via Ubuntu repo
  fi
  # Compose v2: present as the "docker compose" plugin (CE or Ubuntu) OR legacy v1.
  if docker compose version >/dev/null 2>&1 || have docker-compose; then
    ok "docker compose available — skipping docker-compose-v2"
  else
    apt_pkgs+=(docker-compose-v2)    # clean machines: v2 plugin from Ubuntu repo
  fi
  sudo apt-get install -y -qq "${apt_pkgs[@]}" >/dev/null
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
    log "Installing Ollama ${ver} (pinned tarball, sha256-checked)…"

    # Preflight: fail loudly NOW instead of a silent skip downstream.
    local code
    code=$(curl -sL --max-time 20 -o /dev/null -w '%{http_code}' -r 0-0 "$url" 2>/dev/null)
    case "$code" in 2*) ;; *)
      die "Ollama asset unreachable (HTTP $code) at:\n  $url\n=== The pinned release may have moved/been renamed. Auto-refresh it with:\n    ./cyberai host ollama-pin\n=== then re-run host-setup.";;
    esac

    # Cache in downloads/ (gitignored) with resume (-c) so retries/re-runs don't re-fetch 1.4 GB.
    local dl
    dl="${CYBERAI_DOWNLOADS}/ollama-${ver}.tar.zst"
    case "$url" in *.tgz) dl="${CYBERAI_DOWNLOADS}/ollama-${ver}.tgz";; esac
    mkdir -p "$(dirname "$dl")"
    wget -c --tries=3 --timeout=120 --show-progress --progress=bar:force -O "$dl" "$url" \
      || die "Ollama download failed (see progress above). Re-run host-setup to retry."

    local want; want="$(platform .ollama.sha256)"
    if [ -n "$want" ] && [ "$want" != "null" ] && \
       ! { echo "$want  $dl" | sha256sum -c - >/dev/null; }; then
      die "Ollama checksum mismatch — the lockfile is out of date. Run: ./cyberai host ollama-pin"
    fi

    # .zst: use --zstd WITHOUT -z (the two conflict); .tgz: plain gzip.
    case "$url" in
      *.zst) sudo tar --zstd -C /usr -xf "$dl" || die "Ollama extraction failed (zstd)." ;;
      *)     sudo tar -C /usr -xzf "$dl"    || die "Ollama extraction failed." ;;
    esac
    id ollama >/dev/null 2>&1 || sudo useradd -r -s /bin/false -U -m -d /usr/share/ollama ollama
    [ -x /usr/bin/ollama ] || die "ollama binary missing after extract (unexpected tarball layout)."
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
Environment="OLLAMA_MODELS=/var/lib/ollama"
Environment="OLLAMA_KEEP_ALIVE=5m"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_NUM_PARALLEL=1"
Environment="OLLAMA_CONTEXT_LENGTH=8192"
Environment="OLLAMA_FLASH_ATTENTION=1"
Environment="OLLAMA_KV_CACHE_TYPE=q8_0"
[Install]
WantedBy=multi-user.target
UNIT
  # Model store lives OUTSIDE the user's home (/var/lib/ollama) so the
  # 'ollama' service user can own it without traversing 700-perm home dirs.
  sudo install -d -o ollama -g ollama /var/lib/ollama
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
  # Docker containers (rag-api, ingest) also call host Ollama for embeddings. They arrive
  # from the private docker bridge range (172.16/12), not the AI plane — without this they
  # are silently dropped by ufw's deny-incoming default and every rag action times out.
  sudo ufw allow from 172.16.0.0/12 to "$CYBERAI_HOST_IP" port "$CYBERAI_OLLAMA_PORT" proto tcp >/dev/null 2>&1 || true
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

host_ollama_pin() { # refresh the pinned Ollama release (version/url/sha256) from GitHub — no manual edits
  command -v yq >/dev/null || die "yq not found — run './cyberai host-setup' once first."
  local tag url sha
  log "Querying GitHub for the latest stable Ollama release…"
  tag=$(curl -fsSL --max-time 25 "https://api.github.com/repos/ollama/ollama/releases/latest" | jq -r .tag_name)
  [ -n "$tag" ] || die "empty tag from GitHub API (no network? rate-limited?)."
  url="https://github.com/ollama/ollama/releases/download/$tag/ollama-linux-amd64.tar.zst"
  sha=$(curl -fsSL --max-time 25 "https://github.com/ollama/ollama/releases/download/$tag/sha256sum.txt" \
        | awk '/ollama-linux-amd64\.tar\.zst$/{print $1; exit}')
  [ -n "$sha" ] || die "no sha256 found for ollama-linux-amd64.tar.zst in release $tag."
  if [ "$(platform .ollama.version)" = "$tag" ] && [ "$(platform .ollama.sha256)" = "$sha" ]; then
    ok "Ollama pins current ($tag) — nothing to do."
    return 0
  fi
  yq -i ".ollama.version=\"$tag\" | .ollama.url=\"$url\" | .ollama.sha256=\"$sha\"" \
     "$CYBERAI_HOME/config/platform.yml"
  ok "Updated config/platform.yml -> version=$tag, sha256=…${sha:0:12} (url point to $url)"
  log "Re-run: ./cyberai host-setup   to install the refreshed release."
}

host_cmd() { # cyberai host setup|ollama-pin
  case "${1:-setup}" in
    setup)      shift || true; host_setup "$@" ;;
    ollama-pin) shift || true; host_ollama_pin "$@" ;;
    *) die "usage: cyberai host setup|ollama-pin" ;;
  esac
}
