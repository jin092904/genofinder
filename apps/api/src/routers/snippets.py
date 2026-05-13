"""Snippet 엔드포인트 — 데이터셋 다운로드 코드 스니펫.

GET /datasets/{id}/snippets
    → 해당 데이터셋의 source 에 맞는 R / Python / Bash 스니펫 리스트.

비용: pure templating (DB 1회 조회 + 메모리 연산). 캐시 불필요.
"""
from __future__ import annotations

from typing import Any
from uuid import UUID

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import text

from src.services.cohort import get_db_engine
from src.services.snippets import build_snippets

router = APIRouter()


class Snippet(BaseModel):
    language: str
    title: str
    description: str
    code: str
    requires: list[str]


class SnippetsResponse(BaseModel):
    dataset_id: str
    source_db: str
    source_id: str
    snippets: list[Snippet]


@router.get("/datasets/{dataset_id}/snippets", response_model=SnippetsResponse)
async def get_snippets(dataset_id: UUID) -> SnippetsResponse:
    eng = get_db_engine()
    async with eng.connect() as conn:
        result = await conn.execute(
            text("SELECT id, source_db, source_id FROM datasets WHERE id = :id LIMIT 1"),
            {"id": dataset_id},
        )
        row = result.mappings().first()
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="dataset not found")

    snippets: list[dict[str, Any]] = build_snippets(row["source_db"], row["source_id"])
    return SnippetsResponse(
        dataset_id=str(row["id"]),
        source_db=row["source_db"],
        source_id=row["source_id"],
        snippets=[Snippet(**s) for s in snippets],
    )
