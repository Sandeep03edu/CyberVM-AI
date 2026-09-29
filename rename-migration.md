# Rename migration: CyberAI → CyberVM-AI

## Context
The old name **CyberAI** read like "a proxy over an AI layer" and hid that this is fundamentally a
**VM lab** (golden Kali image + disposable clones) that *uses* AI. Renamed to **CyberVM-AI** so the
name states both halves: a **VM** platform, **AI**-assisted.

- New name: **CyberVM-AI** · CLI slug **`cybervm`** · env prefix **`CYBERVM_`**
- Strategy: **clean rebuild** — rename all code, then regenerate every host/guest artifact under the
  new name and re-clone the disposable VMs (no in-place VM surgery).

## Naming map
Four ordered, case-sensitive substitutions cover the entire surface (every compound name is a
superset of one root):

| Old | New |
|---|---|
| `CyberAIKaliVM` | `CyberVM-AI` (repo folder — run first) |
| `CYBERAI` | `CYBERVM` (env vars `CYBERAI_*`) |
| `CyberAI` | `CyberVM` (display, VM names, `.ova`) |
| `cyberai` | `cybervm` (CLI, dotfiles, `~/.config`, `/etc`, docker, network) |

Concrete results: `./cyberai`→`./cybervm`; guest `/usr/local/bin/cyberai`→`/usr/local/bin/cybervm`;
VMs `CyberVM-Kali-Base` / `CyberVM-Kali-Golden`; dotfiles `.cybervm.*`; state dirs
`~/.config/cybervm/` + guest `/etc/cybervm/`, `/etc/profile.d/cybervm.sh`; docker `cybervm-rag`;
host-only network `cybervm`; systemd drop-in `cybervm-llm-tune.conf`.

## Phase A — code & config rename  ✅ DONE (branch `rename/cybervm-ai`)
- File renames: `cyberai`→`cybervm`, `.cyberai.env.example`→`.cybervm.env.example`,
  `factory/ansible/roles/ai_guest/templates/cyberai-guest.sh.j2`→`cybervm-guest.sh.j2`.
- Content: the four substitutions applied across all 59 tracked text files. `git grep -Ii cyberai` → 0.
- Hand-polish: README H1 → `# CyberVM-AI Kali Platform`; `CYBERVM_ROOT="$HOME/Personal/CyberVM-AI"`.
- `.gitignore` patterns now `.cybervm.*`.

## Phase B — preserve API keys  ✅ DONE (or skipped if absent)
- `~/.config/cyberai/secrets.env` → `~/.config/cybervm/secrets.env` (only non-name-coupled state worth keeping).
- Old SSH key is NOT reused; host-setup regenerates `~/.config/cybervm/id_ed25519`.

## Phase C — teardown old artifacts, then rebuild (run manually — see chat for exact commands)
1. Copy out anything wanted from existing clones FIRST (`./cyberai transfer out <vm> <file>` on old checkout).
2. Rename the working folder: `mv ~/Personal/CyberAIKaliVM ~/Personal/CyberVM-AI`; create `.cybervm.env` from the example.
3. Delete old VMs (clones, `CyberAI-Kali-Golden`+snapshot, `CyberAI-Kali-Base`), old host-only net `cyberai`,
   systemd drop-in `cyberai-llm-tune.conf`, docker RAG stack, `~/.config/cyberai`, stale `.cyberai.*` dotfiles.
4. Rebuild in order: `host-setup` → `base import` → `golden build` → `rag up` + `rag update stable`
   → (optional) `ai tune` → `new <name>`.

## Verification
- `grep -rIi cyberai . --exclude-dir=.git` → nothing (except this file).
- `./cybervm doctor` PASS; `./cybervm list` shows `CyberVM-Kali-*`.
- `VBoxManage list vms` has no `CyberAI-*`; host-only net + docker show `cybervm` resources only.
- In a clone: `cybervm ai run "hi"`, `cybervm mcp status`, `cat /etc/cybervm/manifest.json`.

## Notes
- Clean rebuild **discards existing clone contents** — disposable by design; transfer out keepsakes first.
- Full env-var prefix renamed (`CYBERAI_*`→`CYBERVM_*`) — deliberate clean break, no legacy alias kept.
- Alternative (not used): in-place migration script (`VBoxManage modifyvm --name`, move `~/.config`,
  rewrite unit/docker names) preserves the current golden image without a rebuild.
