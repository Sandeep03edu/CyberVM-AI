# Phase 6 — Shared RAG knowledge base

> New to RAG? Read [`06-rag-understanding.md`](06-rag-understanding.md) first — it explains what these commands actually do, what lands on disk, and how LLMs query it.

**Goal:** one host service every VM queries; fresh CVE/KEV/EPSS intel with source tiers.

## 6.1 Start the stack
```
$ ./cybervm rag up          # docker: qdrant + rag-api on 192.168.57.1:8088
$ ./cybervm rag status
```

## 6.2 Ingest knowledge
```
$ ./cybervm rag update live      # NVD CVE (21-day window) + CISA KEV + GitHub advisories + EPSS + nuclei-templates
$ ./cybervm rag update stable    # MITRE ATT&CK + CWE + OWASP WSTG + OWASP CheatSheetSeries + PayloadsAllTheThings
```
Put your own notes in `rag/sources/personal/*.md`, then `./cybervm rag update personal`.

All fetchers are implemented (see `services/rag/ingest/run.py`). Ingestion is incremental: a per-source
state file (`rag/state/cybervm_rag_state.json`) tracks every document's `key→version`, so re-runs only
embed and upsert new/changed content. If a source errors (e.g. GitHub's unauthenticated rate limit),
it is logged and skipped so the rest of the index still updates.

Why it gives low-false-positive, in-the-wild intel: every chunk stores **tier (1–4)**, **KEV**
(confirmed exploitation), **EPSS** (likelihood) and dates. The MCP tool returns those so the model
weighs authority + freshness instead of trusting any random source.

## 6.3 Query from a clone (MCP)
The golden image configures the `cybervm-rag` MCP server for **Codex** today. (OpenCode ships it
disabled, and Claude is **not** wired up yet — Claude Code does not read
`~/.config/cybervm/claude-mcp.json`. See the known-gap note in `06-rag-understanding.md` §6a.2.
The Playwright MCP, by contrast, is registered with all three clients.)
Use the guest `cybervm` CLI's opencode wrapper (see `05-local-ai.md` §5.3) or opencode directly:
```
kali$ cybervm ai opencode "Which CVEs were added to CISA KEV recently? cite tier and date."
kali$ opencode run "Which CVEs were added to CISA KEV recently? cite tier and date."
```
Or hit REST directly:
```
kali$ curl -s 192.168.57.1:8088/search -d '{"query":"KEV added recently","tier_max":1}' | jq .
```

## 6.4 Verify
```
$ ./cybervm rag status          # shows per-collection counts + responds
```
✅ **Pass gate:** `status` returns counts; a clone gets tiered, dated results; `./cybervm rag down` doesn't affect any VM.

> **Where the data lives:** Qdrant stores points under `rag/data/` (root-owned, git-ignored). Raw downloads
> are mirrored in `rag/sources/`, git-based sources are cloned into `rag/state/git-cache/`, and the
> incremental dedup state is in `rag/state/cybervm_rag_state.json`. Check per-source counts with
> `./cybervm rag status`.

## 6.5 Keep it fresh
`./cybervm rag update live` daily, `stable` weekly (wire host systemd-user timers — see `services/rag`).
To re-ingest a single source (e.g. after a rate-limit hiccup) add `--only <source-id>`.
