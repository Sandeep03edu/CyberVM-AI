# lib/golden.sh — provision the golden image with Ansible over SSH.

golden_dispatch() { local sub="${1:-}"; shift || true
  case "$sub" in
    build)  golden_build "$@" ;;
    verify) golden_verify "$@" ;;
    reset)  golden_reset "$@" ;;
    *) die "usage: cyberai golden build|verify|reset [--keep-ova] [--dry-run] [--no-verify]" ;;
  esac; }

_golden_ip() { # boot golden, return an IP that actually accepts SSH (provisioning ready)
  local vm="$1" ip=""
  vm_running "$vm" || VBoxManage startvm "$vm" --type headless >/dev/null 2>&1
  # Re-poll the guest property each pass: it may hold a STALE IP from the previous
  # boot until guest additions republish on the current network.
  for _ in $(seq 1 90); do
    ip=$(vm_wait_ip "$vm" 1 2) || { sleep 2; continue; }
    ssh -i "$CYBERAI_SSH_KEY" -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=3 \
        -o ServerAliveInterval=5 -o ServerAliveCountMax=3 \
        "${CYBERAI_VM_USER}@$ip" true >/dev/null 2>&1 && { echo "$ip"; return 0; }
    sleep 2
  done
  return 1
}

_write_inventory() { # <ip>
  local inv="$CYBERAI_HOME/factory/ansible/inventory/golden.ini"
  cat > "$inv" <<INV
[golden]
$1 ansible_user=${CYBERAI_VM_USER} ansible_ssh_private_key_file=${CYBERAI_SSH_KEY} ansible_python_interpreter=/usr/bin/python3 ansible_ssh_common_args='-o StrictHostKeyChecking=no'
INV
  echo "$inv"
}

golden_build() {
  local base golden snap
  source "$CYBERAI_HOME/lib/pins.sh"
  if ! pins_dispatch check burp; then
    die "Burp extension pins are stale. Fix with: ./cyberai pins refresh burp"
  fi
  base="$(platform .vm_names.base)"; golden="$(platform .vm_names.golden)"
  vm_exists "$base" || die "Base image missing — run: cyberai base import"
  if vm_exists "$golden"; then warn "$golden exists; re-provisioning in place."; else
    log "Full-cloning $base -> $golden …"
    VBoxManage clonevm "$base" --snapshot "$(platform .snapshots.base)" \
      --options link --name "$golden" --register 2>/dev/null \
    || VBoxManage clonevm "$base" --name "$golden" --register
  fi
  # Give golden internet for provisioning (NAT) + AI plane (NIC2)
  require_off "$golden"
  source "$CYBERAI_HOME/lib/net.sh"; net_apply "$golden" nat
  # clipboard/DnD are host-side, clone-time-only settings. Converge them on EVERY
  # build — including re-provisioning an existing golden — so the snapshot we are
  # about to take has them baked in for every clone made from it.
  vm_apply_host_config "$golden"

  local ip; ip=$(_golden_ip "$golden") || die "No IP from golden VM."
  ok "Golden reachable at $ip"
  local inv; inv=$(_write_inventory "$ip")

  log "Running Ansible provisioning playbook…"
  ( cd "$CYBERAI_HOME/factory/ansible" && \
    ansible-galaxy collection install -r requirements.yml >/dev/null && \
    ansible-playbook -i "$inv" playbooks/golden.yml )

  log "Cleaning apt caches + shutting down…"
  ssh -i "$CYBERAI_SSH_KEY" -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=10 \
      -o ServerAliveInterval=5 -o ServerAliveCountMax=3 "${CYBERAI_VM_USER}@$ip" \
      "sudo apt-get clean && sudo rm -rf /var/lib/apt/lists/*" || true
  VBoxManage controlvm "$golden" acpipowerbutton; sleep 8
  for _ in $(seq 1 30); do vm_running "$golden" || break; sleep 2; done

  snap="$(platform .snapshots.golden)-$(date +%Y.%m.%d-%H%M%S)"
  snap_uuid="$(VBoxManage snapshot "$golden" take "$snap" --description "provisioned golden image" 2>&1 | sed -n 's/.*UUID: *\([0-9a-f-]\{36\}\).*/\1/p' | tail -1)"
  [ -n "$snap_uuid" ] || snap_uuid="$snap"
  echo "$snap_uuid" > "$CYBERAI_HOME/.cyberai.golden-snap"
  # host-side manifest
  cat > "$CYBERAI_IMAGES/golden/manifest.json" <<M
{ "snapshot": "$snap", "kali": "$(platform .kali.release)",
  "built": "$(date -Iseconds)", "git_sha": "$(git -C "$CYBERAI_HOME" rev-parse --short HEAD 2>/dev/null || echo n/a)" }
M
  ok "Golden built. Snapshot: $snap"
}

golden_verify() {
  local golden ip; golden="$(platform .vm_names.golden)"
  vm_exists "$golden" || die "No golden VM."
  source "$CYBERAI_HOME/lib/pins.sh"
  if ! pins_dispatch check burp; then
    die "Burp extension pins are stale. Fix with: ./cyberai pins refresh burp"
  fi
  ip=$(_golden_ip "$golden") || die "No IP."
  local inv; inv=$(_write_inventory "$ip")
  log "Ansible check-mode (expect: no changes)…"
  ( cd "$CYBERAI_HOME/factory/ansible" && ansible-playbook -i "$inv" playbooks/golden.yml --check ) || warn "check-mode reported changes."
  log "SSH smoke tests…"
  ssh -i "$CYBERAI_SSH_KEY" -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=10 \
      "${CYBERAI_VM_USER}@$ip" '
    set -e
    nmap --version | head -1
    ls ~/.BurpSuite/bapps 2>/dev/null && echo "burp bapps present" || echo "no bapps yet"
    command -v opencode && opencode --version || echo "opencode missing"
    /usr/local/bin/cyberai ai run "reply with exactly guest-ok" | grep -q guest-ok && echo "guest cyberai ai run OK" || echo "guest cyberai ai run FAILED"
    curl -fsm3 http://'"$CYBERAI_HOST_IP"':'"$CYBERAI_OLLAMA_PORT"'/api/tags >/dev/null && echo "ollama reachable from guest" || echo "ollama unreachable"
  '
  VBoxManage controlvm "$golden" acpipowerbutton 2>/dev/null || true
  ok "Verify complete."
}

# ── golden reset ────────────────────────────────────────────
# Every `golden build` re-provisions in place, which appends another differencing
# disk to the golden's chain. Nothing ever prunes it, so the chain - and the
# golden's on-disk size - grows by ~1.3GB per build without bound, and
# eventually hits VirtualBox's 255 differencing-disk ceiling and starts failing.
# Resetting destroys the chain and rebuilds from base, collapsing it back to a
# single delta.
#
# There is deliberately NO safety copy by default: base is never touched, so a
# failed reset is always recoverable with `./cyberai golden build`. Exporting an
# .ova only adds a way back to the *old* state if the new build comes out broken
# - useful, but 39GB and ~10min you usually do not need, hence --keep-ova.

_human_bytes() { numfmt --to=iec --suffix=B "$1" 2>/dev/null || echo "${1}B"; }

# On-disk cost of a VM folder, i.e. its differencing chain. du -sb is apparent
# size and the disks are sparse, so this is a deliberate over-estimate of both
# what a reset reclaims and what --keep-ova needs - never an under-estimate.
_golden_bytes() { local b; b="$(du -sb "$CYBERAI_IMAGES/$1" 2>/dev/null | cut -f1)"; echo "${b:-0}"; }

# NOTE: df here has no working -b, and cyberai runs under `set -euo pipefail`, so
# every one of these must degrade to a printable value rather than abort.
_host_free_bytes() { df -P -B1 "${CYBERAI_ROOT:-/}" 2>/dev/null | awk 'NR==2{print $4+0}'; }

# grep -c exits 1 on a zero count, which would abort under `set -e`.
_golden_snaps() { VBoxManage snapshot "$1" list 2>/dev/null | grep -c 'UUID:' || true; }

golden_reset() {
  local keep_ova=0 dry=0 no_verify=0
  while [ $# -gt 0 ]; do case "$1" in
    --keep-ova)  keep_ova=1; shift ;;
    --dry-run)   dry=1; shift ;;
    --no-verify) no_verify=1; shift ;;
    *) die "unknown option for 'cyberai golden reset': $1 (valid: --keep-ova, --dry-run, --no-verify)" ;;
  esac; done

  local base golden; base="$(platform .vm_names.base)"; golden="$(platform .vm_names.golden)"
  source "$CYBERAI_HOME/lib/vm.sh"   # _cyberai_vms / _vm_unregister

  vm_exists "$base"   || die "Base image missing - nothing to rebuild from. Run: cyberai base import"
  vm_exists "$golden" || die "no golden VM to reset. Just run: cyberai golden build"
  require_off "$golden"

  # A linked clone pins the golden snapshot it descends from, and VirtualBox
  # refuses to delete a snapshot that has dependants - so the destroy below would
  # fail partway through, after the confirmation was already given. Refuse now.
  local clones; clones="$(_cyberai_vms | while read -r n; do
      [ -n "$n" ] || continue
      [ "$n" = "$base" ] || [ "$n" = "$golden" ] || echo "$n"
    done | tr '\n' ' ')"
  [ -z "$clones" ] || die "linked clones exist: $clones
A clone pins the golden snapshot it was built from, and VirtualBox will not delete
a snapshot that has dependants. Destroy them first:
  cyberai destroy <name>"

  local before snaps; before="$(_golden_bytes "$golden")"; snaps="$(_golden_snaps "$golden")"

  if [ "$keep_ova" = 1 ]; then
    # The export flattens the chain, so it costs roughly what the chain costs on
    # disk now. Measure rather than guess, and refuse rather than fill the disk.
    source "$CYBERAI_HOME/lib/release.sh"   # release_export / RELEASE_LAST_OVA
    local free need; free="$(_host_free_bytes)"; need=$((before + 1073741824))
    case "$free" in ''|*[!0-9]*) die "could not read free space on $CYBERAI_ROOT - aborting rather than risk filling the disk." ;; esac
    [ "$free" -ge "$need" ] || die "not enough free space to export a safety copy.
  need : $(_human_bytes "$need")  (chain $(_human_bytes "$before") + 1GB margin)
  have : $(_human_bytes "$free")
Skip the copy and reset anyway (recoverable via 'cyberai golden build'):
  ./cyberai golden reset"
  fi

  if [ "$dry" = 1 ]; then
    log "DRY RUN - nothing will be changed"
    printf '  %-12s %s\n' golden "$golden" "snapshots" "$snaps" \
      "disk now" "$(_human_bytes "$before")" \
      "safety copy" "$([ "$keep_ova" = 1 ] && echo "yes (~$(_human_bytes "$before") free needed)" || echo "no - recovery is 'cyberai golden build'")" \
      "after" "1 snapshot, one fresh provision from base" \
      "verify" "$([ "$no_verify" = 1 ] && echo "skipped (--no-verify)" || echo "ansible check-mode + SSH smoke tests")"
    return 0
  fi

  warn "This permanently deletes $golden and its $snaps-snapshot chain ($(_human_bytes "$before"))."
  warn "Base ($base) is NOT touched, so this is always recoverable with: cyberai golden build"
  [ "$keep_ova" = 1 ] || warn "No safety copy. If the rebuild is broken, fix the build to get a working golden back."
  confirm "Reset $golden?" || die "aborted."

  local ova=""
  if [ "$keep_ova" = 1 ]; then
    log "Exporting a safety copy first (large; be patient)…"
    RELEASE_LAST_OVA=""
    release_export          # dies (leaving golden untouched) if the export fails
    [ -n "$RELEASE_LAST_OVA" ] || die "export finished without reporting an output path - aborting before the destroy"
    ova="$RELEASE_LAST_OVA"
    ok "Safety copy: $ova"
  fi

  log "Deleting $golden…"
  _vm_unregister "$golden"
  # The snapshot pointer is now dangling. Clearing it means a failed rebuild makes
  # `cyberai new` say "no golden snapshot - run cyberai golden build" instead of
  # failing deep inside VBoxManage with an unknown-snapshot error.
  rm -f "$CYBERAI_HOME/.cyberai.golden-snap"
  [ -d "$CYBERAI_IMAGES/$golden" ] \
    && die "unregister reported success but $CYBERAI_IMAGES/$golden still exists - inspect it before rebuilding"
  ok "Deleted. Free space now: $(_human_bytes "$(_host_free_bytes)")"

  # Print recovery guidance BEFORE building: golden_build calls die on failure,
  # which exits immediately and would otherwise leave the user with no next step.
  log "Rebuilding golden from $base (full Ansible provision)…"
  warn "If this fails, recover with:  ./cyberai golden build"
  [ -n "$ova" ] && warn "  or restore the safety copy:  ./cyberai release import $ova"
  golden_build

  if [ "$no_verify" = 1 ]; then
    warn "Skipped verification (--no-verify). The new golden is UNTESTED."
  else
    log "Verifying the new golden…"
    golden_verify
  fi

  local after; after="$(_golden_bytes "$golden")"
  echo
  ok "Golden reset complete."
  printf '  %-12s %s -> %s\n' "snapshots" "$snaps" "$(_golden_snaps "$golden")" \
    "disk" "$(_human_bytes "$before")" "$(_human_bytes "$after")" \
    "reclaimed" "$(echo "$((before - after))")" "$(_human_bytes $((before - after)))"
  if [ -n "$ova" ]; then
    echo
    warn "Safety copy kept: $ova  ($(du -h "$ova" 2>/dev/null | cut -f1))"
    echo "  Once you trust this build it is dead weight. Free it with:"
    echo "    ./cyberai release rm $(basename "$ova")"
  fi
}
