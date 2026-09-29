# Phase 7 — Release, portability, backup

## 7.1 Export a portable image
```
$ ./cybervm stop CyberVM-Kali-Golden 2>/dev/null || true
$ ./cybervm release          # -> images/releases/CyberVM-Kali-<date>.ova (+ .sha256 + manifest)
```

## 7.2 Back up (to your HDD)
```
$ ./cybervm backup /media/$USER/YOUR-HDD
```
Copies source + config + releases + RAG snapshot + a model list (models are re-pullable).

## 7.3 On another machine
```
$ git clone <repo> CyberVM-AI && cd CyberVM-AI
$ cp .cybervm.env.example .cybervm.env    # edit CYBERVM_ROOT
$ ./cybervm host-setup
# fast path:
$ ./cybervm import /path/to/CyberVM-Kali-<date>.ova
# or rebuild from source:
$ ./cybervm base import && ./cybervm golden build
$ ./cybervm rag up && ./cybervm rag update live
```
✅ **Pass gate:** imported OVA boots and a clone reaches host Ollama + RAG.

See `ssd-migration.md` for moving everything to an external SSD (change one path).
