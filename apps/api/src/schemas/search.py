"""Search request/response schemas. 마스터 플랜 §7.2 의 v1 사양 단순화.

ADR 0006 평가 (evaluation/ 패키지) 를 위해 `mode` + `corpus` 필드 추가 (2026-05).
production 트래픽은 기본값 (rrf_rerank, production) 그대로라 영향 없음.
"""
from __future__ import annotations

from datetime import date
from enum import StrEnum
from typing import Literal

from pydantic import BaseModel, Field


class DateRange(BaseModel):
    start: date | None = None
    end: date | None = None


class SearchMode(StrEnum):
    """Retrieval ablation mode — 4-system evaluation 용.

    BM25_ONLY    OpenSearch BM25 단독
    DENSE_ONLY   Qdrant 1024d cosine 단독
    RRF          BM25 + Dense → Reciprocal Rank Fusion (k=60). rerank 비활성.
    RRF_RERANK   RRF top-15 → Qwen3-Reranker-0.6B reorder. **production 기본 동작.**

    Safety: `mode != RRF_RERANK` 호출은 router 가 `X-Eval-Mode: 1` 헤더를 요구하여
    production 의 실수 호출을 차단 (evaluation/ 패키지만 헤더 send).
    """

    BM25_ONLY = "bm25_only"
    DENSE_ONLY = "dense_only"
    RRF = "rrf"
    RRF_RERANK = "rrf_rerank"


class SearchRequest(BaseModel):
    query_text: str = Field(min_length=1, max_length=2000)
    modality: list[str] | None = None  # e.g. ["scRNA-seq", "ChIP-seq"]
    organism_taxid: list[int] | None = None
    library_strategy: list[str] | None = None
    disease_ids: list[str] | None = None  # MONDO curies
    tissue_ids: list[str] | None = None  # UBERON curies
    cell_type_ids: list[str] | None = None  # CL curies
    access_preference: Literal["any", "open_only"] = "open_only"
    must_have_processed_data: bool = False
    page: int = Field(default=1, ge=1)
    page_size: int = Field(default=20, ge=1, le=100)
    mode: SearchMode = SearchMode.RRF_RERANK  # ADR 0006 evaluation ablation
    corpus: Literal["production", "biocaddie_2016_eval"] = "production"


class ScoreBreakdown(BaseModel):
    semantic: float | None = None
    lexical: float | None = None
    rrf: float
    rerank: float | None = None


class SearchResult(BaseModel):
    dataset_id: str
    source_db: str
    source_id: str
    title: str | None
    abstract_snippet: str | None
    score: float
    score_breakdown: ScoreBreakdown
    modality: list[str] = []
    organism_taxid: list[int]
    disease_ids: list[str] = []
    tissue_ids: list[str] = []
    cell_type_ids: list[str] = []
    library_strategy: str | None
    platform: str | None
    access_type: str
    has_processed_data: bool
    submission_date: date | None
    n_samples: int | None


class FacetCount(BaseModel):
    value: str
    count: int


class Facets(BaseModel):
    modality: list[FacetCount] = []
    source_db: list[FacetCount] = []
    disease_ids: list[FacetCount] = []
    tissue_ids: list[FacetCount] = []
    cell_type_ids: list[FacetCount] = []


class SearchResponse(BaseModel):
    results: list[SearchResult]
    facets: Facets = Facets()
    page: int = 1
    page_size: int = 20
    total_estimated: int
    latency_ms: int
    query_id: str  # opaque id for feedback (later)
