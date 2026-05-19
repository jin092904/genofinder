# Geno Finder — 시스템 보고서

> 한 페이지 요약 · 5분 안에 읽기.
> 더 깊이 보려면: [PROJECT_OVERVIEW_KO.md](PROJECT_OVERVIEW_KO.md) (비전문가용 종합), [PAPER_DRAFT.md](PAPER_DRAFT.md) (학위논문 챕터), [paper_en/manuscript.md](paper_en/manuscript.md) (Genomics & Informatics 영문 투고).

작성일: 2026-05-14 → 2026-05-19 갱신 (v1.0 full corpus batch Step 4/7 진행 중)

---

## 1. 한 줄로

**연구자가 자기 실험에 쓸 공개 생명정보 데이터셋을 자연어로, 한국어든 영어든, 찾을 수 있게 해주는 검색 엔진.**

비유: NCBI GEO / HCA / GDC / SRA 흩어진 데이터 카탈로그에 *"단일세포 BCG 면역 응답"* 같은 자연어로 질문하면, 의미·키워드·연구디자인을 동시에 보는 다단계 검색이 *왜 이 결과인지 점수까지 설명* 하면서 답을 돌려줍니다. 모든 AI 처리는 연구실 GPU 안에서 끝나 외부로 데이터가 새지 않습니다.

---

## 2. 왜 이게 필요했는가

| 문제 | 현실 |
|---|---|
| 데이터가 4 곳에 흩어져 있다 | GEO 28만 / HCA 530 / GDC 91 / SRA 4400만 — 각 카탈로그 인터페이스 따로 |
| 메타데이터가 자유 서술 | scRNA-seq vs single-cell vs 단일세포 — 키워드 매칭 깨짐 |
| 연구 디자인은 더 안 잡힘 | "대조군과 치료군 비교" 같은 그룹 구조는 abstract 안에 숨어있음 |
| 한국어 연구자에게 영어 벽 | NCBI 검색창은 한국어 입력에 약함 |
| LLM 으로 요약하면 IP 위험 | 클라우드 LLM 에 가설을 통째로 흘리는 게 publish 전까지는 부담 |

---

## 3. 아키텍처 (4 계층)

```
┌────────────────────────────────────────────────────────────────┐
│  CLIENT  Next.js 16 (App Router, Turbopack)                    │
│          Firebase Auth (Google sign-in) → Bearer ID token       │
└────────────┬────────────────────────────────────────────────────┘
             │
┌────────────▼────────────────────────────────────────────────────┐
│  API     FastAPI + Pydantic v2                                   │
│   • POST /search           (하이브리드 검색)                     │
│   • GET  /datasets/{id}    (상세 + 코호트 + 다운로드 스니펫)     │
│   • POST /datasets/{id}/translate?lang=ko (한국어 번역 on-demand)│
│   • POST /datasets/{id}/cohort/extract    (실험 그룹 추출)       │
└──┬────────┬──────────┬───────────┬───────────────────────────────┘
   │        │          │           │
   ▼        ▼          ▼           ▼
┌──────┐ ┌─────┐ ┌────────┐  ┌──────────┐
│PG 16 │ │Redis│ │Qdrant  │  │OpenSearch│  ← 검색·캐시·관계
│ RLS  │ │ 8   │ │1024d v2│  │  2.16    │
└──────┘ └─────┘ └────────┘  └──────────┘
                      │           │
                      └─────┬─────┘
                            │
              ┌─────────────▼──────────────┐
              │  Ollama 0.23 @ port 11435  │
              │  • Gemma 4 31B Q4 (gen)    │  ← 추출·번역·코호트
              │  • Qwen3-Embedding-8B M-1024 (index)
              │  • Qwen3-Reranker-0.6B (rerank)
              └────────────────────────────┘
                   GPU 5 (A100 80GB)
```

**핵심 운영 결정:** 학내 공유 HPC 의 podman 제약 (subuid 미할당 + CDI 미지원) 우회를 위해 **모든 서비스가 컨테이너 없이 호스트 binary 로 직접** 가동. `scripts/a100-native-bootstrap.sh` 한 줄 실행이면 stack 전체 가동.

---

## 4. 데이터 흐름 (4 단계)

```
[1] HARVEST          [2] EXTRACT          [3] INDEX            [4] SEARCH
NCBI/HCA/GDC/SRA →   Gemma 4 가 자유      Qdrant (의미) +      자연어 질문 →
incremental fetch    서술 → modality /    OpenSearch (단어)    embed → 양쪽 top200
(watermark 기반)     ontology CURIE /                          → RRF (k=60)
                     cohort design        Matryoshka 1024d     → top15 → 
                     JSON 구조화          truncate             Qwen3-Reranker
                                                              → score 분해 UI
```

각 단계가 idempotent (재실행 안전), incremental (변경분만 처리), local-only (외부 LLM 호출 0).

---

## 5. 핵심 기술 스택 (v1.0)

| 영역 | 선택 | 한 줄 |
|---|---|---|
| Web | Next.js 16 + App Router | SSR + RSC + Turbopack |
| API | FastAPI + Pydantic v2 | async + 타입 강제 + OpenAPI |
| RDB | PostgreSQL 16 (RLS) | 사용자 간 row 단위 격리 강제 |
| Vector | Qdrant 1.12 | 1024d Matryoshka |
| Lexical | OpenSearch 2.16 | BM25 (Apache 2.0, SSPL 회피) |
| Cache | Redis 8 | translate / detail / search |
| Batch LLM | **Gemma 4 31B Q4** | 다국어 + 코호트 + 한국어 번역 |
| Embedding | **Qwen3-Embedding-8B → 1024d** | MTEB Multi 70.58 (1위) |
| Reranker | **Qwen3-Reranker-0.6B** | Apache 2.0, 100+ 언어 |
| Auth | Firebase (Google) | popup sign-in |
| 인프라 | **Native host binary** | 컨테이너 의존성 폐기 |

전체 license 가 Apache 2.0 / MIT / Gemma 으로 상업적 사용 가능.

---

## 6. 차별화 포인트 (5)

1. **다국어 1-stack** — 동일 시스템이 영어 / 한국어 쿼리 모두 처리. 별도 번역 게이트 불필요 (Qwen3 시리즈가 native 다국어).
2. **연구 디자인까지 자동 추출** — `case / control / treatment / comparison` 라벨 + 그룹별 n + design_type 까지 LLM 으로 정형화 → UI 의 실험 그룹 카드.
3. **점수 가시화 (black-box 거부)** — semantic / lexical / RRF / rerank 4 개 신호를 모두 사용자에게 노출. 단일 막대 외에 "상세" 토글로 원시값 확인 가능.
4. **외부 API 호출 0건 (LLM 측)** — 사용자 쿼리 / abstract 가 클라우드에 노출되지 않음. 모든 추론은 학내 GPU.
5. **컨테이너 없이 재현 가능한 배포** — `subuid` 없는 학내 공유 HPC 에서도 1인 사용자가 admin 협조 없이 부트스트랩 가능 (`a100-native-bootstrap.sh` 한 줄).

---

## 7. 보안 / 프라이버시

| 위협 | 대응 |
|---|---|
| 운영자가 쿼리 평문 열람 | DB 저장 시 envelope 암호화 (per-tenant DEK) |
| 클라우드 LLM 이 쿼리 학습 사용 | 외부 LLM 호출 0건, 모든 추론 local Ollama |
| 다른 사용자가 내 데이터 접근 | PostgreSQL Row-Level Security (FORCE 모드, BYPASSRLS 비활성 role) |
| 로그에 쿼리 잔존 | structlog redact processor 가 SENSITIVE_KEYS 출력 직전 검열 |
| Prompt injection | `<user_input>` wrapping + JSON schema 강제 + 회귀 테스트 12종 |
| Multi-tenant cross-read | 11개 자동 회귀 테스트 (SELECT / INSERT / DELETE 모두) |

---

## 8. 현재 데이터 규모 (v1.0 full corpus batch, 2026-05-19 13:18 시점)

| 출처 | 상태 | 수치 |
|---|---|---|
| **GEO** | ✅ harvest 완료 (2026-05-15) | **283,871 건** (전체 ~284k 의 99.7%) |
| HCA | △ incremental watermark 기준 0 추가 | (v0.8 의 530건은 별도 backfill 가능) |
| GDC | ✅ 전체 | 91 건 |
| SRA | (다음 release) | — |
| **합계** | datasets | **283,962 건** |
| **samples (GEO Series Matrix)** | ✅ backfill 완료 (2026-05-18) | **7,473,065 건** (distinct datasets 249,256, no-matrix 34,618) |
| **LLM extraction** | ⏳ 진행 중 (Step 4) | **38,240 / 283,962 (13.5%)** |
| Qdrant (1024d embedding) | ⏳ Step 5 에서 reindex | 0 (현재) |
| OpenSearch (BM25) | ⏳ Step 5 에서 reindex | 0 (현재) |

### Batch 진행 실적 + 잔여 (실측 기반)

```
✅  Step 1   GEO harvest           5/14 ~ 5/15    283,871 건 (NCBI key 효과 7.6 rps)
✅  Step 1.5 HCA + GDC             5/14           HCA 0, GDC 91
✅  Step 3   Sample backfill       5/16 ~ 5/18    744만 samples / 42시간
⏳  Step 4   LLM 추출 (gemma4)     5/18 ~  ?      현재 38k, 2.5초/건 (예상 4초보다 빠름)
                                                    잔여 246k → ~7일 남음
↻   Step 5   Embedding + lexical reindex          ~1-2일 (batched 1000/chunk patch 적용 후)
↻   Step 7   Dump bundle                          5분
─────────────────────────────────────────────────────────────
종료 예상: 2026-05-26 ~ 5-28 (현 속도 유지 시)
```

### 사고 회복 history (참고)

| 시점 | 사고 | 회복 |
|---|---|---|
| 5/15 03:00 | OpenSearch bulk 413 (28만 record 단일 페이로드 1.4GB) | `lexical.py upsert_many` 를 batch_size=1000 으로 분할 patch + push (commit `1cac04c`) |
| 5/15 ~ 5/16 | chain wrapper script 종료 후 33시간 idle | `scripts/a100-resume-from-extract.sh` 작성, Step 3 부터 재개 |

### 가속 가능 옵션 (현재 미적용)

다른 사용자가 GPU 1-4 점거 중이라 GPU 5 단일 모드. 만약 GPU 가 풀리면:
- GPU 2 장 + `OLLAMA_NUM_PARALLEL=2` + reextract stride=2 → ~3-4일 단축
- GPU 4 장 → ~5일 단축 (Step 4 가 3-4일로)

`scripts/a100-full-db-cycle.sh` 의 `FULLCYCLE_TARGET_GPUS` 환경변수로 동적 결정.

---

## 9. 한계 / 알려진 trade-off

- **GPU 1장 점유 (현재)**: 다른 사용자가 GPU 0-4 점거 중이라 우리는 GPU 5 만 사용 — single process LLM 추출 모드 (~7일 잔여). GPU 풀리면 N-process fork 로 가속 가능 (`FULLCYCLE_TARGET_GPUS` 환경변수).
- **gemma4 + Qwen3-Embedding 동시 적재 불가**: 각각 47GB + 16GB. `OLLAMA_MAX_LOADED_MODELS=1` 정책상 단계별 swap (5분 unload + reload). batch wall-clock 에 영향 미미.
- **한국어 정량 검색 품질 측정 미완**: v0.8 (nomic + ms-marco) 의 한국어 약점이 v1.0 (Qwen3 통일 stack) 으로 얼마나 개선됐는지 정량 평가는 batch 완료 후 30 ground-truth 쿼리 + 4-system ablation 으로 진행 예정 (논문 figure 1순위 후보).
- **GEO 전체 인덱싱 wall-clock**: 현재 hardware 로 ~7-10일 (이번 batch 진행 중). 만약 미래에 추가 사이클 필요하면 incremental beat 로 점진 채우기 권장 (매일 ~1-2시간).
- **SRA 미통합**: 4400만 run 단위는 BioProject 로 압축해도 수십만 → 별도 release.
- **Translate top-N**: uvicorn API 가동된 상태에서만 동작. batch 단독으로는 skip. 정식 서빙 (T1000) 가동 후 별도 호출 권장.
- **OpenSearch bulk payload 한계** (해결됨, 2026-05-15): 28만 record 한 번에 1.4GB → 413 Payload Too Large. `lexical.upsert_many` 의 batch_size=1000 분할로 회피.

---

## 10. 전체 개발 진행도 — 영역별 완성률

| # | 영역 | 완성도 | 비고 |
|---|---|---|---|
| 1 | 기획 / ADR 설계 | **100%** ✅ | ADR 0001~0006, migration_v2, threat model |
| 2 | 데이터 수집 (harvest) | **95%** | GEO+HCA+GDC ✅, SRA 미통합 |
| 3 | 메타데이터 추출 (LLM gemma4) | **20% (진행 중)** | 38k/284k, 5/26 종료 예상 |
| 4 | Sample-level backfill | **100%** ✅ | 744만 samples |
| 5 | 검색 엔진 코어 (RRF + Reranker) | **95%** ✅ | lexical reindex 만 남음 |
| 6 | 백엔드 API | **95%** ✅ | 모든 endpoint 동작 |
| 7 | 프론트엔드 (Next.js 15) | **90%** ✅ | Next.js 16 migration 미수행 |
| 8 | 인증 / 보안 / RLS | **90%** ✅ | 11 RLS 테스트 통과, T1-T10 중 5건 |
| 9 | 자동 테스트 | **85%** ✅ | API 36 + 워커 50+ |
| 10 | 문서 (한국어) | **95%** ✅ | PAPER_DRAFT + PROGRESS + REPORT + runbook |
| 11 | 문서 (영문 manuscript) | **70%** | Genomics & Informatics 본문 ✅, **figures 미생성** |
| 12 | 정량 평가 / figure | **10%** | EVALUATION_PLAN 까지만 |
| 13 | A100 운영 인프라 | **100%** ✅ | Native bootstrap + batch automation chain |
| 14 | T1000 영구 서빙 | **0%** ❌ | dump → T1000 이주 / 도메인 / HTTPS 미실행 |
| 15 | 모니터링 / 알림 / CI/CD | **0%** ❌ | Grafana / GitHub Actions 미설정 |

```
████████████████████░  완성 영역 (코어 + 데이터 인프라 + 문서) ─── ~85%
████░░░░░░░░░░░░░░░░  진행 영역 (v1.0 batch, 평가 figure)    ─── ~30%
░░░░░░░░░░░░░░░░░░░░  남은 영역 (T1000 영구 서빙 + 운영)      ─── 0%
종합 ────────────────  마스터 플랜 12주 중 약 9-10주차 완료
```

→ 코어는 더 이상 손볼 게 없음. 남은 작업이 *corpus + evaluation + deployment* 라 **비-개발 작업이 60% 이상**.

## 11. 다음 마일스톤

| 마일스톤 | 예상 시점 |
|---|---|
| **Step 4 LLM 추출 완료** | **2026-05-26** (현 속도 유지 시) |
| Step 5 embedding + lexical reindex | 5/27 ~ 5/28 |
| Step 7 dump bundle 생성 | 5/28 |
| dump 백업 (외장 / 노트북) | dump 직후 |
| 30 쿼리 ground truth + 4-system ablation figure | dump 후 3-5일 |
| T1000 서버 dump 이주 + 영구 서빙 | dump 후 1-2일 (driver 설치 의존) |
| 영문 manuscript figures 완성 + 투고 | dump 후 1-2주 |

---

## 12. 코드 / 데이터 위치 (이 서버)

```
~/genofinder/                          # repo (8 commits, GitHub jin092904/genofinder push 동기화)
├── apps/{api, web, workers}/          # FastAPI / Next.js / 추출 워커
├── docs/
│   ├── REPORT.md                      # 이 문서 (5분 요약)
│   ├── PROJECT_OVERVIEW_KO.md         # 비전문가용 종합
│   ├── PAPER_DRAFT.md                 # 학위논문 챕터 (한)
│   ├── paper_en/                      # Genomics & Informatics 영문 + docx
│   ├── PROGRESS.md                    # 진행 현황
│   ├── decisions/0001~0006            # ADR
│   └── runbooks/a100-setup.md         # 운영 가이드
├── scripts/
│   ├── a100-native-bootstrap.sh       # 1회 부트스트랩 (postgres/redis/qdrant/opensearch/ollama)
│   ├── a100-batch-pipeline-native.sh  # 데모용 10k batch (Step 1 포함)
│   ├── a100-batch-resume.sh           # 데모 batch 재개
│   ├── a100-full-db-cycle.sh          # 정식 서비스 corpus (GPU N 동적 자동탐지)
│   ├── a100-wait-and-chain.sh         # PID wait → next script chain
│   └── a100-resume-from-extract.sh    # Step 4 부터 재개 (현재 가동 중)
└── services/                          # qdrant / opensearch / ollama 바이너리

~/genofinder/{pgdata,redis-data,qdrant-data,opensearch-data}/  # 런타임 데이터
~/genofinder/services/ollama/data/     # Ollama 모델 (~47GB)
~/genofinder/dumps/20260514-173648/    # 데모 v0.9 batch dump (23 MB)
~/genofinder/dumps/<TBD>-fullcycle/    # v1.0 정식 dump (Step 7 완료 후 생성)
```

## 13. 현재 가동 process (2026-05-19 13:18 기준)

| PID | 역할 | log |
|---|---|---|
| 496737 | resume-from-extract script (3일째 가동) | `/tmp/genofinder-resume-from-extract.log` |
| 303263 | ollama serve (GPU 5, gemma4:31b 로드 상태) | `/tmp/ollama-sosa.log` |
| 241360 | postgres 16.13 (datasets 283,962 + samples 744만) | `pgdata/postgres.log` |
| 241399 | redis 8 | `redis-data/redis.log` |
| 241478 | qdrant 1.12 | `qdrant-data/qdrant.log` |
| 242631 | opensearch 2.16 | `opensearch-data/opensearch.log` |

모든 process PPID=1, TTY=`?` (SSH 와 분리, 노트북 끄셔도 계속 가동).

---

*문의: 이호진 · teamclaudeihojin@gmail.com*
