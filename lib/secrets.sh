# lib/secrets.sh — push named cloud API keys into a VM's tmpfs (never into images).
# Also pushes the host's live Claude Code subscription session ('claude-session') via
# the same tmpfs-only mechanism, but at the real path Claude Code auto-reads — see
# secrets_push's claude-session branch below for why that needs different handling.
#
# Transport: plain SSH/SCP over the AI-plane IP (same primitives as lib/transfer.sh),
# NOT `VBoxManage guestcontrol`. guestcontrol's `run --exe /bin/bash` is broken by a
# Guest Additions/host VirtualBox version mismatch on this fleet ("cannot execute binary
# file" even though /bin/bash is a perfectly valid binary over plain SSH) — SSH sidesteps
# it entirely. Unlike transfer.sh, this never stages through /tmp: Debian/Kali's /tmp is
# disk-backed, not tmpfs, so landing a secret there even briefly before moving it would
# touch persistent disk (and a cross-filesystem mv is copy+unlink, not a rename — a plain
# rm afterward doesn't securely erase the original on-disk bytes). Every secret is scp'd
# directly into its final /run/user/1000/... (tmpfs) destination instead.

secrets_dispatch() { local sub="${1:?push|wipe}"; shift || true
  case "$sub" in push) secrets_push "$@";; wipe) secrets_wipe "$@";; *) die "usage: cybervm secrets push|wipe <vm> [names..]";; esac; }

_vmname_s() { local n="$1"; vm_exists "$(platform .vm_names.clone_prefix)$n" && echo "$(platform .vm_names.clone_prefix)$n" || echo "$n"; }

# _secrets_ip <vm> — resolve the running clone's AI-plane IP (same call shape as transfer.sh).
_secrets_ip() { vm_wait_ip "$1" 1 120; }

_secrets_ssh() { # _secrets_ssh <ip> <command...>
  local ip="$1"; shift
  command ssh -i "$CYBERVM_SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o BatchMode=yes -o ConnectTimeout=10 "${CYBERVM_VM_USER}@$ip" "$@"
}

_secrets_scp() { # _secrets_scp <local-file> <ip> <remote-path> — writes DIRECTLY to <remote-path>, no /tmp hop
  local file="$1" ip="$2" dest="$3"
  command scp -i "$CYBERVM_SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o BatchMode=yes -o ConnectTimeout=10 "$file" "${CYBERVM_VM_USER}@$ip:$dest"
}

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
    local ip; ip=$(_secrets_ip "$vm") || { warn "No AI-plane IP yet for $vm; retry shortly."; return 1; }
    declare -A M=( [anthropic]=ANTHROPIC_API_KEY [openai]=OPENAI_API_KEY [deepseek]=DEEPSEEK_API_KEY [openrouter]=OPENROUTER_API_KEY )
    local tmp; tmp=$(mktemp)
    # shellcheck disable=SC1090
    # Trailing `true`: without it, a requested name with no configured value makes the
    # loop's last `&&` chain evaluate false, which becomes the SUBSHELL's own exit status
    # under the inherited `set -e` — silently killing the whole script with no error
    # message (confirmed live: pushing `anthropic` with no ANTHROPIC_APIKEY set in
    # $CYBERVM_SECRETS died here, pre-existing in the original code this was copied from).
    ( set -a; source "$CYBERVM_SECRETS"; set +a
      for n in "${other_names[@]}"; do local var="${M[$n]:-}"; [ -n "$var" ] && [ -n "${!var:-}" ] && echo "export $var=${!var}"; done
      true ) > "$tmp"
    _secrets_ssh "$ip" "mkdir -p /run/user/1000/cybervm && chmod 700 /run/user/1000/cybervm" \
      || { rm -f "$tmp"; die "guest-side setup failed for $vm"; }
    _secrets_scp "$tmp" "$ip" "/run/user/1000/cybervm/secrets.env" \
      || { rm -f "$tmp"; die "scp to $vm failed"; }
    rm -f "$tmp"
    _secrets_ssh "$ip" "chmod 600 /run/user/1000/cybervm/secrets.env" \
      || die "could not chmod secrets.env on $vm"
    ok "Pushed keys to $vm tmpfs. In guest: source /run/user/1000/cybervm/secrets.env"
  fi
}

# _secrets_push_claude_session <vm> — copy the HOST's live Claude Code OAuth session
# (~/.claude/.credentials.json, a personal subscription login, not an API key) directly
# into the guest's tmpfs, then symlink the guest's ~/.claude/.credentials.json to it.
# Claude Code reads (and, on token refresh, rewrites) that exact path automatically on
# every run, so this needs zero guest-side action — unlike secrets.env, which needs a
# manual `source`. Kept tmpfs-only on purpose: a reboot clears /run/user/1000, the
# symlink goes dangling, and the VM silently reverts to "not logged in" — the same
# ephemerality guarantee the generic API-key push already has, applied to a much more
# sensitive credential. The secret is scp'd directly to its tmpfs destination — it is
# NEVER written to any path on the guest's persistent disk, not even transiently.
_secrets_push_claude_session() {
  local vm="$1" host_cred="$HOME/.claude/.credentials.json" ip
  [ -f "$host_cred" ] || die "not logged into Claude Code on the HOST (missing $host_cred) — run 'claude login' on the host first."
  warn "This copies your real Claude subscription session (not a bounded API key) into $vm's tmpfs."
  warn "If this VM is later used against an untrusted/hostile target, that session is part of its blast radius."
  confirm "Push the live Claude session into $vm?" || die "aborted."
  ip=$(_secrets_ip "$vm") || { warn "No AI-plane IP yet for $vm; retry shortly."; return 1; }
  _secrets_ssh "$ip" "mkdir -p /run/user/1000/cybervm/claude-session && chmod 700 /run/user/1000/cybervm/claude-session" \
    || die "guest-side setup failed for $vm"
  _secrets_scp "$host_cred" "$ip" "/run/user/1000/cybervm/claude-session/.credentials.json" \
    || die "scp to $vm failed"
  _secrets_ssh "$ip" "chmod 600 /run/user/1000/cybervm/claude-session/.credentials.json && mkdir -p \$HOME/.claude && ln -sfn /run/user/1000/cybervm/claude-session/.credentials.json \$HOME/.claude/.credentials.json" \
    || die "could not finish guest-side setup on $vm"
  ok "Pushed Claude session to $vm (tmpfs-backed symlink). 'claude' in the guest is already logged in."
  warn "This does NOT survive a reboot (tmpfs clears) and must never be baked into golden/snapshots/.ova — re-push after every restart, and run 'cybervm secrets wipe $vm' when you're done with this VM."
  warn "An ONLINE snapshot (cybervm snapshot, taken while running) captures RAM and would include this session — wipe before taking one."
}

secrets_wipe() {
  local vm ip; vm="$(_vmname_s "${1:?vm}")"
  ip=$(_secrets_ip "$vm") || { warn "No AI-plane IP for $vm; nothing to wipe over the network (tmpfs clears on its own if the VM isn't running)."; return 0; }
  _secrets_ssh "$ip" "shred -u /run/user/1000/cybervm/secrets.env 2>/dev/null; shred -u /run/user/1000/cybervm/claude-session/.credentials.json 2>/dev/null; rm -rf /run/user/1000/cybervm" || true
  ok "Wiped secrets (including any pushed Claude session) from $vm."
}
