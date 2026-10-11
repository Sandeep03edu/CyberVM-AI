# Phase 1 — Host setup

**Goal:** make this Ubuntu machine ready to run CyberVM. Idempotent — safe to re-run.

## 1.1 Point the config at your project
```
$ cd ~/Personal/CyberVM-AI
$ cp .cybervm.env.example .cybervm.env
$ nano .cybervm.env         # leave CYBERVM_ROOT as-is for now (change only when you move to an SSD)
```

## 1.2 Run host setup
```
$ ./cybervm host-setup
```
This will (each step prints a line):
1. **Preflight** — checks VT-x, RAM, VirtualBox, and warns if KVM might clash with VirtualBox.
   - If it warns about KVM, run the two commands it prints, then reboot, then re-run host-setup.
2. **apt deps** — yq, jq, ansible-core (via pipx), docker, 7z, sshpass, ufw. *(sudo password prompt)*
3. **SSH key** — generates `~/.config/cybervm/id_ed25519` used to log into VMs.
4. **Host-only network** — creates the private `$CYBERVM_NET_CIDR` "AI plane" with DHCP.
5. **Ollama** — installs the pinned version, binds it to `$CYBERVM_HOST_IP:11434` (NOT localhost).
6. **ufw** — allows only Ollama (11434) + RAG (8088) from that subnet.
7. **secrets file** — creates `~/.config/cybervm/secrets.env` (chmod 600).
8. **models** — pulls `qwen2.5:3b-instruct` + `nomic-embed-text` (several GB; needs internet).

Expected tail: `[ ok ] host-setup complete. Run: ./cybervm doctor`

> **Where the AI-plane address comes from.** `CYBERVM_HOST_IP` (default `192.168.57.1`) and
> `CYBERVM_NET_CIDR` are set in `.cybervm.env` and nowhere else. It is the address of a VirtualBox
> host-only adapter (`vboxnetN`), not your LAN IP, and it does not change across reboots.
> To change it: edit `.cybervm.env` → `./cybervm host-setup` → `./cybervm golden build` → recreate
> clones (the address is baked into the guest at build time).

## 1.3 Verify
```
$ ./cybervm doctor
```
✅ **Pass gate:** every row is `[PASS]`, especially:
- `Ollama @ $CYBERVM_HOST_IP` PASS **and** `Ollama NOT on loopback` PASS (good isolation)
- `host-only net $CYBERVM_HOST_IP` PASS
- `ufw active` PASS
- `Kali archive checksum` PASS

If a row is `[FAIL]`, see `09-troubleshooting.md` before continuing.
