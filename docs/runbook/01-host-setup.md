# Phase 1 — Host setup

**Goal:** make this Ubuntu machine ready to run CyberAI. Idempotent — safe to re-run.

## 1.1 Point the config at your project
```
$ cd ~/Personal/CyberAIKaliVM
$ cp .cyberai.env.example .cyberai.env
$ nano .cyberai.env         # leave CYBERAI_ROOT as-is for now (change only when you move to an SSD)
```

## 1.2 Run host setup
```
$ ./cyberai host-setup
```
This will (each step prints a line):
1. **Preflight** — checks VT-x, RAM, VirtualBox, and warns if KVM might clash with VirtualBox.
   - If it warns about KVM, run the two commands it prints, then reboot, then re-run host-setup.
2. **apt deps** — yq, jq, ansible-core (via pipx), docker, 7z, sshpass, ufw. *(sudo password prompt)*
3. **SSH key** — generates `~/.config/cyberai/id_ed25519` used to log into VMs.
4. **Ollama** — installs the pinned version, binds it to `192.168.57.1:11434` (NOT localhost).
5. **Host-only network** — creates the private `192.168.57.0/24` "AI plane" with DHCP.
6. **ufw** — allows only Ollama (11434) + RAG (8088) from that subnet.
7. **secrets file** — creates `~/.config/cyberai/secrets.env` (chmod 600).
8. **models** — pulls `qwen3:8b` + `nomic-embed-text` (several GB; needs internet).

Expected tail: `[ ok ] host-setup complete. Run: ./cyberai doctor`

## 1.3 Verify
```
$ ./cyberai doctor
```
✅ **Pass gate:** every row is `[PASS]`, especially:
- `Ollama @ 192.168.57.1` PASS **and** `Ollama NOT on loopback` PASS (good isolation)
- `host-only net 192.168.57.1` PASS
- `ufw active` PASS
- `Kali archive checksum` PASS

If a row is `[FAIL]`, see `09-troubleshooting.md` before continuing.
