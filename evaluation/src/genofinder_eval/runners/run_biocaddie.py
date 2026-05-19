"""bioCADDIE 2016 evaluation runner.

15 query × 4 mode = 60 search calls. 각 query top-100 retrieval.

흐름:
  1. preflight: GPU 가용성 점검 (`ollama ps`, `nvidia-smi`)
  2. warmup: reranker cold start 회피
  3. corpus 지정: `corpus="biocaddie_2016_eval"` (별도 임시 인덱스)
  4. 4 mode × 15 query 순차 호출
  5. runfile 저장 → results/raw/biocaddie_<mode>_<timestamp>.run
  6. metric 계산 → results/aggregated/biocaddie_results.csv
"""
from __future__ import annotations


async def main() -> None:
    # TODO(step-6): load qrels + queries (adapters.beir_compat)
    # TODO(step-6): for mode in SearchMode: client.search(corpus="biocaddie_2016_eval", ...)
    # TODO(step-6): pytrec_eval 호출 + infNDCG
    # TODO(step-6): atomic write run files + CSV
    raise NotImplementedError("Step 6 에서 구현.")


if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
