# lib/rag.sh — manage the host RAG docker stack + ingestion.

_compose() { docker compose -f "$CYBERAI_HOME/services/rag/docker-compose.yml" \
  --env-file "$CYBERAI_HOME/.cyberai.env" "$@"; }

rag_dispatch() { local sub="${1:?up|down|status|update|backup|restore}"; shift || true
  case "$sub" in
    up)      _compose up -d && ok "RAG stack up on ${CYBERAI_HOST_IP}:${CYBERAI_RAG_PORT}" ;;
    down)    _compose down && ok "RAG stack stopped" ;;
    status)  curl -fsS "http://${CYBERAI_HOST_IP}:${CYBERAI_RAG_PORT}/status" | jq . || warn "RAG not responding" ;;
    update)  _rag_update "${1:-all}" ;;
    backup)  _rag_backup ;;
    restore) _rag_restore "${1:?snapshot path}" ;;
    *) die "usage: cyberai rag up|down|status|update [stable|live]|backup|restore" ;;
  esac; }

_rag_update() { # runs the ingest container against the chosen layer
  local layer="$1"
  log "RAG ingest ($layer)…"
  _compose run --rm ingest python -m ingest.run --layer "$layer" \
    --qdrant "http://qdrant:6333" \
    --embed "http://${CYBERAI_HOST_IP}:${CYBERAI_OLLAMA_PORT}" || die "ingest failed"
  ok "RAG update ($layer) done."
}

_rag_backup() {
  local dst="$CYBERAI_RAG/backups/qdrant-$(date +%Y%m%d-%H%M).snapshot"
  mkdir -p "$(dirname "$dst")"
  curl -fsS -X POST "http://${CYBERAI_HOST_IP}:6333/snapshots" >/dev/null 2>&1 || true
  cp -a "$CYBERAI_RAG/data" "$dst" 2>/dev/null || warn "copy fallback"
  ok "RAG backup: $dst"
}
_rag_restore() { cp -a "$1"/* "$CYBERAI_RAG/data/" && ok "restored from $1"; }
