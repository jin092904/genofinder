"""Search 라우터 — POST /api/v1/search.

본 v0 는 인증·tenant scoping·envelope encryption 없이 동작 (L0 데이터만 검색하므로 안전).
저장된 query 는 §13.7 의 saved_queries 라우터(Week 8 도입)에서 처리.

ADR 0006 evaluation 안전장치 (2026-05):
  - `mode != rrf_rerank` 호출은 `X-Eval-Mode: 1` 헤더 필수. production 트래픽이
    실수로 비-default mode 로 호출되어 검색 품질이 저하되는 것을 차단.
  - `corpus != "production"` 도 동일 헤더 요구.
"""
from __future__ import annotations

from fastapi import APIRouter, Header, HTTPException

from src.schemas.search import SearchMode, SearchRequest, SearchResponse
from src.services.search import hybrid_search

router = APIRouter()


@router.post("/search", response_model=SearchResponse)
async def search(
    req: SearchRequest,
    x_eval_mode: str | None = Header(default=None),
) -> SearchResponse:
    # Safety: non-default mode / non-production corpus 는 X-Eval-Mode 헤더 필수.
    needs_eval_header = (
        req.mode != SearchMode.RRF_RERANK or req.corpus != "production"
    )
    if needs_eval_header and not x_eval_mode:
        raise HTTPException(
            status_code=400,
            detail=(
                "mode != 'rrf_rerank' 또는 corpus != 'production' 호출은 "
                "`X-Eval-Mode: 1` 헤더가 필요합니다 (production 트래픽 보호)."
            ),
        )
    payload = await hybrid_search(req.model_dump())
    return SearchResponse.model_validate(payload)
