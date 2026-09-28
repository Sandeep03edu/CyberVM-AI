# CyberAI Kali Platform — Beginner Runbook + Build Plan

> On approval I will: (1) copy this file to `docs/runbook/00-master-plan.md` inside the repo and split it into
> per-phase files `docs/runbook/01…09-*.md`; (2) create the directory structure below; (3) restructure `KaliImage/`
> into `downloads/`; (4) scaffold the `cyberai` CLI, Ansible roles, manifests and RAG service. You then run each phase
> using the exact commands here, checking the **Verify** box before moving on.

---

## Context

`AIPlan/ChatGPT-Offline Kali AI Setup-20260919-2310.md` is the requirements source of truth: a golden Kali image with
disposable clones, manifest-driven tools, automated Burp + extensions, AI that isn't locked to one LLM (local Ollama plus
cloud Claude/Codex/DeepSeek via OpenCode), a shared always-fresh RAG (CVE + in-the-wild exploitation, source-tiered),
switchable network modes, controlled file transfer, no secrets in images, and portability to other machines.
It is conceptual only — no runnable commands, and the design flip-flopped between KVM/VirtualBox/SSD. This runbook makes it concrete.

**Your decisions:** Ollama runs **natively on the Ubuntu host**; automation is **Ansible + a `cyberai` bash CLI** (Packer optional later);
one host-setup script works on any machine; deliverable is a **runbook + code scaffold** you execute yourself.

### Verified machine state (2026-09-19)
- Ubuntu 24.04.5, kernel 7.0, **i5-13600K** (6P+8E, 20 threads), **31 GiB RAM** (~25 GiB available now), **~599 GB free** on `/`.
- **VirtualBox 7.2.16 installed.** Docker + compose v5.5.1 installed. `git`, `7z`, `python3` present. **Missing:** `ansible`, `ollama` (Packer not needed).
- `kvm_intel` loaded but coexists with VirtualBox (`enable_virt_at_load=N`). Don't run KVM and VBox VMs simultaneously.
- You are in the `docker` and `sudo` groups. Host-only net `vboxnet0` (192.168.56.1) exists (used by other VMs) — CyberAI will get its **own** network.
- Default VirtualBox machine folder is already `…/CyberAIKaliVM/images` (dir not created yet).
- **You already removed the golden VM from VirtualBox** (confirmed: not in `VBoxManage list vms`). Its files still exist:
  - `KaliImage/kali-linux-2026.2-virtualbox-amd64.7z` — the official prebuilt archive (keep, this is our source).
  - `KaliImage/CyberAI-Kali-Golden/` — an old extracted `.vbox` + 16 GB `.vdi` (stale, will be removed with your OK).
- `.gitignore` currently does **not** exclude `*.7z`, `*.vdi`, `*.ova`, `KaliImage/` → risk of committing the 3.9 GB archive. Phase 0 fixes this.

### Image file-type note (important for "how to create the image")
The Kali download for VirtualBox is a **`.7z` containing a `.vbox` + `.vdi`** (a ready-made VM), *not* an ISO and *not* an `.ova`.
- ISO → you'd install the OS by hand (we are **not** doing this).
- `.ova`/`.ovf` → use **`VBoxManage import`** ("Import Appliance").
- `.vbox` + `.vdi` (our case) → **`VBoxManage registervm <file>.vbox`**, or clone the `.vdi`. This is the path Phase 2 uses.

---

## Architecture (final)

```
UBUNTU HOST  ── ./cyberai host-setup (one script, any machine)
 ├─ Ollama (native systemd)     bind 192.168.57.1:11434   models → models/ollama
 ├─ RAG (docker compose)        bind 192.168.57.1:8088    data   → rag/data
 │    qdrant + rag-api (REST + MCP /mcp) + host systemd-user ingest timers
 ├─ ufw on cyberai host-only net: allow only 11434, 8088 (+8000 during transfer)
 └─ VirtualBox
      ├─ CyberAI-Kali-Base    (verified official image; never used for work; the rebuild path)
      ├─ CyberAI-Kali-Golden  (Ansible-provisioned; snapshot golden-<date>; rebuilt via `golden reset`)
      └─ kali-<name>          (LINKED clones of the golden snapshot; disposable)
           NIC1 internet plane: none | nat(localhost-off) | bridged(confirm)
           NIC2 AI plane: host-only "cyberai" 192.168.57.0/24 → reaches Ollama+RAG only
```

**Golden disk growth.** Each `golden build` re-provisions in place and snapshots again, and VirtualBox
stores every snapshot as a differencing disk that is never pruned — the golden grows ~1.3 GB per build
forever. `./cyberai golden reset` collapses the chain back to a single disk by rebuilding from Base
(~15 GB Base + ~24 GB provisioned floor). It never touches Base, so it is always safe to run and always
recoverable with `golden build`. See §3.5 of the golden-build runbook.

**RAM budget (32 GB):** desktop ~7 + Kali `balanced` 12 + qwen2.5:3b-instruct ~6–7 (unloads after 5 min idle) + RAG ~1.5 ≈ 27 GB — one Kali VM at a time, comfortably. Two at once needs `--ram 8` clones (`lean`).
`cyberai start` refuses to boot if the host would drop below a 6 GB reserve. Profiles: `lean` 8 GB/4 vCPU, `balanced` 12 GB/6 vCPU (default), `large` 16 GB/8 vCPU. Override per clone with `--ram GB` / `--cpus N`, or change an existing clone with `./cyberai resize <name> --ram GB` (VM off) — neither modifies the golden image.

**Network modes** (`cyberai net <vm> MODE`, VM powered off): `offline`(default, no internet, AI on) · `airgap`(no net at all) · `nat`(internet + AI) · `bridged`(explicit exposure, typed confirmation).
Cloud AI needs `nat` **and** `cyberai secrets push`. Keys live only in `~/.config/cyberai/secrets.env` (chmod 600) and are copied into VM tmpfs at runtime — never into an image.

---

## Repo layout created on approval (data dirs are gitignored)

```
cyberai                     lib/*.sh                 .cyberai.env(.example)
config/ platform.yml  tools/{apt,pip,github,binaries}.yml  burp/{extensions.lock.yml,user-options.json}
        ai/{models,clients,providers}.yml  mcp/servers.yml
factory/ansible/ ansible.cfg playbooks/golden.yml roles/{common,hardening,security_tools,burp,ai_clients,ai_guest,rag_client,disable_sleep,mcp_servers}
services/rag/ docker-compose.yml sources.yml api/ ingest/
docs/runbook/ 00-master-plan.md 01…09-*.md recovery.md ssd-migration.md new-machine.md
# gitignored: downloads/ images/{base,golden,releases}/ labs/ models/ rag/data/ transfer/ backups/ artifacts/
```

---

# PHASE-BY-PHASE RUNBOOK (exact commands + expected output + Verify)

> Convention: lines starting `$` run on the **Ubuntu host**; `kali$` run **inside a Kali VM**. Do not type the `$`.

## Phase 0 — Repo cleanup & keep the Kali source (host)
```
$ cd ~/Personal/CyberAIKaliVM
# 0.1 Fix .gitignore (scaffolded), then confirm the big files are ignored:
$ git status --short            # expect: no *.7z / *.vdi / KaliImage listed
# 0.2 Move the official archive out of KaliImage into downloads/ (kept as our source):
$ mkdir -p downloads/kali
$ mv KaliImage/kali-linux-2026.2-virtualbox-amd64.7z downloads/kali/
# 0.3 Verify the archive against Kali's official SHA256 (value pinned in config/platform.yml):
$ sha256sum downloads/kali/kali-linux-2026.2-virtualbox-amd64.7z
#   → compare to the pinned checksum; STOP if it differs.
# 0.4 Remove the stale extracted copy (16 GB) — I will ASK before running this:
$ rm -rf KaliImage/CyberAI-Kali-Golden && rmdir KaliImage 2>/dev/null
```
**Verify:** `git status` clean of large files; sha256 matches; `VBoxManage list vms` no longer shows CyberAI-Kali-Golden. ✅

## Phase 1 — `./cyberai host-setup` (host; idempotent, re-runnable on any machine)
Installs/configures everything the host needs. Run once:
```
$ cp .cyberai.env.example .cyberai.env      # edit CYBERAI_ROOT if needed
$ ./cyberai host-setup
```
What it does, each step logged: preflight (VT-x, RAM, disk, KVM/VBox conflict) → apt install ansible-core(pipx), yq, jq,
sshpass, ufw → install pinned **Ollama** tarball (sha256-checked, not `curl|sh`) with a systemd override binding
`192.168.57.1:11434`, `OLLAMA_MODELS=$CYBERAI_ROOT/models/ollama`, keep-alive 5m, 1 model, ctx 8192, kv q8_0 →
create host-only net `192.168.57.1/24` (DHCP .100–.199) → ufw rules → `ollama pull qwen2.5:3b-instruct nomic-embed-text` →
write `~/.config/cyberai/secrets.env` (mode 600).
```
$ ./cyberai doctor      # PASS/FAIL table
```
**Verify:** doctor all-PASS: VBox ok, VT-x yes, host-only IP up, Ollama reachable on 192.168.57.1:11434 and **not** on 0.0.0.0, ufw active, disk/RAM ok. ✅

## Phase 2 — Create the base image from your `.7z` (host)
```
$ ./cyberai base import
```
Steps it runs (the "correct image process" for your file type):
```
$ 7z x downloads/kali/kali-linux-2026.2-virtualbox-amd64.7z -o"$CYBERAI_ROOT/images/base/"
$ VBoxManage registervm "$CYBERAI_ROOT/images/base/<name>.vbox"   # NOT 'import' — this is .vbox+.vdi
$ VBoxManage modifyvm <name> --name CyberAI-Kali-Base
# harden the shipped VM: no audio/USB, NAT localhost-reachable off, add NIC2 host-only "cyberai"
# clipboard/DnD come from config/platform.yml .vm_defaults (bidirectional) and are applied by
# lib/common.sh vm_apply_host_config on base import, golden build and every clone — not hardcoded here.
$ VBoxManage snapshot CyberAI-Kali-Base take base-clean
```
Then SSH is enabled headlessly via Guest Additions (no GUI needed):
`VBoxManage guestcontrol … run` as user `kali` (password `kali`, from the image description) enables `ssh`, installs the
host public key `~/.config/cyberai/id_ed25519.pub`, and grants passwordless sudo. SSH is used over NIC2.
**Verify:** `ssh -i ~/.config/cyberai/id_ed25519 kali@<nic2-ip> true` succeeds; snapshot `base-clean` exists. ✅

## Phase 3 — `./cyberai golden build` (host runs Ansible over SSH into the VM)
```
$ ./cyberai golden build
```
Full-clones Base → CyberAI-Kali-Golden → boots `--net nat` → runs `ansible-playbook playbooks/golden.yml` (roles:
common, hardening, security_tools, burp, ai_clients, ai_guest, rag_client, disable_sleep, mcp_servers) → cleans apt → shuts down → snapshots `golden-<date>`.
- **security_tools** reads `config/tools/*.yml`: Kali metapackages (`kali-linux-default`, `kali-tools-web`,
  `-information-gathering`, `-vulnerability`, `-fuzzing`, `-database`) + nmap ffuf gobuster nikto sqlmap wpscan
  metasploit-framework john hashcat wireshark tcpdump nuclei httpx amass dnsutils seclists + pinned pip/github/binaries.
- **burp** installs `burpsuite`, Jython jar, and pinned BApps (Turbo Intruder …) from `burp/extensions.lock.yml`
  (sha256-checked) into `~/.BurpSuite/bapps/`, then a templated `UserConfigCommunity.json` auto-loads them.
- **ai_clients** installs pinned opencode, `@anthropic-ai/claude-code`, `@openai/codex`; **ai_guest** installs a
  guest `cyberai` CLI (`ai run|list|pull|rm|opencode`) that talks to host Ollama over the AI plane; **rag_client** creates
  the client config dirs; **disable_sleep** keeps the VM awake; **mcp_servers** reads `config/mcp/servers.yml`, bakes the
  Playwright MCP + Chromium into `/opt/ms-playwright`, and writes all three client configs pointing at `192.168.57.1`
  (Ollama OpenAI-compat endpoint + MCP `cyberai-rag`).
```
$ ./cyberai golden verify
```
**Verify:** Ansible check-mode reports no changes; SSH smoke tests pass (`nmap --version`, burp jar present, extension
hashes match, `opencode --version`, `guest cyberai ai run OK`, `curl 192.168.57.1:11434/api/tags`). ✅

## Phase 4 — VM lifecycle, network, transfer, secrets (host) — ChatGPT "Milestone 1"
```
$ ./cyberai new work-01            # linked clone of golden-<date> + snapshot "clean"
$ ./cyberai start work-01 --net offline
$ ./cyberai stop work-01
$ ./cyberai destroy work-01        # refuses to touch Golden/Base
$ ./cyberai transfer in work-01 ./payload.txt   # transient read-only share, auto-removed
$ ./cyberai secrets push work-01 anthropic      # keys → VM tmpfs only
$ ./cyberai list
```
**Verify (isolation matrix):** create work-01→marker file→destroy; work-02 has no marker & golden snapshot unchanged;
in `offline`: `curl -m5 https://kali.org` fails, `curl 192.168.57.1:11434` works, `nc -zv 192.168.57.1 22` blocked;
in `nat`: internet works, host 127.0.0.1 unreachable. ✅

## Phase 5 — Local AI + benchmark (host) + guest `cyberai` CLI (inside clones)
```
$ ./cyberai ai list
$ ./cyberai ai bench qwen2.5:3b-instruct       # tokens/s, TTFT, RSS → docs/benchmarks/<date>.md
```
In a clone the golden image ships `/usr/local/bin/cyberai` so the *same command shape* works in Kali:
```
kali$ source /etc/profile.d/cyberai.sh
kali$ cyberai ai run "what does nmap -sV do?"       # streams from host Ollama, offline
kali$ cyberai ai opencode "what does nmap -sV do?"  # opencode wrapper → --model ollama/qwen2.5:3b-instruct
```
**Verify:** from a clone in `offline` mode, `cyberai ai run` answers using qwen2.5:3b-instruct via `192.168.57.1:11434`,
and `cyberai ai opencode` answers the same way through opencode. ✅

## Phase 6 — RAG service (host)
```
$ ./cyberai rag up                  # docker compose: qdrant + rag-api (REST + MCP /mcp)
$ ./cyberai rag update live         # NVD CVE 2.0, CISA KEV, GitHub Advisories, EPSS
$ ./cyberai rag update stable       # MITRE ATT&CK, CWE, OWASP WSTG/Cheatsheets
$ ./cyberai rag status
```
Chunks carry: source, url, **tier(1–4)**, kind(fundamental/vulnerability/technique/exploit-poc/advisory/personal),
dates, cve, cwe, attack_ids, **kev**, **epss**, confidence. Layers: `stable`, `live`, `personal`. Daily/weekly host
systemd-user timers refresh it. This is how "hackers in the wild" + low false positives is met: KEV = confirmed
exploitation, EPSS = likelihood, tier+date returned so the model separates evidence from inference.
**Verify:** `rag status` shows per-source counts + last-updated; from a clone, an MCP query "CVEs in KEV added this week" returns tiered, dated items; stopping the stack doesn't affect VMs. ✅

## Phase 7 — Release, portability, backup, SSD (host)
```
$ ./cyberai release                 # images/releases/CyberAI-Kali-<date>.ova + .sha256 + manifest.json
$ ./cyberai backup /media/$USER/HDD # rsync repo+config+releases+rag snapshot+model list
```
New machine: `git clone` → edit `.cyberai.env` → `./cyberai host-setup` → `./cyberai import <ova>` (fast) **or**
`base import && golden build` (from source) → `./cyberai rag restore`.
SSD later (`docs/runbook/ssd-migration.md`): stop VMs → backup → `VBoxManage movevm` → rsync data dirs → change `CYBERAI_ROOT` → `doctor`.
**Verify:** OVA imports into a scratch `CYBERAI_ROOT` (simulated second machine) and boots. ✅

## Phase 8 — Offline acceptance test (host cable unplugged)
Start a clone `--net offline` → `cyberai ai run` / `cyberai ai opencode` answer with qwen2.5:3b-instruct → RAG MCP query works → nmap a lab VM on the host-only net → destroy clone.
**Verify:** everything works except cloud models and RAG `live` refresh. ✅

### Out of scope now (documented, not built): mcp-kali-server tool layer with approval; a DVWA/Juice-Shop lab VM; Packer wrapping golden build; Windows-host PowerShell port.

---

## What I will do on approval, in order
1. **Phase 0 files:** rewrite `.gitignore`; add `.cyberai.env.example`; create the directory skeleton; move the `.7z` to `downloads/kali/`; save this plan to `docs/runbook/`. (Deleting the stale 16 GB `KaliImage/CyberAI-Kali-Golden/` — I ask first.)
2. **`cyberai` + `lib/*.sh`** — every subcommand above.
3. **`config/*` manifests** with pinned versions (I look up the current Ollama release, confirm the Kali `.7z` SHA256, BApp UUIDs, and client versions at write time).
4. **Ansible roles** (common, hardening, security_tools, burp, ai_clients, ai_guest, rag_client, disable_sleep, mcp_servers).
5. **`services/rag`** (compose, FastAPI + MCP api, ingest modules, tiered sources.yml).
6. **`docs/runbook/01–09`** — the per-phase beginner files, each command with expected output + Verify checkbox.
7. **Static checks here** (no system changes): `bash -n`+`shellcheck` on scripts, `ansible-playbook --syntax-check`, `docker compose config`, `./cyberai doctor` dry-run. Then you run Phase 1 onward.

## End-to-end verification
`doctor` all PASS → `base import` → `golden build`+`verify` → Phase 4 isolation matrix → `ai bench` → `rag update` + MCP query from a clone → `release`+`import` into scratch root → offline acceptance test.
