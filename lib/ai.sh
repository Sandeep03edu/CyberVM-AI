# lib/ai.sh — manage/benchmark host-native Ollama models.

OLLAMA_API() { echo "http://${CYBERAI_HOST_IP}:${CYBERAI_OLLAMA_PORT}"; }
_oll() { OLLAMA_HOST="${CYBERAI_HOST_IP}:${CYBERAI_OLLAMA_PORT}" ollama "$@"; }

ai_dispatch() { local sub="${1:?pull|list|rm|bench}"; shift || true
  case "$sub" in
    pull)  _ai_pull "$@" ;;
    list)  _oll list ;;
    rm)    _oll rm "${1:?model}" ;;
    bench) _ai_bench "$@" ;;
    *) die "usage: cyberai ai pull|list|rm|bench" ;;
  esac; }

_ai_pull() {
  if [ $# -gt 0 ]; then _oll pull "$1"; return; fi
  while read -r m; do [ -n "$m" ] && _oll pull "$m"; done \
    < <(yq_get "$CYBERAI_HOME/config/ai/models.yml" '.chat[], .embedding[]')
}

_ai_bench() {
  local model="${1:-qwen3:8b}"
  local out="$CYBERAI_HOME/docs/benchmarks/$(date +%Y-%m-%d)-${model//[:\/]/_}.md"
  local prompts=(
    "Explain this nmap result and what to probe next: 22/tcp open ssh; 80/tcp open http; 3306/tcp open mysql."
    "Given HTTP 500 with 'You have an error in your SQL syntax' on ?id=1', what class of bug and next test?"
    "Outline a methodical approach to a web CTF box exposing only port 80 with a login form."
  )
  log "Benchmarking $model on $(nproc) threads -> $out"
  { echo "# Bench $model — $(date -Iseconds)"; echo; echo "Host: $(uname -sr), $(nproc) threads"; echo; } > "$out"
  local i=0
  for p in "${prompts[@]}"; do
    i=$((i+1))
    local resp; resp=$(curl -fsS "$(OLLAMA_API)/api/generate" -d "$(jq -nc --arg m "$model" --arg p "$p" '{model:$m,prompt:$p,stream:false}')") || { warn "request failed"; continue; }
    local ec ed pd tt tps
    ec=$(jq -r '.eval_count // 0' <<<"$resp"); ed=$(jq -r '.eval_duration // 0' <<<"$resp")
    pd=$(jq -r '.prompt_eval_duration // 0' <<<"$resp"); tt=$(jq -r '.total_duration // 0' <<<"$resp")
    tps=$(awk -v e="$ec" -v d="$ed" 'BEGIN{ if(d>0) printf "%.1f", e/(d/1e9); else print "n/a"}')
    { echo "## Prompt $i"; echo "- tokens/s: **$tps**"; printf -- "- eval tokens: %s\n" "$ec"
      printf -- "- TTFT (prompt eval): %.2fs\n" "$(awk -v d="$pd" 'BEGIN{print d/1e9}')"
      printf -- "- total: %.2fs\n\n" "$(awk -v d="$tt" 'BEGIN{print d/1e9}')"; } >> "$out"
    log "prompt $i: ${tps} tok/s"
  done
  ok "Benchmark written: $out"
}
