# lib/release.sh — export/import portable OVA + backup.

release_dir() { echo "$CYBERAI_IMAGES/releases"; }

# Accept either a bare filename or an absolute/relative path, so the command we
# print after a reset can be pasted back verbatim.
_resolve_ova() { local n="$1" f
  case "$n" in /*) f="$n" ;; *) f="$(release_dir)/$n" ;; esac
  [ -f "$f" ] || die "no such release: $n (see: cyberai release list)"
  echo "$f"
}

# Exported .ova basenames, newest first, with the filename breaking mtime ties
# so `release list` and `release prune` can never disagree on which are newest.
_release_ovas() {
  find "$(release_dir)" -maxdepth 1 -type f -name 'CyberAI-Kali-*.ova' \
       -printf '%T@ %f\n' 2>/dev/null | sort -k1,1nr -k2,2r | cut -d' ' -f2-
}

release_list() {
  local any=0 base
  printf '  %-34s %10s  %s\n' "RELEASE" "SIZE" "BUILT"
  while read -r base; do
    [ -n "$base" ] || continue
    any=1
    printf '  %-34s %10s  %s\n' "$base" \
      "$(du -h "$(release_dir)/$base" | cut -f1)" \
      "$(date -r "$(release_dir)/$base" '+%Y-%m-%d %H:%M')"
  done < <(_release_ovas)
  [ "$any" = 1 ] || { echo "  (no releases - 'cyberai release' creates one)"; return 0; }
  echo; echo "  total: $(du -sh "$(release_dir)" 2>/dev/null | cut -f1)"
}

# Deletes the .ova together with the sidecars release_export writes beside it,
# so a partial cleanup never leaves a .sha256 pointing at nothing.
release_rm() {
  local f; f="$(_resolve_ova "${1:?usage: cyberai release rm <name.ova>}")"
  warn "removing $(basename "$f") + sidecars"
  rm -f "$f" "${f}.sha256" "${f%.ova}.manifest.json"
  ok "Removed $(basename "$f")"
}

release_prune() { # keep the newest N (default 2)
  local keep="${1:-2}" base
  # Order by mtime descending with the filename as a deterministic tiebreak.
  # Two exports can easily land in the same second, and plain `ls -t` leaves
  # tied mtimes in arbitrary order -- so which release survived would come down
  # to filesystem luck, silently deleting the wrong one.
  _release_ovas | tail -n +$((keep + 1)) | while read -r base; do
    [ -n "$base" ] || continue
    warn "pruning old release: $base"
    rm -f "$(release_dir)/$base" "$(release_dir)/$base.sha256" "$(release_dir)/${base%.ova}.manifest.json"
  done || true
  return 0
}

release_dispatch() { local sub="${1:-export}"; shift || true
  case "$sub" in
    export|"") release_export "$@" ;;
    list)       release_list "$@" ;;
    rm)         release_rm "$@" ;;
    prune)      release_prune "$@" ;;
    import)     release_import "$@" ;;
    *) die "usage: cyberai release [export|list|rm <name.ova>|prune [keep-n]]" ;;
  esac; }

release_export() {
  local golden ova ver; golden="$(platform .vm_names.golden)"
  vm_exists "$golden" || die "no golden VM."
  require_off "$golden"
  ver="$(date +%Y.%m.%d)"; ova="$(release_dir)/CyberAI-Kali-${ver}.ova"
  mkdir -p "$(release_dir)"
  # Never silently clobber an existing safety copy: two exports on the same day
  # would otherwise overwrite each other, and `--keep-ova` is a backup.
  if [ -e "$ova" ]; then
    local n=2
    while [ -e "$(release_dir)/CyberAI-Kali-${ver}-$n.ova" ]; do n=$((n + 1)); done
    ova="$(release_dir)/CyberAI-Kali-${ver}-$n.ova"
    warn "$(basename "$(release_dir)/CyberAI-Kali-${ver}.ova") already exists - writing $(basename "$ova") instead"
  fi
  log "Exporting $golden -> $ova (this is large; be patient)…"
  VBoxManage export "$golden" --output "$ova" --manifest \
    --vsys 0 --product "CyberAI-Kali" --version "$ver" \
    || { rm -f "$ova" "${ova}.sha256" "${ova%.ova}.manifest.json"
         die "export failed - removed partial $(basename "$ova")"; }
  sha256sum "$ova" | tee "${ova}.sha256"
  cp -f "$CYBERAI_IMAGES/golden/manifest.json" "${ova%.ova}.manifest.json" 2>/dev/null || true
  release_prune 2
  RELEASE_LAST_OVA="$ova"     # read by golden reset to print its cleanup command
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
