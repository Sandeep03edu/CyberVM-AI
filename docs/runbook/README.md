# CyberVM Runbook

Follow these in order. Each file has exact commands, the output you should expect, and a **Verify**
gate you must pass before moving on. `$` = run on the Ubuntu host; `kali$` = inside a Kali VM.

- `00-master-plan.md` — the whole plan + architecture (read once)
- `01-host-setup.md` — prepare the host (VirtualBox net, Ollama, deps, ufw)
- `02-base-image.md` — turn the verified Kali `.7z` into `CyberVM-Kali-Base`
- `03-golden-build.md` — provision the golden image with Ansible
- `04-vm-lifecycle.md` — clones, network modes, transfer, secrets (the isolation test)
- `05-local-ai.md` — models + benchmark
- `06-rag.md` — the shared knowledge base
- `07-release-portability.md` — OVA export, new machine, backup
- `08-offline-test.md` — the final air-gapped acceptance test
- `09-troubleshooting.md` — common problems + fixes
- `recovery.md`, `ssd-migration.md`, `new-machine.md` — occasional procedures
