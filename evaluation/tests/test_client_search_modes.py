"""GenoFinderClient + SearchMode 단위 테스트 (respx 로 API mock).

Step 2 client 구현 완료 후 실제 assertion 채움. Step 1 시점에는 import / placeholder.
"""
from __future__ import annotations

from genofinder_eval.client.search_modes import SearchMode


def test_search_mode_values() -> None:
    assert SearchMode.BM25_ONLY == "bm25_only"
    assert SearchMode.DENSE_ONLY == "dense_only"
    assert SearchMode.RRF == "rrf"
    assert SearchMode.RRF_RERANK == "rrf_rerank"


def test_search_mode_default_is_rrf_rerank() -> None:
    """Geno Finder 의 기본 동작 (production) 은 항상 RRF_RERANK."""
    import inspect

    from genofinder_eval.client.geno_finder import GenoFinderClient

    sig = inspect.signature(GenoFinderClient.search)
    assert sig.parameters["mode"].default == SearchMode.RRF_RERANK
