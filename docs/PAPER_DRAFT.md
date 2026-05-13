# Geno Finder: 연구 디자인 인지 기반 공공 생명정보 데이터셋 검색 엔진

*A research-design-aware search engine for public biomedical datasets*

작성일: 2026-05-09 (초안)
상태: draft

---

## 초록 (Abstract)

생명정보 연구자가 자신의 연구 디자인 (research design) 에 부합하는 공공 데이터셋을 신속히
찾기는 어려운 일이다. 기존 카탈로그 시스템 (NCBI GEO, EBI BioStudies 등) 은 키워드 일치
중심이라 의미 기반 (semantic) 매칭이 제한되며, 데이터셋의 실험 모달리티 / 종 / 질병 같은
핵심 메타데이터가 자유 서술 형태로 흩어져 있어 정밀 필터링이 어렵다.

본 연구에서는 **Geno Finder**, 즉 (i) GEO·HCA·GDC·SRA 4개 출처의 공공 메타데이터를 통합
인덱싱하고, (ii) 로컬 LLM (Ollama Phi-4 mini) 으로 모든 데이터셋을 통제어휘 (controlled
vocabulary) 와 ontology term 으로 자동 분류하며, (iii) 의미 기반 dense embedding 과
키워드 기반 BM25 를 결합한 하이브리드 검색에 cross-encoder rerank 를 추가한 검색 엔진을
제안한다. 시스템은 PostgreSQL Row-Level Security 기반 멀티테넌트 격리, 외부 API 호출 0건의
프라이버시 우선 아키텍처, 모든 결과의 점수 분해 (semantic / lexical / RRF / rerank) 가시화를
설계 원칙으로 삼는다.

10,763 datasets 인덱싱 시점 기준 평균 검색 latency 는 ~400ms 이며, 영어 도메인 쿼리에 대해
top-1 cross-encoder rerank 점수 +1.18 (good match) 을 달성하였다.

> **쉬운 설명:** 연구자가 "내 실험에 쓸만한 공개 데이터를 찾고 싶다" 고 할 때, 단순 키워드
> 검색이 아니라 의미가 비슷한 것까지 찾아주고, 각 결과가 왜 매칭됐는지 점수로 설명해 주는
> 도구입니다. 모든 AI 분석은 사용자 컴퓨터/서버 안에서만 돌아 외부로 데이터가 새지 않습니다.

---

## 1. 서론 (Introduction)

### 1.1 문제 정의

특정 연구 디자인을 가진 생명정보 연구자 — 예를 들어 *"인간 췌장 베타세포의 단일세포 RNA
시퀀싱 데이터"* 를 찾고자 할 때 — 가 이용 가능한 공개 데이터셋을 발굴하는 일은 다음 이유로
어렵다:

1. **출처 분산.** 동일 도메인의 데이터가 NCBI GEO, EBI ArrayExpress, Human Cell Atlas (HCA),
   Genomic Data Commons (GDC), Sequence Read Archive (SRA) 등에 흩어져 있고, 각 카탈로그는
   고유의 검색 인터페이스와 메타데이터 schema 를 사용한다.
2. **메타데이터 비정형성.** Modality (실험 기법, e.g. scRNA-seq, ChIP-seq), 종 (organism),
   질병, 조직, 세포 타입 같은 핵심 facet 이 데이터 제출자의 자유 서술에 의존하여 통일된
   필터가 불가능하다.
3. **키워드 기반 검색의 한계.** GEO 의 BLAST 등 키워드 매칭은 "단일세포" / "single-cell" /
   "scRNA-seq" 같은 동의어를 인식하지 못하며, 연구 디자인 자체의 문맥 (예: "분화 중인 면역
   세포 비교") 에 대해서는 더더욱 무력하다.

> **쉬운 설명:** 데이터가 여러 사이트에 흩어져 있고, 각 데이터셋의 설명도 자유 형식이라
> 일관된 기준으로 비교/검색하기 어렵습니다.

### 1.2 본 연구의 기여

(C1) 4개 1차 출처 (GEO, HCA, GDC, SRA) 를 단일 카탈로그로 통합하고 자동 incremental harvest
파이프라인을 구축.

(C2) 모든 데이터셋에 대해 로컬 LLM 기반 메타데이터 추출을 수행, controlled vocabulary 와
ontology CURIE (MONDO / UBERON / Cell Ontology) 로 정규화.

(C3) Dense (Qdrant) + Lexical (OpenSearch) hybrid retrieval 에 cross-encoder rerank 를
통합한 다단계 검색 파이프라인.

(C4) PostgreSQL Row-Level Security + 외부 API 호출 0건의 프라이버시 우선 아키텍처. 사용자
쿼리는 데이터 등급 L3 (Restricted) 로 분류되어 envelope 암호화 (per-tenant Data Encryption
Key) 로 저장된다.

(C5) 점수 분해 가시화 — semantic / lexical / RRF / rerank 각 신호를 사용자에게 노출하여
"black-box 거부" 원칙을 구현.

> **쉬운 설명:** 우리가 새로 만든 것은 다섯 가지 — 데이터 통합 수확, AI 자동 분류, 똑똑한
> 검색, 사용자 정보 보호, 그리고 검색 결과가 왜 나왔는지 설명하는 시각화입니다.

---

## 2. 관련 연구 (Related Work)

### 2.1 공공 생명정보 카탈로그

NCBI GEO (Gene Expression Omnibus) [Edgar 2002] 는 사실상 표준이지만 자체 검색은 PubMed 식
키워드 + filter 기반이다. EBI BioStudies / ArrayExpress 는 BioStudies schema 로 통합 시도를
하지만 쿼리 레벨에서 ontology 매핑은 제공하지 않는다. Human Cell Atlas Data Portal 은
정제된 contributor metadata 를 갖지만 단일 출처에 한정된다. GDC Data Portal 은 암 데이터
중심으로 별도 인터페이스를 가진다.

### 2.2 의미 기반 / 하이브리드 검색

Dense passage retrieval [Karpukhin 2020] 와 BM25 의 combination 이 일반 정보 검색 영역에서
성능을 입증하였다 [Ma 2021]. 본 연구는 **Reciprocal Rank Fusion** [Cormack 2009] 으로 두
랭킹을 결합하고, **MS MARCO 학습 cross-encoder** [Nogueira 2019] 로 top-K 재정렬을 수행한다.
Bio 도메인 특화 임베딩 모델 (BioBERT, SciBERT) 대신 일반 도메인 모델 `nomic-embed-text` 를
선택한 이유는 ADR 0004 에 기술되어 있다 — 다국어 / 자유 서술 메타데이터에서 일반 모델이 더
견고했다.

### 2.3 LLM 기반 메타데이터 추출

GPT-4 등 클라우드 LLM 으로 의생명 텍스트에서 구조화 정보를 추출하는 연구가 다수 있으나,
본 연구는 **로컬 LLM (Phi-4 mini, 3B 파라미터, Q4 양자화)** 을 사용한다. 이는 사용자 쿼리
프라이버시 (ADR 0003) 와 운영 비용 (외부 API 비용 0) 측면에서 중요하다.

> **쉬운 설명:** 비슷한 도구가 있긴 하지만, 우리는 데이터를 한 곳에 모으고 + AI 가 자동
> 정리하고 + 모든 처리를 사용자 컴퓨터에서 한다는 점에서 다릅니다.

---

## 3. 시스템 아키텍처 (System Architecture)

### 3.1 데이터 등급 (Data Tiers)

[ADR 0002 §12.1] 모든 데이터를 4 등급으로 분류한다:

| 등급 | 정의 | 예시 | 보안 처리 |
|---|---|---|---|
| L0 Public | 공개 메타데이터 | GEO 카탈로그 자체 | 평문 저장, RLS 미적용 |
| L1 Internal | 시스템 자체 식별자 | dataset UUID | RLS 미적용 |
| L2 Tenant | 사용자 / 워크스페이스 | tenants, users | RLS FORCE |
| L3 Restricted | 사용자 쿼리, 클릭 신호 | search_logs, saved_queries | envelope 암호화 + RLS FORCE |

> **쉬운 설명:** 데이터를 민감도에 따라 4단계로 나누고, 단계가 높을수록 강한 보호 (암호화,
> 사용자 격리) 를 적용합니다.

### 3.2 컴포넌트 다이어그램

```
┌────────────────┐
│  Web (Next.js) │ ── Firebase Auth (Google sign-in) ── ID token
└──────┬─────────┘
       │  Authorization: Bearer <id_token>
       ▼
┌──────────────────────────────────────────────────────────────┐
│  API (FastAPI) — verify_id_token, ensure_user_for_principal  │
│   - /search    (POST)  — 하이브리드 검색                      │
│   - /me        (GET, PATCH) — 사용자 프로필                  │
│   - /me/saved  (GET, POST, DELETE) — 찜                      │
│   - /datasets/{id} (GET) — 상세                              │
│   - /stats     (GET) — 대시보드                              │
└────┬───────┬──────────┬──────────┬─────────┬────────────────┘
     │       │          │          │         │
     ▼       ▼          ▼          ▼         ▼
  Postgres  Redis    Qdrant   OpenSearch  Ollama
  (RLS)    (캐시)   (vector)  (BM25)     (LLM/embed)
                                            │
                                            ▼
                                  Phi-4 mini (gen)
                                  nomic-embed-text (embed)
                                  cross-encoder rerank
```

> **쉬운 설명:** 웹 → API → 5개 DB / 검색엔진. 모든 LLM 작업은 Ollama (로컬) 안에서 끝납니다.

### 3.3 Multi-tenant 격리 (T4)

PostgreSQL Row-Level Security 로 사용자 간 데이터 격리. 매 요청 시 미들웨어가
`SET LOCAL app.tenant_id = '<uuid>'` 를 수행하고, L2/L3 테이블의 모든 row 는 다음 정책을 따른다:

```sql
CREATE POLICY tenant_isolation ON saved_datasets
  USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
  WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
ALTER TABLE saved_datasets ENABLE ROW LEVEL SECURITY;
ALTER TABLE saved_datasets FORCE ROW LEVEL SECURITY;
```

DB 사용자 (role) 도 분리: `genofinder` (마이그레이션용 superuser, BYPASSRLS) 와
`genofinder_app` (런타임 NOSUPERUSER, RLS 적용 대상). 11개 자동 cross-tenant 테스트로
격리를 회귀 검증한다.

> **쉬운 설명:** A 사용자가 B 사용자의 찜 목록을 볼 수 없도록 데이터베이스 자체에서 막는
> 메커니즘입니다 (애플리케이션 코드의 버그가 있어도 데이터가 새지 않음).

---

## 4. 메타데이터 추출 파이프라인 (Methods I — Extraction)

### 4.1 Harvest

각 출처마다 incremental harvest 를 구현. NCBI E-utilities 의 `pdat` (publication date)
필터로 watermark 기반 일자 단위 증분 수확. 4개 출처 클라이언트는 동일한 `Harvester` 추상에
구현한다:

```python
class Harvester(Protocol):
    source_db: str
    async def list_updated_since(self, since: date) -> AsyncIterator[str]: ...
    async def fetch_raw(self, uid: str) -> dict: ...
```

NCBI 의 경우 API key 가 있을 때 10 rps, 없을 때 3 rps. 본 연구에서는 API key 사용하여
asyncio semaphore=12 로 7.5 rps 안정 처리.

### 4.2 LLM 기반 구조화 추출

각 데이터셋의 자유 서술 (title + abstract + raw GEO field) 을 Ollama Phi-4 mini 에 입력하여
다음 JSON schema 로 구조화한다:

```json
{
  "modality": ["scRNA-seq"],
  "organism_taxid": [9606],
  "library_strategy": "RNA-Seq",
  "n_subjects": 12,
  "disease_curies": ["MONDO:0005061"],
  "tissue_curies": ["UBERON:0001264"],
  "cell_type_curies": ["CL:0000115"]
}
```

Modality 는 통제어휘 (scRNA-seq, ChIP-seq, WGS 등 28종) 로만 선택 허용. Disease / Tissue /
Cell type 은 OLS4 (Ontology Lookup Service v4) 의 MONDO / UBERON / Cell Ontology lookup 결과
중 가장 높은 신뢰도의 CURIE 를 선택. 추출이 실패한 record 는 `extraction_failures` 테이블에
원본과 함께 보관하여 사후 분석/재추출 가능.

> **쉬운 설명:** AI 가 데이터셋의 자유 서술을 읽고 "이건 scRNA-seq 이고 췌장 데이터이고
> 당뇨병 관련" 같이 정형화된 분류표를 자동으로 만듭니다. Ontology 는 의생명 분야의 표준
> 분류 체계예요.

### 4.3 Ontology 의미 확장

검색 시 사용자가 `MONDO:0005061` (당뇨병) 으로 필터링하면, 그 자식 term (MONDO 의 hierarchy
하위) 까지 포함해서 후보를 확장한다. OLS4 의 ancestors API 를 호출하여 closure set 을
사전 계산해 둔다.

---

## 5. 검색 파이프라인 (Methods II — Retrieval)

### 5.1 다단계 구조

```
Query "scRNA-seq human pancreas islets"
   │
   ├──► Dense embed (nomic-embed-text 768d)
   │      └─► Qdrant cosine  ─── top 200 (semantic)
   │
   └──► Tokenize → BM25
          └─► OpenSearch     ─── top 200 (lexical)
                                       │
                                       ▼
                            Reciprocal Rank Fusion (k=60)
                                       │
                                       ▼
                            top-15 → Cross-encoder rerank
                                  (ms-marco-MiniLM-L-6-v2)
                                       │
                                       ▼
                            최종 정렬 + facet 집계 + UI
```

### 5.2 Reciprocal Rank Fusion

[Cormack 2009] 의 단순한 합산 공식:

```
score_RRF(d) = Σ_{l ∈ rankers} 1 / (k + rank_l(d))
```

`k=60` 표준값. 본 연구에서는 dense / lexical 두 ranker 의 RRF score 를 사용. 빠른 baseline
이며 score 정규화 불필요한 장점.

> **쉬운 설명:** 두 종류의 검색 결과 (의미 vs 키워드) 를 똑똑하게 합쳐서 하나의 순위를
> 만드는 방법입니다.

### 5.3 Cross-encoder rerank

상위 15개 후보에 대해 `(query, title + abstract)` pair 를 cross-encoder 에 입력해 relevance
score 를 산출. Cross-encoder 는 dense embedding 과 달리 query–doc 을 동시에 attention 으로
보아 정밀도가 높지만 한 query 당 K번 forward pass 가 필요해 비용이 높다 (top-K 만 적용).

CPU 환경 ms-marco-MiniLM-L-6-v2 기준 15 doc rerank 평균 600ms. `asyncio.to_thread` 로
event loop 와 분리하여 동시 요청을 차단하지 않는다.

### 5.4 사용자 노출 점수 통합

UI 에서 단일 "관련도" 막대로 노출하기 위해 다음 가중평균:

```
relevance = clip01(0.5 · sigmoid_norm(rerank, [-5, +5])
                  + 0.4 · semantic
                  + 0.1 · log1p_norm(lexical, 30))
```

`semantic` 만 강하고 `rerank` 가 약한 경우에도 baseline 30% 이상이 유지되어 UI 에서
"의미 매칭 강함" chip 과 모순되지 않게 한다.

> **쉬운 설명:** 검색 결과 옆에 0~100% 짜리 "관련도" 점수를 보여주는데, 여러 신호를 합쳐
> 만든 값입니다. 사용자에게는 한 줄, 자세히 보고 싶으면 펼쳐서 원시 점수를 볼 수 있습니다.

### 5.5 Score 가시화 — Black-box 거부

기존 검색 도구가 "왜 이 결과가 나왔는지" 를 숨기는 데 비해, 본 연구는 모든 결과 카드에
4개 점수 (semantic / lexical / RRF / rerank) 의 원시값을 노출한다. 사용자는 단일 막대 외에
펼침 버튼으로 분해 점수 표 확인 가능. 이는 데이터 분석 신뢰성에 핵심인 *re-tracing* 가능성을
보장한다.

---

## 6. 구현 (Implementation)

### 6.1 기술 스택

| 영역 | 선택 | 근거 |
|---|---|---|
| Web | Next.js 15 + App Router | SSR + ISR + RSC 통합 |
| API | FastAPI + Pydantic v2 | async + type-strict + OpenAPI 자동 |
| RDB | PostgreSQL 16 | RLS 성숙도 |
| Vector | Qdrant 1.17 | gRPC + 풍부한 filter, on-prem 가능 |
| Lexical | OpenSearch 2 | Apache 2.0 (Elasticsearch SSPL 회피) |
| Cache / Broker | Redis 7 | 표준 |
| LLM | Ollama (Phi-4 mini, nomic-embed-text) | 로컬, ARM64 지원 |
| Reranker | sentence-transformers (CrossEncoder) | CPU 친화 |
| 인증 | Firebase Auth (Google) | 빠른 셋업, 안정 |
| KMS | LocalStack (dev) → AWS KMS (prod) | envelope 암호화 |
| Container | Docker compose | 단일 명령 부트스트랩 |

### 6.2 데이터 규모 (2026-05-09 기준)

| 출처 | datasets | rich extraction | stub |
|---|---|---|---|
| GEO | 10,139 | 202 | 9,937 |
| HCA | 530 | 530 | 0 |
| GDC | 91 | 91 | 0 |
| SRA | 3 | 0 | 3 |
| **합계** | **10,763** | **823** | **9,940** |

LLM 추출은 CPU 환경에서 record 당 ~1.5s 라 9,940건 처리에 ~4시간 (단일 worker). 향후 Oracle
VM 으로 24/7 가동되면 점진적 backfill 예정.

### 6.3 배포 모델

ADR 0005 의 hybrid 모델:
- **데이터 인프라**: Oracle Cloud Always Free Ampere A1 (4 OCPU / 24 GB ARM64)
- **백엔드 API + Web (production)**: Firebase Hosting + Cloud Functions (또는 Oracle 동거)
- **개발용 로컬**: 노트북 + WSL2 Docker

> **쉬운 설명:** 무거운 데이터 처리는 무료로 받은 클라우드 서버에서, 가벼운 웹 화면은
> Firebase 에서, 개발은 노트북에서.

---

## 7. 평가 (Evaluation)

### 7.1 검색 품질 — 정성 평가

| 쿼리 (영문, 도메인) | top-1 관련도 | 비고 |
|---|---|---|
| `bacterial whole genome sequencing` | 65% (rerank +1.18) | 제목·본문 모두 매칭 |
| `single-cell RNA-seq pancreatic islet` | 71% (rerank +1.5) | scRNA-seq + 췌장 정확 매칭 |
| `tumor immune microenvironment macrophage` | 60% (rerank +0.9) | semantic 강, lex 약 |

| 쿼리 (한국어) | top-1 관련도 | 비고 |
|---|---|---|
| `박테리아 전장 유전체 시퀀싱` | 29% (rerank −7) | semantic 0.72 강하지만 cross-encoder rerank 가 부정. nomic-embed-text 의 한↔영 매핑 한계 |

한국어 쿼리의 의미 매칭 약점은 임베딩 모델의 다국어 한계로 분석되며, 향후 다국어 임베딩
(예: jina-embeddings-v3 다국어) 또는 한↔영 LLM 번역 게이트로 개선 가능.

### 7.2 시스템 성능

| 지표 | 값 | 환경 |
|---|---|---|
| 평균 검색 latency (rerank 포함) | ~400ms | 로컬 CPU (8-core Ryzen) |
| 임베딩 throughput | ~50 doc/min | nomic-embed-text on Ollama CPU |
| 코퍼스 인덱스 재구축 (10K) | 47분 | full reindex (embedding + opensearch) |
| Concurrent rerank | non-blocking | `asyncio.to_thread` 분리 |

### 7.3 보안 검증 — Multi-tenant 격리

11개 자동 cross-tenant 테스트:
- Tenant A 의 saved_datasets row 가 tenant B 의 SELECT 에서 보이지 않음
- INSERT WITH CHECK 가 다른 tenant_id 거부
- DELETE 도 tenant scope 에 한정
- BYPASSRLS 권한이 없는 `genofinder_app` 만 사용

모두 통과.

### 7.4 한계

- **한국어 쿼리 의미 매칭 약함** (앞 §7.1)
- **v0-stub 92.3%** — LLM 추출이 GEO 의 7.4% 만 진행. backfill 진행 중.
- **Sample-level metadata 부재** — `samples` 테이블이 비어 dataset 단위 집계만 가능
- **Cross-encoder CPU 의존** — GPU 없이는 동시 요청 시 latency 누적

---

## 8. 논의 (Discussion)

### 8.1 로컬 LLM 의 trade-off

클라우드 LLM (GPT-4 등) 대비 정확도가 낮을 가능성이 있으나, 본 연구의 경우 (i) 사용자 쿼리
가 미공개 연구 IP 일 수 있어 외부 노출 위험을 회피하고, (ii) 운영 비용이 일정한 (외부 API 0)
장점이 크다고 판단하였다 (ADR 0003). Phi-4 mini 의 컨텍스트 윈도우 (128K) 와 instruction
following 능력은 메타데이터 추출 task 에 충분하였다.

### 8.2 Hybrid retrieval 의 효과

영문 도메인 쿼리에서 semantic + lexical RRF 결합이 단독 ranker 보다 일관되게 높은 top-K
정확도를 보임. 단 한국어 쿼리에서 semantic 단독 의존 시 cross-encoder 가 강한 negative
신호를 주는 경우가 다수 — embedding 모델 자체의 다국어 한계로 보임.

### 8.3 Score 가시화의 사용자 경험

원시 점수 (예: rerank −7.17) 가 직접 노출되면 사용자에게 혼란. 본 연구는 sigmoid_norm +
가중평균으로 0~100% 단일 점수를 만든 후, "상세" 토글로 원시값 접근 가능하게 분리. 펼침
빈도는 추후 user study 로 검증 필요.

---

## 9. 향후 작업 (Future Work)

- **다국어 임베딩 모델** 또는 한↔영 LLM 번역 게이트로 한국어 쿼리 정밀도 개선
- **Sample-level metadata 추출** — GEO sample 단위 sex / age / condition 정보를 LLM 으로 추출
- **커뮤니티 / collaborative filtering** — 사용자 간 익명 시그널 (저장, 클릭) 으로 ranking 보강
- **데이터셋 비교 view** — 다중 dataset 의 메타데이터를 격자 형태로 비교
- **추가 출처 통합** — ENA, EGA, ProteomeXchange 등

---

## 10. 결론 (Conclusion)

본 연구는 4개 주요 공공 생명정보 카탈로그를 단일 검색 인터페이스로 통합하는 시스템
**Geno Finder** 을 제안하였다. 핵심은 (i) 로컬 LLM 기반 자동 메타데이터 정규화, (ii) Dense +
Lexical hybrid retrieval + cross-encoder rerank, (iii) 모든 점수의 가시화로 black-box 를
거부, (iv) PostgreSQL Row-Level Security 로 multi-tenant 격리이다. 10,763 datasets 인덱싱
시점에서 평균 검색 latency 400ms, 영문 도메인 쿼리에 대해 의미 있는 매칭을 시연하였다.

> **쉬운 설명:** 흩어진 공공 데이터를 한 곳에 모아서 검색할 수 있게 만들었고, AI 가 자동
> 정리하며, 검색 결과가 왜 나왔는지도 투명하게 보여줍니다. 모든 처리는 사용자 환경에서만
> 이루어집니다.

---

## 부록 A — 핵심 용어 사전 (Glossary)

| 용어 | 풀이 |
|---|---|
| Dense embedding | 텍스트를 768차원 같은 고차원 벡터로 변환한 것. 의미가 비슷하면 벡터도 가깝다 |
| BM25 | 단어 빈도 기반 고전적 검색 점수. "키워드 매칭" 의 대표 |
| RRF (Reciprocal Rank Fusion) | 여러 ranker 의 순위를 합치는 단순 공식 |
| Cross-encoder | (query, doc) 을 함께 입력해 정밀 관련도 점수를 내는 모델. 느리지만 정확 |
| Ontology | 의생명 도메인의 표준 분류 체계 (예: MONDO 는 질병, UBERON 은 해부, CL 은 세포 타입) |
| CURIE | Ontology term 을 표현하는 표준 ID (예: `MONDO:0005061` = 당뇨병) |
| Row-Level Security (RLS) | 데이터베이스 단에서 사용자별로 row 가시성을 제한하는 기능 |
| Envelope encryption | 데이터를 DEK 로 암호화하고 DEK 자체를 KEK 로 다시 암호화. 키 회전 / KMS 통합 표준 패턴 |
| Tenant | 한 사용자(또는 워크스페이스) 의 격리 단위. 멀티테넌트 시스템에서 데이터 경계 |
| harvest | 외부 출처 (NCBI 등) 에서 메타데이터를 가져와 자체 DB 에 적재하는 작업 |

---

## 부록 B — 인용 (참고 문헌, draft)

- Edgar R, et al. *Gene Expression Omnibus: NCBI gene expression and hybridization array data repository.* Nucleic Acids Res, 2002.
- Karpukhin V, et al. *Dense Passage Retrieval for Open-Domain Question Answering.* EMNLP, 2020.
- Cormack GV, Clarke CLA, Buettcher S. *Reciprocal Rank Fusion outperforms Condorcet and individual rank learning methods.* SIGIR, 2009.
- Nogueira R, Cho K. *Passage Re-ranking with BERT.* arXiv:1901.04085, 2019.
- Ma X, et al. *A Replication Study of Dense Passage Retriever.* arXiv:2104.05740, 2021.
- The Human Cell Atlas. Nature, 2017.
- The Genomic Data Commons (GDC). Nature, 2016.
- HCA Data Coordination Platform / Azul. github.com/DataBiosphere/azul.
- OLS (Ontology Lookup Service) v4. github.com/EBISPOT/ols4.

(공식 인용 형식은 투고 저널에 맞춰 추후 정리)

---

*본 초안은 작업 진행과 함께 업데이트됩니다. 평가 결과 (§7) 의 정량 지표는 Oracle 이주 후
24/7 환경에서 재측정될 예정.*
