"""TREC metric known-answer test.

Step 5 trec_metrics 구현 후 hand-computed nDCG / MAP 와 cross-check.
"""
from __future__ import annotations

from genofinder_eval.metrics.trec_metrics import aggregate_macro


def test_aggregate_macro_empty() -> None:
    out = aggregate_macro({})
    assert out["mean"] == 0.0
    assert out["median"] == 0.0


def test_aggregate_macro_simple() -> None:
    per_query = {"Q1": 0.5, "Q2": 0.7, "Q3": 0.9}
    out = aggregate_macro(per_query)
    assert abs(out["mean"] - 0.7) < 1e-6
    assert abs(out["median"] - 0.7) < 1e-6
