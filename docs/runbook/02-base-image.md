# Phase 2 — Base image (from your verified Kali `.7z`)

**Goal:** register the official Kali prebuilt VM as `CyberVM-Kali-Base` and enable headless SSH.

## Why this way (file-type note)
Your Kali download is a **`.7z` containing a `.vbox` + `.vdi`** — a ready-made VM.
- That means **`VBoxManage registervm <file>.vbox`**, *not* "Import Appliance" (which is only for `.ova`).
- We do **not** install from an ISO (no manual OS install).

## 2.1 Run
```
$ cd ~/Personal/CyberVM-AI
$ ./cybervm base import
```
Steps it performs automatically:
1. Verifies the archive sha256 against `config/platform.yml` (STOPS if mismatch).
2. `7z x` into `images/base/`.
3. `VBoxManage registervm …/*.vbox` → renames to `CyberVM-Kali-Base`.
4. Hardens it: audio/USB off, NAT loopback off, adds NIC2 on the AI plane. Clipboard/DnD are set from
   `config/platform.yml` `.vm_defaults` (currently `bidirectional`) and applied by
   `lib/common.sh vm_apply_host_config`; `./cybervm doctor` reports read-only drift.
5. Boots headless and, via Guest Additions, enables SSH + installs your key + passwordless sudo.
6. Takes snapshot `base-clean`, then powers off.

## 2.2 Verify
```
$ VBoxManage list vms | grep CyberVM-Kali-Base
$ VBoxManage snapshot CyberVM-Kali-Base list
# start it, grab its AI-plane IP, test SSH:
$ VBoxManage startvm CyberVM-Kali-Base --type headless
$ IP=$(VBoxManage guestproperty get CyberVM-Kali-Base /VirtualBox/GuestInfo/Net/1/V4/IP | sed 's/Value: //')
$ ssh -i ~/.config/cybervm/id_ed25519 kali@$IP true && echo "SSH OK"
$ VBoxManage controlvm CyberVM-Kali-Base acpipowerbutton
```
✅ **Pass gate:** `SSH OK` printed and snapshot `base-clean` exists.

> Note: the official image login is `kali` / `kali` (from the VM description). We never work in Base.
