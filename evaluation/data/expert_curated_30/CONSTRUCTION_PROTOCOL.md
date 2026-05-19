# Expert-Curated 30 Query Ground Truth — Construction Protocol

작성자: 호진 (편집자, single annotator)
작성 시점: v1.0 batch 완료 후 (2026-05-26 ~ 28)

## 0. 원칙

1. **LLM 자동 생성 금지** — query text 는 모두 사람이 직접 작성. 기계번역도 금지 (KO 직접 작성).
2. **Geno Finder corpus 의 실제 데이터 가용성 고려** — 답이 없는 query 는 무의미.
3. **편집자 도메인 (BCG / bladder cancer) 편향 회피** — 직접 언급 ≤ 3 query.
4. **Pooled relevance judgment** — 4-system 의 top-10 union 을 본인이 0/1/2/3 라벨링.

## 1. Query 카테고리 + 도메인 다양성 강제 매트릭스

### Short (10 queries, 1-3 단어)

| qid | modality slot | Disease / context (자유) | 예시 (사용자 직접 변경) |
|---|---|---|---|
| Q01 | scRNA-seq | (자유) | "scRNA-seq pancreatic islet" |
| Q02 | bulk RNA-seq | (자유) | "RNA-seq lung cancer" |
| Q03 | ChIP-seq | (자유) | "ChIP-seq H3K27ac" |
| Q04 | ATAC-seq | (자유) | "ATAC-seq immune" |
| Q05 | WGS / WES | (자유) | "WGS tumor mutation" |
| Q06 | proteomics | (자유) | "proteomics CSF" |
| Q07 | spatial transcriptomics | (자유) | "spatial RNA brain" |
| Q08 | methylation | (자유) | "DNA methylation aging" |
| Q09 | microbiome | (자유) | "gut microbiome IBD" |
| Q10 | metabolomics | (자유) | "metabolomics serum" |

### Medium (10 queries, 1 sentence, 1-2 facets)

| qid | Disease slot | 강제 facet 수 | 예시 |
|---|---|---|---|
| Q11 | cancer (solid) | 2 | "single-cell RNA-seq of human pancreatic islet beta cells from T2DM patients" |
| Q12 | cancer (hematologic) | 2 | "bulk RNA-seq of AML bone marrow blasts" |
| Q13 | immune / autoimmune | 2 | "scRNA-seq of synovial tissue in rheumatoid arthritis" |
| Q14 | neurological | 2 | "single-nucleus RNA-seq of Alzheimer's disease cortex" |
| Q15 | cardiovascular | 2 | "RNA-seq of heart failure left ventricle" |
| Q16 | infectious bacterial / TB | 2 | "tuberculosis granuloma scRNA-seq" |
| Q17 | infectious viral / COVID | 2 | "scRNA-seq of COVID-19 PBMC" |
| Q18 | metabolic / diabetes | 2 | "WGS of MODY pancreas" |
| Q19 | rare disease | 2 | "RNA-seq of Duchenne muscular dystrophy muscle" |
| Q20 | reproductive / developmental | 2 | "scRNA-seq of human embryonic gonad" |

### Complex (10 queries, 다중 facet + design)

| qid | Design type | 강제 facet 수 | 예시 (편집자 작성) |
|---|---|---|---|
| Q21 | case-control | 4+ | "scRNA-seq comparing inflamed vs normal colonic mucosa in ulcerative colitis patients" |
| Q22 | treatment vs control | 4+ | "RNA-seq comparing treatment-naive vs cisplatin-treated bladder cancer tissue" |
| Q23 | time series | 4+ | "longitudinal scRNA-seq of immune cells during checkpoint inhibitor treatment" |
| Q24 | dose-response | 4+ | "RNA-seq of macrophages at varying LPS doses" |
| Q25 | knockout / knockdown | 4+ | "scRNA-seq of wild-type vs Foxp3-knockout regulatory T cells" |
| Q26 | tissue / cell type comparison | 4+ | "scRNA-seq comparing brain microglia vs blood monocytes in MS patients" |
| Q27 | pre vs post treatment | 4+ | "bulk RNA-seq of tumor pre- and post-immunotherapy in melanoma" |
| Q28 | responder vs non-responder | 4+ | "scRNA-seq of bladder cancer BCG-responsive vs non-responsive vs naive patients" |
| Q29 | age / sex stratification | 4+ | "scRNA-seq comparing young vs aged mouse heart, male and female stratified" |
| Q30 | multi-omics integration | 4+ | "matched scRNA-seq + scATAC-seq of glioblastoma" |

## 2. 편집자 작업 절차

1. `bash scripts/02-build-30q-template.sh` → `data/expert_curated_30/queries_{en,ko}.jsonl` 의 빈 template 생성.
2. 각 row 의 `text` 필드를 편집자가 직접 작성:
   - **EN**: 위 매트릭스의 slot 을 만족하는 자연어 query (학술적 영어).
   - **KO**: EN 과 동일 의도, 한국어 학술 어조로 직접 번역 (기계번역 금지).
3. `expected_facets` 필드 채움 — 가능한 ontology CURIE (MONDO/UBERON/CL) 사용, 어려우면 normalized 영어 string.
4. `pytest tests/test_adapters_expert_curated.py::test_diversity_within_limit` 로 BCG 편향 자동 검증 통과 확인.

## 3. Relevance Judgment (pooled)

1. 30 query 작성 후 4-system 의 top-10 결과 union → 각 query 당 후보 ~15-40개.
2. 편집자가 0/1/2/3 라벨링:
   - **3** (highly relevant): query 의 모든 facet 일치 + abstract 가 명확히 일치
   - **2** (relevant): 대부분 facet 일치
   - **1** (marginally): 일부 facet 일치 / 동일 도메인이지만 정확하지 않음
   - **0** (not relevant): 무관
3. `qrels.tsv` 형식: `qid \t Q0 \t docid \t relevance`
4. 작업 시간 기록 (편집자 noise 추정 용도).

## 4. Inter-annotator Agreement

본 평가는 single annotator. EVALUATION_REPORT.md / manuscript.md 의 limitations 에 명시.
future work 로 외부 annotator 1-2 명 더 + Cohen's κ 측정 명기.

## 5. 검증 체크리스트 (작업 완료 후)

- [ ] `wc -l queries_en.jsonl queries_ko.jsonl` 모두 30
- [ ] `grep -c "TODO" queries_en.jsonl queries_ko.jsonl` 모두 0
- [ ] BCG / bladder cancer 직접 언급 ≤ 3
- [ ] EN ↔ KO qid 1:1 paired (test_adapters_expert_curated 통과)
- [ ] expected_facets 빈 dict 가 아닌 query 가 ≥ 25 (도메인 다양성)
- [ ] qrels.tsv 의 query 당 평균 candidate 수 ≥ 15
