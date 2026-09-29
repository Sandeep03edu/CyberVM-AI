# Phase 5 — Local AI + benchmark

**Goal:** confirm host Ollama serves models to clones, and measure CPU speed.

## 5.1 Manage models (on the host)
```
$ ./cybervm ai list
$ ./cybervm ai pull qwen2.5:3b-instruct      # or edit config/ai/models.yml then: ./cybervm ai pull
$ ./cybervm ai rm <model>
```

## 5.1b Run a prompt (quick chat from the host)
```
$ ./cybervm ai run "what does nmap -sV do?"              # default model (qwen2.5:3b-instruct)
$ ./cybervm ai run qwen2.5:3b-instruct "what does nmap -sV do?"   # explicit model
```
A leading `model:tag` argument selects the model; otherwise `$CYBERVM_AI_MODEL` (default
`qwen2.5:3b-instruct`) is used. The reply streams to your terminal and qwen3 "thinking" is disabled for speed.
CPU-only inference is slow for 8B models — pull a smaller one (e.g. `qwen3:1.7b`, `qwen2.5:3b`) for
interactive use.

## 5.2 Benchmark (your i5-13600K, CPU-only)
```
$ ./cybervm ai bench qwen2.5:3b-instruct
```
Writes `docs/benchmarks/<date>-qwen3_8b.md` with tokens/s, time-to-first-token and totals for a
fixed prompt set. To compare P-core-only vs all threads, temporarily set `OLLAMA_NUM_THREAD` in the
ollama systemd override and re-run.

## 5.2b Tune / untune for running alongside a VM
CPU-only inference is bursty and can briefly grab every core. To keep a VM running in parallel
responsive, `tune` installs a **reversible systemd drop-in** that caps and de-prioritises Ollama;
`untune` removes it and restores everything.

### Tune (apply)
```
$ ./cybervm ai tune                      # coexistence defaults (recommended)
$ ./cybervm ai tune --governor           # also set CPU governor to performance (faster; more heat)
$ ./cybervm ai tune --swappiness 10      # also lower swappiness to avoid swap
$ ./cybervm ai tune --cpu-quota 400 --keepalive 5m --context 2048   # custom
```
Defaults applied via `/etc/systemd/system/ollama.service.d/cybervm-llm-tune.conf`:
`CPUQuota=500%` (Ollama may use at most ~5 of your 20 threads, ever), `Nice=10` (the VM wins the
scheduler), `OLLAMA_KEEP_ALIVE=2m` (frees ~2 GB when idle), `OLLAMA_CONTEXT_LENGTH=4096`.
Optional `--governor` / `--swappiness` record their prior value in `config/ai/.llm-tune.state`
so `untune` can restore them.

### Untune (revert)
```
$ ./cybervm ai untune
```
Reverting is **deletion, not restoration**: the tuning lives only in the drop-in file, which layers
on top of the base `ollama.service` (written by `host-setup`) and never edits it. `untune` deletes
the drop-in and reloads, so systemd falls back to the base unit exactly — `CPUQuota` disappears
(unlimited), `Nice` returns to `0`, and the base `OLLAMA_KEEP_ALIVE=5m` / `OLLAMA_CONTEXT_LENGTH=8192`
apply again. It then restores the governor/swappiness from the state file (if you set them) and
deletes the state file. Safe to run even if you never tuned.

### Verify tuned vs untuned
```
$ systemctl show ollama -p CPUQuota,Nice,Environment
```
- **Tuned:** `CPUQuota=500%` (or `CPUQuotaPerSecUSec=5s`), `Nice=10`, and `OLLAMA_KEEP_ALIVE=2m`
  + `OLLAMA_CONTEXT_LENGTH=4096` present in `Environment`.
- **Untuned:** `CPUQuota=` empty / `infinity`, `Nice=0`, and `Environment` shows the base
  `OLLAMA_KEEP_ALIVE=5m` + `OLLAMA_CONTEXT_LENGTH=8192`.
```
$ ls /etc/systemd/system/ollama.service.d/cybervm-llm-tune.conf   # exists only when tuned
$ cat /proc/sys/vm/swappiness                                     # if you used --swappiness
$ cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor       # if you used --governor
```
Watch coexistence while a VM runs: `watch -n2 'free -h | grep -E "Mem|Swap"'` — keep `Swap` low.

## 5.3 Guest AI CLI (inside a clone) — `cybervm ai run` in Kali
The golden image now ships a **guest-side `cybervm`** at `/usr/local/bin/cybervm`, so you run the *same
command shape* inside Kali instead of only on the host. It talks to host Ollama over the AI plane and never
needs internet. Subcommands (subset of the host CLI that makes sense in-VM):

- `cybervm ai run [model:tag] <prompt>` — stream a reply from host Ollama (default `qwen2.5:3b-instruct`)
- `cybervm ai list` — models on the host
- `cybervm ai pull <model>` — pull a model onto the host
- `cybervm ai rm <model>` — delete a model from the host
- `cybervm ai opencode [model:tag] <task>` — `opencode run "<task>" --model ollama/<model>`

> The guest `cybervm` and the host `./cybervm` are **different binaries**. Orchestration
> (golden build, `bench`, `tune`, RAG, transfer) stays host-only. If a clone predates this
> golden version it won't have the guest CLI — rebuild golden (`./cybervm golden build`) and
> recreate the clone.

## 5.3a Verify (from inside a clone)
```
$ ./cybervm start work-02 --net offline
kali$ source /etc/profile.d/cybervm.sh
kali$ cybervm ai run "Summarize what nmap -sV does"        # default model (qwen2.5:3b-instruct)
kali$ cybervm ai run qwen2.5:3b-instruct "what does nmap -sV do?"   # explicit model
kali$ cybervm ai opencode "Summarize what nmap -sV does"   # convenience opencode wrapper
```
✅ **Pass gate:** you get an answer with no internet — it came from host Ollama over the AI plane.
A leading `model:tag` argument selects the model; otherwise `$CYBERVM_AI_MODEL` (default
`qwen2.5:3b-instruct`) is used. The reply streams to your terminal.
