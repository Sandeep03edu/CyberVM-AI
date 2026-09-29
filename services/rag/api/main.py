"""CyberVM RAG API — REST search + MCP endpoint over a Qdrant vector store.

Metadata-aware: every hit carries tier (1-4), kind, dates, cve/cwe, kev, epss so the
model can separate authoritative evidence from unverified inference (low false positives).
"""
import os
import httpx
from fastapi import FastAPI
from pydantic import BaseModel
from qdrant_client import QdrantClient

QDRANT_URL = os.environ.get("QDRANT_URL", "http://qdrant:6333")
OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://192.168.57.1:11434")
EMBED_MODEL = os.environ.get("EMBED_MODEL", "nomic-embed-text")
COLLECTIONS = ["stable", "live", "personal"]

app = FastAPI(title="CyberVM RAG")
qc = QdrantClient(url=QDRANT_URL)


def embed(text: str) -> list[float]:
    r = httpx.post(f"{OLLAMA_URL}/api/embeddings",
                   json={"model": EMBED_MODEL, "prompt": text}, timeout=60)
    r.raise_for_status()
    return r.json()["embedding"]


class SearchReq(BaseModel):
    query: str
    tier_max: int = 4
    since: str | None = None      # ISO date filter (updated_at >=)
    cve: str | None = None
    kind: str | None = None
    limit: int = 8


def _search(req: SearchReq):
    vec = embed(req.query)
    hits = []
    for col in COLLECTIONS:
        try:
            res = qc.search(collection_name=col, query_vector=vec, limit=req.limit)
        except Exception:
            continue
        for h in res:
            p = h.payload or {}
            if p.get("tier", 4) > req.tier_max:
                continue
            if req.cve and req.cve.upper() not in (p.get("cve") or "").upper():
                continue
            if req.kind and p.get("kind") != req.kind:
                continue
            if req.since and (p.get("updated_at") or "") < req.since:
                continue
            hits.append({"score": h.score, "text": p.get("text", ""),
                         "source": p.get("source"), "tier": p.get("tier"),
                         "kind": p.get("kind"), "url": p.get("url"),
                         "cve": p.get("cve"), "cwe": p.get("cwe"),
                         "kev": p.get("kev"), "epss": p.get("epss"),
                         "updated_at": p.get("updated_at")})
    hits.sort(key=lambda x: x["score"], reverse=True)
    return hits[: req.limit]


@app.get("/status")
def status():
    out = {"qdrant": QDRANT_URL, "collections": {}}
    for c in COLLECTIONS:
        try:
            out["collections"][c] = qc.count(collection_name=c, exact=True).count
        except Exception:
            out["collections"][c] = 0
    return out


@app.post("/search")
def search(req: SearchReq):
    return {"results": _search(req)}


# ── Minimal MCP (Streamable HTTP, JSON-RPC) ──────────────────────────────
TOOLS = [
    {"name": "search_security_kb",
     "description": "Search the tiered security knowledge base (OWASP/CWE/ATT&CK/CVE/KEV/EPSS/PoCs/personal notes). Returns source tier and dates so you can weigh evidence vs. inference.",
     "inputSchema": {"type": "object", "properties": {
         "query": {"type": "string"},
         "tier_max": {"type": "integer", "default": 4},
         "since": {"type": "string"}, "cve": {"type": "string"},
         "kind": {"type": "string"}}, "required": ["query"]}},
    {"name": "get_cve",
     "description": "Fetch a specific CVE record with KEV (in-the-wild exploitation) and EPSS score.",
     "inputSchema": {"type": "object", "properties": {"id": {"type": "string"}}, "required": ["id"]}},
]


@app.post("/mcp")
async def mcp(body: dict):
    mid = body.get("id")
    method = body.get("method")
    if method == "initialize":
        return {"jsonrpc": "2.0", "id": mid, "result": {
            "protocolVersion": "2025-06-18",
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "cybervm-rag", "version": "0.1.0"}}}
    if method == "tools/list":
        return {"jsonrpc": "2.0", "id": mid, "result": {"tools": TOOLS}}
    if method == "tools/call":
        params = body.get("params", {})
        name = params.get("name")
        args = params.get("arguments", {})
        if name == "search_security_kb":
            res = _search(SearchReq(**args))
        elif name == "get_cve":
            res = _search(SearchReq(query=args.get("id", ""), cve=args.get("id"), tier_max=1))
        else:
            return {"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": "unknown tool"}}
        import json
        return {"jsonrpc": "2.0", "id": mid, "result": {
            "content": [{"type": "text", "text": json.dumps(res, indent=2)}]}}
    return {"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": "unknown method"}}
