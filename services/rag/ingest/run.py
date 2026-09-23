"""CyberAI RAG ingestion — layer-aware, tier-tagged, incremental.

Design notes (why it's built this way):
- Each source declares a trust *tier* and a *layer* (stable/live/personal) in sources.yml.
- 'live' sources (NVD, CISA KEV, GitHub advisories, EPSS, nuclei) are refreshed daily or hourly;
  'stable' (OWASP/CWE/ATT&CK/Payloads) on a slower cadence. This keeps the KB current without
  rebuilding any VM.
- Every chunk stores rich metadata (tier, kind, cve, cwe, kev, epss, attack_ids, dates) so
  retrieval can filter by authority + freshness and the model can cite provenance
  -> fewer false positives.
- Incremental: each source tracks a per-document key -> version (updated_at or content hash)
  in a state file on the /state volume. Unchanged docs are skipped, so re-runs only embed and
  upsert new/changed content.

All fetchers in sources.yml are implemented (no more TODO stubs):
  cisa_kev / epss / nvd_cve / github_advisories / mitre_attack / cwe /
  owasp_wstg / owasp_cheatsheets / nuclei_templates / payloadsallthethings / personal_notes
"""
import argparse
import csv
import datetime as dt
import gzip
import hashlib
import io
import json
import os
import pathlib
import re
import shutil
import subprocess
import time
import zipfile
import xml.etree.ElementTree as ET

import httpx
import yaml
from qdrant_client import QdrantClient
from qdrant_client.models import Distance, VectorParams, PointStruct

QDRANT = os.environ.get("QDRANT_URL", "http://qdrant:6333")
OLLAMA = os.environ.get("OLLAMA_URL", "http://192.168.57.1:11434")
EMBED_MODEL = os.environ.get("EMBED_MODEL", "nomic-embed-text")
STATE_FILE = os.environ.get("CYBERAI_STATE_FILE", "/state/cyberai_rag_state.json")
GIT_CACHE = os.environ.get("CYBERAI_GIT_CACHE", "/state/git-cache")
SOURCES = yaml.safe_load(open(pathlib.Path(__file__).parent.parent / "sources.yml"))["sources"] \
    if (pathlib.Path(__file__).parent.parent / "sources.yml").exists() else \
    yaml.safe_load(open("/app/sources.yml"))["sources"]

# Payload keys we forward into Qdrant (anything else on a doc is dropped).
PAYLOAD_KEYS = ("text", "source", "tier", "kind", "url", "cve", "cwe", "kev", "epss",
                "attack_ids", "severity", "vendor", "product",
                "published_at", "updated_at", "confidence")
GIT_SOURCES = {"owasp_wstg", "owasp_cheatsheets", "nuclei_templates", "payloadsallthethings"}


def now_iso() -> str:
    return dt.datetime.now(dt.UTC).isoformat()


def utcnow() -> dt.datetime:
    return dt.datetime.now(dt.UTC)


# ── shared HTTP + embed helpers ──────────────────────────────

def http_client() -> httpx.Client:
    return httpx.Client(timeout=120, follow_redirects=True,
                        headers={"User-Agent": "cyberai-rag/0.1 (authorized security lab)"})


def embed_batch(texts: list[str], batch: int = 32) -> list[list[float]]:
    """Embed texts in batches via Ollama /api/embed (falls back to /api/embeddings)."""
    out: list[list[float]] = []
    with httpx.Client(timeout=300) as cl:
        for i in range(0, len(texts), batch):
            part = texts[i:i + batch]
            try:
                r = cl.post(f"{OLLAMA}/api/embed", json={"model": EMBED_MODEL, "input": part, "truncate": True})
                r.raise_for_status()
                embs = r.json().get("embeddings")
                if embs and len(embs) == len(part):
                    out.extend(embs)
                    continue
            except Exception:
                pass
            for t in part:
                r = cl.post(f"{OLLAMA}/api/embeddings", json={"model": EMBED_MODEL, "prompt": t[:8000]})
                r.raise_for_status()
                out.append(r.json()["embedding"])
    return out


def ensure_collection(qc: QdrantClient, name: str, dim: int):
    try:
        qc.get_collection(name)
    except Exception:
        qc.create_collection(name, vectors_config=VectorParams(size=dim, distance=Distance.COSINE))


def stable_id(key: str) -> int:
    """Deterministic point id (previous code used hash() -> unstable across processes)."""
    return int(hashlib.sha1(str(key).encode()).hexdigest()[:15], 16)


def _payload(d: dict) -> dict:
    d.setdefault("retrieved_at", now_iso())
    return {k: d[k] for k in PAYLOAD_KEYS if d.get(k) is not None}


def ingest_docs(qc: QdrantClient, state: dict, src: dict, docs: list[dict]):
    """Batch-embed + upsert only docs whose version changed vs the state's 'seen' map."""
    if not docs:
        print("  no docs")
        return
    rec = state["sources"].setdefault(src["id"], {"seen": {}})
    seen = rec.setdefault("seen", {})
    fresh = [d for d in docs if seen.get(d["key"]) != d["ver"]]
    if not fresh:
        print(f"  {len(docs)} docs unchanged - skipping")
        return
    texts = [d["text"] for d in fresh]
    embs = embed_batch(texts)
    if len(embs) != len(texts):
        raise RuntimeError(f"embed count mismatch: got {len(embs)} for {len(texts)} texts")
    dim = len(embs[0])
    ensure_collection(qc, src["layer"], dim)
    points = [PointStruct(id=stable_id(f"{d['source']}|{d['key']}"), vector=v, payload=_payload(d))
              for d, v in zip(fresh, embs)]
    qc.upsert(collection_name=src["layer"], points=points)
    for d in fresh:
        seen[d["key"]] = d["ver"]
    print(f"  upserted {len(points)} -> {src['layer']} ({len(docs)} total for source)")


def chunk_text(text: str, max_len: int = 4000, overlap: int = 200) -> list[str]:
    if len(text) <= max_len:
        return [text]
    out, i = [], 0
    while i < len(text):
        out.append(text[i:i + max_len])
        i += max_len - overlap
    return out


# ── JSON/CSV fetchers ────────────────────────────────────────

def _base_doc(src: dict) -> dict:
    return {"source": src["id"], "tier": src["tier"], "kind": src["kind"], "confidence": "high"}


def fetch_kev(src) -> list[dict]:
    with http_client() as cl:
        data = cl.get(src["url"]).raise_for_status().json()
    out = []
    for v in data.get("vulnerabilities", []):
        d = _base_doc(src)
        d.update(key=v.get("cveID"), ver=v.get("dateAdded", ""),
                 text=f"{v.get('cveID')} {v.get('vulnerabilityName')}: {v.get('shortDescription')} "
                      f"Action: {v.get('requiredAction')}",
                 cve=v.get("cveID"), kev=True, vendor=v.get("vendorProject"), product=v.get("product"),
                 url="https://www.cisa.gov/known-exploited-vulnerabilities-catalog",
                 published_at=v.get("dateAdded"), updated_at=v.get("dateAdded"))
        out.append(d)
    return out[: int(src.get("cap", 5000))]


def fetch_epss(src) -> dict:
    with http_client() as cl:
        raw = gzip.decompress(cl.get(src["url"]).raise_for_status().content).decode()
    scores = {}
    for row in csv.reader(io.StringIO(raw)):
        if len(row) >= 2 and row[0].startswith("CVE"):
            scores[row[0]] = row[1]
    return scores  # merged into CVE docs by the caller


def fetch_nvd(src) -> list[dict]:
    base = src["api"]
    days = int(os.environ.get("RAG_NVD_WINDOW_DAYS", src.get("window_days", 21)))
    fmt = "%Y-%m-%dT%H:%M:%S.000"
    end = utcnow().strftime(fmt)
    start = (utcnow() - dt.timedelta(days=days)).strftime(fmt)
    out, start_idx, total = [], 0, None
    with http_client() as cl:
        while total is None or start_idx < total:
            params = {"resultsPerPage": 2000, "startIndex": start_idx,
                      "lastModStartDate": start, "lastModEndDate": end}
            r = cl.get(base, params=params)
            r.raise_for_status()
            data = r.json()
            total = data.get("totalResults", 0)
            items = data.get("vulnerabilities", [])
            for v in items:
                c = v["cve"]
                cid = c["id"]
                desc = next((x["value"] for x in c.get("descriptions", []) if x.get("lang") == "en"), "")
                m = (c.get("metrics") or {}).get("cvssMetricV31") or [{}]
                cv = m[0].get("cvssData", {})
                score = cv.get("baseScore")
                sev = m[0].get("baseSeverity")
                refs = " ".join(x.get("url", "") for x in c.get("references", [])[:5])
                text = f"{cid}: {desc}"
                if score is not None:
                    text += f" (CVSS {score} {sev})"
                if refs:
                    text += f" References: {refs}"
                d = _base_doc(src)
                d.update(key=cid, ver=c.get("lastModified", ""), text=text,
                         cve=cid, url=f"https://nvd.nist.gov/vuln/detail/{cid}",
                         updated_at=c.get("lastModified", ""))
                out.append(d)
                if len(out) >= int(src.get("cap", 1500)):
                    return out
            start_idx += len(items)
            if not items:
                break
            time.sleep(float(src.get("rate_limit", 6)))
    return out


def fetch_github(src) -> list[dict]:
    out, seen_keys = [], set()
    with http_client() as cl:
        for page in range(1, int(src.get("cap_pages", 12)) + 1):
            r = cl.get(src["api"], params={"per_page": 100, "page": page})
            if r.status_code in (403, 429):
                print("  github rate-limited - partial ingest")
                break
            r.raise_for_status()
            items = r.json()
            if not items:
                break
            new_items = [a for a in items if a.get("ghsa_id") not in seen_keys]
            for a in new_items:
                ghsa = a.get("ghsa_id")
                seen_keys.add(ghsa)
                cve = a.get("cve_id") or ""
                d = _base_doc(src)
                d.update(key=ghsa, ver=a.get("updated_at", ""),
                         text=f"{a.get('summary','')} {a.get('description','')} "
                              f"[severity={a.get('severity')}]",
                         cve=cve.upper() or None, severity=a.get("severity"),
                         url=a.get("html_url"), published_at=a.get("published_at"),
                         updated_at=a.get("updated_at"))
                out.append(d)
            if len(new_items) < len(items) or len(items) < 100:
                break
    return out


# ── document-ish fetchers (STIX / XML) ───────────────────────

def _localname(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def fetch_attack(src) -> list[dict]:
    with http_client() as cl:
        data = cl.get(src["url"]).raise_for_status().json()
    out = []
    for obj in data.get("objects", []):
        if obj.get("type") != "attack-pattern":
            continue
        name = obj.get("name", "")
        desc = obj.get("description", "")
        refs = [e.get("url") for e in obj.get("external_references", []) if e.get("url")]
        ext_ids = [e.get("external_id") for e in obj.get("external_references", [])
                   if str(e.get("external_id", "")).startswith("T")]
        text = f"ATT&CK technique {name}: {desc}"
        if refs:
            text += " References: " + " ".join(refs[:5])
        d = _base_doc(src)
        d.update(key=obj.get("id") or name, ver=obj.get("modified", ""), text=text,
                 attack_ids=ext_ids, url="https://attack.mitre.org", updated_at=obj.get("modified", ""))
        out.append(d)
        if len(out) >= int(src.get("cap", 1500)):
            break
    return out


def fetch_cwe(src) -> list[dict]:
    with http_client() as cl:
        z = zipfile.ZipFile(io.BytesIO(cl.get(src["url"]).raise_for_status().content))
    xml_name = next(n for n in z.namelist() if n.endswith(".xml"))
    root = ET.fromstring(z.read(xml_name))
    out = []
    for node in root.iter():
        if _localname(node.tag) != "Weakness":
            continue
        wid = node.attrib.get("ID")
        name = node.attrib.get("Name", "")
        desc = next((el.text or "" for el in node.iter() if _localname(el.tag) in ("Description",)
                     and el.text), "")
        ext = "\n".join(el.text or "" for el in node.iter()
                        if _localname(el.tag) == "Extended_Description" and el.text)
        text = f"CWE-{wid} {name}: {desc}".strip()
        if ext:
            text += f"\n{ext}"
        for ci, chunk in enumerate(chunk_text(text, src.get("chunk", 4000))):
            d = _base_doc(src)
            d.update(key=f"CWE-{wid}", ver=hashlib.sha1(chunk.encode()).hexdigest(),
                     text=chunk, cwe=f"CWE-{wid}",
                     url=f"https://cwe.mitre.org/data/definitions/{wid}.html",
                     updated_at=now_iso())
            out.append(d)
        if len(out) >= int(src.get("cap", 1000)):
            break
    return out


# ── git repo chunking ────────────────────────────────────────

def git_clone(url: str, name: str) -> pathlib.Path:
    dest = pathlib.Path(GIT_CACHE) / name
    dest.parent.mkdir(parents=True, exist_ok=True)
    if (dest / ".git").exists():
        subprocess.run(["git", "-C", str(dest), "pull", "--quiet", "--ff-only"],
                       check=False, capture_output=True)
    elif shutil.which("git"):
        subprocess.run(["git", "clone", "--quiet", "--depth", "1", url, str(dest)],
                       check=True, capture_output=True)
    else:
        raise RuntimeError("git is required to ingest repo sources")
    return dest


def chunk_repo(src) -> list[dict]:
    repo = git_clone(src["git"], src["id"])
    exts = tuple(src.get("exts", [".md", ".markdown"]))
    max_bytes = int(src.get("max_bytes", 200000))
    cap = int(src.get("cap", 400))
    out = []
    for p in sorted(repo.rglob("*")):
        if not p.is_file() or p.suffix not in exts:
            continue
        if any(part.startswith(".") for part in p.parts):
            continue
        rel = str(p.relative_to(repo))
        if rel.lower().endswith(("readme.md",)) and len(list(repo.rglob("*"))) > 50:
            continue  # skip repo README boilerplate
        try:
            text = p.read_text(errors="ignore")[:max_bytes]
        except Exception:
            continue
        if not text.strip():
            continue
        for ci, chunk in enumerate(chunk_text(text, src.get("chunk", 4000))):
            key = f"{src['id']}:{rel}:{ci}"
            d = _base_doc(src)
            d.update(key=key, ver=hashlib.sha1(chunk.encode()).hexdigest(), text=chunk,
                     url=f"{src['git'].rstrip('/')}/blob/master/{rel}", updated_at=now_iso())
            out.append(d)
            if len(out) >= cap:
                return out
    return out


def fetch_personal(src) -> list[dict]:
    base = pathlib.Path(src["path"])
    out = []
    if not base.exists():
        return out
    for p in base.rglob("*.md"):
        text = p.read_text(errors="ignore")
        d = _base_doc(src)
        d.update(key=f"personal:{p}", ver=hashlib.sha1(text.encode()).hexdigest(),
                 text=text, url=str(p), updated_at=now_iso())
        out.append(d)
    return out


FETCHERS = {
    "cisa_kev": fetch_kev,
    "nvd_cve": fetch_nvd,
    "github_advisories": fetch_github,
    "mitre_attack": fetch_attack,
    "cwe": fetch_cwe,
}


# ── orchestration ────────────────────────────────────────────

def load_state() -> dict:
    try:
        return json.loads(pathlib.Path(STATE_FILE).read_text())
    except Exception:
        return {"sources": {}}


def save_state(state: dict):
    pathlib.Path(STATE_FILE).parent.mkdir(parents=True, exist_ok=True)
    pathlib.Path(STATE_FILE).write_text(json.dumps(state, indent=2))


def run(layer: str, only: str | None = None):
    qc = QdrantClient(url=QDRANT)
    state = load_state()
    state.setdefault("sources", {})
    selected = [s for s in SOURCES if layer in ("all", s["layer"])]
    if only:
        selected = [s for s in selected if s["id"] == only]

    epss = {}
    for s in selected:
        if s["id"] == "epss":
            try:
                epss = fetch_epss(s)
                print(f"epss: {len(epss)} scores")
            except Exception as e:
                print(f"epss failed: {e}")

    for s in selected:
        if s["id"] == "epss":
            continue
        print(f"[{s['layer']}] {s['id']} (tier {s['tier']})")
        try:
            if s["id"] in GIT_SOURCES:
                docs = chunk_repo(s)
            elif s["id"] in FETCHERS:
                docs = FETCHERS[s["id"]](s)
            else:
                docs = fetch_personal(s)
            for d in docs:
                if d.get("cve"):
                    d["epss"] = epss.get(d["cve"])
            ingest_docs(qc, state, s, docs)
            state["sources"].setdefault(s["id"], {})["last_run"] = now_iso()
            save_state(state)
        except Exception as e:
            print(f"  ERROR {s['id']}: {e}")
    save_state(state)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--layer", default="all", choices=["all", "stable", "live", "personal"])
    ap.add_argument("--only", help="ingest a single source id (e.g. nvd_cve)")
    ap.add_argument("--qdrant")
    ap.add_argument("--embed")
    a = ap.parse_args()
    if a.qdrant:
        QDRANT = a.qdrant
    if a.embed:
        OLLAMA = a.embed
    run(a.layer, a.only)