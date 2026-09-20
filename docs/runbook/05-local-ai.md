# Phase 5 — Local AI + benchmark

**Goal:** confirm host Ollama serves models to clones, and measure CPU speed.

## 5.1 Manage models (on the host)
```
$ ./cyberai ai list
$ ./cyberai ai pull qwen3:8b      # or edit config/ai/models.yml then: ./cyberai ai pull
$ ./cyberai ai rm <model>
```

## 5.2 Benchmark (your i5-13600K, CPU-only)
```
$ ./cyberai ai bench qwen3:8b
```
Writes `docs/benchmarks/<date>-qwen3_8b.md` with tokens/s, time-to-first-token and totals for a
fixed prompt set. To compare P-core-only vs all threads, temporarily set `OLLAMA_NUM_THREAD` in the
ollama systemd override and re-run.

## 5.3 Verify (from inside a clone)
```
$ ./cyberai start work-02 --net offline
kali$ source /etc/profile.d/cyberai.sh
kali$ opencode run "Summarize what nmap -sV does" --model ollama/qwen3:8b
```
✅ **Pass gate:** you get an answer with no internet — it came from host Ollama over the AI plane.
