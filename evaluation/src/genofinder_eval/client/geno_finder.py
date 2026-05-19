"""Geno Finder `/api/v1/search` async client.

`apps/api/src/schemas/search.py` 의 `SearchRequest` / `SearchResponse` 와 일치하는 schema 를
사용. 본 client 가 schema 를 *재정의* 하지 않고, 호환 가능한 minimal model 만 정의 (api
패키지를 evaluation 패키지가 import 하지 않도록 — 결합도 최소화).

Step 2.5 API patch 이후 (commit e9f757d) `SearchRequest` 에 `mode: SearchMode` 와
`corpus: Literal["production","biocaddie_2016_eval"]` field 가 추가됨. 본 client 는
그 field 를 body 에 그대로 실어 보낸다.

Retry / error 정책:
  - 5xx: exponential backoff max 3 retry (1s → 2s → 4s)
  - 4xx (400/401/403): 즉시 raise GenoFinderUnavailable (사용자 오류 / 인증)
  - timeout / connect error: retry 후 GenoFinderUnavailable
  - Bearer token 우선순위: 인자 > GENOFINDER_BEARER_TOKEN env
  - query_text 는 structlog redact 처리.
"""
from __future__ import annotations

import os
from typing import Any, Literal

import httpx
import structlog
from pydantic import BaseModel
from tenacity import (
    AsyncRetrying,
    retry_if_exception,
    stop_after_attempt,
    wait_exponential,
)

from genofinder_eval.client.search_modes import SearchMode
from genofinder_eval.utils.logging import get_logger

logger: structlog.stdlib.BoundLogger = get_logger(__name__)


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


def _is_retryable(exc: BaseException) -> bool:
    """5xx 또는 transient network error 만 retry. 4xx 는 즉시 fail."""
    if isinstance(exc, httpx.HTTPStatusError):
        return 500 <= exc.response.status_code < 600
    if isinstance(exc, httpx.TransportError | httpx.TimeoutException):
        return True
    return False


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
        self._token = (
            bearer_token if bearer_token is not None else os.environ.get("GENOFINDER_BEARER_TOKEN", "")
        )
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
        """Geno Finder `/api/v1/search` 호출.

        Args:
            query_text: 검색 query.
            top_k: 결과 갯수 상한 (api 의 page_size 에 매핑, 1-100).
            mode: 4-system ablation 모드. non-default 시 X-Eval-Mode 헤더 자동 추가.
            lang: 평가 메타정보 (request body 에 직접 사용 안 함, log 만).
            corpus: 'production' | 'biocaddie_2016_eval'.
            filters: api `SearchRequest` 의 기타 필드 (modality / disease_ids 등).

        Raises:
            GenoFinderUnavailable: 5xx retry 초과, timeout, connect error, 4xx (즉시).
        """
        if self._client is None:
            raise RuntimeError("Use `async with GenoFinderClient()` context manager.")

        body: dict[str, Any] = {
            "query_text": query_text,
            "mode": str(mode),
            "corpus": corpus,
            "page": 1,
            "page_size": max(1, min(100, top_k)),
        }
        if filters:
            body.update(filters)

        headers: dict[str, str] = {}
        if mode != SearchMode.RRF_RERANK or corpus != "production":
            headers["X-Eval-Mode"] = "1"

        logger.info(
            "search_request",
            mode=str(mode),
            corpus=corpus,
            top_k=top_k,
            lang=lang,
            query_text=query_text,  # redact processor 가 masking
        )

        async for attempt in AsyncRetrying(
            stop=stop_after_attempt(3),
            wait=wait_exponential(multiplier=1, min=1, max=4),
            retry=retry_if_exception(_is_retryable),
            reraise=True,
        ):
            with attempt:
                try:
                    resp = await self._client.post(
                        "/api/v1/search", json=body, headers=headers
                    )
                    resp.raise_for_status()
                except httpx.HTTPStatusError as e:
                    if not _is_retryable(e):
                        # 4xx — 즉시 raise (retry 안 함)
                        raise GenoFinderUnavailable(
                            f"HTTP {e.response.status_code}: {e.response.text[:200]}"
                        ) from e
                    raise
                except (httpx.TransportError, httpx.TimeoutException):
                    raise

        data = resp.json()
        return _SearchResponseMin.model_validate(data)
