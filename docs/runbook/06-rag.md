# Phase 6 — Shared RAG knowledge base

**Goal:** one host service every VM queries; fresh CVE/KEV/EPSS intel with source tiers.

## 6.1 Start the stack
```
$ ./cyberai rag up          # docker: qdrant + rag-api on 192.168.57.1:8088
$ ./cyberai rag status
```

## 6.2 Ingest knowledge
```
$ ./cyberai rag update live      # CISA KEV + EPSS work out-of-the-box; NVD/GH advisories are TODO fetchers
$ ./cyberai rag update stable    # ATT&CK/CWE/OWASP (TODO fetchers — see services/rag/ingest/run.py)
```
Put your own notes in `rag/sources/personal/*.md`, then `./cyberai rag update personal`.

Why it gives low-false-positive, in-the-wild intel: every chunk stores **tier (1–4)**, **KEV**
(confirmed exploitation), **EPSS** (likelihood) and dates. The MCP tool returns those so the model
weighs authority + freshness instead of trusting any random source.

## 6.3 Query from a clone (MCP)
The golden image already configured OpenCode/Codex/Claude with the `cyberai-rag` MCP server.
Use the guest `cyberai` CLI's opencode wrapper (see `05-local-ai.md` §5.3) or opencode directly:
```
kali$ cyberai ai opencode "Which CVEs were added to CISA KEV recently? cite tier and date."
kali$ opencode run "Which CVEs were added to CISA KEV recently? cite tier and date."
```
Or hit REST directly:
```
kali$ curl -s 192.168.57.1:8088/search -d '{"query":"KEV added recently","tier_max":1}' | jq .
```

## 6.4 Verify
```
$ ./cyberai rag status          # shows per-collection counts + responds
```
✅ **Pass gate:** `status` returns counts; a clone gets tiered, dated results; `./cyberai rag down` doesn't affect any VM.

## 6.5 Keep it fresh
`./cyberai rag update live` daily, `stable` weekly (wire host systemd-user timers — see `services/rag`).
