# lib/secrets.sh — push named cloud API keys into a VM's tmpfs (never into images).
# Also pushes the host's live Claude Code subscription session ('claude-session') via
# the same tmpfs-only mechanism, but at the real path Claude Code auto-reads — see
# secrets_push's claude-session branch below for why that needs different handling.

secrets_dispatch() { local sub="${1:?push|wipe}"; shift || true
  case "$sub" in push) secrets_push "$@";; wipe) secrets_wipe "$@";; *) die "usage: cybervm secrets push|wipe <vm> [names..]";; esac; }

_vmname_s() { local n="$1"; vm_exists "$(platform .vm_names.clone_prefix)$n" && echo "$(platform .vm_names.clone_prefix)$n" || echo "$n"; }

secrets_push() {
  local vm; vm="$(_vmname_s "${1:?vm}")"; shift || true
  vm_running "$vm" || die "start $vm first."
  local names=("$@"); [ ${#names[@]} -eq 0 ] && names=(anthropic openai deepseek openrouter)

  # claude-session is handled entirely separately from the generic env-var keys below:
  # it is a live personal OAuth session (access+refresh token), not a bounded API key,
  # so it never goes through $CYBERVM_SECRETS and is never required to push the others.
  local want_claude_session=0 other_names=()
  for n in "${names[@]}"; do
    if [ "$n" = "claude-session" ]; then want_claude_session=1; else other_names+=("$n"); fi
  done

  if [ "$want_claude_session" = 1 ]; then
    _secrets_push_claude_session "$vm"
  fi

  if [ ${#other_names[@]} -gt 0 ]; then
    [ -f "$CYBERVM_SECRETS" ] || die "no secrets file: $CYBERVM_SECRETS"
    declare -A M=( [anthropic]=ANTHROPIC_API_KEY [openai]=OPENAI_API_KEY [deepseek]=DEEPSEEK_API_KEY [openrouter]=OPENROUTER_API_KEY )
    local tmp; tmp=$(mktemp)
    # shellcheck disable=SC1090
    ( set -a; source "$CYBERVM_SECRETS"; set +a
      for n in "${other_names[@]}"; do local var="${M[$n]:-}"; [ -n "$var" ] && [ -n "${!var:-}" ] && echo "export $var=${!var}"; done ) > "$tmp"
    local gc="VBoxManage guestcontrol $vm --username $CYBERVM_VM_USER --password $CYBERVM_VM_PASS"
    $gc run --exe /bin/bash -- bash -c "mkdir -p /run/user/1000/cybervm && chmod 700 /run/user/1000/cybervm"
    $gc copyto --target-directory /run/user/1000/cybervm "$tmp"
    $gc run --exe /bin/bash -- bash -c "mv /run/user/1000/cybervm/$(basename "$tmp") /run/user/1000/cybervm/secrets.env && chmod 600 /run/user/1000/cybervm/secrets.env"
    rm -f "$tmp"
    ok "Pushed keys to $vm tmpfs. In guest: source /run/user/1000/cybervm/secrets.env"
  fi
}

# _secrets_push_claude_session <vm> — copy the HOST's live Claude Code OAuth session
# (~/.claude/.credentials.json, a personal subscription login, not an API key) into the
# guest's tmpfs, then symlink the guest's ~/.claude/.credentials.json to it. Claude Code
# reads (and, on token refresh, rewrites) that exact path automatically on every run, so
# this needs zero guest-side action — unlike secrets.env, which needs a manual `source`.
# Kept tmpfs-only on purpose: a reboot clears /run/user/1000, the symlink goes dangling,
# and the VM silently reverts to "not logged in" — the same ephemerality guarantee the
# generic API-key push already has, applied to a much more sensitive credential.
_secrets_push_claude_session() {
  local vm="$1" host_cred="$HOME/.claude/.credentials.json"
  [ -f "$host_cred" ] || die "not logged into Claude Code on the HOST (missing $host_cred) — run 'claude login' on the host first."
  warn "This copies your real Claude subscription session (not a bounded API key) into $vm's tmpfs."
  warn "If this VM is later used against an untrusted/hostile target, that session is part of its blast radius."
  confirm "Push the live Claude session into $vm?" || die "aborted."
  local gc="VBoxManage guestcontrol $vm --username $CYBERVM_VM_USER --password $CYBERVM_VM_PASS"
  $gc run --exe /bin/bash -- bash -c "mkdir -p /run/user/1000/cybervm/claude-session && chmod 700 /run/user/1000/cybervm/claude-session"
  $gc copyto --target-directory /run/user/1000/cybervm/claude-session "$host_cred"
  $gc run --exe /bin/bash -- bash -c "chmod 600 /run/user/1000/cybervm/claude-session/.credentials.json && mkdir -p \$HOME/.claude && ln -sfn /run/user/1000/cybervm/claude-session/.credentials.json \$HOME/.claude/.credentials.json"
  ok "Pushed Claude session to $vm (tmpfs-backed symlink). 'claude' in the guest is already logged in."
  warn "This does NOT survive a reboot (tmpfs clears) and must never be baked into golden/snapshots/.ova — re-push after every restart, and run 'cybervm secrets wipe $vm' when you're done with this VM."
}

secrets_wipe() {
  local vm; vm="$(_vmname_s "${1:?vm}")"
  VBoxManage guestcontrol "$vm" --username "$CYBERVM_VM_USER" --password "$CYBERVM_VM_PASS" \
    run --exe /bin/bash -- bash -c "shred -u /run/user/1000/cybervm/secrets.env 2>/dev/null; shred -u /run/user/1000/cybervm/claude-session/.credentials.json 2>/dev/null; rm -rf /run/user/1000/cybervm" || true
  ok "Wiped secrets (including any pushed Claude session) from $vm."
}
