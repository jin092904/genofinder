"""Hybrid search — Qdrant (semantic) + OpenSearch (BM25), RRF merge.

마스터 플랜 §6.1 의 v0 단순화:
    - 양쪽에서 top K 가져와 Reciprocal Rank Fusion 으로 합친다.
    - Cross-encoder rerank·랭킹 점수 함수는 Week 7+ (별도 service 모듈).

ADR 0003 T7: 사용자 쿼리 임베딩은 ephemeral — Qdrant 에 저장하지 않는다.
본 모듈은 query 시점에만 임베딩을 만들고, 결과 반환 후 메모리에서 사라진다.
"""
from __future__ import annotations

import os
import time
import uuid
from dataclasses import dataclass
from typing import Any

import httpx
from opensearchpy._async.client import AsyncOpenSearch
from qdrant_client import AsyncQdrantClient
from qdrant_client.models import FieldCondition, Filter, MatchAny, MatchValue

# ADR 0006: v2 = Qwen3-Embedding 1024d. v1 (768d nomic) deprecated.
QDRANT_COLLECTION = "datasets_v2"
OS_INDEX = "datasets_v2"
DEFAULT_OLLAMA_URL = "http://ollama:11434"
DEFAULT_QDRANT_URL = "http://qdrant:6333"
DEFAULT_OS_URL = "http://opensearch:9200"
RRF_K = 60  # 일반적인 RRF 상수
MIN_top_k = 50
MAX_top_k = 200  # 페이지 ≥ 10 까지 안전한 상한


@dataclass
class HybridHit:
    dataset_id: str
    payload: dict[str, Any]
    semantic: float | None = None
    lexical: float | None = None
    semantic_rank: int | None = None
    lexical_rank: int | None = None
    rrf: float = 0.0
    rerank: float | None = None


_ARRAY_FIELDS = (
    ("modality", "modality"),
    ("organism_taxid", "organism_taxid"),
    ("library_strategy", "library_strategy"),
    ("disease_ids", "disease_ids"),
    ("tissue_ids", "tissue_ids"),
    ("cell_type_ids", "cell_type_ids"),
)


def _build_qdrant_filter(req: dict[str, Any]) -> Filter | None:
    must: list[FieldCondition] = []
    for req_key, payload_key in _ARRAY_FIELDS:
        if req.get(req_key):
            must.append(FieldCondition(key=payload_key, match=MatchAny(any=req[req_key])))
    if req.get("access_preference") == "open_only":
        must.append(FieldCondition(key="access_type", match=MatchValue(value="open")))
    if req.get("must_have_processed_data"):
        must.append(FieldCondition(key="has_processed_data", match=MatchValue(value=True)))
    return Filter(must=must) if must else None


def _build_os_filter(req: dict[str, Any]) -> list[dict[str, Any]]:
    f: list[dict[str, Any]] = []
    for req_key, doc_key in _ARRAY_FIELDS:
        if req.get(req_key):
            f.append({"terms": {doc_key: req[req_key]}})
    if req.get("access_preference") == "open_only":
        f.append({"term": {"access_type": "open"}})
    if req.get("must_have_processed_data"):
        f.append({"term": {"has_processed_data": True}})
    return f


async def _embed_query(query_text: str) -> list[float]:
    """ephemeral query 임베딩 — 호출 후 폐기.

    ADR 0006: 인덱스는 1024d (Qwen3-Embedding-8B Matryoshka truncate). 쿼리 모델이
    8B (4096d native) 이든 0.6B (1024d native) 이든, Qdrant collection dim 과
    일치시키기 위해 클라이언트 측에서 [:1024] truncate.
    """
    ollama_url = os.environ.get("OLLAMA_URL", DEFAULT_OLLAMA_URL)
    model = os.environ.get("OLLAMA_MODEL_EMBED", "qwen3-embedding:0.6b")
    async with httpx.AsyncClient(base_url=ollama_url, timeout=30.0) as cli:
        resp = await cli.post("/api/embed", json={"model": model, "input": query_text})
        resp.raise_for_status()
        vec = resp.json()["embeddings"][0]
    QDRANT_DIM = 1024  # datasets_v2 collection 의 차원 — embeddings.py:EMBED_DIM 과 sync
    if len(vec) < QDRANT_DIM:
        raise RuntimeError(
            f"query embedding dim {len(vec)} < {QDRANT_DIM}: OLLAMA_MODEL_EMBED 가 "
            "1024d 미만 모델로 설정됨. qwen3-embedding:8b 또는 :0.6b 권장."
        )
    return vec[:QDRANT_DIM]


async def hybrid_search(req: dict[str, Any]) -> dict[str, Any]:
    """Hybrid search 실행. dict-in / dict-out — router 가 Pydantic 변환.

    req 키:
        query_text          (str, required)
        organism_taxid      (list[int])
        library_strategy    (list[str])
        access_preference   ('any' | 'open_only')
        must_have_processed_data (bool)
        page, page_size     (int)
    """
    t0 = time.perf_counter()
    query_text: str = req["query_text"]
    page = max(1, int(req.get("page", 1)))
    page_size = max(1, min(100, int(req.get("page_size", 20))))
    # 페이지 N 까지 보려면 layer 당 N×page_size 이상 가져와야 RRF merge 후 충분한 후보 확보.
    # buffer 1.5x + bound.
    top_k = max(MIN_top_k, min(MAX_top_k, int(page * page_size * 1.5)))

    qdrant = AsyncQdrantClient(url=os.environ.get("QDRANT_URL", DEFAULT_QDRANT_URL))
    os_client = AsyncOpenSearch(
        hosts=[os.environ.get("OPENSEARCH_URL", DEFAULT_OS_URL)],
        http_compress=True, use_ssl=False, verify_certs=False, ssl_show_warn=False,
    )

    try:
        # 1) Embed query
        qvec = await _embed_query(query_text)

        # 2) Qdrant top K
        qd_filter = _build_qdrant_filter(req)
        qd_hits = await qdrant.query_points(
            collection_name=QDRANT_COLLECTION,
            query=qvec,
            limit=top_k,
            query_filter=qd_filter,
            with_payload=True,
        )

        # 3) OpenSearch top K
        os_filters = _build_os_filter(req)
        os_resp = await os_client.search(
            index=OS_INDEX,
            body={
                "size": top_k,
                "query": {
                    "bool": {
                        "must": [{
                            "multi_match": {
                                "query": query_text,
                                # source_id boost 15 — accession 직접 검색 (예: "GSE317412")
                                # 시 해당 데이터셋이 BM25 상위에 잡힘.
                                "fields": [
                                    "source_id^15",
                                    "title^3",
                                    "abstract",
                                    "platform",
                                    "library_strategy",
                                ],
                                "type": "best_fields",
                            }
                        }],
                        "filter": os_filters,
                    }
                },
            },
        )

        # 4) RRF merge
        merged: dict[str, HybridHit] = {}
        for rank, p in enumerate(qd_hits.points, start=1):
            did = str(p.id)
            merged[did] = HybridHit(
                dataset_id=did, payload=p.payload or {},
                semantic=float(p.score), semantic_rank=rank,
                rrf=1.0 / (RRF_K + rank),
            )
        for rank, h in enumerate(os_resp["hits"]["hits"], start=1):
            did = h["_id"]
            payload = h["_source"]
            score = float(h["_score"])
            if did in merged:
                hit = merged[did]
                hit.lexical = score; hit.lexical_rank = rank
                hit.rrf += 1.0 / (RRF_K + rank)
                # OpenSearch source 의 title/abstract 등을 payload 에 보강
                hit.payload = {**hit.payload, **payload}
            else:
                merged[did] = HybridHit(
                    dataset_id=did, payload=payload,
                    lexical=score, lexical_rank=rank,
                    rrf=1.0 / (RRF_K + rank),
                )

        # 5) Sort by RRF
        ordered = sorted(merged.values(), key=lambda x: x.rrf, reverse=True)
        total = len(ordered)

        # 5b) Cross-encoder rerank (top-N) — 가능할 때만, fallback 은 RRF
        from src.services.reranker import is_available as rerank_available
        from src.services.reranker import rerank_pairs, rerank_top_n

        rerank_n = rerank_top_n()
        if rerank_available() and len(ordered) > 0:
            top = ordered[:rerank_n]
            docs = []
            for h in top:
                p = h.payload
                title = p.get("title") or ""
                abstract = (p.get("abstract") or "")[:1000]
                docs.append(f"{title}\n\n{abstract}")
            # CPU-bound (PyTorch inference). 별도 thread 로 빼서 event loop 비움.
            # 안 그러면 reranker 도는 1-3초 동안 다른 요청 (예: /me/saved POST) 가
            # queue 에 쌓이며 브라우저가 timeout/reset.
            import asyncio
            scores = await asyncio.to_thread(rerank_pairs, query_text, docs)
            if scores is not None:
                for h, s in zip(top, scores):
                    h.rerank = s
                # rerank 점수 기준 재정렬 — 못 받은 (top-N 밖) 은 그대로 후순위
                top_sorted = sorted(top, key=lambda x: x.rerank or float("-inf"), reverse=True)
                ordered = top_sorted + ordered[rerank_n:]

        start = (page - 1) * page_size
        chunk = ordered[start : start + page_size]

        # 6) Facets — 전체 후보(merged) 기준 카운트
        def _count_array(field: str) -> dict[str, int]:
            counts: dict[str, int] = {}
            for hit in ordered:
                for v in (hit.payload.get(field) or []):
                    counts[v] = counts.get(v, 0) + 1
            return counts

        def _count_scalar(field: str) -> dict[str, int]:
            counts: dict[str, int] = {}
            for hit in ordered:
                v = hit.payload.get(field)
                if v:
                    counts[v] = counts.get(v, 0) + 1
            return counts

        def _to_facet_list(counts: dict[str, int], top: int = 30) -> list[dict[str, Any]]:
            return [
                {"value": k, "count": v}
                for k, v in sorted(counts.items(), key=lambda x: x[1], reverse=True)[:top]
            ]

        facets = {
            "modality": _to_facet_list(_count_array("modality")),
            "source_db": _to_facet_list(_count_scalar("source_db")),
            "disease_ids": _to_facet_list(_count_array("disease_ids")),
            "tissue_ids": _to_facet_list(_count_array("tissue_ids")),
            "cell_type_ids": _to_facet_list(_count_array("cell_type_ids")),
        }

        results: list[dict[str, Any]] = []
        for hit in chunk:
            p = hit.payload
            abstract_full = p.get("abstract") or ""
            results.append({
                "dataset_id": hit.dataset_id,
                "source_db": p.get("source_db") or "",
                "source_id": p.get("source_id") or "",
                "title": p.get("title"),
                "abstract_snippet": abstract_full[:240] if abstract_full else None,
                "score": hit.rerank if hit.rerank is not None else hit.rrf,
                "score_breakdown": {
                    "semantic": hit.semantic,
                    "lexical": hit.lexical,
                    "rrf": hit.rrf,
                    "rerank": hit.rerank,
                },
                "modality": p.get("modality") or [],
                "organism_taxid": p.get("organism_taxid") or [],
                "disease_ids": p.get("disease_ids") or [],
                "tissue_ids": p.get("tissue_ids") or [],
                "cell_type_ids": p.get("cell_type_ids") or [],
                "library_strategy": p.get("library_strategy"),
                "platform": p.get("platform"),
                "access_type": p.get("access_type") or "open",
                "has_processed_data": bool(p.get("has_processed_data", False)),
                "submission_date": p.get("submission_date"),
                "n_samples": p.get("n_samples"),
            })

        latency_ms = int((time.perf_counter() - t0) * 1000)
        return {
            "results": results,
            "facets": facets,
            "page": page,
            "page_size": page_size,
            "total_estimated": total,
            "latency_ms": latency_ms,
            "query_id": str(uuid.uuid4()),
        }
    finally:
        await qdrant.close()
        await os_client.close()
