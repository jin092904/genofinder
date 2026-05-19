"""TREC 표준 retrieval metric (pytrec_eval 기반).

지원 metric:
    infNDCG       — bioCADDIE 표준 (Yilmaz & Aslam, 2006). pytrec_eval 미지원 시
                    `trec_eval` C binary 호출 또는 reference impl 사용 (TODO Step 5).
    nDCG@10, @100
    MAP
    Recall@10, @100, @1000
    MRR@10
    P@10

모든 metric 은 per-query value list + macro mean 둘 다 반환.
"""
from __future__ import annotations

# pytrec_eval 의 measure 이름 표준 (https://github.com/cvangysel/pytrec_eval)
PYTREC_MEASURES: frozenset[str] = frozenset({
    "ndcg_cut_10", "ndcg_cut_100",
    "map",
    "recall_10", "recall_100", "recall_1000",
    "recip_rank",        # MRR
    "P_10",
})


def evaluate_run(
    qrels: dict[str, dict[str, int]],
    run: dict[str, dict[str, float]],
    measures: frozenset[str] = PYTREC_MEASURES,
) -> dict[str, dict[str, float]]:
    """pytrec_eval 호출 — {measure: {qid: value}} 반환.

    TODO (Step 5): pytrec_eval RelevanceEvaluator wrap.
    """
    raise NotImplementedError("Step 5 에서 구현.")


def compute_inf_ndcg(
    qrels: dict[str, dict[str, int]],
    run: dict[str, dict[str, float]],
) -> dict[str, float]:
    """infNDCG (Yilmaz & Aslam, 2006) — pooled qrels 환경에서의 nDCG.

    pytrec_eval 이 직접 지원 안 하면 NIST `trec_eval` (https://github.com/usnistgov/trec_eval)
    C binary 호출 또는 reference impl.

    TODO (Step 5): 구현 선택 — binary wrap 우선, fallback reimplementation.
    """
    raise NotImplementedError("Step 5 에서 구현.")


def aggregate_macro(per_query: dict[str, float]) -> dict[str, float]:
    """{mean, median, std, p95} 계산 — significance test 의 input."""
    import statistics

    if not per_query:
        return {"mean": 0.0, "median": 0.0, "std": 0.0, "p95": 0.0}
    vals = list(per_query.values())
    vals_sorted = sorted(vals)
    p95_idx = max(0, int(0.95 * len(vals_sorted)) - 1)
    return {
        "mean": statistics.fmean(vals),
        "median": statistics.median(vals),
        "std": statistics.pstdev(vals) if len(vals) > 1 else 0.0,
        "p95": vals_sorted[p95_idx],
    }
