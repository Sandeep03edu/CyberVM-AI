# CyberAI Kali VM Platform

A reproducible, portable lab for security testing with AI assistance. One **golden Kali image**
you never touch, cheap **disposable clones** for real work, a **host-native local LLM** (Ollama),
optional **cloud models** (Claude/Codex/DeepSeek via OpenCode), and a **shared, always-fresh RAG**
knowledge base — all rebuildable from configuration and movable to another machine by changing one path.

> **New here? Read [`docs/runbook/00-master-plan.md`](docs/runbook/00-master-plan.md) first**, then follow
> `docs/runbook/01…09-*.md` in order. Every step has an exact command and a **Verify** check.

---

## Why we're doing this (the goals)

From the design discussion in `AIPlan/` (the requirements source of truth), the platform must:

| Requirement | How this repo meets it |
|---|---|
| Create/kill a Kali environment anytime without touching the host OS | VirtualBox VMs; `cyberai new/destroy` |
| Never rebuild VM #2 by hand | **Ansible** provisions a golden image from `config/` manifests |
| Not be tied to one LLM | Model / runtime / client are separated; local Ollama **and** cloud providers |
| Same RAG shared by every VM, updated once | One **host RAG service**; VMs query it over one endpoint |
| Fresh CVE + in-the-wild intel, few false positives | Tiered sources + **CISA KEV** + **EPSS** + freshness metadata |
| Tools (incl. Burp + extensions) present without manual setup | Manifest-driven install; pinned, checksum-verified BApps |
| Strong sandbox, but switchable internet + controlled file transfer | Two NICs + `cyberai net` modes + transient transfer |
| No secrets in images | API keys stay on the host, pushed to VM **tmpfs** at runtime |
| Portable to other machines / an SSD later | OVA export + `CYBERAI_ROOT` is the only path that changes |

## How it works (the shape)

```
Ubuntu host ── ./cyberai
 ├─ Ollama (native)   192.168.57.1:11434     ← local models, unloads when idle
 ├─ RAG (docker)      192.168.57.1:8088      ← qdrant + REST/MCP + tiered ingest
 └─ VirtualBox
      CyberAI-Kali-Base   (verified official image; untouched)
      CyberAI-Kali-Golden (Ansible-provisioned; snapshot golden-<date>)
      kali-<name>         (disposable LINKED clones)
        NIC1 internet plane: none | nat | bridged
        NIC2 AI plane: host-only 192.168.57.0/24 → reaches ONLY Ollama + RAG
```

**The source of truth is `config/` + `factory/` + `services/` in git — not the VM images.**
If a VM breaks, you reclone. If the golden breaks, you rebuild it from config. If you add a tool,
you edit a manifest and rebuild — you never hand-edit a running VM.

## Layout

```
cyberai              # the CLI you run for everything
lib/*.sh             # CLI implementation (one file per area)
config/              # PINNED source of truth: versions, tools, burp, ai
  platform.yml       #   Kali/Ollama/VBox versions + checksums + resource profiles
  tools/*.yml        #   apt / pip / github / binaries manifests
  burp/              #   extension lock + Burp user config
  ai/*.yml           #   models, clients, provider endpoints (no keys)
factory/ansible/     # provisions the golden image (roles + playbook)
services/rag/        # docker compose + FastAPI/MCP api + tiered ingest
docs/runbook/        # step-by-step beginner guide (start at 00)
# gitignored data (large, machine-local): downloads/ images/ labs/ models/ rag/data/ transfer/ backups/
```

## Quick start (summary — full detail in the runbook)

```bash
cp .cyberai.env.example .cyberai.env     # edit CYBERAI_ROOT if you like
./cyberai host-setup                     # installs Ollama, network, ufw, deps
./cyberai doctor                         # must be all PASS
./cyberai base import                    # register the verified Kali image
./cyberai golden build                   # Ansible-provision + snapshot
./cyberai new work-01                    # a disposable clone
./cyberai start work-01 --net offline
```

**Inside a Kali clone** (the golden image ships a guest `cyberai` CLI that talks to host Ollama
over the AI plane — works offline):

```bash
kali$ source /etc/profile.d/cyberai.sh
kali$ cyberai ai run "what does nmap -sV do?"        # stream a reply from the local model
kali$ cyberai ai opencode "what does nmap -sV do?"   # same, through opencode (ollama/qwen2.5:3b-instruct)
```

## Safety rules (baked into the tooling)

- **Never work in Golden or Base** — `destroy` refuses them; you work only in clones.
- **Default network is `offline`** (AI + RAG, no internet). `bridged` requires typing `yes`.
- **Secrets never enter an image** — they live in `~/.config/cyberai/secrets.env` (chmod 600)
  and are pushed to a VM's tmpfs only when you ask.
- **Everything pinned + checksum-verified** — Kali archive, Ollama, Burp extensions.

## Status

Scaffold complete and statically validated (shell `bash -n`, YAML parse, `docker compose config`).
Fill-in-before-first-run items are marked `TODO` in `config/burp/extensions.lock.yml`,
`config/tools/{github,binaries}.yml`, `config/platform.yml` (ollama sha256), and NVD/git fetchers in
`services/rag/ingest/run.py`. See `docs/runbook/` for what to run and verify at each phase.
