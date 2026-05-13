# Geno Finder

> 공공 생명정보 DB(NCBI SRA/GEO, EBI ENA/ArrayExpress, HCA, GDC 등)에서
> 사용자의 자연어 연구 디자인 입력에 가장 적합한 데이터셋을
> 시맨틱 매칭 + 접근성 우선으로 랭킹하여 제공하는 SaaS.

## 시작하기

이 프로젝트는 마스터 플랜 [`기획/IMPLEMENTATION_PROMPT.md`](../기획/IMPLEMENTATION_PROMPT.md) 의 §13 첫 행동 지시를 따라 부트스트랩되었다.

| 단계 | 산출물 | 상태 |
|---|---|---|
| §13.1 외부 API 검증 | [`docs/external-apis.md`](docs/external-apis.md) | ✓ 초안 (TODO(verify) 항목 있음) |
| §13.2 Tech Stack ADR | [`docs/decisions/0001-tech-stack.md`](docs/decisions/0001-tech-stack.md) | ✓ |
| §13.3 Threat Model ADR | [`docs/decisions/0002-threat-model.md`](docs/decisions/0002-threat-model.md) | ✓ |
| §13.4 LLM Vendor ADR | [`docs/decisions/0003-llm-vendor.md`](docs/decisions/0003-llm-vendor.md) | ✓ Ollama local-only 확정 |
| §13.5 Monorepo bootstrap | 본 저장소 트리, Dockerfile, compose, Makefile | ✓ 골격 |
| §13.6 Alembic v1 schema | `apps/api/alembic/versions/0001~0004` | ✓ 0001~0004 (samples + cohort 확장 포함) |
| §13.7 Security skeleton | `apps/api/src/security/` | ✓ T1·T3·T4·T8·T9 실구현 + 회귀 테스트 |
| §13.8 CI 파이프라인 | `.github/workflows/security-gates.yml` | ✓ 5 게이트 실 동작 (cross-tenant / envelope / redaction / prompt injection 등) |
| §13.9 GEO harvester | `apps/workers/src/harvesters/geo.py` + `geo_matrix.py` | ✓ study-level + sample-level (Series Matrix) |
| 데이터셋 상세 신규 섹션 | 코호트 분포 / 실험 디자인 / 다운로드 스니펫 | ✓ 2026-05-12 |

## 디렉토리

```
genofinder/
├── apps/
│   ├── api/               FastAPI 백엔드
│   ├── web/               Next.js 14 프론트엔드
│   └── workers/           Celery (harvester / extractor / indexer)
├── packages/
│   ├── shared-schemas/    Pydantic 모델 (zod 코드젠 대상)
│   └── eval/              평가 데이터셋 + 메트릭
├── infra/
│   ├── docker/            Dockerfile (distroless / non-root)
│   ├── compose/           docker-compose.dev.yml
│   ├── lint/              semgrep / custom rule
│   └── terraform/         (v2)
└── docs/
    ├── external-apis.md   §13.1 산출물 — 외부 API 단일 source of truth
    ├── decisions/         ADR
    ├── runbooks/
    └── weekly/            주간 deliverable 기록
```

## 로컬 개발 (예정)

`make dev` — Docker 설치 후 사용 가능. 현재 Docker는 WSL2에 미설치.

```
make dev          # docker-compose 전체 기동 (Postgres / Redis / Qdrant / OpenSearch / Ollama / LocalStack KMS)
make test         # pytest (api, workers) + jest (web)
make lint         # ruff, mypy, eslint, tsc
make security-scan  # pip-audit + npm audit + trivy fs + gitleaks
```

## 보안

본 프로젝트는 **사용자 쿼리(L3 Restricted)** 를 pre-publication IP로 취급한다.
보안 control은 [`docs/decisions/0002-threat-model.md`](docs/decisions/0002-threat-model.md) 의 T1~T10 mapping 을 따른다.
보안 control을 우회하거나 약화하는 변경은 ADR 갱신 없이 머지하지 않는다.

취약점 신고: `apps/web/public/.well-known/security.txt` (Week 9)
