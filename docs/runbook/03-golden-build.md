# Phase 3 — Golden build (Ansible provisioning)

**Goal:** turn Base into a fully-tooled `CyberAI-Kali-Golden` snapshot, reproducibly.

## Before you run
- Fill any `TODO`s you care about in `config/tools/*.yml` and `config/burp/extensions.lock.yml`
  (URLs + sha256 for Burp extensions). Empty entries are simply skipped, so you *can* run without them.
- The golden build needs internet (it boots the VM on NAT to `apt install`).

## 3.1 Build
```
$ ./cyberai golden build
```
It clones Base → boots on NAT → runs `ansible-playbook playbooks/golden.yml`:
- **common:** upgrade, git/python/node, base utils
- **hardening:** ufw default-deny inbound (ssh only on AI plane), disable extra services
- **security_tools:** Kali metapackages + the tool list from `config/tools/apt.yml` (+ pip/github/binaries)
- **burp:** Burp + Jython + pinned BApps + auto-load config
- **ai_clients:** opencode, claude-code, codex + a profile.d hook
- **rag_client:** writes OpenCode/Codex/Claude MCP configs pointing at the host
Then it cleans apt, powers off, and snapshots `golden-<date>`.

## 3.2 Verify
```
$ ./cyberai golden verify
```
Runs Ansible in `--check` mode (expect no changes) and SSH smoke tests.
✅ **Pass gate:** you see `nmap` version, `opencode` version, and `ollama reachable from guest`.
The snapshot name is saved to `.cyberai.golden-snap` (used by `cyberai new`).
