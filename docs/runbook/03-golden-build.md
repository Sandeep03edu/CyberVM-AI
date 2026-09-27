# Phase 3 — Golden build (Ansible provisioning)

**Goal:** turn Base into a fully-tooled `CyberAI-Kali-Golden` snapshot, reproducibly.

## Before you run
- Fill any `TODO`s you care about in `config/tools/*.yml` and `config/burp/extensions.lock.yml`
  (URLs + sha256 for Burp extensions). Empty entries are simply skipped, so you *can* run without them.
- The golden build needs internet (it boots the VM on NAT to `apt install`), and so do the
  Burp pins: every build/verify begins with a **pins preflight** that checks the BApp serial
  numbers in `config/burp/extensions.lock.yml` against the live PortSwigger store. If any have
  drifted, the build aborts before the VM even boots — fix with `./cyberai pins refresh burp`.

## 3.1 Build
```
$ ./cyberai golden build
```
It verifies the Burp pins → clones Base → boots on NAT → runs `ansible-playbook playbooks/golden.yml`:
- **common:** upgrade, git/python/node, base utils
- **hardening:** ufw default-deny inbound (ssh only on AI plane), disable extra services
- **security_tools:** Kali metapackages + the tool list from `config/tools/apt.yml` (+ pip/github/binaries)
- **burp:** Burp + Jython + pinned BApps + auto-load config
- **ai_clients:** opencode, claude-code, codex + a profile.d hook
- **ai_guest:** installs a guest-side `cyberai` CLI (`ai run|list|pull|rm|opencode`) that talks to host Ollama over the AI plane, plus `mcp status|verify|update` for the baked MCP servers
- **rag_client:** creates the `~/.config/opencode`, `~/.codex` and `~/.config/cyberai` config dirs
- **disable_sleep:** masks the sleep/power targets and installs a per-user idle power-off so the VM stays awake
- **mcp_servers:** reads `config/mcp/servers.yml`, bakes the **Playwright MCP** into the image, and writes
  all three client configs
Then it cleans apt, powers off, and snapshots `golden-<date>`.

### What `mcp_servers` bakes in
- `@playwright/mcp` installed globally via npm, and Chromium installed to **`/opt/ms-playwright`** with its
  OS shared libraries. Expect the golden disk to grow by roughly **500–700 MB** (Chromium ~280 MB plus the
  GTK/NSS/X11 libraries; the separate headless-shell build is skipped because this MCP is headed-only).
- Every linked clone inherits that browser through copy-on-write at ~zero marginal cost, so a clone created
  with the default `--net offline` can still drive a real browser.
- Two details that are easy to get wrong and are handled for you: the npm install runs with
  `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1` (otherwise the `playwright` postinstall pulls a second copy of the
  browser into `/root/.cache`, unreadable by `kali`), and the launcher sets the *same*
  `PLAYWRIGHT_BROWSERS_PATH` used at install time (a mismatch is the classic
  `Executable doesn't exist at ...` failure).
- The resolved versions are recorded in **`/etc/cyberai/mcp.lock`** — that file, not the manifest, is the
  real reproducibility anchor, because `@playwright/mcp` pins a `playwright` version which pins an exact
  Chromium build.
- `bake` is a no-op when `/opt/ms-playwright/.cyberai-baked` already exists, so re-running the role on an
  existing golden does not re-download. To force a re-bake, run `/usr/local/bin/cyberai-mcp-install bake --force` inside the golden VM (or `cyberai mcp update` inside a clone). `golden build` itself takes no flags — it always re-provisions the existing golden in place.

### Refreshing a clone to the newest release
`config/mcp/servers.yml` uses `version: "latest"` (same convention as `config/ai/clients.yml`), so each
clone can pull a newer release on demand from inside the VM:
```
kali$ cyberai mcp status      # baked versions; diffs against the npm registry when reachable
kali$ cyberai mcp verify      # offline health check of the baked browser
kali$ cyberai mcp update      # refresh package + browser (skips OS deps); needs net nat|bridged
```
`update` is the only one that touches the network, and it fails with an explicit message when the VM has no
route (net mode `offline`/`airgap`) rather than hanging — the baked version keeps working in that case.
The `mcp_*` commands are on the guest `cyberai` CLI; there is no host-side equivalent.

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
$ ./cyberai new work-01            # a new clone is always offline; change it with --net at start
kali$ source /etc/profile.d/cyberai.sh
kali$ cyberai ai run "what does nmap -sV do?"        # streams from host Ollama
kali$ cyberai ai opencode "what does nmap -sV do?"   # opencode run ... --model ollama/qwen2.5:3b-instruct
```
✅ **Pass gate:** both answer with no internet — the reply came from host Ollama over the AI plane.

## 3.4 Test the baked Playwright MCP from a fresh clone
The browser is **headed by design** — the window is always visible so you can watch the agent work. It
therefore needs a GUI session, and it never silently falls back to headless.
```
$ ./cyberai new work-01
$ ./cyberai start work-01                    # NOT --headless: a headed browser needs an X display
kali$ cyberai mcp verify                     # offline: browser present + executable by kali
kali$ cyberai mcp status
```
Then from any of the three clients, ask it to visit a page and report the title:
```
kali$ opencode run "open example.com and tell me the page title"
kali$ claude  "open example.com and tell me the page title"
kali$ codex   "open example.com and tell me the page title"
```
✅ **Pass gate:** a Chromium window appears on the VM desktop, and `opencode mcp list` / `codex mcp list` /
`claude mcp list` each show a `playwright` server. Running two clients at once opens two windows without
any profile conflict (each server is registered with `--isolated`).

> **Claude Code needs a one-time approval.** A server added with `claude mcp add` shows as
> `⏸ Pending approval` until you approve it. Run `claude` once in the clone and accept the
> `playwright` prompt, or use `/mcp` inside a session. `opencode` and `codex` have no such step.
