# Phase 6 (companion) — Understanding the RAG: what it is, what it built, and how to use it

> Read this **before** you start relying on the RAG. `06-rag.md` is the terse
> operator runbook (the commands). This file explains the *mechanics* — what
> actually happened when you ran `cybervm rag update`, what got created on disk,
> how the data is stored, how a local LLM queries it, and whether you can/should
> hand it to OpenCode or a cloud model.
>
> Every fact here is traced to the real code: `services/rag/ingest/run.py`,
> `services/rag/api/main.py`, `services/rag/docker-compose.yml`,
> `services/rag/sources.yml`, `lib/rag.sh`, and the client templates under
> `factory/ansible/roles/mcp_servers/templates/` (rendering moved out of `rag_client` into the
> `mcp_servers` role, which owns all three client config files; the `cybervm-rag` entries are unchanged).

---

## 6a.1 The 30-second mental model

**RAG** (Retrieval-Augmented Generation) here = a **local, private search index
of security knowledge** that any Kali clone (or the host) can query in plain
English. Instead of the LLM guessing from memory, it *retrieves* real
CVE/KEV/OWASP/ATT&CK text — tagged with a trust tier and dates — and answers from
that.

Everything runs on the **host**, bound to the internal AI-plane IP
`192.168.57.1` (nothing is exposed to the internet). Four moving parts:

| Part | What it is | Where |
|------|------------|-------|
| **Qdrant** | Vector database that stores the embedded knowledge | container `qdrant/qdrant:v1.12.4`, port `6333` |
| **rag-api** | FastAPI service: REST `/search`, `/status`, and an MCP endpoint `/mcp` | container, port `8088` |
| **ingest** | One-shot job (run by `cybervm rag update`) that fetches sources, embeds them, upserts into Qdrant | container, `profiles: ["tools"]` |
| **Ollama** | Turns text into vectors ("embeddings") using `nomic-embed-text` | host, port `11434` |

The only outbound traffic is the ingester fetching public sources (NVD, CISA,
GitHub, OWASP repos, etc.). Queries and embeddings stay on the box.

```
                         ┌──────────────── host (192.168.57.1) ────────────────┐
  public internet        │                                                      │
  (NVD, CISA, GitHub, ───┼──►  ingest ──embeds via──►  Ollama (nomic-embed-text)│
   OWASP, nuclei…)       │      │                          │                    │
                         │      └── upserts vectors ──►  Qdrant  ◄── search ──┐  │
                         │                                  ▲                 │  │
   Kali clone ───────────┼──► rag-api  (/search REST, /mcp)─┘                 │  │
   (opencode/claude/     │        also embeds the *query* via Ollama ─────────┘  │
    codex via MCP)       │                                                      │
                         └──────────────────────────────────────────────────────┘
```

---

## 6a.2 What actually happened in your run

Here is your terminal output mapped line-by-line to what the code did.

```
[+] up 1/1  ✔ Container rag-qdrant-1 Running
```
→ `_rag_update` (`lib/rag.sh`) runs `docker compose up -d qdrant` first. The
ingester writes to Qdrant over the internal Docker DNS name `qdrant`, so Qdrant
must be running before ingest. `rag-api` is **not** needed to ingest.

```
Image rag-ingest Building … Built
```
→ `_rag_update` passes `--build`, which rebuilds the ingest image so any change
to the Dockerfile/code takes effect (otherwise compose reuses a stale tag). Your
log shows all layers `CACHED` — nothing changed, so it was ~2s.

```
epss: 378156 scores
```
→ `fetch_epss` downloaded the EPSS CSV (gzipped) and parsed 378k CVE→score rows
**into memory**. Important: **EPSS is not stored as its own collection.** Those
scores are merged onto CVE documents as an `epss` payload field right before
ingest (`run.py`, the `for d in docs: if d.get("cve"): d["epss"] = epss.get(...)`
loop). So a CVE hit later carries its exploit-likelihood score inline.

```
[live] nvd_cve (tier 1)
  upserted 269 -> live (1500 total for source)
```
→ NVD returned CVEs modified in the last 21 days. 269 were new-or-changed since
your last run, so only those 269 were embedded and upserted into the **`live`**
collection. `1500 total for source` is the per-source cap from `sources.yml`.

```
[live] cisa_kev (tier 1)
  1721 docs unchanged - skipping
```
→ This is the **incremental dedup** working. The ingester keeps a ledger of every
document's `key → version`. All 1721 KEV entries had the same version as last
time, so nothing was re-embedded. Re-running is cheap and safe.

```
[live] github_advisories (tier 1)
  upserted 100 -> live (100 total for source)
[live] nuclei_templates (tier 3)
  500 docs unchanged - skipping
```
→ Same pattern: 100 fresh GitHub advisories embedded; 500 nuclei templates
already current.

```
[stable] owasp_wstg      upserted 4  … 150 total for source
[stable] owasp_cheatsheets upserted 6 … 400 total for source
[stable] mitre_attack / cwe / payloadsallthethings … unchanged - skipping
```
→ The `stable` run touched only the OWASP repos (a few files changed upstream);
ATT&CK, CWE, and PayloadsAllTheThings were already current.

**Takeaway:** the first ingest is the expensive one (everything gets embedded);
every run after that only embeds the delta. You can run `live` daily and `stable`
weekly without worrying about redundant work.

---

## 6a.3 The sources — what each one is

From `services/rag/sources.yml`. **Tier** = trust (1 = authoritative … 4 =
unverified). **Layer** = both the refresh cadence *and* the Qdrant collection the
docs land in (`live`, `stable`, or `personal`).

| id | tier | layer | kind | What it is | How it's fetched |
|----|------|-------|------|------------|------------------|
| `mitre_attack` | 1 | stable | technique | MITRE ATT&CK Enterprise techniques | STIX JSON download |
| `cwe` | 1 | stable | fundamental | MITRE CWE weakness catalog | XML-in-ZIP download |
| `owasp_wstg` | 1 | stable | fundamental | OWASP Web Security Testing Guide | git clone (`.md`) |
| `owasp_cheatsheets` | 1 | stable | fundamental | OWASP Cheat Sheet Series | git clone (`.md`) |
| `nvd_cve` | 1 | live | vulnerability | NVD CVEs, last 21 days modified | NVD REST API (paged) |
| `cisa_kev` | 1 | live | advisory | CISA Known Exploited Vulns | JSON feed |
| `github_advisories` | 1 | live | advisory | GitHub Security Advisories | GitHub API (unauth, rate-limit tolerant) |
| `epss` | 2 | live | advisory | EPSS exploit-likelihood scores | CSV.gz → **merged into CVE docs**, not its own collection |
| `nuclei_templates` | 3 | live | exploit-poc | ProjectDiscovery nuclei templates | git clone (`.yaml/.yml`) |
| `payloadsallthethings` | 3 | stable | technique | PayloadsAllTheThings cheat repo | git clone (`.md`) |
| `personal_notes` | 1 | personal | personal | **Your** notes | reads `rag/sources/personal/*.md` |

Why tiers matter: at query time you can say "only give me tier ≤ 1" to get
authoritative evidence and exclude tier-3 PoCs/payloads. That's the whole
low-false-positive design — the model can tell confirmed intel from inference.

---

## 6a.4 What got created on disk (the folder map)

Root is `rag/` in the repo (`CYBERVM_RAG="$CYBERVM_ROOT/rag"` in `.cybervm.env`).
It is **git-ignored** — the index never gets committed. Current live layout:

```
rag/
├── data/                 ← Qdrant's storage volume  (root-owned, ~62 MB)
│   ├── collections/
│   │   ├── live/         ← vectors + payloads for the "live" layer
│   │   └── stable/       ← vectors + payloads for the "stable" layer
│   │       (a personal/ collection appears only after you ingest personal notes)
│   ├── aliases/          ← Qdrant internal
│   ├── raft_state.json   ← Qdrant internal
│   └── .deleted/         ← Qdrant internal
│
├── state/                ← ingester's working state  (~194 MB)
│   ├── cybervm_rag_state.json   ← the dedup ledger: source → {seen:{key→version}, last_run}
│   └── git-cache/               ← shallow git clones of the 4 git sources
│       ├── nuclei_templates/    (this is most of the 194 MB)
│       ├── owasp_cheatsheets/
│       ├── owasp_wstg/
│       └── payloadsallthethings/
│
├── sources/
│   └── personal/         ← drop YOUR own *.md notes here, then: cybervm rag update personal
│
└── backups/             ← snapshots written by: cybervm rag backup
```

Two things that surprise first-timers:

- **`rag/data/` is owned by `root`.** That's normal — the Qdrant container runs
  as root and owns its volume. Don't `chown` it; use `cybervm rag` commands to
  interact with it.
- **`git-cache/` is large** because the ingester does real (shallow) clones of
  the source repos so it can re-scan them incrementally. It's a cache — safe to
  delete; the next `update` re-clones what it needs.

Mapping the two Docker volumes (`docker-compose.yml`): the ingester mounts
`rag/sources` read-only at `/sources` and `rag/state` read-write at `/state`.
Qdrant mounts `rag/data` at `/qdrant/storage`.

---

## 6a.5 How the data is stored (the storage model)

The pipeline for every source document:

1. **Chunk** (if long): `chunk_text` splits text into ~4000-char pieces with a
   200-char overlap, so a long CWE/OWASP page becomes several searchable chunks.
2. **Embed**: each chunk is sent to Ollama's `nomic-embed-text` model, which
   returns a vector (a list of floats representing the meaning).
3. **Upsert into Qdrant** as a **point**:
   - **id** — deterministic: `sha1("<source>|<key>")` (`stable_id`). Deterministic
     so re-ingesting the same doc overwrites rather than duplicates.
   - **vector** — the embedding.
   - **payload** — the metadata that travels with every hit. Only these keys are
     kept (`PAYLOAD_KEYS`): `text, source, tier, kind, url, cve, cwe, kev, epss,
     attack_ids, severity, vendor, product, published_at, updated_at, confidence`
     (plus `retrieved_at`). Anything else on the doc is dropped.

Collections are created on first write with the embedding's dimensionality and
**cosine** distance (`ensure_collection`). That's why `collections/personal/`
doesn't exist until you actually ingest personal notes.

**Why the rich payload matters:** because tier, KEV status, EPSS score, and dates
are stored *on every point*, the search layer can filter by authority and
freshness, and the LLM can cite provenance ("CVE-…, tier 1, KEV=true, added
2026-09-…"). That is the project's core anti-false-positive move.

---

## 6a.6 How a local LLM (or you) queries it

All three front doors hit the **same** `_search` function in `api/main.py`: it
embeds your query with Ollama, vector-searches **all three collections**
(`live`, `stable`, `personal`), applies your filters, sorts by score, and returns
the top hits with full provenance.

```
your question ─► embed (Ollama) ─► vector search live+stable+personal
              ─► filter (tier_max / since / cve / kind) ─► sort by score ─► hits + provenance
```

### 1. REST (simplest to eyeball)
```bash
curl -s 192.168.57.1:8088/search \
  -d '{"query":"KEV added recently","tier_max":1}' | jq .
```
Filters you can pass: `tier_max` (max trust tier, default 4), `since` (ISO date,
`updated_at >=`), `cve` (substring match), `kind` (e.g. `vulnerability`,
`technique`), `limit` (default 8).

### 2. MCP (how the AI tools consume it)
`rag-api` exposes an MCP endpoint at `/mcp` with two tools:
`search_security_kb` and `get_cve`. The golden image already wires this server —
named **`cybervm-rag`** — into the three CLIs via templates in
`factory/ansible/roles/mcp_servers/templates/`:

- **Claude** (`claude-mcp.json.j2`) → `http://<host>:8088/mcp`
- **Codex** (`codex-config.toml.j2`) → same endpoint
- **OpenCode** (`opencode.json.j2`) → same endpoint, but **`"enabled": false` by
  default** — flip it to `true` to turn the tool on for OpenCode.

> **Known gap (not yet fixed).** Claude Code does not read
> `~/.config/cybervm/claude-mcp.json`, and templating `~/.claude.json` is not an
> option because it holds onboarding state and caches. The fix is to register the
> server with `claude mcp add --scope user --transport http cybervm-rag <url>`
> during provisioning, the same way the `mcp_servers` role already registers the
> Playwright MCP. Until that lands, **`cybervm-rag` is effectively configured for
> Codex only**, not for Claude or OpenCode. The Playwright MCP *is* correctly
> registered with all three.

### 3. CLI wrappers (the everyday path)
```bash
kali$ cybervm ai opencode "Which CVEs were added to CISA KEV recently? cite tier and date."
kali$ opencode run "Which CVEs were added to CISA KEV recently? cite tier and date."
```

---

## 6a.7 Can I / should I give this RAG to OpenCode or a cloud LLM?

**Short answer:** yes to local tools (that's the design); be deliberate about
anything cloud.

### Local tools in the VM (OpenCode / Codex / Claude CLI) — yes
This is exactly what it's for. It's just an HTTP/MCP endpoint on the internal IP.
For OpenCode specifically, set the `cybervm-rag` MCP block to `"enabled": true`
in its config (it ships disabled). Nothing else to do — the golden image already
knows the URL.

### Cloud / hosted LLMs (Claude.ai, ChatGPT web, a hosted agent) — careful
The service is bound to `192.168.57.1`, a **host-only, non-routable IP**. A cloud
model literally **cannot reach it** unless you deliberately expose or tunnel it.
Before you do, weigh two things:

1. **Reachability / posture.** Punching port 8088 out to the internet (reverse
   proxy, tunnel) breaks the "host-only, nothing leaves the box" security model
   this lab is built around. The endpoint has no auth — don't expose it publicly.
2. **Data sensitivity.** The *knowledge* is public intel (CVE/KEV/OWASP/etc.), so
   the index content itself isn't secret. But two things do leave: your
   `rag/sources/personal/` notes (which may be sensitive), and **every query you
   send** — a cloud provider would see both.

**Recommended pattern:** keep the RAG host-only. If you want a *cloud* model to
benefit from it, run a **local agent** in the VM (OpenCode/Codex/Claude CLI) that
holds the MCP connection, and let *that* agent talk to the cloud model. Then only
the *retrieved context the agent chose to send* reaches the cloud — never the raw
index or the endpoint itself. Don't expose 8088 directly.

---

## 6a.8 Quick reference

```bash
# lifecycle
cybervm rag up                 # start qdrant + rag-api on 192.168.57.1:8088
cybervm rag status             # per-collection counts (proves it responds)
cybervm rag down               # stop the stack (does not touch any VM)

# ingest (incremental — safe to re-run)
cybervm rag update live        # NVD + KEV + GitHub advisories + EPSS + nuclei
cybervm rag update stable      # ATT&CK + CWE + OWASP WSTG + Cheatsheets + Payloads
cybervm rag update personal    # your rag/sources/personal/*.md notes
cybervm rag update live --only nvd_cve   # re-ingest one source (e.g. after a rate-limit hiccup)

# backup / restore (copies rag/data + rag/state)
cybervm rag backup
cybervm rag restore rag/backups/qdrant-YYYYMMDD-HHMM.snapshot
```

**Where things live:** vectors → `rag/data/collections/{live,stable,personal}` ·
dedup ledger → `rag/state/cybervm_rag_state.json` · git clones →
`rag/state/git-cache/` · your notes → `rag/sources/personal/`.

**Verify anytime:**
```bash
cybervm rag status
curl -s 192.168.57.1:8088/search -d '{"query":"KEV added recently","tier_max":1}' | jq .
```

See `06-rag.md` for the operator runbook and `05-local-ai.md` §5.3 for the
OpenCode/Ollama wiring.
