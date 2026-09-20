# lib/release.sh — export/import portable OVA + backup.

release_export() {
  local golden snap ova ver; golden="$(platform .vm_names.golden)"
  vm_exists "$golden" || die "no golden VM."
  require_off "$golden"
  ver="$(date +%Y.%m.%d)"; ova="$CYBERAI_IMAGES/releases/CyberAI-Kali-${ver}.ova"
  mkdir -p "$CYBERAI_IMAGES/releases"
  log "Exporting $golden -> $ova (this is large; be patient)…"
  VBoxManage export "$golden" --output "$ova" --manifest \
    --vsys 0 --product "CyberAI-Kali" --version "$ver"
  sha256sum "$ova" | tee "${ova}.sha256"
  cp -f "$CYBERAI_IMAGES/golden/manifest.json" "${ova%.ova}.manifest.json" 2>/dev/null || true
  # keep only last 2 releases
  ls -1t "$CYBERAI_IMAGES/releases"/CyberAI-Kali-*.ova 2>/dev/null | tail -n +3 | while read -r old; do
    warn "pruning old release: $(basename "$old")"; rm -f "$old" "${old}.sha256" "${old%.ova}.manifest.json"
  done
  ok "Release exported: $ova"
}

release_import() {
  local ova="${1:?path to .ova}"
  [ -f "$ova" ] || die "no such file: $ova"
  [ -f "${ova}.sha256" ] && { log "verifying checksum…"; (cd "$(dirname "$ova")" && sha256sum -c "$(basename "$ova").sha256") || die "checksum mismatch"; }
  log "Importing appliance (.ova -> import)…"
  VBoxManage import "$ova" --vsys 0 --vmname "$(platform .vm_names.golden)"
  ok "Imported as $(platform .vm_names.golden). Snapshot it, then: cyberai new <name>"
}

backup_run() {
  local dest="${1:?usage: cyberai backup <dest-dir>}"
  mkdir -p "$dest"
  log "Backing up source + config + releases + rag snapshot -> $dest"
  rsync -a --delete \
    --include='cyberai' --include='lib/***' --include='config/***' \
    --include='factory/***' --include='services/***' --include='docs/***' \
    --include='.cyberai.env.example' --include='.gitignore' \
    --include='images/' --include='images/releases/***' \
    --include='rag/' --include='rag/backups/***' \
    --exclude='*' "$CYBERAI_HOME/" "$dest/CyberAIKaliVM/"
  _oll_list() { OLLAMA_HOST="${CYBERAI_HOST_IP}:${CYBERAI_OLLAMA_PORT}" ollama list 2>/dev/null; }
  _oll_list > "$dest/CyberAIKaliVM/models.list" 2>/dev/null || true
  ok "Backup complete (models are re-pullable; see models.list)."
}
