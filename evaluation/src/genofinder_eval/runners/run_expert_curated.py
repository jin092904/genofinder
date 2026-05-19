"""Expert-curated 30q evaluation runner.

30 query × 4 mode × 2 lang = 240 search calls. 각 query top-100 retrieval.

흐름:
  1. preflight + warmup
  2. corpus="production" (우리 v1.0 인덱스)
  3. 4 mode × 30 query × {EN, KO} 순차 호출
  4. TREC metric + facet satisfaction 계산
  5. results/aggregated/expert_curated_results.csv (long-form)
"""
from __future__ import annotations


async def main() -> None:
    # TODO(step-6): expert-curated 30q load + facet_judgments 동시 load
    # TODO(step-6): mode × lang × query 그리드 실행
    # TODO(step-6): TREC + facet_satisfaction_at_k 동시 계산
    raise NotImplementedError("Step 6 에서 구현.")


if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
