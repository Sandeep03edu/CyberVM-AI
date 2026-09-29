# Phase 3 — Golden build (Ansible provisioning)

**Goal:** turn Base into a fully-tooled `CyberVM-Kali-Golden` snapshot, reproducibly.

## Before you run
- Fill any `TODO`s you care about in `config/tools/*.yml` and `config/burp/extensions.lock.yml`
  (URLs + sha256 for Burp extensions). Empty entries are simply skipped, so you *can* run without them.
- The golden build needs internet (it boots the VM on NAT to `apt install`), and so do the
  Burp pins: every build/verify begins with a **pins preflight** that checks the BApp serial
  numbers in `config/burp/extensions.lock.yml` against the live PortSwigger store. If any have
  drifted, the build aborts before the VM even boots — fix with `./cybervm pins refresh burp`.

## 3.1 Build
```
$ ./cybervm golden build
```
It verifies the Burp pins → clones Base → boots on NAT → runs `ansible-playbook playbooks/golden.yml`:
- **common:** upgrade, git/python/node, base utils
- **hardening:** ufw default-deny inbound (ssh only on AI plane), disable extra services
- **security_tools:** Kali metapackages + the tool list from `config/tools/apt.yml` (+ pip/github/binaries)
- **burp:** Burp + Jython + pinned BApps + auto-load config
- **ai_clients:** opencode, claude-code, codex + a profile.d hook
- **ai_guest:** installs a guest-side `cybervm` CLI (`ai run|list|pull|rm|opencode`) that talks to host Ollama over the AI plane, plus `mcp status|verify|update` for the baked MCP servers
- **rag_client:** creates the `~/.config/opencode`, `~/.codex` and `~/.config/cybervm` config dirs
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
- The resolved versions are recorded in **`/etc/cybervm/mcp.lock`** — that file, not the manifest, is the
  real reproducibility anchor, because `@playwright/mcp` pins a `playwright` version which pins an exact
  Chromium build.
- `bake` is a no-op when `/opt/ms-playwright/.cybervm-baked` already exists, so re-running the role on an
  existing golden does not re-download. To force a re-bake, run `/usr/local/bin/cybervm-mcp-install bake --force` inside the golden VM (or `cybervm mcp update` inside a clone). `golden build` itself takes no flags — it always re-provisions the existing golden in place.

### Refreshing a clone to the newest release
`config/mcp/servers.yml` uses `version: "latest"` (same convention as `config/ai/clients.yml`), so each
clone can pull a newer release on demand from inside the VM:
```
kali$ cybervm mcp status      # baked versions; diffs against the npm registry when reachable
kali$ cybervm mcp verify      # offline health check of the baked browser
kali$ cybervm mcp update      # refresh package + browser (skips OS deps); needs net nat|bridged
```
`update` is the only one that touches the network, and it fails with an explicit message when the VM has no
route (net mode `offline`/`airgap`) rather than hanging — the baked version keeps working in that case.
The `mcp_*` commands are on the guest `cybervm` CLI; there is no host-side equivalent.

## 3.2 Verify
```
$ ./cybervm golden verify
```
Runs Ansible in `--check` mode (expect no changes) and SSH smoke tests.
✅ **Pass gate:** you see `nmap` version, `opencode` version, `guest cybervm ai run OK`,
and `ollama reachable from guest`.
The snapshot name is saved to `.cybervm.golden-snap` (used by `cybervm new`).

## 3.3 Test the guest AI CLI from a fresh clone
The guest `cybervm` (at `/usr/local/bin/cybervm`) is a separate, much smaller binary from the host CLI:
```
$ ./cybervm new work-01            # a new clone is always offline; change it with --net at start
kali$ source /etc/profile.d/cybervm.sh
kali$ cybervm ai run "what does nmap -sV do?"        # streams from host Ollama
kali$ cybervm ai opencode "what does nmap -sV do?"   # opencode run ... --model ollama/qwen2.5:3b-instruct
```
✅ **Pass gate:** both answer with no internet — the reply came from host Ollama over the AI plane.

## 3.4 Test the baked Playwright MCP from a fresh clone
The browser is **headed by design** — the window is always visible so you can watch the agent work. It
therefore needs a GUI session, and it never silently falls back to headless.
```
$ ./cybervm new work-01
$ ./cybervm start work-01                    # NOT --headless: a headed browser needs an X display
kali$ cybervm mcp verify                     # offline: browser present + executable by kali
kali$ cybervm mcp status
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

## 3.5 Reset the golden (chain growth and disk)

Every `golden build` re-provisions the existing golden **in place**, and every provision ends by taking a
new snapshot. VirtualBox implements each snapshot as a *differencing disk* layered on the previous one, and
**nothing ever prunes them** — so the chain, and the golden's on-disk size, grows by roughly **1.3 GB per
build** without bound.

| | |
|---|---|
| Base (immutable parent) | ~15 GB, 1 snapshot — never grows |
| Golden, freshly built | ~24 GB — one snapshot, the floor |
| Golden, after N builds | ~24 GB + N × 1.3 GB |

Two ceilings eventually bite: **disk** (a build-a-day costs ~470 GB/year), and VirtualBox's **255
differencing-disk limit per chain**, which is reached in well under a year at that rate and makes
`golden build` start failing.

`golden reset` collapses the chain back to a single disk by destroying the golden and rebuilding it from
Base:

```
$ ./cybervm golden reset --dry-run      # show the plan, change nothing
$ ./cybervm golden reset
```
```
  DRY RUN - nothing will be changed
    golden       CyberVM-Kali-Golden
    snapshots    14
    disk now     39GB
    safety copy  no - recovery is 'cybervm golden build'
    after        1 snapshot, one fresh provision from base
    verify       ansible check-mode + SSH smoke tests
```

It refuses to run unless **no linked clone exists** — a clone pins the golden snapshot it was built from, and
VirtualBox will not delete a snapshot that has dependants, so the destroy would otherwise fail partway.
Destroy your clones first. It then deletes the golden, clears the now-dangling `.cybervm.golden-snap` (so a
failed rebuild reports the real cause instead of a confusing VBoxManage error), rebuilds from Base, and runs
`golden verify`. Add `--no-verify` to skip the tests.

### Why there is no safety copy by default

**Base is never touched**, so a failed reset is always recoverable:

```bash
./cybervm golden build      # Base is intact; this always works
```

A snapshot chain is a convenience, not a safety net. Exporting an `.ova` first only adds a way back to the
*old* state if the new build comes out broken — useful when you are changing the Ansible roles and need a
working VM immediately, but it costs ~39 GB and ~10 minutes you usually do not need. Hence opt-in:

```
$ ./cybervm golden reset --keep-ova
```
This exports a flattened `.ova` first, checks that there is room for it, and refuses rather than fill the
filesystem (in which case it tells you to drop the flag). After a successful reset it prints the exact
command to discard the copy once you trust the new build.

### Managing exported releases

```
$ ./cybervm release list                            # .ova files, sizes, dates
$ ./cybervm release rm CyberVM-Kali-2026.09.27.ova  # delete one + its .sha256/.manifest.json
$ ./cybervm release prune 2                         # keep only the 2 newest (export does this itself)
$ ./cybervm import <file.ova>                       # re-register an exported appliance
```

### When to run it

Roughly every few weeks, or whenever `./cybervm golden reset --dry-run` shows a deep chain. It is
maintenance, not a repair — run it on a build you have already verified, not in the middle of risky edits.
