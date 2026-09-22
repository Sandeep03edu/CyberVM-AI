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
- **ai_guest:** installs a guest-side `cyberai` CLI (`ai run|list|pull|rm|opencode`) that talks to host Ollama over the AI plane
- **rag_client:** writes OpenCode/Codex/Claude MCP configs pointing at the host
Then it cleans apt, powers off, and snapshots `golden-<date>`.

## 3.2 Verify
```
$ ./cyberai golden verify
```
Runs Ansible in `--check` mode (expect no changes) and SSH smoke tests.
✅ **Pass gate:** you see `nmap` version, `opencode` version, `guest cyberai ai run OK`,
and `ollama reachable from guest`.
The snapshot name is saved to `.cyberai.golden-snap` (used by `cyberai new`).

## 3.3 Test the guest AI CLI from a fresh clone
The guest `cyberai` (at `/usr/local/bin/cyberai`) is a separate, much smaller binary from the host CLI:
```
$ ./cyberai new work-01 --net offline
kali$ source /etc/profile.d/cyberai.sh
kali$ cyberai ai run "what does nmap -sV do?"        # streams from host Ollama
kali$ cyberai ai opencode "what does nmap -sV do?"   # opencode run ... --model ollama/qwen2.5:3b-instruct
```
✅ **Pass gate:** both answer with no internet — the reply came from host Ollama over the AI plane.
