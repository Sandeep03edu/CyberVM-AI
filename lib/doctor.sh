# lib/doctor.sh — readiness PASS/FAIL table

doctor() {
  local pass=0 fail=0
  # cybervm runs under `set -e`: a failing probe (e.g. curl to a down Ollama)
  # would abort the table early. Evaluate every check explicitly instead.
  local had_e=0; [[ $- == *e* ]] && had_e=1; set +e
  _row() { # _row <label> <ok?0/1> <detail>
    if [ "$2" -eq 0 ]; then printf '  %s[PASS]%s %-28s %s\n' "$GRN" "$RST" "$1" "$3"; pass=$((pass+1))
    else printf '  %s[FAIL]%s %-28s %s\n' "$RED" "$RST" "$1" "$3"; fail=$((fail+1)); fi
  }
  log "CyberVM doctor — host readiness"

  grep -qE '(vmx|svm)' /proc/cpuinfo; _row "CPU virtualization (VT-x)" $? ""
  have VBoxManage && v=$(VBoxManage --version) || v="missing"; [ "$v" != missing ]; _row "VirtualBox" $? "$v"
  have ansible-playbook; _row "ansible-core" $? "$(ansible-playbook --version 2>/dev/null | head -1)"
  have docker; _row "docker" $? "$(docker --version 2>/dev/null)"
  have yq; _row "yq" $? ""; have jq; _row "jq" $? ""

  # pinned Burp extensions: lock serial must match the live store (no downloads)
  if source "$CYBERVM_HOME/lib/pins.sh" && pins_dispatch check burp >/dev/null 2>&1; then
    _row "Burp pins current" 0 "serial+sha256 match live store"
  else
    _row "Burp pins current" 1 "run: ./cybervm pins refresh burp"
  fi

  # host-only interface with our IP
  VBoxManage list hostonlyifs | awk -v ip="$CYBERVM_HOST_IP" '/^IPAddress:/{if($2==ip)f=1} END{exit !f}'
  _row "host-only net $CYBERVM_HOST_IP" $? ""

  # Ollama reachable on private IP but NOT on 0.0.0.0
  curl -fsm3 "http://${CYBERVM_HOST_IP}:${CYBERVM_OLLAMA_PORT}/api/tags" >/dev/null 2>&1
  _row "Ollama @ $CYBERVM_HOST_IP" $? ""
  if curl -fsm3 "http://127.0.0.1:${CYBERVM_OLLAMA_PORT}/api/tags" >/dev/null 2>&1; then
    _row "Ollama NOT on loopback" 1 "reachable on 127.0.0.1 (tighten OLLAMA_HOST)"
  else _row "Ollama NOT on loopback" 0 "good"; fi

  sudo ufw status 2>/dev/null | grep -q "Status: active"; _row "ufw active" $? ""
  [ "$(readlink -f /usr/local/bin/cybervm 2>/dev/null)" = "$(readlink -f "$CYBERVM_HOME/cybervm")" ]
  _row "cybervm on PATH" $? "/usr/local/bin/cybervm (re-run host-setup if moved)"
  [ -f "$CYBERVM_SSH_KEY" ]; _row "provisioning SSH key" $? "$CYBERVM_SSH_KEY"
  [ -f "$CYBERVM_SECRETS" ]; _row "secrets file" $? "$CYBERVM_SECRETS"

  local free; free=$(host_free_mb); [ "$free" -ge "$CYBERVM_HOST_RESERVE_MB" ]
  _row "host free RAM" $? "${free}MB (reserve ${CYBERVM_HOST_RESERVE_MB}MB)"
  # vm_start compares *free* RAM against a VM's *full* allocation, so a host can
  # look roomy and still refuse a second VM. Report what the running clones have
  # claimed, and whether another one would fit.
  if have VBoxManage; then
    source "$CYBERVM_HOME/lib/vm.sh"   # _clone_ram_allocated_mb / _cybervm_vms
    local alloc nram; alloc=$(_clone_ram_allocated_mb); nram=$((free - alloc))
    [ "$nram" -ge "$CYBERVM_HOST_RESERVE_MB" ]
    _row "clone RAM headroom" $? "${alloc}MB claimed by running clones; ${nram}MB would be free for one more (need >= ${CYBERVM_HOST_RESERVE_MB}MB)"
  fi
  local avail; avail=$(df -Pm "$CYBERVM_ROOT" 2>/dev/null | awk 'NR==2{print $4}')
  [ "${avail:-0}" -ge 60000 ]; _row "disk free @ root" $? "${avail}MB"

  # verified Kali archive present + checksum
  local arc="$CYBERVM_DOWNLOADS/kali/$(platform .kali.archive)"
  if [ -f "$arc" ]; then
    local want; want="$(platform .kali.sha256)"
    echo "$want  $arc" | sha256sum -c - >/dev/null 2>&1
    _row "Kali archive checksum" $? "$(basename "$arc")"
  else _row "Kali archive present" 1 "missing: $arc"; fi

  # Shared host-side VM config (clipboard/DnD) vs config/platform.yml .vm_defaults.
  # Read-only: never mutates a VM. This is the drift alarm for the clone-time-only
  # VirtualBox settings that a golden rebuild or a clone re-creation resolves.
  if _vm_defaults_ok; then
    local anyvm=0 badvm=0 nvm badlist=""
    while read -r nvm; do
      [ -n "$nvm" ] || continue
      case "$nvm" in CyberVM-Kali-*) ;; *) continue ;; esac
      anyvm=1
      if ! vm_host_config_drift "$nvm" >/dev/null 2>&1; then badvm=1; badlist="$badlist $nvm"; fi
    done <<<"$(VBoxManage list vms 2>/dev/null | sed -n 's/^"\([^"]*\)".*/\1/p')"
    if [ "$anyvm" -eq 0 ]; then
      _row "VM clipboard/DnD" 1 "no CyberVM VMs registered"
    elif [ "$badvm" -eq 0 ]; then
      _row "VM clipboard/DnD" 0 "all VMs match config ($(vm_desired_clipboard)/$(vm_desired_draganddrop))"
    else
      _row "VM clipboard/DnD" 1 "drift on:$badlist -> ./cybervm golden build, then re-create clones"
    fi
  else
    _row "VM clipboard/DnD" 1 ".vm_defaults missing in config/platform.yml"
  fi

  echo; log "Result: ${GRN}${pass} PASS${RST}, ${RED}${fail} FAIL${RST}"
  [ "$fail" -eq 0 ]; local rc=$?
  [[ $had_e == 1 ]] && set -e
  return "$rc"
}
