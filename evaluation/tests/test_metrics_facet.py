"""Facet matching unit test."""
from __future__ import annotations

from genofinder_eval.metrics.facet_satisfaction import facet_matches, normalize_text


def test_normalize_text_nfkc() -> None:
    assert normalize_text("ＨＥＬＬＯ") == "hello"  # full-width → half-width via NFKC


def test_facet_matches_curie() -> None:
    assert facet_matches("MONDO:0008903", ["MONDO:0008903", "MONDO:0001"])
    assert not facet_matches("MONDO:0008903", ["MONDO:0001"])


def test_facet_matches_string() -> None:
    assert facet_matches("bladder cancer", ["Bladder Cancer", "lung"])
    assert facet_matches("scRNA-seq", ["scrna-seq"])
    assert not facet_matches("scRNA-seq", ["bulk RNA-seq"])


def test_facet_matches_none_expected() -> None:
    """expected=None 이면 무조건 hit (해당 facet 무관)."""
    assert facet_matches(None, [])
    assert facet_matches(None, ["whatever"])
