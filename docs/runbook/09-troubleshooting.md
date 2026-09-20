# Phase 9 — Troubleshooting

**VirtualBox VM won't start / VERR_VMX_IN_VMX_ROOT_MODE**
KVM has grabbed VT-x. Run, then reboot:
```
$ echo 'options kvm enable_virt_at_load=0' | sudo tee /etc/modprobe.d/kvm-cyberai.conf
$ sudo update-initramfs -u
```

**`doctor` says Ollama reachable on loopback**
Tighten `OLLAMA_HOST` in `/etc/systemd/system/ollama.service` to `192.168.57.1:11434`, then
`sudo systemctl daemon-reload && sudo systemctl restart ollama`.

**Guest can't reach 192.168.57.1**
Check the clone has NIC2 host-only on the cyberai interface: `VBoxManage showvminfo <vm> | grep -i nic`.
Re-apply: `./cyberai net <vm> offline` (VM off).

**No IP from a VM (`vm_wait_ip` times out)**
Guest Additions may not be running yet. Wait longer, or open the GUI once to confirm it booted.

**Ansible SSH fails**
Confirm `ssh -i ~/.config/cyberai/id_ed25519 kali@<ip> true` works; the key was installed in Phase 2.

**ufw blocks Docker RAG port**
Docker publishes bypass ufw; we bind compose ports to `192.168.57.1` explicitly. Verify with
`ss -ltnp | grep 8088` — it should show `192.168.57.1:8088`, not `0.0.0.0`.

**Disk filling up**
Linked clones grow. `./cyberai destroy <name>` unused ones; keep only the last 2 OVA releases (automatic).
