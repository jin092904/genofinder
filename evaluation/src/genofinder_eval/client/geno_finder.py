"""Geno Finder `/api/v1/search` async client.

`apps/api/src/schemas/search.py` 의 `SearchRequest` / `SearchResponse` 와 일치하는 schema 를
사용. 본 client 가 schema 를 *재정의* 하지 않고, 호환 가능한 minimal model 만 정의 (api
패키지를 evaluation 패키지가 import 하지 않도록 — 결합도 최소화).

Step 2.5 API patch 후 `SearchRequest` 에 `mode: SearchMode` 와 `corpus: str` field 가
추가된다고 가정. 본 client 는 그 field 를 그대로 전달.

TODO (Step 2 구현):
- async retry (tenacity, 5xx → exponential backoff max 3, 1s → 2s → 4s)
- timeout 60s
- Bearer token auth (env GENOFINDER_BEARER_TOKEN)
- `GenoFinderUnavailable` exception (API 다운 시)
- structlog 구조화 로그 (query_text redact)
"""
from __future__ import annotations

import os
from typing import Any, Literal

import httpx
from pydantic import BaseModel

from genofinder_eval.client.search_modes import SearchMode


class GenoFinderUnavailable(RuntimeError):
    """Geno Finder API 가 응답하지 않거나 5xx 가 retry 초과 시 raise."""


class _SearchResultMin(BaseModel):
    """`SearchResult` 의 minimal subset — eval 에서 필요한 필드만."""

    dataset_id: str
    source_db: str
    source_id: str
    title: str | None = None
    score: float
    score_breakdown: dict[str, float | None]  # semantic / lexical / rrf / rerank
    modality: list[str] = []
    disease_ids: list[str] = []
    tissue_ids: list[str] = []
    cell_type_ids: list[str] = []


class _SearchResponseMin(BaseModel):
    results: list[_SearchResultMin]
    latency_ms: int
    query_id: str


class GenoFinderClient:
    """async wrapper for `/api/v1/search`.

    Usage:
        async with GenoFinderClient() as client:
            resp = await client.search("scRNA-seq lung", top_k=15, mode=SearchMode.RRF_RERANK)
    """

    def __init__(
        self,
        base_url: str | None = None,
        bearer_token: str | None = None,
        timeout_s: float = 60.0,
    ) -> None:
        self._base = (base_url or os.environ.get("GENOFINDER_API_BASE", "http://localhost:8000")).rstrip("/")
        self._token = bearer_token if bearer_token is not None else os.environ.get("GENOFINDER_BEARER_TOKEN", "")
        self._timeout = timeout_s
        self._client: httpx.AsyncClient | None = None

    async def __aenter__(self) -> GenoFinderClient:
        headers = {"Content-Type": "application/json"}
        if self._token:
            headers["Authorization"] = f"Bearer {self._token}"
        self._client = httpx.AsyncClient(base_url=self._base, headers=headers, timeout=self._timeout)
        return self

    async def __aexit__(self, *_: Any) -> None:
        if self._client is not None:
            await self._client.aclose()
            self._client = None

    async def search(
        self,
        query_text: str,
        *,
        top_k: int = 15,
        mode: SearchMode = SearchMode.RRF_RERANK,
        lang: Literal["ko", "en"] | None = None,
        corpus: str = "production",
        filters: dict[str, Any] | None = None,
    ) -> _SearchResponseMin:
        """Geno Finder `/api/v1/search` 호출. 자세한 retry / error 처리는 Step 2 에서 채움.

        Step 2.5 API patch 후 body schema:
            { query_text, mode, corpus, page, page_size=top_k, ... }
        `mode != rrf_rerank` 호출은 헤더 `X-Eval-Mode: 1` 필수.
        """
        # TODO(step-2): 본 함수 구현 — body 구성 + retry + error handling + redacted logging.
        raise NotImplementedError("Step 2 에서 구현. 본 skeleton 은 시그니처만 fix.")
