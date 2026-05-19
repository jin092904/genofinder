"""4-system ablation 결과 통합 + paired bootstrap significance test.

흐름:
  1. results/aggregated/*.csv long-form 로드
  2. 4 mode 의 pairwise (4C2 = 6 비교)
  3. per-query 차이 distribution → 1000-iter paired bootstrap → 95% CI + p-value
  4. results/aggregated/significance_tests.csv 생성
"""
from __future__ import annotations


def paired_bootstrap(
    a: list[float],
    b: list[float],
    iterations: int = 1000,
    seed: int = 42,
) -> tuple[float, tuple[float, float], float]:
    """returns (mean_diff, 95%_CI, two-sided p-value).

    TODO(step-6): scipy.stats 활용. seed 는 utils.seed.set_global_seed() 와 연동.
    """
    raise NotImplementedError("Step 6 에서 구현.")
