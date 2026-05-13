# Geno Finder 진행 현황

작성일: 2026-05-12

## 한 줄 요약

공공 생명정보 데이터셋(GEO/HCA/GDC/SRA) **10,763건** 을 인덱싱한 하이브리드 검색 시스템.
프론트엔드/백엔드/검색/인증 핵심 기능 모두 동작 + 데이터셋 상세 페이지에 **코호트 분포 시각화 / 실험 디자인 LLM 도식 / R·Python·Bash 다운로드 스니펫** 3종 신규 섹션. **로컬 개발 환경에서 완성**, 자체 호스팅 (Oracle Cloud) 만 capacity 대기 중.

## 완료된 작업

### 1. 인프라 / 데이터 기반
- ✓ Docker compose 스택 8개 컨테이너 (Postgres, Qdrant, OpenSearch, Redis, Ollama, LocalStack KMS, Celery worker / beat)
- ✓ PostgreSQL Row-Level Security 로 사용자 격리. RLS 자동 테스트 11건 통과
- ✓ Alembic 마이그레이션 0001~0003 (datasets / users-with-firebase-uid / users-nickname)
- ✓ DB role 분리: `genofinder` (마이그레이션 전용 superuser) ↔ `genofinder_app` (런타임 NOSUPERUSER)

### 2. 데이터 수확 (4개 source)
| 출처 | 건수 | 메서드 |
|---|---|---|
| GEO | 10,139 | NCBI E-utilities API + GEO esummary |
| HCA | 530 | Azul Data Browser API |
| GDC | 91 | NCI GDC REST API |
| SRA | 3 | pysradb |
- ✓ Celery beat 자동 정기 수확 (시작·종료 시각 watermark 기반 incremental)
- ✓ 일자 단위 dedup, ON CONFLICT UPDATE

### 3. 메타데이터 추출 + Ontology 매핑
- ✓ Local LLM (Ollama Phi-4 mini) — 외부 API 호출 0건
- ✓ 통제어휘 분류: scRNA-seq, ChIP-seq, WGS 등
- ✓ Ontology: MONDO (질병), UBERON (조직), CL (세포 타입) — OLS4 API
- 풍부 추출 진행률: **823 / 10,763 = 7.6%** (나머지 9,940건 v0-stub placeholder)

### 4. 검색 (Hybrid retrieval + Rerank)
- ✓ Dense embedding: nomic-embed-text 768-dim → Qdrant cosine
- ✓ Lexical: BM25 → OpenSearch
- ✓ RRF (Reciprocal Rank Fusion, k=60) 으로 두 신호 결합
- ✓ Cross-encoder rerank (ms-marco MiniLM-L-6-v2, top-15) — `asyncio.to_thread` 로 event loop 분리
- ✓ Ontology 의미 확장 (CURIE 검색 시 자식 term 까지)
- 평균 latency: ~400ms

### 5. 프론트엔드 (Next.js 15 + App Router)
- ✓ Sidebar (collapsible, 모바일 drawer) + 슬림 Header
- ✓ 다크모드 (CSS variables, 라이트/다크/시스템)
- ✓ i18n (한국어 / 영어, cookie 기반)
- ✓ 검색 결과 + 필터 (modality / source DB / disease / tissue / cell type / access)
- ✓ Pagination
- ✓ 데이터셋 상세 페이지 (헤더 카드 + 4 metric tile + TOC + 4-card 본문)
- ✓ 점수 분해 시각화 (관련도 단일 바 + 의미/단어 매칭 chip + 펼침/접기)
- ✓ 메타데이터 풍부도 도넛 + 9-필드 체크리스트
- ✓ 대시보드 (stats + 최근 데이터셋 + 추천 검색어)
- ✓ Loading skeleton (라우트별 `loading.tsx`) + NavigationProgress 바

### 6. 인증 (Firebase Auth)
- ✓ Google sign-in (popup)
- ✓ Backend `firebase-admin` ID 토큰 검증
- ✓ FastAPI dependency: `require_user` / `optional_user`
- ✓ Firebase uid → DB user → tenant_id 매핑 (1:1, lazy create)
- ✓ 로그인 페이지 / 마이페이지 / 프로필 설정 (닉네임 / 언어 / 다크모드)

### 7. 개인화
- ✓ 찜 (saved_datasets) — 서버 동기, RLS, optimistic UI + 모듈 cache 공유 동기
- ✓ 최근 본 (localStorage)
- ✓ Sidebar 에 카운트 배지

### 8. 테스트 / 검증
- API: **36 tests passed** (RLS T4, redaction T3, envelope encryption, firebase auth dependency, dataset cache, reranker, ontology, search e2e)
- Frontend: typecheck + production build clean
- 9 routes 모두 200 응답 확인

### 9. 디자인 / UX 정리
- ✓ 카피 한국어 자연스럽게 다듬음 (직역체 → 자연 종결)
- ✓ 사이드바·헤더 구분선 정렬
- ✓ Score breakdown 점수 0% 깔림 버그 수정 (semantic baseline 보존)
- ✓ 찜 풀림 race condition 해결 (cache 덮어쓰기 방지)
- ✓ API 0.0.0.0 바인딩 + reranker 비차단 (브라우저 ERR_CONNECTION_RESET 해결)

### 10. 데이터셋 상세 — 코호트 / 실험 디자인 / 다운로드 (2026-05-12 추가)
- ✓ **Alembic 0004** — `samples` 에 `sex / age_value / age_unit / disease_state / treatment` 5컬럼 + `datasets.cohort_design JSONB` + `cohort_design_version` 추가. 라이브 DB 적용 완료.
- ✓ **GEO Series Matrix harvester** (`apps/workers/src/harvesters/geo_matrix.py`) — NCBI FTP 의 `_series_matrix.txt.gz` fetch + 파서 + 정규화 사전 (sex M/F/남/여 등 → male/female; age 단위 통일). rate limit + tenacity retry. 50MB 하드 캡.
- ✓ **Sample indexer** + backfill 스크립트 — `samples` UPSERT + `summarize_samples` 집계 (성·연령 5-bucket·라벨 top10). `scripts/harvest_geo_samples.py` 로 concurrency / batch_commit 옵션 지원.
- ✓ **Cohort design LLM 추출** — `cohort_design extractor` (workers 측 batch + api 측 on-demand). JSON schema 강제로 그룹·역할·N·기준 + design_type 정형 출력. `extraction_version=cohort-v1-phi4-2026-05-12`.
- ✓ **API 신규 엔드포인트** — `GET /datasets/{id}/cohort` (precomputed view + Redis 1h 캐시), `POST /datasets/{id}/cohort/extract?force=` (on-demand LLM, timeout 90s for CPU cold start), `GET /datasets/{id}/snippets`.
- ✓ **다운로드 스니펫** — GEO (GEOquery / supp / GEOparse / FTP wget) / SRA (sra-toolkit / pysradb) / HCA (curl / requests) / GDC (REST API) 9 종 템플릿. 결정형 templating — 저장 안 함.
- ✓ **UI 신규 컴포넌트** — `CohortBreakdown` (성비 도넛 + 연령 히스토그램 + condition / treatment 막대), `ExperimentDesign` (그룹 카드 그리드 + role 별 색상 + "지금 분석하기" on-demand 트리거), `DownloadSnippets` (R/Python/Bash 탭 + 복사 버튼).
- ✓ **Next.js route handler** — `app/api/cohort-extract/route.ts` 가 backend POST 를 server-side proxy 해서 CORS 회피.
- ✓ **데이터셋 상세 페이지 통합** — 기존 4 섹션(요약/메타데이터/풍부도/기술정보)에 코호트·실험 디자인·다운로드 3개 추가. TOC 7 항목으로 확장. fetch 병렬화.
- **테스트**: workers +26 (Series Matrix 파서 12 + cohort extractor 14), api +26 (snippets 9 + cohort extractor 12 + cohort samples 5). 회귀 모두 통과.
- **Live smoke**: GSE317412 (mouse glutamine study, 14 samples) → Series Matrix fetch ✓ → samples 14건 sex+age UPSERT ✓ → cohort 응답 200 ms ✓ → 실험 디자인 LLM 추출 10.7s ✓ (control vs treatment 2그룹 추출).
- **Cohort design v2 (같은 날 개선)**: sample factor 분포 (raw_attributes 의 varying / constant 키) 도 prompt 에 포함. v1 의 "control/treatment" → **v2 의 "young (12wk) / old (68wk), design_type=cohort"** 로 정확도 향상. version `cohort-v2-phi4-2026-05-12`.
- **UI 픽스**: `AgeBars` 의 막대 height % 가 부모-자식 순환 참조로 어긋나던 버그 + 라벨 wrap 수정. 빈 disease/treatment fallback 메시지 명확화.

### 11. Accession 검색 + 한국어 번역 토글 (2026-05-12 추가)
- ✓ **Accession 검색** — OpenSearch `source_id` 매핑을 multi-field (text + keyword) 로 변경 + `source_id^15` boost. drop + reindex 10,873 건 10s. `POST /search "GSE317412"` → **#1 매칭** (rerank top, lexical 143).
- ✓ **한국어 번역 (on-demand)** — `services/translate.py` + `POST /datasets/{id}/translate?lang=ko`. Phi-4 mini + JSON schema. Redis 캐시 `gf:translate:ko:{uuid}` TTL 24h. cold 1m44s / cache hit **0.129s**.
- ✓ **Web 토글 UI** — `TranslatableContent` 클라이언트 컴포넌트, locale=ko 일 때만 토글 노출. 기본 원문 유지. title/abstract 양쪽 교체.
- ✓ **회귀**: workers 53 / api 66 / typecheck / build 12 routes 모두 통과. 알려진 한계: Phi-4 mini 의 한국어 long-context 에서 일부 영어 잔존 (품질 v2 후보).

## 진행 중

| 항목 | 상태 |
|---|---|
| Oracle Cloud Always Free Ampere A1.Flex (4 OCPU / 24 GB) capacity 확보 | 270+회 시도, 모두 capacity 부족. 한국 Chuncheon 리전이 빡셈. retry 스크립트 백그라운드 무한 시도 중 |

## 남은 작업

### 단기 (Oracle capacity 잡히면 즉시)
1. VM 부트스트랩
   - Tailscale 설치 (양쪽: 노트북 + Oracle VM) → 가상 LAN
   - Docker + docker-compose 설치
2. Docker 스택 Oracle 로 이주
   - postgres + qdrant + opensearch + redis + ollama + workers + beat 모두 24/7 가동
   - 옵션 A: 로컬 DB `pg_dump` + Qdrant snapshot → 복원
   - 옵션 B: Oracle 에서 처음부터 harvest (1-2일, 자연스럽게 v0-stub 도 풀려나감)
3. Ollama 모델 pull (phi4-mini, nomic-embed-text)
4. 노트북 `.env` 의 `DATABASE_URL` / `QDRANT_URL` / `OPENSEARCH_URL` / `REDIS_URL` / `OLLAMA_URL` 을 Oracle 의 Tailscale IP 로 변경
5. 검증: 검색 / 찜 / 인증 end-to-end

### 중기
- v0-stub 9,940건 LLM 풍부 추출 (Oracle 24/7 가동되면 자연 진행)
- **GEO sample-level backfill** — 10,139 GSE 전부 Series Matrix fetch + sample indexer (Oracle 가동 후 ~6-8시간 백그라운드). 현재 1건 (GSE317412) 만 fixture 로 들어가있음.
- **cohort_design 코퍼스 추출** — 10,139 GSE 모두 batch LLM 추출 (Phi-4 mini 평균 10s/건 × 10k = ~28시간 백그라운드). on-demand 폴백이 있으므로 안 해도 동작은 함.
- Firebase Hosting 에 web 배포 (외부 도메인 접근)
- API 도 Oracle 에 deploy (현재는 노트북에서 dev)
- 도메인 + HTTPS (Cloudflare 또는 Caddy)

### 장기 / 기능 확장
- 커뮤니티 (닉네임 기반 토론) — DB 스키마 + UI
- 검색 히스토리 + 알림 (saved_queries 활용)
- 여러 데이터셋 비교 분석 (장바구니 → 비교 뷰)
- 한국어 쿼리 의미 매칭 개선 (다국어 임베딩 또는 한↔영 게이트)
- ENA / EGA 등 추가 source DB
- sample-level 메타데이터 (현재 `samples` 테이블 비어있음)

## 차단 요인 / 의존성

- **Oracle capacity**: 글로벌 Always Free Ampere A1 의 한국 리전 capacity 부족이 가장 큰 차단 요인. retry 가 알아서 시도 중이라 사용자 개입 불필요. 일주일 안에 잡힐 가능성 높음.
- **노트북 가동 시간**: 현재 모든 게 노트북에서 돌아 노트북 끄면 harvest/index 도 멈춤. Oracle 이주 후 해결.

## 사용 / 검증 명령

```bash
# 전체 시스템 시작
~/bioinfo0929/work_7_search/genofinder/scripts/start-all.sh

# OCI retry 진행 확인
tail -f /home/hojin/bioinfo0929/work_7_search/oci-retry.log
grep -q '✓ SUCCESS' /home/hojin/bioinfo0929/work_7_search/oci-retry.log && echo '잡힘!' || echo '아직...'

# 웹 / API
http://localhost:3000
http://localhost:8000/api/v1/health
http://localhost:8000/api/v1/stats

# 신규 엔드포인트 (2026-05-12)
http://localhost:8000/api/v1/datasets/{uuid}/cohort         # GET — 코호트 분포 + (있으면) 실험 디자인
http://localhost:8000/api/v1/datasets/{uuid}/cohort/extract # POST — on-demand LLM 추출 (5-30s)
http://localhost:8000/api/v1/datasets/{uuid}/snippets       # GET — R/Python/Bash 다운로드 코드
http://localhost:8000/api/v1/datasets/{uuid}/translate?lang=ko  # POST — 한국어 번역 (캐시 24h)

# GEO sample-level backfill
cd apps/workers
DATABASE_URL=postgresql+asyncpg://genofinder:devpassword@localhost:5432/genofinder \
  uv run python -m scripts.harvest_geo_samples --limit 200 --concurrency 6
```

## 코드 베이스 구조

```
genofinder/
├── apps/
│   ├── api/             FastAPI + Pydantic v2
│   │   ├── src/routers  (search / datasets / me / stats / health / ontology)
│   │   ├── src/services (search / db / users / saved_datasets / reranker / ontology)
│   │   └── src/security (firebase_auth / tenant / kms / redaction / policies)
│   ├── web/             Next.js 15 + App Router
│   │   └── src/         (app / components / lib)
│   └── workers/         Celery beat + workers
│       └── src/         (harvesters / extractors / indexer)
├── docs/
│   ├── decisions/       ADR 0001~0005
│   ├── runbooks/
│   └── PROGRESS.md      (이 문서)
└── infra/compose/       Docker compose dev 스택
```

## ADR (Architecture Decision Records)

- 0001 Tech Stack — Next.js 15 / FastAPI / Postgres 16 / Qdrant / OpenSearch
- 0002 Threat Model — T1~T10 보안 위협 모델
- 0003 LLM Vendor — Ollama (외부 API 호출 X)
- 0004 LLM Models — Phi-4 mini (3B Q4) + nomic-embed-text
- 0005 Auth — Firebase + Hybrid Hosting (Firebase 호스팅 + Oracle 백엔드)
