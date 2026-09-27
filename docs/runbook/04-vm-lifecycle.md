# Phase 4 — Disposable VMs, network, transfer, secrets

**Goal:** prove the disposable-clone workflow and the sandbox boundary (ChatGPT "Milestone 1").

## 4.1 Create and use a clone
```
$ ./cyberai new work-01                    # linked clone (disk-cheap) + snapshot "clean"
$ ./cyberai start work-01 --net offline    # add --headless to skip the GUI
$ ./cyberai list
```

### Sizing: RAM and vCPU

Every clone starts at the `balanced` profile (12 GB / 6 vCPU). Pick a named
profile, or set sizes explicitly — the two are mutually exclusive:

```
$ ./cyberai new work-01 --profile lean      #  8 GB / 4 vCPU
$ ./cyberai new work-01 --profile balanced  # 12 GB / 6 vCPU  (default)
$ ./cyberai new work-01 --profile large     # 16 GB / 8 vCPU
$ ./cyberai new work-01 --ram 10 --cpus 5   # exact sizes
$ ./cyberai new work-01 --ram 10            # vCPU derived, 10 GB -> 5
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
$ ./cyberai stop work-01                     # required: the VM must be powered off
$ ./cyberai resize work-01 --ram 16          # 16 GB, vCPU derived -> 8
$ ./cyberai resize work-01 --cpus 4          # vCPU only; RAM is left alone
$ ./cyberai resize work-01 --ram 6 --cpus 2  # both explicitly
```

`resize` requires at least one of `--ram`/`--cpus` and refuses `--profile` —
it never silently re-reads a profile. Omitting one flag leaves that value at
the VM's current setting. RAM and vCPU are properties of the VM's own
`.vbox` file, so resizing a clone **never touches the golden image**; the
golden stays 2 GB / 2 vCPU. Disk capacity is not affected by `resize`.

`cyberai list` shows RAM and vCPU per VM, and `./cyberai doctor` reports how
much RAM running clones have claimed, so you can see why a second VM would
refuse to start.

## 4.2 Network modes (VM must be off to change)
```
$ ./cyberai stop work-01
$ ./cyberai net work-01 nat                # internet on; host loopback still blocked
$ ./cyberai net work-01 offline            # default: no internet, AI+RAG reachable
```
Modes: `offline` (default) · `airgap` (no net at all) · `nat` (internet) · `bridged` (asks for `yes`).

## 4.3 File transfer (SCP over the AI plane — no shared folders)
`transfer` moves files host↔guest over SSH (no staging copy, no vboxsf, no `transfer/` pollution).
The guest runs the shared SCP helper (`/usr/bin/scp` → openSSH); `/mnt` is a plain root-owned dir.

```
# host -> guest (default landing dir /mnt; optional 3rd arg = guest/dir):
$ ./cyberai transfer in work-01 ./README.md
  [ ok ] Copied ./README.md -> work-01:/mnt/README.md

# guest -> host (defaults to your current dir; optional 3rd arg = host/dest):
$ ./cyberai transfer out work-01 /mnt/abc.txt
  [ ok ] Copied work-01:/mnt/abc.txt -> /home/sandeep03edu-ubuntu/Personal/CyberAIKaliVM/abc.txt

$ ./cyberai transfer in  work-01 ./payload.txt            # -> /mnt/payload.txt
$ ./cyberai transfer in  work-01 ./payload.txt /tmp       # -> /tmp/payload.txt
$ ./cyberai transfer out work-01 /mnt/payload.txt          # -> ./payload.txt
$ ./cyberai transfer out work-01 /mnt/payload.txt /root    # -> /root/payload.txt
```
Notes:
- `in` writes via `sudo install` (root-owned `/mnt`); the guest has passwordless sudo for provisioning.
- `/mnt` is root-only — inside the guest use `sudo` to write there (e.g. `echo test | sudo tee /mnt/abc.txt`); the root-owned file is world-readable, so plain `kali` SCP can pull it back out.
- Same-name overrides normal SCP semantics: `out` to your cwd overwrites a local file of that name.
- Requires the VM to be running and Guest Additions to report its AI-plane IP.

## 4.4 Cloud keys (only when you want them)
```
$ ./cyberai start work-01 --net nat
$ ./cyberai secrets push work-01 anthropic     # key -> VM tmpfs only, never an image
# in guest: source /run/user/1000/cyberai/secrets.env
$ ./cyberai secrets wipe work-01
```

## 4.5 Verify — the isolation matrix
```
# disposability:
$ ./cyberai start work-01 --net offline
#   (in guest) touch ~/MARKER ; then stop + destroy:
$ ./cyberai destroy work-01
$ ./cyberai new work-02 && ./cyberai start work-02 --net offline
#   (in guest) ls ~/MARKER  -> should NOT exist
# network boundary (in an offline guest):
kali$ curl -m5 https://kali.org         # FAILS (no internet)
kali$ curl -s 192.168.57.1:11434/api/tags   # WORKS (AI plane)
kali$ nc -zv 192.168.57.1 22            # BLOCKED (ufw)
```
✅ **Pass gate:** marker absent in work-02; golden snapshot unchanged; offline curl fails, Ollama works, ssh-to-host blocked.
