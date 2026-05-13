"""Search 라우터 — POST /api/v1/search.

본 v0 는 인증·tenant scoping·envelope encryption 없이 동작 (L0 데이터만 검색하므로 안전).
저장된 query 는 §13.7 의 saved_queries 라우터(Week 8 도입)에서 처리.
"""
from __future__ import annotations

from fastapi import APIRouter

from src.schemas.search import SearchRequest, SearchResponse
from src.services.search import hybrid_search

router = APIRouter()


@router.post("/search", response_model=SearchResponse)
async def search(req: SearchRequest) -> SearchResponse:
    payload = await hybrid_search(req.model_dump())
    return SearchResponse.model_validate(payload)
