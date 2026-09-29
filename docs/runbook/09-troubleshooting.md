# Phase 9 — Troubleshooting

**VirtualBox VM won't start / VERR_VMX_IN_VMX_ROOT_MODE**
KVM has grabbed VT-x. Run, then reboot:
```
$ echo 'options kvm enable_virt_at_load=0' | sudo tee /etc/modprobe.d/kvm-cybervm.conf
$ sudo update-initramfs -u
```

**`doctor` says Ollama reachable on loopback**
Tighten `OLLAMA_HOST` in `/etc/systemd/system/ollama.service` to `192.168.57.1:11434`, then
`sudo systemctl daemon-reload && sudo systemctl restart ollama`.

**Guest can't reach 192.168.57.1**
Check the clone has NIC2 host-only on the cybervm interface: `VBoxManage showvminfo <vm> | grep -i nic`.
Re-apply: `./cybervm net <vm> offline` (VM off).

**No IP from a VM (`vm_wait_ip` times out)**
Guest Additions may not be running yet. Wait longer, or open the GUI once to confirm it booted.

**Ansible SSH fails**
Confirm `ssh -i ~/.config/cybervm/id_ed25519 kali@<ip> true` works; the key was installed in Phase 2.

**ufw blocks Docker RAG port**
Docker publishes bypass ufw; we bind compose ports to `192.168.57.1` explicitly. Verify with
`ss -ltnp | grep 8088` — it should show `192.168.57.1:8088`, not `0.0.0.0`.

**Disk filling up**
Three usual causes, in the order worth checking:
1. **Golden snapshot chain.** Every `golden build` appends a differencing disk that is never pruned, so the
   golden grows ~1.3 GB per build forever. This is usually the biggest one — check it with
   `./cybervm golden reset --dry-run` and fix with `./cybervm golden reset`. See §3.5 of the golden-build
   runbook.
2. **Linked clones.** `./cybervm destroy <name>` for unused ones.
3. **OVA releases.** Keep only the last 2 (automatic on export); `./cybervm release list` shows them and
   `./cybervm release prune 2` trims.

`du -sh images/CyberVM-Kali-Golden` tells you which of these is biting.

**`golden reset` refuses: "linked clones exist"**
A clone pins the golden snapshot it was built from, and VirtualBox will not delete a snapshot that has
dependants — so the reset would fail partway through. Destroy the clones first (`./cybervm destroy <name>`).
The check runs before anything is deleted, so a refusal is always safe.

**`cybervm new` says "no golden snapshot" right after a reset**
The reset deletes `.cybervm.golden-snap` because it pointed at a snapshot that no longer exists. Finish the
build (`./cybervm golden build`) and it is rewritten.

**The golden is gone / missing after a failed `golden reset`**
Expected and always recoverable — the reset never touches Base:
```
$ ./cybervm golden build          # Base is intact, this always works
```
If you ran the reset with `--keep-ova` and want the old state back instead:
```
$ ./cybervm release import images/releases/CyberVM-Kali-<date>.ova
```

**`golden build` starts failing with a snapshot/differencing-disk error**
The chain has probably hit VirtualBox's 255 differencing-disk limit. `./cybervm golden reset` clears it.

---

## Playwright MCP (`mcp_servers` role)

**`Executable doesn't exist at /opt/ms-playwright/chromium-…/chrome-linux/chrome`**
The install-time and run-time browser paths disagree. The installer writes to `browsers_path` from
`config/mcp/servers.yml`; the launcher reads the same value, so this normally means the manifest changed after
the image was baked. Re-bake and re-create the clone:
```
./cybervm golden build          # re-provisions the existing golden in place
./cybervm destroy <name> && ./cybervm new <name>   # then re-create the clone
```
`golden build` takes no flags. To force only the browser re-bake, run
`/usr/local/bin/cybervm-mcp-install bake --force` inside the golden VM. Browsers are
inherited by clones copy-on-write, so a manifest change always needs a fresh clone
rather than a re-bake.
`cybervm mcp verify` prints the path it checked, which is the fastest way to confirm.

**`cybervm-playwright-mcp: no X display available`**
This MCP is **headed-only by design** — the browser window is always visible, so a headed Chromium needs an X
display. It fails loudly rather than silently falling back to headless, because a silent fallback would mean
you cannot see what the agent is doing. Fixes:
- Start the VM with a GUI session: `./cybervm start <vm>` (**not** `--headless`).
- Over plain SSH, forward X (`ssh -X`) or export `DISPLAY` and `XAUTHORITY` before launching the agent.
  The launcher auto-detects `/tmp/.X11-unix/X0` and falls back to `DISPLAY=:0`.

**`cybervm mcp update` fails with "no internet route from this VM"**
Expected in net mode `offline` or `airgap` — those modes set `--nic1 null`, so there is no route out. The
baked version still works offline; only `update` needs the network:
```
./cybervm net <vm> nat        # on the host, VM must be powered off
```
Then re-run `cybervm mcp update` in the guest.

**`claude mcp list` shows `playwright` as "Pending approval"**
Expected. Claude Code requires a one-time approval for MCP servers added via `claude mcp add`. Run `claude`
once in the clone and accept the prompt (or use `/mcp` inside a session). `opencode` and `codex` register
the same server with no approval step.

**The browser works but cannot reach any site**
The VM is on `offline`/`airgap`, so the browser launches and renders but has no internet NIC. Same fix as
above (`cybervm net <vm> nat`). MCP itself is fine; this is purely VM networking.

**Chromium fails to launch with a namespace / sandbox error**
Some hardened kernels refuse Chromium's sandbox. The wrapper does not pass `--no-sandbox` by default because
that is a real security downgrade. If you hit it, add the flag in `config/mcp/servers.yml` under
`args: ["--isolated", "--no-sandbox"]` and re-create the clone.

**Playwright deleted the baked browser**
Prevented by `PLAYWRIGHT_SKIP_BROWSER_GC=1`, which the launcher exports. If you ever see a browser build
disappear, that env var was lost — the launcher sets it on every start, so check that the wrapper at
`/usr/local/bin/cybervm-playwright-mcp` was not replaced.

**`the MCP servers are not in this image`**
The clone predates the `mcp_servers` role. Browsers are baked at golden-build time and inherited by linked
clones, so an existing clone cannot gain them in place: rebuild golden and re-create the clone
(`./cybervm destroy <name> && ./cybervm new <name>`).

**`node ... is too old — @playwright/mcp requires Node >= 18`**
The `common` role installs distro `nodejs` unpinned. The role asserts the major version and fails the build
with this message rather than producing a broken image. Install a newer Node from nodesource.io in the
`common` role.

**Old Chromium builds accumulating in `/opt/ms-playwright`**
Each `cybervm mcp update` can add a new `chromium-<build>` directory while older ones stay (GC is
intentionally off so it never deletes a shared build). Prune the ones you no longer need; keep the build
named in `/etc/cybervm/mcp.lock`.
