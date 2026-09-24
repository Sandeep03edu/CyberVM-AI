# lib/doctor.sh — readiness PASS/FAIL table

doctor() {
  local pass=0 fail=0
  # cyberai runs under `set -e`: a failing probe (e.g. curl to a down Ollama)
  # would abort the table early. Evaluate every check explicitly instead.
  local had_e=0; [[ $- == *e* ]] && had_e=1; set +e
  _row() { # _row <label> <ok?0/1> <detail>
    if [ "$2" -eq 0 ]; then printf '  %s[PASS]%s %-28s %s\n' "$GRN" "$RST" "$1" "$3"; pass=$((pass+1))
    else printf '  %s[FAIL]%s %-28s %s\n' "$RED" "$RST" "$1" "$3"; fail=$((fail+1)); fi
  }
  log "CyberAI doctor — host readiness"

  grep -qE '(vmx|svm)' /proc/cpuinfo; _row "CPU virtualization (VT-x)" $? ""
  have VBoxManage && v=$(VBoxManage --version) || v="missing"; [ "$v" != missing ]; _row "VirtualBox" $? "$v"
  have ansible-playbook; _row "ansible-core" $? "$(ansible-playbook --version 2>/dev/null | head -1)"
  have docker; _row "docker" $? "$(docker --version 2>/dev/null)"
  have yq; _row "yq" $? ""; have jq; _row "jq" $? ""

  # pinned Burp extensions: lock serial must match the live store (no downloads)
  if source "$CYBERAI_HOME/lib/pins.sh" && pins_dispatch check burp >/dev/null 2>&1; then
    _row "Burp pins current" 0 "serial+sha256 match live store"
  else
    _row "Burp pins current" 1 "run: ./cyberai pins refresh burp"
  fi

  # host-only interface with our IP
  VBoxManage list hostonlyifs | awk -v ip="$CYBERAI_HOST_IP" '/^IPAddress:/{if($2==ip)f=1} END{exit !f}'
  _row "host-only net $CYBERAI_HOST_IP" $? ""

  # Ollama reachable on private IP but NOT on 0.0.0.0
  curl -fsm3 "http://${CYBERAI_HOST_IP}:${CYBERAI_OLLAMA_PORT}/api/tags" >/dev/null 2>&1
  _row "Ollama @ $CYBERAI_HOST_IP" $? ""
  if curl -fsm3 "http://127.0.0.1:${CYBERAI_OLLAMA_PORT}/api/tags" >/dev/null 2>&1; then
    _row "Ollama NOT on loopback" 1 "reachable on 127.0.0.1 (tighten OLLAMA_HOST)"
  else _row "Ollama NOT on loopback" 0 "good"; fi

  sudo ufw status 2>/dev/null | grep -q "Status: active"; _row "ufw active" $? ""
  [ -f "$CYBERAI_SSH_KEY" ]; _row "provisioning SSH key" $? "$CYBERAI_SSH_KEY"
  [ -f "$CYBERAI_SECRETS" ]; _row "secrets file" $? "$CYBERAI_SECRETS"

  local free; free=$(host_free_mb); [ "$free" -ge "$CYBERAI_HOST_RESERVE_MB" ]
  _row "host free RAM" $? "${free}MB (reserve ${CYBERAI_HOST_RESERVE_MB}MB)"
  local avail; avail=$(df -Pm "$CYBERAI_ROOT" 2>/dev/null | awk 'NR==2{print $4}')
  [ "${avail:-0}" -ge 60000 ]; _row "disk free @ root" $? "${avail}MB"

  # verified Kali archive present + checksum
  local arc="$CYBERAI_DOWNLOADS/kali/$(platform .kali.archive)"
  if [ -f "$arc" ]; then
    local want; want="$(platform .kali.sha256)"
    echo "$want  $arc" | sha256sum -c - >/dev/null 2>&1
    _row "Kali archive checksum" $? "$(basename "$arc")"
  else _row "Kali archive present" 1 "missing: $arc"; fi

  echo; log "Result: ${GRN}${pass} PASS${RST}, ${RED}${fail} FAIL${RST}"
  [ "$fail" -eq 0 ]; local rc=$?
  [[ $had_e == 1 ]] && set -e
  return "$rc"
}
