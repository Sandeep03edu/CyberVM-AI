# Phase 8 — Offline acceptance test

**Goal:** prove the lab works fully air-gapped (this is the whole point).

## Steps (physically unplug / disable host networking first)
```
$ ./cyberai new offline-demo && ./cyberai start offline-demo --net offline
kali$ source /etc/profile.d/cyberai.sh
kali$ cyberai ai run "Explain this HTTP 500 with a SQL error and my next test"   # local model answers (guest cyberai CLI)
kali$ cyberai ai opencode "Explain this HTTP 500 with a SQL error and my next test"  # or via opencode
kali$ curl -s 192.168.57.1:8088/search -d '{"query":"sql injection","tier_max":2}' | jq '.results[0]'
kali$ nmap -sV <a lab VM IP on 192.168.57.0/24>
$ ./cyberai destroy offline-demo
```
✅ **Pass gate:** local AI answers, RAG returns stable-layer results, nmap runs; only cloud models and
RAG `live` refresh are unavailable (expected — those need internet).
