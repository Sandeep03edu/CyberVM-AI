"""CyberAI RAG ingestion — layer-aware, tier-tagged, incremental.

Design notes (why it's built this way):
- Each source declares a trust *tier* and a *layer* (stable/live/personal) in sources.yml.
- 'live' sources (NVD, CISA KEV, GitHub advisories, EPSS) are refreshed daily; 'stable'
  (OWASP/CWE/ATT&CK) weekly. This is how the KB stays current without rebuilding any VM.
- Every chunk stores rich metadata (cve, cwe, kev, epss, dates) so retrieval can filter by
  authority + freshness and the model can cite provenance -> fewer false positives.

This is a working skeleton: fetchers for KEV/EPSS/personal are implemented; NVD/ATT&CK/git
sources have stubs marked TODO with the exact endpoint + parse strategy.
"""
import argparse
import gzip
import io
import os
import csv
import json
import pathlib
import datetime as dt

import httpx
import yaml
from qdrant_client import QdrantClient
from qdrant_client.models import Distance, VectorParams, PointStruct

QDRANT = os.environ.get("QDRANT_URL", "http://qdrant:6333")
OLLAMA = os.environ.get("OLLAMA_URL", "http://192.168.57.1:11434")
EMBED_MODEL = os.environ.get("EMBED_MODEL", "nomic-embed-text")
SOURCES = yaml.safe_load(open(pathlib.Path(__file__).parent.parent / "sources.yml"))["sources"] \
    if (pathlib.Path(__file__).parent.parent / "sources.yml").exists() else \
    yaml.safe_load(open("/app/sources.yml"))["sources"]
NOW = dt.datetime.utcnow().isoformat()


def embed(text: str) -> list[float]:
    r = httpx.post(f"{OLLAMA}/api/embeddings",
                   json={"model": EMBED_MODEL, "prompt": text[:8000]}, timeout=120)
    r.raise_for_status()
    return r.json()["embedding"]


def ensure_collection(qc: QdrantClient, name: str, dim: int):
    try:
        qc.get_collection(name)
    except Exception:
        qc.create_collection(name, vectors_config=VectorParams(size=dim, distance=Distance.COSINE))


def upsert(qc: QdrantClient, layer: str, docs: list[dict]):
    if not docs:
        return
    dim = len(embed(docs[0]["text"]))
    ensure_collection(qc, layer, dim)
    points = []
    for i, d in enumerate(docs):
        d.setdefault("retrieved_at", NOW)
        points.append(PointStruct(id=abs(hash((d.get("source"), d.get("cve"), i))) % (10**15),
                                  vector=embed(d["text"]), payload=d))
    qc.upsert(collection_name=layer, points=points)
    print(f"  upserted {len(points)} -> {layer}")


# ── fetchers ────────────────────────────────────────────────
def fetch_kev(src) -> list[dict]:
    r = httpx.get(src["url"], timeout=120); r.raise_for_status()
    data = r.json()
    out = []
    for v in data.get("vulnerabilities", []):
        out.append({
            "text": f"{v.get('cveID')} {v.get('vulnerabilityName')}: {v.get('shortDescription')} "
                    f"Action: {v.get('requiredAction')}",
            "source": "cisa_kev", "tier": src["tier"], "kind": src["kind"],
            "cve": v.get("cveID"), "kev": True, "vendor": v.get("vendorProject"),
            "product": v.get("product"), "url": "https://www.cisa.gov/known-exploited-vulnerabilities-catalog",
            "published_at": v.get("dateAdded"), "updated_at": v.get("dateAdded"), "confidence": "high"})
    return out


def fetch_epss(src) -> dict:
    r = httpx.get(src["url"], timeout=120); r.raise_for_status()
    raw = gzip.decompress(r.content).decode()
    scores = {}
    for row in csv.reader(io.StringIO(raw)):
        if len(row) >= 2 and row[0].startswith("CVE"):
            scores[row[0]] = row[1]
    return scores  # merged into CVE docs by the caller


def fetch_personal(src) -> list[dict]:
    base = pathlib.Path(src["path"])
    out = []
    if base.exists():
        for p in base.rglob("*.md"):
            out.append({"text": p.read_text(errors="ignore"), "source": "personal",
                        "tier": 1, "kind": "personal", "url": str(p),
                        "updated_at": NOW, "confidence": "high"})
    return out


# TODO fetchers (endpoint + strategy documented for the implementer):
#   nvd_cve: GET api with ?lastModStartDate=<last>&resultsPerPage=2000 paginated; store descriptions,
#            merge EPSS score + KEV flag by CVE id. Respect the NVD rate limit (6s w/o key).
#   github_advisories: GET api.github.com/advisories?per_page=100 (paginate via Link header).
#   mitre_attack / cwe / owasp / nuclei / payloads: git clone (or zip) then chunk markdown/JSON.

def run(layer: str):
    qc = QdrantClient(url=QDRANT)
    selected = [s for s in SOURCES if layer in ("all", s["layer"])]
    epss = {}
    # pull EPSS first so CVE docs can be enriched
    for s in selected:
        if s["id"] == "epss":
            try:
                epss = fetch_epss(s); print(f"epss: {len(epss)} scores")
            except Exception as e:
                print(f"epss failed: {e}")
    for s in selected:
        print(f"[{s['layer']}] {s['id']} (tier {s['tier']})")
        try:
            if s["id"] == "cisa_kev":
                docs = fetch_kev(s)
                for d in docs:
                    d["epss"] = epss.get(d.get("cve"))
                upsert(qc, s["layer"], docs)
            elif s["id"] == "personal_notes":
                upsert(qc, s["layer"], fetch_personal(s))
            elif s["id"] == "epss":
                pass  # handled above
            else:
                print(f"  TODO fetcher for {s['id']} — see notes in run.py")
        except Exception as e:
            print(f"  ERROR {s['id']}: {e}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--layer", default="all", choices=["all", "stable", "live", "personal"])
    ap.add_argument("--qdrant"); ap.add_argument("--embed")
    a = ap.parse_args()
    if a.qdrant: QDRANT = a.qdrant
    if a.embed: OLLAMA = a.embed
    run(a.layer)
