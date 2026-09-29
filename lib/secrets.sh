# lib/secrets.sh — push named cloud API keys into a VM's tmpfs (never into images).

secrets_dispatch() { local sub="${1:?push|wipe}"; shift || true
  case "$sub" in push) secrets_push "$@";; wipe) secrets_wipe "$@";; *) die "usage: cybervm secrets push|wipe <vm> [names..]";; esac; }

_vmname_s() { local n="$1"; vm_exists "$(platform .vm_names.clone_prefix)$n" && echo "$(platform .vm_names.clone_prefix)$n" || echo "$n"; }

secrets_push() {
  local vm; vm="$(_vmname_s "${1:?vm}")"; shift || true
  [ -f "$CYBERVM_SECRETS" ] || die "no secrets file: $CYBERVM_SECRETS"
  vm_running "$vm" || die "start $vm first."
  # map friendly names to env var names
  declare -A M=( [anthropic]=ANTHROPIC_API_KEY [openai]=OPENAI_API_KEY [deepseek]=DEEPSEEK_API_KEY [openrouter]=OPENROUTER_API_KEY )
  local names=("$@"); [ ${#names[@]} -eq 0 ] && names=(anthropic openai deepseek openrouter)
  local tmp; tmp=$(mktemp)
  # shellcheck disable=SC1090
  ( set -a; source "$CYBERVM_SECRETS"; set +a
    for n in "${names[@]}"; do local var="${M[$n]:-}"; [ -n "$var" ] && [ -n "${!var:-}" ] && echo "export $var=${!var}"; done ) > "$tmp"
  local gc="VBoxManage guestcontrol $vm --username $CYBERVM_VM_USER --password $CYBERVM_VM_PASS"
  $gc run --exe /bin/bash -- bash -c "mkdir -p /run/user/1000/cybervm && chmod 700 /run/user/1000/cybervm"
  $gc copyto --target-directory /run/user/1000/cybervm "$tmp"
  $gc run --exe /bin/bash -- bash -c "mv /run/user/1000/cybervm/$(basename "$tmp") /run/user/1000/cybervm/secrets.env && chmod 600 /run/user/1000/cybervm/secrets.env"
  rm -f "$tmp"
  ok "Pushed keys to $vm tmpfs. In guest: source /run/user/1000/cybervm/secrets.env"
}

secrets_wipe() {
  local vm; vm="$(_vmname_s "${1:?vm}")"
  VBoxManage guestcontrol "$vm" --username "$CYBERVM_VM_USER" --password "$CYBERVM_VM_PASS" \
    run --exe /bin/bash -- bash -c "shred -u /run/user/1000/cybervm/secrets.env 2>/dev/null; rm -rf /run/user/1000/cybervm" || true
  ok "Wiped secrets from $vm."
}
