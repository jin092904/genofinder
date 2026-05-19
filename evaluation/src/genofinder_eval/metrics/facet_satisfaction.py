"""Facet-aware satisfaction scoring (자체 정의, motivated by DeepGEOSearch 2025).

원전:
    DeepGEOSearch: LLM-Powered Schemaless Retrieval for Biomedical Data Discovery.
    bioRxiv 2025, doi:10.64898/2025.12.27.696662.
    본 메트릭은 그 paper 가 제기한 *ranking-only metric 이 facet-attribute 매칭을
    과소평가한다* 는 관찰에 동기를 두고 자체 정의한 것이며, 원전 framework 의 1:1
    재현이 아님.

정의:
    각 query q 에 대해 expected_facets = {disease, tissue, cell_type, modality, design_type}
    의 일부 또는 전부가 주어진다. 상위 top-k retrieved dataset 의 cohort_design /
    extraction 결과와 facet 별 일치 여부를 측정.

    facet_satisfaction@k(q) = |{f ∈ expected_facets : ∃ d ∈ top-k, d.facet[f] matches q.expected[f]}|
                              / |expected_facets|

    macro avg 와 facet 별 break-down 둘 다 보고.

매칭 우선순위:
    1. CURIE exact match (예: MONDO:0008903 == MONDO:0008903)
    2. Normalized string match (NFKC + lowercase + whitespace trim)
    3. mismatch
"""
from __future__ import annotations

import unicodedata
from typing import Any


def normalize_text(s: str) -> str:
    """NFKC + lowercase + strip + collapse internal whitespace."""
    s = unicodedata.normalize("NFKC", s)
    s = s.lower().strip()
    return " ".join(s.split())


def facet_matches(expected: str | None, candidates: list[str]) -> bool:
    """expected 가 None 이면 True (해당 facet 무관). 아니면 CURIE / normalized text 매칭."""
    if expected is None:
        return True
    if not candidates:
        return False
    if ":" in expected:  # CURIE
        return expected in candidates
    norm_exp = normalize_text(expected)
    for c in candidates:
        if normalize_text(c) == norm_exp:
            return True
    return False


def facet_satisfaction_at_k(
    expected_facets: dict[str, str | None],
    retrieved_docs: list[dict[str, Any]],
    k: int = 10,
) -> dict[str, float]:
    """단일 query 의 facet-aware satisfaction.

    Args:
        expected_facets: {"disease": "bladder cancer", "tissue": ..., ...}
        retrieved_docs: top-k 결과. 각 doc 은 {disease_ids, tissue_ids, cell_type_ids,
                       modality, cohort_design.design_type} 보유.
    Returns:
        {"macro": float, per_facet: {facet_name: hit_bool}, ...}

    TODO (Step 5): 구현. doc.cohort_design 의 design_type 매핑 + None facet skip.
    """
    raise NotImplementedError("Step 5 에서 구현.")
