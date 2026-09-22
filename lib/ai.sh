# lib/ai.sh — manage/benchmark host-native Ollama models.

OLLAMA_API() { echo "http://${CYBERAI_HOST_IP}:${CYBERAI_OLLAMA_PORT}"; }
_oll() { OLLAMA_HOST="${CYBERAI_HOST_IP}:${CYBERAI_OLLAMA_PORT}" ollama "$@"; }

ai_dispatch() { local sub="${1:?pull|list|rm|run|bench|tune|untune}"; shift || true
  case "$sub" in
    pull)   _ai_pull "$@" ;;
    list)   _oll list ;;
    rm)     _oll rm "${1:?model}" ;;
    run)    _ai_run "$@" ;;
    bench)  _ai_bench "$@" ;;
    tune)   exec "$CYBERAI_HOME/lib/local-llm-setup.sh"  "$@" ;;
    untune) exec "$CYBERAI_HOME/lib/local-llm-remove.sh" "$@" ;;
    *) die "usage: cyberai ai pull|list|rm|run|bench|tune|untune" ;;
  esac; }

# Send a prompt to a host-native model and stream the reply.
#   cyberai ai run "what does nmap -sV do?"            # default model
#   cyberai ai run qwen3:1.7b "what does nmap -sV do?" # explicit model
# A leading model:tag argument selects the model; otherwise CYBERAI_AI_MODEL
# (default qwen2.5:3b-instruct) is used. qwen3 "thinking" is disabled for speed.
_ai_run() {
  local model="${CYBERAI_AI_MODEL:-qwen2.5:3b-instruct}"
  # A model:tag is a single whitespace-free token; anything with a space is prompt text.
  case "${1:-}" in
    *[[:space:]]*) ;;            # has spaces -> it's the prompt, keep default model
    *:*) model="$1"; shift ;;    # bare model:tag -> use it as the model
  esac
  local prompt="$*"
  [ -n "$prompt" ] || die "usage: cyberai ai run [model:tag] <prompt>"
  curl -fsSN "$(OLLAMA_API)/api/generate" \
    -d "$(jq -nc --arg m "$model" --arg p "$prompt" \
        '{model:$m,prompt:$p,stream:true,think:false,options:{temperature:0}}')" \
  | while IFS= read -r line; do
      printf '%s' "$(jq -rj '.response // empty' <<<"$line")"
    done
  echo
}

_ai_pull() {
  if [ $# -gt 0 ]; then _oll pull "$1"; return; fi
  while read -r m; do [ -n "$m" ] && _oll pull "$m"; done \
    < <(yq_get "$CYBERAI_HOME/config/ai/models.yml" '.chat[], .embedding[]')
}

_ai_bench() {
  local model="${1:-qwen2.5:3b-instruct}"
  local out="$CYBERAI_HOME/docs/benchmarks/$(date +%Y-%m-%d)-${model//[:\/]/_}.md"
  mkdir -p "$(dirname "$out")"
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
    local resp; resp=$(curl -fsS -m 480 "$(OLLAMA_API)/api/generate" -d "$(jq -nc --arg m "$model" --arg p "$p" '{model:$m,prompt:$p,stream:false,think:false,options:{num_predict:400,temperature:0}}')") || { warn "request failed"; continue; }
    local ec ed pd tt tps
    ec=$(jq -r '.eval_count // 0' <<<"$resp"); ed=$(jq -r '.eval_duration // 0' <<<"$resp")
    pd=$(jq -r '.prompt_eval_duration // 0' <<<"$resp"); tt=$(jq -r '.total_duration // 0' <<<"$resp")
    tps=$(awk -v e="$ec" -v d="$ed" 'BEGIN{ if(d>0) printf "%.1f", e/(d/1e9); else print "n/a"}')
    { echo "## Prompt $i"; echo "**Q:** $p"; echo; echo "- **A:** $(jq -r '.response // "(empty)"' <<<"$resp")"; echo
      echo "- tokens/s: **$tps**"; printf -- "- eval tokens: %s\n" "$ec"
      printf -- "- TTFT (prompt eval): %.2fs\n" "$(awk -v d="$pd" 'BEGIN{print d/1e9}')"
      printf -- "- total: %.2fs\n\n" "$(awk -v d="$tt" 'BEGIN{print d/1e9}')"; } >> "$out"
    log "prompt $i: ${tps} tok/s"
  done
  ok "Benchmark written: $out"
}
