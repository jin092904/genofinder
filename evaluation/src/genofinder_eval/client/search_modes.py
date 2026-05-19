"""4-system retrieval ablation 모드 정의.

Geno Finder `/api/v1/search` 가 본 모드 enum 값을 `mode` field 로 받는다 (Step 2.5 patch).

  bm25_only   — OpenSearch BM25 top-k 단독. Qdrant / RRF / rerank 비활성.
  dense_only  — Qdrant 1024d cosine top-k 단독. OpenSearch / RRF / rerank 비활성.
  rrf         — BM25 top200 + Dense top200 → RRF (k=60) → top-k. rerank 비활성.
  rrf_rerank  — RRF top15 → Qwen3-Reranker-0.6B reorder → top-k. **Geno Finder 기본 동작.**

Safety: `mode != RRF_RERANK` 호출은 API 측에서 `X-Eval-Mode` 헤더를 요구하여 production 의
실수 호출을 차단한다 (Step 2.5 patch).
"""
from __future__ import annotations

from enum import StrEnum


class SearchMode(StrEnum):
    BM25_ONLY = "bm25_only"
    DENSE_ONLY = "dense_only"
    RRF = "rrf"
    RRF_RERANK = "rrf_rerank"
