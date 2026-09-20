# Recovery

- **A clone is broken:** `./cyberai destroy <name>` then `./cyberai new <name>` (golden is untouched).
- **Golden is broken:** delete it in VirtualBox, then `./cyberai golden build` (rebuilds from config).
- **Everything gone:** `git clone` the repo → `host-setup` → `base import` → `golden build` → `rag up/update`.
  The images are disposable; **git config + this runbook are the real backup.**
- **Restore RAG:** `./cyberai rag restore rag/backups/<snapshot>`.
