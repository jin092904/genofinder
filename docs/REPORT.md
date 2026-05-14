# Geno Finder — 시스템 보고서

> 한 페이지 요약 · 5분 안에 읽기.
> 더 깊이 보려면: [PROJECT_OVERVIEW_KO.md](PROJECT_OVERVIEW_KO.md) (비전문가용 종합), [PAPER_DRAFT.md](PAPER_DRAFT.md) (학위논문 챕터), [paper_en/manuscript.md](paper_en/manuscript.md) (Genomics & Informatics 영문 투고).

작성일: 2026-05-14 (v1.0 batch 진행 중)

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

## 8. 현재 데이터 규모

**v1.0 코퍼스 batch 진행 중** (2026-05-14 09:30 시작, 종료 예상 약 자정).

| 출처 | 진행 | 비고 |
|---|---|---|
| GEO | ✅ **9,992 건** indexed (최근 365일 신규) | 8건만 NCBI 429 로 skip |
| HCA | ⏳ 0건 (incremental watermark 기준 신규 0) | v0.8 의 530건은 별도 backfill 옵션 |
| GDC | ✅ **91 건** (전체) | NCI GDC `/projects` REST |
| SRA | (다음 release) | `_harvest_sra` 통합 예정 |
| **합계** | **약 10,083 records** | 추후 HCA 530 추가 → 10,613 |

### Batch 단계 wall-clock

```
1.  GEO harvest         ✅ 78분 (이전 cycle 에서 완료)
1.5 HCA + GDC harvest   ✅ 3분
2.  LLM extraction      ⏳ ~10-14h  (gemma4:31b, 4초/record)
2.5 Sample backfill     ⏳ ~1-2h    (GEO Series Matrix)
3.  Embedding reindex   ⏳ ~1-2h    (Qwen3-Embedding-8B)
6.  Dump                ⏳ 5분
─────────────────────────────────────────────────────
   총 약 14-18시간 1 cycle, 1회성 비용
```

---

## 9. 한계 / 알려진 trade-off

- **GPU 1장 점유**: gemma4 47GB + Qwen3-Embedding 16GB 가 동시 적재 불가 — batch 가 단계별 모델 swap (5분 unload + reload).
- **한국어 정량 검색 품질 측정 미완**: v0.8 의 한국어 쿼리 약점 (nomic + ms-marco) 이 v1.0 의 Qwen3 stack 으로 얼마나 개선됐는지 정량 평가는 batch 완료 후 30 ground-truth 쿼리로 진행 예정.
- **GEO 전체 (28만) 미인덱싱**: 본 batch 는 최근 1년만. 전체 인덱싱은 현재 hardware 로 ~17일 필요 → incremental beat 로 점진 채우기 권장.
- **SRA 미통합**: 4400만 run 단위는 BioProject 로 압축해도 수십만 → 별도 release.
- **Translate top-N**: uvicorn API 가동된 상태에서만 동작. batch 단독으로는 skip.

---

## 10. 다음 마일스톤

1. **오늘 자정 전후**: v1.0 batch 완료, dump bundle 생성.
2. **+1주**: 30 쿼리 ground-truth × {v0.8, v1.0} 정량 비교 → 논문 figure.
3. **+1주**: T1000 서버로 dump 이주, 영구 서빙 가동.
4. **+2주**: Genomics & Informatics 영문 manuscript 투고.

---

## 11. 코드 / 데이터 위치 (이 서버)

```
~/genofinder/                          # repo
├── apps/{api, web, workers}/          # FastAPI / Next.js / 추출 워커
├── docs/
│   ├── REPORT.md                      # 이 문서
│   ├── PROJECT_OVERVIEW_KO.md         # 비전문가용 종합
│   ├── PAPER_DRAFT.md                 # 학위논문 챕터 (한)
│   ├── paper_en/                      # 영문 manuscript + docx
│   ├── PROGRESS.md                    # 진행 현황
│   ├── decisions/0001~0006            # ADR
│   └── runbooks/a100-setup.md         # 운영 가이드
├── scripts/
│   ├── a100-native-bootstrap.sh       # 한 줄 부트스트랩
│   ├── a100-batch-pipeline-native.sh  # 첫 batch (Step 1 포함)
│   └── a100-batch-resume.sh           # Step 1 이후 재개
└── services/                          # qdrant / opensearch / ollama 바이너리

~/genofinder/{pgdata,redis-data,qdrant-data,opensearch-data}/  # 런타임 데이터
~/genofinder/services/ollama/data/     # Ollama 모델 (~47GB)
~/genofinder/dumps/<timestamp>.tar.gz  # batch 결과 (이주 단위)
```

---

*문의: 이호진 · teamclaudeihojin@gmail.com*
