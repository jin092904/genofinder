# Geno Finder Retrieval Evaluation Pipeline

Geno Finder v1.0 의 retrieval ablation + Korean/English parity + facet-aware satisfaction
평가 파이프라인. Genomics & Informatics 영문 manuscript 의 Figure 1-3 + Table 1-2 산출용.

본 디렉토리는 *production code 와 분리*된 평가 전용 패키지입니다. Geno Finder API 의
search endpoint 만을 호출하며, 외부 LLM SaaS 호출은 *전혀 없습니다* (Geno Finder 원칙
유지).

## Status (2026-05-19)

| Step | 상태 |
|---|---|
| 1. Skeleton | ✅ 작성 중 |
| 2. Client | ⏳ apps/api schema 확인 후 |
| 2.5. API mode toggle patch (별도 commit) | ⏳ |
| 3. bioCADDIE adapter (코드) + fetch script | ⏳ |
| 4. 30q expert-curated template + protocol | ⏳ |
| 5. Metrics (TREC + facet, TTFR 제외) | ⏳ |
| 6. Runners (warmup + idempotent) | ⏳ |
| 7-10. Figures / report / manuscript (batch 후) | 🔒 v1.0 batch 종료 의존 |
| 11. v0.8 비교 (optional, revision 대응) | 🔒 first submission 후 |

## Evaluation 설계 요약

### 4-system ablation
- `bm25_only` — OpenSearch BM25
- `dense_only` — Qdrant 1024d cosine
- `rrf` — BM25 + Dense → Reciprocal Rank Fusion (k=60)
- `rrf_rerank` — RRF top-15 → Qwen3-Reranker-0.6B reorder (Geno Finder 기본)

### Datasets
1. **bioCADDIE 2016** — 외부 표준 벤치마크. 794,992 datasets, 15 queries, 20,000+ qrels.
   *별도 임시 인덱스* (`biocaddie_2016_eval`) 로 격리 평가. 우리 production corpus 와는
   join 하지 않음 — out-of-distribution generalization 평가.
2. **Expert-curated 30q** — 본 연구 자체 ground truth. Short 10 + Medium 10 + Complex 10,
   각 EN/KO 1:1 paired. 편집자 (호진) 가 직접 작성, pooled labeling (4-system top-10 union).
   도메인 다양성 매트릭스 강제 (BCG/bladder cancer 직접 언급 ≤ 3).

### Metrics
- **TREC**: infNDCG (bioCADDIE 표준), nDCG@10/100, MAP, Recall@10/100/1000, MRR@10, P@10
- **Facet-aware satisfaction** (자체 정의, motivated by DeepGEOSearch 2025) — top-k 결과의
  disease / tissue / cell_type / modality / design_type 가 query 의 기대 facet 과 일치하는
  비율.
- **Significance**: paired bootstrap 1000 iter, 95% CI + pairwise p-value.

## 설치

```bash
cd ~/genofinder/evaluation
cp .env.example .env  # 값 채우기
uv venv
source .venv/bin/activate
uv pip install -e ".[dev]"
```

## Quick start

```bash
# 1. bioCADDIE corpus fetch (실 fetch 는 batch 종료 후)
bash scripts/01-fetch-biocaddie.sh

# 2. 30q ground truth 빈 template 생성 → 편집자 직접 작성
bash scripts/02-build-30q-template.sh

# 3. 전체 evaluation 일괄 실행
bash scripts/03-run-all-eval.sh

# 4. Figure 3종 + report 생성
bash scripts/04-generate-figures.sh
```

## Troubleshooting

- **API 미가동**: Geno Finder uvicorn 이 안 떠있으면 `GenoFinderUnavailable` raise. batch
  종료 후 `cd apps/api && uv run uvicorn src.main:app --port 8000` 으로 가동.
- **reranker cold start**: 첫 query 가 3-5초 지연. runner 가 자동 warmup 호출.
- **GPU 점거 (다른 사용자)**: `nvidia-smi` 로 GPU 5 가용성 확인. `OLLAMA_MAX_LOADED_MODELS=2`
  일시 조정으로 embedding + reranker 동시 적재.

## Definition of Done

`docs/EVALUATION_PIPELINE_PROMPT.md` §8 + 결정 답신 §8 의 통합 체크리스트 참조.

## 라이선스 / 인용

- 본 패키지: MIT.
- bioCADDIE 2016 corpus: 자체 라이선스 (fetch script 확인). *원본 corpus 는 본 repo 에
  commit 하지 않음.*
- 인용: Cohen T, et al. *Database (Oxford)*, 2017 (doi:10.1093/database/bax061, bax068),
  DeepGEOSearch (bioRxiv 2025, doi:10.64898/2025.12.27.696662).
