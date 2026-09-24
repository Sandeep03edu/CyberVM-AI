# lib/pins.sh — verify/refresh external-download pins so a stale pin can never
# kill a long build half-way. Currently covers Burp BApp extensions.
#
#   cyberai pins check   [burp]  — compare lock serials vs live store, exit 0/1
#   cyberai pins refresh [burp]  — re-pin drifted/serial+hash to current, no-op if fresh
#
# Lock: config/burp/extensions.lock.yml — each BApp pins `serial` + `sha256`;
# url is the serial-versioned PortSwigger download path .../download/<uuid>/<serial>.

pins_dispatch() { local sub="${1:-}"; shift || true
  case "$sub" in
    check|refresh) _pins_run "$sub" "${1:-burp}" ;;
    *) die "usage: cyberai pins check|refresh <burp>" ;;
  esac; }

_pins_lock() { echo "$CYBERAI_HOME/config/burp/extensions.lock.yml"; }

# Compare each BApp's pinned serial against the live storefront page and, when
# refreshing, re-download + re-hash the drifted ones and rewrite the lock.
_pins_run() { # <check|refresh> <scope>
  local mode="$1" scope="$2"
  [ "$scope" = burp ] || die "usage: cyberai pins $mode <burp>"
  local lock; lock="$(_pins_lock)"
  [ -f "$lock" ] || die "no such lock file: $lock"
  log "cyberai pins $mode (burp) — querying portswigger.net BApp store…"
  local tmp; tmp=$(mktemp)
  python3 - "$mode" "$lock" <<'PY'
import sys, re, hashlib, urllib.request, yaml
mode, lock = sys.argv[1], sys.argv[2]
cfg = yaml.safe_load(open(lock))
rows, problems = [], []
for idx, ext in enumerate(cfg["extensions"]):
    name = ext["name"]
    m = re.search(r"bapps/download/([a-f0-9]{32})", ext.get("url",""))
    if not m:
        problems.append((idx, name, "url has no bapp uuid")); continue
    uuid = m.group(1)
    req = urllib.request.Request(f"https://portswigger.net/bappstore/{uuid}",
                                 headers={"User-Agent": "Mozilla/5.0"})
    try:
        html = urllib.request.urlopen(req, timeout=20).read().decode("utf-8","ignore")
    except Exception as ex:
        problems.append((idx, name, f"store page error: {ex}"))
        continue
    cur = re.search(r"bapps/download/" + uuid + r"/(\d+)", html)
    cur = cur.group(1) if cur else ""
    if not cur:
        problems.append((idx, name, "no current serial on store page")); continue
    status = "ok" if str(ext.get("serial","")) == cur else "drift"
    rows.append({"i": idx, "name": name, "lock": str(ext.get("serial","")), "cur": cur,
                 "status": status, "uuid": uuid})

if mode == "check":
    for r in rows:
        flag = "OK" if r["status"]=="ok" else ("DRIFT" if r["status"]=="drift" else "PROBLEM")
        print(f"  {flag:<7} {r['name']:<24} lock={r['lock']:<4} current={r['cur']}")
    for (i,n,msg) in problems:
        print(f"  PROBLEM {n}: {msg}")
    drift = [r for r in rows if r["status"]!="ok"] or problems
    print(f"SUMMARY: {sum(1 for r in rows if r['status']=='ok')}/{len(rows)} fresh, "
          f"{sum(1 for r in rows if r['status']!='ok')} drifted, {len(problems)} problems")
    sys.exit(1 if drift else 0)
else:
    changed = 0
    updates = {}  # name -> (serial, url, sha)
    for r in rows:
        if r["status"] == "ok":
            print(f"  unchanged {r['name']:<24} serial={r['cur']}")
            continue
        url = f"https://portswigger.net/bappstore/bapps/download/{r['uuid']}/{r['cur']}"
        try:
            data = urllib.request.urlopen(url, timeout=60).read()
            sha = hashlib.sha256(data).hexdigest()
        except Exception as ex:
            problems.append((r["i"], r["name"], f"download error: {ex}"))
            continue
        print(f"  re-pin    {r['name']:<24} serial {r['lock']} -> {r['cur']}  "
              f"sha256 {sha[:12]}…")
        updates[r["name"]] = (r["cur"], url, sha)
        changed += 1
    if changed:
        lines = open(lock).read().splitlines(keepends=True)
        out, cur_name, in_block = [], None, False
        for ln in lines:
            m = re.match(r'^(\s*)-\s*name:\s*"([^"]+)"', ln)
            if m:
                cur_name, in_block = m.group(2), True
                out.append(ln); continue
            if ln.rstrip() == "" or cur_name is None:
                out.append(ln); continue
            m2 = re.match(r'^(\s*)-\s*(?:name|type):', ln)
            if m2:  # new entry started
                in_block = False
            if in_block and cur_name in updates:
                new_serial, new_url, new_sha = updates[cur_name]
                stripped = ln.lstrip()
                indent = ln[:len(ln) - len(ln.lstrip())]
                if stripped.startswith("serial:"):
                    out.append(f"{indent}serial: {new_serial}\n"); continue
                if stripped.startswith("url:"):
                    out.append(f'{indent}url: "{new_url}"\n'); continue
                if stripped.startswith("sha256:"):
                    out.append(f'{indent}sha256: "{new_sha}"\n'); continue
            out.append(ln)
        open(lock, "w").writelines(out)
        print(f"REWRITE: {changed} extension(s) re-pinned in {lock}")
    else:
        print("nothing to refresh")
    if problems:
        print(f"PROBLEMS: {len(problems)} — left for manual fix:")
        for (i,n,msg) in problems: print(f"  {n}: {msg}")
        sys.exit(1)
PY
  local rc=$?
  rm -f "$tmp"
  if [ "$mode" = check ]; then
    if [ "$rc" -eq 0 ]; then ok "All Burp extension pins are current."
    else warn "Stale Burp extension pins. Run: ./cyberai pins refresh burp"; fi
  elif [ "$mode" = refresh ] && [ "$rc" -eq 0 ]; then
    ok "Burp extension pins refreshed."
  fi
  return "$rc"
}