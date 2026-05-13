"""Search request/response schemas. 마스터 플랜 §7.2 의 v1 사양 단순화."""
from __future__ import annotations

from datetime import date
from typing import Literal

from pydantic import BaseModel, Field


class DateRange(BaseModel):
    start: date | None = None
    end: date | None = None


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
