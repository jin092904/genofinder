"""OpenSearch (Elasticsearch-compatible) BM25 indexer for datasets.

마스터 플랜 §6.1: hybrid retrieval — BM25 + dense.
본 모듈은 BM25 (OpenSearch) layer.

Index 이름: 'datasets_v2' (ADR 0006 — Qdrant collection 과 동일 버전).
"""
from __future__ import annotations

import logging
import os
from typing import Any

from opensearchpy._async.client import AsyncOpenSearch

logger = logging.getLogger(__name__)

INDEX_NAME = "datasets_v2"
DEFAULT_OS_URL = "http://localhost:9200"

# 기본 BM25 분석기 + multi-field. abstract/title 가중치는 검색 시 boost 로 조정.
INDEX_BODY: dict[str, Any] = {
    "settings": {
        "number_of_shards": 1,
        "number_of_replicas": 0,
        "analysis": {
            "analyzer": {
                "default": {
                    "type": "standard",
                    "stopwords": "_english_",
                }
            }
        },
    },
    "mappings": {
        "dynamic": "strict",
        "properties": {
            "dataset_id": {"type": "keyword"},
            "source_db": {"type": "keyword"},
            # source_id 는 multi-field: text (BM25 query 매칭용) + keyword (filter / DB join 용).
            # standard analyzer 가 "GSE317412" 같은 alphanum 토큰을 lowercase 단일 토큰으로
            # 보존하므로 "GSE317412" / "gse317412" 검색 모두 매칭됨.
            "source_id": {
                "type": "text",
                "analyzer": "standard",
                "fields": {"keyword": {"type": "keyword"}},
            },
            "title": {"type": "text"},
            "abstract": {"type": "text"},
            "modality": {"type": "keyword"},
            "organism_taxid": {"type": "integer"},
            "disease_ids": {"type": "keyword"},
            "tissue_ids": {"type": "keyword"},
            "cell_type_ids": {"type": "keyword"},
            "access_type": {"type": "keyword"},
            "has_processed_data": {"type": "boolean"},
            "platform": {"type": "keyword"},
            "library_strategy": {"type": "keyword"},
            "submission_date": {"type": "date"},
            "n_samples": {"type": "integer"},
            "n_subjects": {"type": "integer"},
            "extraction_version": {"type": "keyword"},
        },
    },
}


def get_os_client() -> AsyncOpenSearch:
    url = os.environ.get("OPENSEARCH_URL", DEFAULT_OS_URL)
    # dev: security plugin 비활성, http only
    return AsyncOpenSearch(
        hosts=[url],
        http_compress=True,
        use_ssl=False,
        verify_certs=False,
        ssl_show_warn=False,
    )


async def ensure_index(client: AsyncOpenSearch) -> None:
    """idempotent — 인덱스가 없으면 생성."""
    exists = await client.indices.exists(index=INDEX_NAME)
    if exists:
        return
    await client.indices.create(index=INDEX_NAME, body=INDEX_BODY)
    logger.info("created opensearch index %s", INDEX_NAME)


def _doc(row: dict[str, Any]) -> dict[str, Any]:
    """datasets row → OpenSearch document."""
    return {
        "dataset_id": str(row["id"]),
        "source_db": row["source_db"],
        "source_id": row["source_id"],
        "title": row.get("title"),
        "abstract": row.get("abstract"),
        "modality": row.get("modality") or [],
        "organism_taxid": row.get("organism_taxid") or [],
        "disease_ids": row.get("disease_ids") or [],
        "tissue_ids": row.get("tissue_ids") or [],
        "cell_type_ids": row.get("cell_type_ids") or [],
        "access_type": row["access_type"],
        "has_processed_data": bool(row.get("has_processed_data", False)),
        "platform": row.get("platform"),
        "library_strategy": row.get("library_strategy"),
        "submission_date": (
            row["submission_date"].isoformat() if row.get("submission_date") else None
        ),
        "n_samples": row.get("n_samples"),
        "n_subjects": row.get("n_subjects"),
        "extraction_version": row.get("extraction_version"),
    }


async def upsert_doc(client: AsyncOpenSearch, row: dict[str, Any]) -> str:
    pid = str(row["id"])
    await client.index(index=INDEX_NAME, id=pid, body=_doc(row), refresh=False)
    return pid


async def upsert_many(client: AsyncOpenSearch, rows: list[dict[str, Any]]) -> int:
    """Bulk index."""
    if not rows:
        return 0
    bulk_body = []
    for row in rows:
        pid = str(row["id"])
        bulk_body.append({"index": {"_index": INDEX_NAME, "_id": pid}})
        bulk_body.append(_doc(row))
    resp = await client.bulk(body=bulk_body, refresh=True)
    if resp.get("errors"):
        # errored items 만 추려서 logger 로 노출 (본문에 SENSITIVE 없음 — L0)
        errs = [
            item for item in resp["items"]
            if item.get("index", {}).get("error")
        ]
        if errs:
            logger.warning("opensearch bulk had %d errors (first: %s)", len(errs), errs[0])
    return len(rows)


async def search_bm25(
    client: AsyncOpenSearch,
    query_text: str,
    *,
    size: int = 20,
    filters: dict[str, Any] | None = None,
) -> list[dict[str, Any]]:
    """간단한 multi_match BM25. filters 는 keyword 필드의 term 매칭.

    source_id 는 boost 15 — accession 직접 검색 (예: "GSE317412") 시 해당 데이터셋이
    최상위로 잡힘. title/abstract 매칭보다 강하게 가중치.
    """
    must: list[dict[str, Any]] = [{
        "multi_match": {
            "query": query_text,
            "fields": [
                "source_id^15",
                "title^3",
                "abstract",
                "platform",
                "library_strategy",
            ],
            "type": "best_fields",
        }
    }]
    filter_clauses: list[dict[str, Any]] = []
    if filters:
        for k, v in filters.items():
            if isinstance(v, list):
                filter_clauses.append({"terms": {k: v}})
            else:
                filter_clauses.append({"term": {k: v}})
    body = {
        "size": size,
        "query": {"bool": {"must": must, "filter": filter_clauses}},
    }
    resp = await client.search(index=INDEX_NAME, body=body)
    hits = resp["hits"]["hits"]
    return [
        {"id": h["_id"], "score": h["_score"], "source": h["_source"]}
        for h in hits
    ]
