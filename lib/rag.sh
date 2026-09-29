# lib/rag.sh — manage the host RAG docker stack + ingestion.

_compose() { docker compose -f "$CYBERVM_HOME/services/rag/docker-compose.yml" \
  --env-file "$CYBERVM_HOME/.cybervm.env" "$@"; }

rag_dispatch() { local sub="${1:?up|down|status|update|backup|restore}"; shift || true
  case "$sub" in
    up)      _compose up -d && ok "RAG stack up on ${CYBERVM_HOST_IP}:${CYBERVM_RAG_PORT}" ;;
    down)    _compose down && ok "RAG stack stopped" ;;
    status)  curl -fsS "http://${CYBERVM_HOST_IP}:${CYBERVM_RAG_PORT}/status" | jq . || warn "RAG not responding" ;;
    update)  local layer="${1:-all}"; shift || true; _rag_update "$layer" "$@" ;;
    backup)  _rag_backup ;;
    restore) _rag_restore "${1:?snapshot path}" ;;
    *) die "usage: cybervm rag up|down|status|update [stable|live]|backup|restore" ;;
  esac; }

_rag_update() { # runs the ingest container against the chosen layer (optional --only <source-id>)
  local layer="$1"; shift || true
  log "RAG ingest ($layer)…"
  # Ensure qdrant is up (ingest writes to it via DNS "qdrant"); rag-api is not needed to ingest.
  _compose up -d qdrant >/dev/null
  # --build: rebuild the image so a changed Dockerfile/context takes effect
  # (docker compose reuses the built tag otherwise, keeping stale code alive).
  _compose run --rm --build ingest python -m ingest.run --layer "$layer" \
    --qdrant "http://qdrant:6333" \
    --embed "http://${CYBERVM_HOST_IP}:${CYBERVM_OLLAMA_PORT}" "$@" || die "ingest failed"
  ok "RAG update ($layer) done."
}

_rag_backup() {
  local dst="$CYBERVM_RAG/backups/qdrant-$(date +%Y%m%d-%H%M).snapshot"
  mkdir -p "$(dirname "$dst")"
  curl -fsS -X POST "http://${CYBERVM_HOST_IP}:6333/snapshots" >/dev/null 2>&1 || true
  cp -a "$CYBERVM_RAG/data" "$dst" 2>/dev/null || warn "copy fallback"
  if [ -d "$CYBERVM_RAG/state" ]; then cp -a "$CYBERVM_RAG/state" "$dst.state" 2>/dev/null || true; fi
  ok "RAG backup: $dst (+ state)"
}
_rag_restore() { cp -a "$1"/* "$CYBERVM_RAG/data/" 2>/dev/null; if [ -d "$1.state" ]; then cp -a "$1.state"/* "$CYBERVM_RAG/state/" 2>/dev/null || true; fi; ok "restored from $1"; }
