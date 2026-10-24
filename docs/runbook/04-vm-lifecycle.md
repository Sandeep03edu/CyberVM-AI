# Phase 4 — Disposable VMs, network, transfer, secrets

**Goal:** prove the disposable-clone workflow and the sandbox boundary (ChatGPT "Milestone 1").

## 4.1 Create and use a clone
```
$ ./cybervm new work-01                    # linked clone (disk-cheap) + snapshot "clean"
$ ./cybervm start work-01 --net offline    # add --headless to skip the GUI
$ ./cybervm list
```

### Sizing: RAM and vCPU

Every clone starts at the `balanced` profile (12 GB / 6 vCPU). Pick a named
profile, or set sizes explicitly — the two are mutually exclusive:

```
$ ./cybervm new work-01 --profile lean      #  8 GB / 4 vCPU
$ ./cybervm new work-01 --profile balanced  # 12 GB / 6 vCPU  (default)
$ ./cybervm new work-01 --profile large     # 16 GB / 8 vCPU
$ ./cybervm new work-01 --ram 10 --cpus 5   # exact sizes
$ ./cybervm new work-01 --ram 10            # vCPU derived, 10 GB -> 5
```

`--ram` accepts `12` (GB), `12G`/`12g` or `12288M` (MB) and rounds *down* to
whole GB. Without `--cpus`, vCPU follows the same 1:2 rule the profiles use
(8 GB → 4, 12 GB → 6, 16 GB → 8), so `--ram 12` is exactly `balanced`.
`--profile` and `--ram`/`--cpus` cannot be combined. Profiles and the default
live in `config/platform.yml` under `resource_profiles` / `default_profile`.

Both sizes are checked against the host before the VM is created: RAM must be
2 GB–host RAM, vCPU 1–`nproc`.

### Changing size on an existing clone

```
$ ./cybervm stop work-01                     # required: the VM must be powered off
$ ./cybervm resize work-01 --ram 16          # 16 GB, vCPU derived -> 8
$ ./cybervm resize work-01 --cpus 4          # vCPU only; RAM is left alone
$ ./cybervm resize work-01 --ram 6 --cpus 2  # both explicitly
```

`resize` requires at least one of `--ram`/`--cpus` and refuses `--profile` —
it never silently re-reads a profile. Omitting one flag leaves that value at
the VM's current setting. RAM and vCPU are properties of the VM's own
`.vbox` file, so resizing a clone **never touches the golden image**; the
golden stays 2 GB / 2 vCPU. Disk capacity is not affected by `resize`.

`cybervm list` shows RAM and vCPU per VM, and `./cybervm doctor` reports how
much RAM running clones have claimed, so you can see why a second VM would
refuse to start.

## 4.2 Network modes (VM must be off to change)
```
$ ./cybervm stop work-01
$ ./cybervm net work-01 nat                # internet on; host loopback still blocked
$ ./cybervm net work-01 offline            # default: no internet, AI+RAG reachable
```
Modes: `offline` (default) · `airgap` (no net at all) · `nat` (internet) · `bridged` (asks for `yes`).

## 4.3 File transfer (SCP over the AI plane — no shared folder)
`transfer` moves files host↔guest over SSH (no staging copy, no vboxsf, no `transfer/` pollution).
The guest runs the shared SCP helper (`/usr/bin/scp` → openSSH); `/mnt` is a plain root-owned dir.
(This is about *ad-hoc file transfer*. The persistent realtime **skills** share in §4.4 is a separate,
deliberate read-only vboxsf mount and does not use this path.)

```
# host -> guest (default landing dir /mnt; optional 3rd arg = guest/dir):
$ ./cybervm transfer in work-01 ./README.md
  [ ok ] Copied ./README.md -> work-01:/mnt/README.md

# guest -> host (defaults to your current dir; optional 3rd arg = host/dest):
$ ./cybervm transfer out work-01 /mnt/abc.txt
  [ ok ] Copied work-01:/mnt/abc.txt -> /home/sandeep03edu-ubuntu/Personal/CyberVM-AI/abc.txt

$ ./cybervm transfer in  work-01 ./payload.txt            # -> /mnt/payload.txt
$ ./cybervm transfer in  work-01 ./payload.txt /tmp       # -> /tmp/payload.txt
$ ./cybervm transfer out work-01 /mnt/payload.txt          # -> ./payload.txt
$ ./cybervm transfer out work-01 /mnt/payload.txt /root    # -> /root/payload.txt
```
Notes:
- `in` writes via `sudo install` (root-owned `/mnt`); the guest has passwordless sudo for provisioning.
- `/mnt` is root-only — inside the guest use `sudo` to write there (e.g. `echo test | sudo tee /mnt/abc.txt`); the root-owned file is world-readable, so plain `kali` SCP can pull it back out.
- Same-name overrides normal SCP semantics: `out` to your cwd overwrites a local file of that name.
- Requires the VM to be running and Guest Additions to report its AI-plane IP.

## 4.4 AI skills share (realtime host→guest, read-only)
Your host `AgenticSkills` folder is shared into every clone so Claude Code and opencode inside the
guest use the exact same skills as the host — edit a skill on the host and the guest sees it
immediately, no copying. It is a VirtualBox `vboxsf` shared folder, **read-only** by default (a VM
that runs untrusted targets cannot modify your host skills).

Mechanism:
- Host folder: `CYBERVM_SKILLS_HOST` (`.cybervm.env`, default
  `$HOME/Personal/Agentic/AgenticSkills`).
- `golden build` bakes the guest symlinks `~/.claude/skills` and `~/.config/opencode/skills` →
  `/media/sf_AgenticSkills`, and adds user `kali` to the `vboxsf` group.
- `cybervm new` auto-attaches the share to each clone (recorded in its `clean` snapshot).

```
$ ./cybervm skills status                 # show the configured host folder / share name / RO flag
$ ./cybervm skills status work-01         # show whether a clone's share is attached + correct
$ ./cybervm skills attach work-01         # (re)attach to an existing clone (VM off), then restart
```

Inside the guest (after the clone boots with the share attached):
```
kali$ mount | grep vboxsf                 # AgenticSkills on /media/sf_AgenticSkills ...
kali$ ls ~/.claude/skills                 # same skills as the host, live
```
To make the share read-write instead (not recommended for a target-facing VM), set
`CYBERVM_SKILLS_READONLY="0"` in `.cybervm.env`, then `cybervm skills attach <name>` (VM off) and
restart.

## 4.5 Plugin-bundled MCP servers share (realtime host→guest, read-only)
Claude Code plugins are **not** auto-discovered from a shared folder the way skills are — a plugin
needs a registered local marketplace (`claude plugin marketplace add` + `claude plugin install`).
This share exists for a narrower, specific reason: a plugin's bundled MCP server can declare a
`command` that is a script living in the plugin's own folder (e.g. `rea-dast-plugin`'s
`playwright-attacker`/`playwright-victim`, which self-launch a proxied, CDP-attachable Chrome and
then attach `@playwright/mcp` to it). For that script to be *reachable* inside the guest at all,
the plugin's folder needs to be mounted — this share is how.

Mechanism:
- Host folder: `CYBERVM_PLUGINS_HOST` (`.cybervm.env`, default
  `$HOME/Personal/Agentic/AgenticPlugins`).
- `config/mcp/servers.yml` lists each bundled server with `bundled: true` and a `command` pointing
  at `/media/sf_AgenticPlugins/<plugin>/...`. That flag excludes the entry from the normal
  npm-package-bake and wrapper-file-templating steps (the script already exists, owned by the
  plugin) but still runs it through the existing `claude mcp add --scope user` loop and the
  `opencode.json` rendering — so both clients register it the same way they would any other local
  MCP server, with no plugin-specific Ansible code needed.
- `cybervm new` auto-attaches the share to each clone (recorded in its `clean` snapshot), same as
  the skills share.

```
$ ./cybervm plugins status                 # show the configured host folder / share name / RO flag
$ ./cybervm plugins status work-01         # show whether a clone's share is attached + correct
$ ./cybervm plugins attach work-01         # (re)attach to an existing clone (VM off), then restart
```

Inside the guest: `mount | grep vboxsf` should show both `AgenticSkills` and `AgenticPlugins`;
`claude mcp list` / the rendered `~/.config/opencode/opencode.json` should list the bundled servers.

## 4.6 Cloud keys (only when you want them)
```
$ ./cybervm start work-01 --net nat
$ ./cybervm secrets push work-01 anthropic     # key -> VM tmpfs only, never an image
# in guest: source /run/user/1000/cybervm/secrets.env
$ ./cybervm secrets wipe work-01
```

### Reusing your host Claude Code login (subscription, not an API key)
If you're logged into Claude Code on the host with a Pro/Max subscription, `secrets push <vm>
claude-session` avoids re-running the interactive OAuth login inside every fresh clone:

```
$ ./cybervm start work-01                      # any net mode; guestcontrol doesn't need network
$ ./cybervm secrets push work-01 claude-session
  [warn] This copies your real Claude subscription session (not a bounded API key)...
  Push the live Claude session into work-01? (type 'yes'):
# in guest: claude   — already logged in, no browser flow
$ ./cybervm secrets wipe work-01               # when done, or before sharing/exporting this VM
```

This is **deliberately never automatic** — it's not wired into `cybervm start`, so a VM you spin up
specifically to point at an untrusted target doesn't silently get your real login. Transport is
plain **SSH/SCP** over the AI-plane IP (the same mechanism `cybervm transfer` already uses) — the
host's `~/.claude/.credentials.json` (the OAuth access/refresh token) is `scp`'d **directly** into
the guest's tmpfs (`/run/user/1000/cybervm/claude-session/`, same destination as the API-key path
above) with no intermediate hop through `/tmp` (which is disk-backed on Kali, not tmpfs — landing a
secret there even briefly, then moving it, would touch persistent disk). The guest's
`~/.claude/.credentials.json` is made a **symlink** into that tmpfs file — Claude Code reads (and,
on token refresh, rewrites) that exact path automatically, so no `source` step is needed, unlike the
generic API-key push. Because the real bytes only ever live in tmpfs, never on persistent disk:
- a **reboot or poweroff** clears it automatically (`/run` is tmpfs — kernel-enforced, not an
  application step that could be skipped) — the symlink goes dangling and the VM reverts to "not
  logged in"; re-run `secrets push ... claude-session` after every restart, same as the API-key
  workflow already requires;
- it is **never** captured by `golden build` or a `.ova` export, and never captured by an
  **offline** snapshot (VM powered off) — the login can't accidentally become part of a persisted
  image this way.

**One caveat worth knowing**: an **online** snapshot (`cybervm snapshot <name> <tag>` taken while
the VM is *running*) captures full RAM state, which includes tmpfs — so it **would** capture a
currently-pushed session. Run `cybervm secrets wipe <vm>` before taking an online snapshot of a VM
with a live push, same as you'd do before sharing/exporting it.

If you ever push this to a VM and later need that VM to be fully clean before handing it off,
snapshotting it live, or exporting it, `secrets wipe` shreds the tmpfs file as part of its normal
cleanup — no separate step.

## 4.7 Verify — the isolation matrix
```
# disposability:
$ ./cybervm start work-01 --net offline
#   (in guest) touch ~/MARKER ; then stop + destroy:
$ ./cybervm destroy work-01
$ ./cybervm new work-02 && ./cybervm start work-02 --net offline
#   (in guest) ls ~/MARKER  -> should NOT exist
# network boundary (in an offline guest):
kali$ curl -m5 https://kali.org         # FAILS (no internet)
kali$ curl -s $OLLAMA_HOST/api/tags     # WORKS (AI plane)
kali$ nc -zv ${OLLAMA_HOST%:*} 22       # BLOCKED (ufw)
```
✅ **Pass gate:** marker absent in work-02; golden snapshot unchanged; offline curl fails, Ollama works, ssh-to-host blocked.
