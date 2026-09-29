# Recovery

- **A clone is broken:** `./cybervm destroy <name>` then `./cybervm new <name>` (golden is untouched).
- **Golden is broken:** delete it in VirtualBox, then `./cybervm golden build` (rebuilds from config).
- **Everything gone:** `git clone` the repo → `host-setup` → `base import` → `golden build` → `rag up/update`.
  The images are disposable; **git config + this runbook are the real backup.**
- **Restore RAG:** `./cybervm rag restore rag/backups/<snapshot>`.
