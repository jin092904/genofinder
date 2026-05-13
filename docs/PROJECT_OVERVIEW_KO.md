# Geno Finder — 프로젝트 한눈에 보기

> 비전문가도 이해할 수 있게 풀어 쓴 종합 안내서.
> 코드 깊이 들어가지 않고 "이게 뭐고, 어디까지 왔고, 어디로 가는지" 파악하는 용도.

---

## 1. 한 줄로

**생물학 연구자가 자기 연구에 쓸 만한 공개 실험 데이터를 자연어로 검색하는 사이트.**

비유하자면 "과학용 알라딘 중고서점 검색" — 누군가 이미 실험을 끝내고 데이터를 공개해둔 것을 검색해서 자기 연구에 재활용할 수 있게 함.

---

## 2. 왜 이 서비스가 필요한가

생물학·의학 연구는 한 번 실험할 때 비싸. 한 사람의 단일세포 RNA 시퀀싱 한 번에 수백만~수천만원 들어.

그래서 학술 정책상 연구자는 **실험 데이터를 공개해야** 해. 그게 NCBI, EBI 같은 공공 데이터베이스에 쌓여있고, 28만 개+ 가량 있어.

문제는 **검색이 답답해**:
- NCBI 검색은 키워드 매칭만 해서 "단일세포 췌장암 면역" 같은 자연어 쿼리는 잘 못 잡음
- 검색 결과의 "왜 이게 추천되는지" 설명이 없어 (블랙박스)
- modality (RNA-seq vs ChIP-seq vs WGS), 질병, 조직 등으로 정밀하게 필터하기 어려움

**Geno Finder가 하는 것** (마스터 플랜 §1.2 "차별화 포인트"):
1. **자연어 연구 디자인 입력** — "PBMC 단일세포 면역응답" 같은 한 문장
2. **AI 기반 의미 매칭** + 키워드 매칭 동시 사용
3. **점수 분해 노출** — 각 결과가 왜 추천됐는지 (의미 점수, 키워드 점수, 종합) 보여줌
4. **모달리티/질병/조직 자동 분류** — 연구자가 정밀 필터링

---

## 3. 어떻게 작동하나 (4단계)

```
[1] 수확 (Harvest)         [2] 이해 (Extract)        [3] 색인 (Index)         [4] 검색 (Search)
─────────────────         ───────────────         ──────────────         ─────────────────
NCBI/EBI 등에서  →   AI가 제목·초록 읽고  →  검색 가능한    →  사용자 쿼리 →
"이 데이터셋의      "이건 단일세포      두 가지 인덱스에  매칭 + 정렬 →
제목은 X, 초록은    RNA-seq, 폐암,     저장:                결과 카드
Y, 종은 Z" 정보     T 세포 연구"라고   - 의미 검색용
받아오기            태그 붙임          - 키워드 검색용
```

각 단계를 더 풀어보면:

### [1] 수확 — NCBI에서 데이터 받아오기
- 정해진 시간 단위 (지난 90일 등) 안에 갱신된 데이터셋 ID 목록을 받음
- 각 ID에 대해 상세 정보 (제목, 초록, 종, 플랫폼 등) 받아와 **DB**에 저장

### [2] 이해 — 로컬 AI가 카테고리 부여
- **Phi-4 mini** (마이크로소프트의 작은 AI) 가 제목+초록을 읽음
- 출력: `{모달리티: "scRNA-seq", 질병: ["폐암"], 조직: ["폐"], 세포타입: ["T세포"]}`
- 그 후 **OLS4** (영국 생물정보 표준 데이터베이스) 가 "폐암" → `MONDO:0008903` 같은 표준 ID로 정규화

### [3] 색인 — 두 종류의 검색 인덱스에 저장
- **Qdrant** (의미 검색 DB): 제목+초록을 768차원 숫자 벡터로 변환해 저장. "비슷한 의미" 검색에 강함
- **OpenSearch** (키워드 검색 DB): 단어 단위로 인덱싱. "정확한 단어" 매칭에 강함

### [4] 검색 — 사용자 쿼리 처리
1. 사용자가 입력한 자연어 쿼리도 768차원 벡터로 변환
2. Qdrant 에서 가장 비슷한 50개 + OpenSearch 에서 가장 매칭 잘 되는 50개를 동시에 가져옴
3. **Reciprocal Rank Fusion** 알고리즘으로 두 결과 병합
4. **Cross-encoder** (작은 정밀 AI) 로 상위 20개를 다시 재정렬 (정밀도 ↑)
5. 최종 결과를 점수 분해와 함께 사용자에게 표시

---

## 4. 보안 — "왜 이렇게 빡빡한가"

연구자가 "내가 어떤 새 가설을 세우고 있는지" 검색하면, **그 쿼리 자체가 출판 전 IP** 야. 경쟁자에게 새면 큰일.

그래서 다음을 빡빡하게 처리:

| 위협 | 우리의 대응 |
|---|---|
| 운영자가 사용자 쿼리 평문 열람 | DB에 저장 시 envelope 암호화 (각 사용자별 키) |
| LLM 회사가 사용자 쿼리를 학습 사용 | **로컬 Phi-4 mini 만 사용**, 외부 LLM (OpenAI/Anthropic) API 호출 0건 |
| 다른 사용자가 내 데이터 접근 | DB 단의 Row-Level Security 로 차단 (코드 레벨이 아니라 DB가 직접 거부) |
| 로그에 쿼리 본문 잔존 | structlog 의 redact processor 가 로그 출력 직전에 SENSITIVE_KEYS 검열 |
| Prompt injection 공격 | 입력 sanitize + JSON schema 강제 + 회귀 테스트 12종 |

---

## 5. 현재 어디까지 만들어졌나

### 작동하는 기능 (v0.8 — 2026-05-12)

| 분야 | 상태 |
|---|---|
| 백엔드 검색 API | ✓ — `POST /search`, `GET /datasets/{id}` 등 |
| 프론트엔드 | ✓ — 랜딩 + 검색 + 상세 페이지, ko/en 토글, Firebase 로그인, 찜·최근본 |
| AI 카테고리 추출 | ✓ — Phi-4 mini 로 modality + disease + tissue + cell_type |
| Cross-encoder 재정렬 | ✓ — top 15-20 정밀도 향상 |
| Redis 캐시 | ✓ — 상세 페이지 50배 빠르게 |
| 보안 (T1, T3, T4, T8, T9) | ✓ — 5/10 위협 모델 control 작동 + 자동 회귀 테스트 |
| 데이터 코퍼스 | ✓ — 10,763 datasets 인덱싱 (GEO 10,139 / HCA 530 / GDC 91 / SRA 3) |
| **코호트 분포 시각화** (신규) | ✓ — 상세 페이지에서 성비 도넛 + 연령 5-bucket + condition/treatment 라벨 막대 |
| **실험 디자인 LLM 도식** (신규) | ✓ — 그룹 카드 (case·control·treatment·comparison 색상). precomputed + on-demand fallback (`POST /cohort/extract`) |
| **R / Python / Bash 다운로드 스니펫** (신규) | ✓ — GEO·SRA·HCA·GDC 9 템플릿. 탭 전환 + 복사 버튼 |
| **Accession 검색** (신규) | ✓ — `GSE317412` 같은 ID 로 검색 시 해당 데이터셋이 1순위 매칭. OpenSearch `source_id^15` boost |
| **한국어 번역 토글** (신규) | ✓ — 한국어 모드 한정 토글. Phi-4 mini on-demand 호출 → Redis 캐시 24h. 기본은 원문 (영어) 유지 |

### 자동화된 테스트
- API 55개 + 워커 50개 = **105개 테스트 통과** (DB 의존 25개는 인프라 미가동 시 skip)

### 설치된 인프라 (Docker)
- Postgres 16 (DB)
- Redis (캐시 + Celery 큐)
- Qdrant (의미 검색)
- OpenSearch (키워드 검색)
- Ollama + Phi-4 mini + nomic-embed-text (로컬 AI)
- LocalStack (KMS 모의)

---

## 6. 앞으로의 개발 계획

### Phase A — 로컬 완성 (현재 진행 중)
**목표**: 모든 기능을 로컬 노트북에서 검증 + 풍부한 데이터로 채우기

- [x] 검색 + AI 추출 + 재정렬 + 캐시
- [x] 5/10 보안 control
- [x] **GEO 1만 ingest** (10,139건 + HCA 530 + GDC 91 + SRA 3 = 10,763)
- [x] HCA harvester
- [x] GDC harvester
- [x] **상세 페이지 코호트·실험 디자인·다운로드 스니펫 3종** (2026-05-12)
- [ ] **GEO sample-level backfill** — Series Matrix file 10,139건 fetch + sample indexer (~6-8시간 백그라운드)
- [ ] **cohort_design 코퍼스 추출** — Phi-4 mini 로 10k 데이터셋 batch (~28시간). on-demand 폴백 있으므로 옵션.
- [ ] GEO 전체 (28만) bulk — ~8시간 백그라운드
- [ ] SRA / ENA partial 추가 — sequencing reads
- [ ] **자동 정기 갱신** — Celery beat 스케줄러 (매일 새벽 GEO/HCA/GDC 자동 update)
- [ ] 6주차 보안 control 추가 — 임베딩 inversion 방어 (T7)

### Phase B — 클라우드 deploy (Phase A 끝난 후)
**목표**: 노트북 닫아도 24/7 운영, 외부 사용자 접속 가능

- Oracle Cloud Free Tier 추천 (4코어 ARM + 24GB RAM 영구 무료)
- 로컬 docker-compose 그대로 옮겨 배포
- 도메인 + HTTPS (Caddy reverse proxy)
- Postgres 자동 백업 (daily pg_dump → off-site)

**예상 작업량**: ~1일

### Phase C — 운영화 (Phase B 후)
**목표**: 안정 운영 + 진짜 사용자 받기

- CI/CD: GitHub push → 자동 deploy (GitHub Actions)
- 모니터링: Grafana Cloud (free tier) + 로그 집계
- 진짜 인증: Clerk + MFA (마스터 플랜 Week 10)
- Saved query 서버 영속화 + envelope encryption 실제 사용
- 결제: Stripe (Pro/Lab tier)
- Cross-encoder fine-tune (도메인 특화 모델로 정확도 ↑)
- 대용량 source 추가 (SRA 4천만 study-level 풀)

**예상 작업량**: ~3-5일

### Phase D — 확장 (장기)
- 더 많은 source: dbGaP, EGA (controlled access — 법적 검토 필요)
- 모바일 친화 UI 또는 native app
- API for 컴퓨팅 파이프라인 통합 (nf-core samplesheet export 등)
- 알림 — 저장한 쿼리에 새 데이터셋 등록 시 이메일

---

## 7. 폴더 구조 한 눈에

```
work_7_search/
├── 기획/                                  최초 디자인 + 마스터 플랜
│   ├── IMPLEMENTATION_PROMPT.md            745줄 마스터 설계서 (이 모든 것의 출발점)
│   └── stitch_genomic_dataset_discovery_platform/
│       └── (4개 페이지 디자인 mockup)
│
└── genofinder/                            실제 코드
    ├── apps/
    │   ├── api/                            FastAPI 백엔드 — 검색·datasets·ontology·cohort·snippets
    │   │   └── src/
    │   │       ├── routers/                  엔드포인트 (search, datasets, cohort, snippets, ontology, me, stats, health)
    │   │       ├── services/                 비즈니스 로직 (search, dataset, reranker, ontology, cohort, cohort_samples, cohort_extractor, snippets)
    │   │       ├── security/                 envelope encryption, redaction, RLS middleware
    │   │       └── alembic/                  DB 마이그레이션 (스키마 변경 이력, 0001~0004)
    │   │
    │   ├── web/                             Next.js 프론트엔드
    │   │   └── src/
    │   │       ├── app/                      페이지 라우팅 (/, /search, /datasets/[id], /me/saved 등) + api/cohort-extract (server-side proxy)
    │   │       ├── components/               재사용 UI 컴포넌트 (ResultCard, Filters, CohortBreakdown, ExperimentDesign, DownloadSnippets, …)
    │   │       └── lib/                      API 클라이언트, i18n, localStorage hooks
    │   │
    │   └── workers/                         Celery 백그라운드 작업
    │       └── src/
    │           ├── harvesters/               GEO + GEO Series Matrix (sample-level), SRA, HCA, GDC
    │           ├── extractors/               LLM 호출 + 입력 sanitize (structurer, ontology, cohort_design)
    │           ├── ontology/                 OLS4 mapper (curie 정규화)
    │           └── indexer/                  DB UPSERT + Qdrant + OpenSearch 색인 (samples 포함)
    │
    ├── packages/
    │   ├── shared-schemas/                  Pydantic 모델 (api ↔ web 공유 예정)
    │   └── eval/                            평가 데이터셋 + 점수 (랭킹 회귀 테스트)
    │
    ├── infra/
    │   ├── docker/                          Dockerfile (api, workers, web)
    │   ├── compose/                         docker-compose.dev.yml + postgres-init.sql
    │   └── lint/                            semgrep 보안 규칙 (외부 LLM SDK 차단 등)
    │
    └── docs/
        ├── PROJECT_OVERVIEW_KO.md            ← 이 문서
        ├── external-apis.md                  외부 API 검증 결과 (NCBI, EBI 등)
        ├── decisions/                        ADR (Architecture Decision Records)
        │   ├── 0001-tech-stack.md
        │   ├── 0002-threat-model.md
        │   ├── 0003-llm-vendor.md             "왜 로컬 LLM만 쓰는가"
        │   └── 0004-llm-models.md             "Phi-4 mini + nomic-embed-text"
        ├── runbooks/local-env.md              "내 노트북 환경 어떻게 됐나"
        └── weekly/w01.md                     주간 진행 기록
```

---

## 8. 자주 쓰는 명령어 (내일 다시 작업 시작할 때)

```bash
cd /home/hojin/bioinfo0929/work_7_search/genofinder

# 데이터 서비스 켜기 (postgres/redis/qdrant/opensearch/ollama/kms)
docker compose -f infra/compose/docker-compose.dev.yml up -d

# 백엔드 API 켜기 (다른 터미널 권장)
cd apps/api
QDRANT_URL='http://localhost:6333' OPENSEARCH_URL='http://localhost:9200' \
OLLAMA_URL='http://localhost:11434' REDIS_URL='redis://localhost:6379/0' \
DATABASE_URL='postgresql+asyncpg://genofinder_app:devpassword@localhost:5432/genofinder' \
RERANKER_TOP_N='15' \
uv run uvicorn src.main:app --host 127.0.0.1 --port 8000

# 프론트 켜기 (또 다른 터미널)
cd apps/web
API_BASE_URL='http://localhost:8000' pnpm dev

# 브라우저: http://localhost:3000

# 테스트 돌리기
cd apps/api && uv run pytest    # 55개 (DB 의존 25개는 인프라 미가동 시 skip)
cd apps/workers && uv run pytest  # 50개

# 데이터 추가로 받기 (시간창·max 변경 가능)
cd apps/workers
set -a; source ../../.env; set +a
DATABASE_URL='postgresql+asyncpg://genofinder:devpassword@localhost:5432/genofinder' \
QDRANT_URL='http://localhost:6333' OPENSEARCH_URL='http://localhost:9200' \
OLLAMA_URL='http://localhost:11434' \
uv run python -u scripts/harvest_geo_large.py --days 90 --max 10000

# AI 카테고리 추출 (선택, ~50분 / 200건)
DATABASE_URL='postgresql+asyncpg://genofinder:devpassword@localhost:5432/genofinder' \
QDRANT_URL='http://localhost:6333' OPENSEARCH_URL='http://localhost:9200' \
OLLAMA_URL='http://localhost:11434' \
uv run python scripts/reextract_with_ontology.py --limit 500

# GEO sample-level backfill (Series Matrix 파일 → samples 테이블)
DATABASE_URL='postgresql+asyncpg://genofinder:devpassword@localhost:5432/genofinder' \
uv run python -m scripts.harvest_geo_samples --limit 200 --concurrency 6
```

---

## 9. 용어 사전 (필요할 때만 펼쳐 보세요)

- **GEO / SRA / ENA / HCA / GDC**: 공공 생명과학 데이터베이스. 한국은 KISTI 등이 있는데, 학계 표준은 미국(NCBI)·유럽(EBI).
- **Series Matrix file**: GEO 의 study 한 건당 텍스트 파일. 안에 `!Sample_characteristics_ch1` 라인으로 sample 별 sex/age/condition 등이 들어있음. 본 프로젝트의 sample-level 시각화 source.
- **cohort_design (코호트 디자인)**: 한 데이터셋의 실험 그룹 구조. case vs control, treatment 등 어떻게 나뉘었는지. LLM 이 abstract + sample 라벨에서 추출.
- **modality**: 실험 종류. RNA-seq, ChIP-seq, WGS 등. "어떤 분석법을 썼느냐".
- **MONDO / UBERON / CL / EFO**: 표준 의학·생물 ontology. 각각 질병 / 해부학 / 세포타입 / 실험.
- **curie**: ontology의 고유 ID. 예: `MONDO:0008903` = 폐암.
- **embedding**: 텍스트를 수백 차원 숫자 벡터로 바꾼 것. 비슷한 의미는 비슷한 벡터.
- **Qdrant**: 벡터 검색 전용 DB. "이 벡터와 비슷한 벡터 50개 줘" 식 쿼리.
- **BM25**: 1990년대 키워드 검색 알고리즘. 여전히 가장 강력한 baseline. OpenSearch가 기본 사용.
- **RRF (Reciprocal Rank Fusion)**: 두 검색 결과 (의미 + 키워드) 를 합치는 표준 알고리즘.
- **Cross-encoder**: 쿼리와 문서를 함께 보고 정밀하게 점수 매기는 작은 AI. 정렬 정확도 ↑.
- **envelope encryption**: 데이터 암호화 키 (DEK) 자체를 다른 마스터 키 (KEK) 로 암호화하는 패턴. AWS/GCP KMS 표준.
- **RLS (Row-Level Security)**: PostgreSQL 기능. "이 사용자는 이 row만 볼 수 있다" 를 DB가 직접 강제.
- **Celery / Celery beat**: Python의 표준 백그라운드 작업 / 스케줄러. cron 같은 정기 실행.
- **ADR (Architecture Decision Record)**: "왜 이렇게 결정했나" 문서. 후임자 또는 미래의 자기가 보고 이해할 수 있게.
- **마스터 플랜**: `기획/IMPLEMENTATION_PROMPT.md`. 12주 마일스톤 + 보안 모델 + 13개 첫 행동 지시.

---

## 10. 막힐 때 어디 보나

- 전체 설계 의도 → `기획/IMPLEMENTATION_PROMPT.md` (745줄, 보스 문서)
- 외부 API 어떻게 쓰나 → `docs/external-apis.md`
- 왜 이런 결정을 → `docs/decisions/000X-*.md`
- 환경 설정 (내 노트북 사양 등) → `docs/runbooks/local-env.md`
- 매주 무얼 했나 → `docs/weekly/w01.md`
- 보안 위협 모델 → `docs/decisions/0002-threat-model.md`
- LLM 모델 선택 사유 → `docs/decisions/0003-llm-vendor.md`, `0004-llm-models.md`
