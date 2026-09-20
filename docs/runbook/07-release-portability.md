# Phase 7 — Release, portability, backup

## 7.1 Export a portable image
```
$ ./cyberai stop CyberAI-Kali-Golden 2>/dev/null || true
$ ./cyberai release          # -> images/releases/CyberAI-Kali-<date>.ova (+ .sha256 + manifest)
```

## 7.2 Back up (to your HDD)
```
$ ./cyberai backup /media/$USER/YOUR-HDD
```
Copies source + config + releases + RAG snapshot + a model list (models are re-pullable).

## 7.3 On another machine
```
$ git clone <repo> CyberAIKaliVM && cd CyberAIKaliVM
$ cp .cyberai.env.example .cyberai.env    # edit CYBERAI_ROOT
$ ./cyberai host-setup
# fast path:
$ ./cyberai import /path/to/CyberAI-Kali-<date>.ova
# or rebuild from source:
$ ./cyberai base import && ./cyberai golden build
$ ./cyberai rag up && ./cyberai rag update live
```
✅ **Pass gate:** imported OVA boots and a clone reaches host Ollama + RAG.

See `ssd-migration.md` for moving everything to an external SSD (change one path).
