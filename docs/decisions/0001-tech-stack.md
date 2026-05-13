# ADR 0001 — Tech Stack

| | |
|---|---|
| Status | Accepted |
| Date | 2026-05-06 |
| Deciders | 사용자, Claude Code |
| Supersedes | — |
| Superseded by | — |

## Context

Geno Finder는 (a) 다수의 공공 생물정보 DB를 정기 수확하는 ETL 파이프라인, (b) 자연어 쿼리에 대한 hybrid retrieval + reranking 검색 API, (c) 검색 결과를 가시화하고 saved query·alerts를 제공하는 웹 UI, (d) 연구 IP에 준하는 사용자 쿼리에 대한 envelope encryption + multi-tenant RLS 보안 모델을 동시에 만족해야 한다 (마스터 플랜 §1, §6, §12).

스택은 다음 제약 위에서 선택한다:

1. **사용자 환경**: 단일 WSL2 Ubuntu 22 (`bioinfo0929`), 단일 GPU 가능. 외부 클라우드 의존 최소화.
2. **외부 LLM API 비용 회피**: 사용자 요청에 따라 v1은 **로컬 LLM 우선**, 외부 구독형 API는 후순위.
3. **단일 머신 → 단일 클라우드 VM 으로의 무리 없는 이행**: 모놀리식 모노레포 + docker-compose.dev → 차후 Terraform 으로 IaC 화.
4. **마스터 플랜 §0.1**: 라이브러리 버전·API 스펙은 1차 출처에서 검증한 값만 사용.

## Decision

| 레이어 | 선택 | 검증된 버전 (2026-05-06) | 비고 |
|---|---|---|---|
| Backend API | FastAPI (Python 3.12) | Python 3.12.3 (사용자 환경에 설치됨) | bioinformatics 생태계와 가장 친화적 |
| ASGI 서버 | Uvicorn (dev) / Gunicorn+UvicornWorker (prod) | TODO(verify) | |
| Async/큐 | Celery + Redis | TODO(verify) | harvester 스케줄링·재시도 |
| RDB | PostgreSQL 16 | docker image `postgres:16-bookworm` | JSONB · RLS · pgcrypto 조합 |
| Vector DB | Qdrant | server: TODO(verify); client `qdrant-client==1.17.1` (2026-03-13) | metadata payload filter 성능 |
| Full-text | OpenSearch 2.x 또는 3.x | client `opensearch-py==3.2.0` (2026-04-27) | BM25 |
| 임베딩 모델 | (미정 — ADR 0004 예정) | — | PubMedBERT/BiomedBERT vs `bge-m3` 등 비교 후 결정. **이 ADR이 머지되기 전에 임베딩 코드 작성 금지** |
| Reranker | cross-encoder (ms-marco) | TODO(verify) | 도메인 fine-tune은 v2 |
| Ontology | OAK (`oaklib`) | `oaklib==0.6.23` (2025-06-05) | OLS4 직접 호출은 fallback |
| LLM (구조화 추출) | **Local — Ollama** + 모델 (ADR 0003에서 선택) | TODO(verify) | 외부 호출 0건 기본값 |
| Frontend | Next.js 14 (App Router) + Tailwind | Node 20.20.2 (사용자 환경) | 정적 출력 가능, BFF로 백엔드 호출 |
| Frontend 데이터 패칭 | TanStack Query v5 | TODO(verify) | server actions와 병행 |
| Frontend 패키지 매니저 | pnpm (corepack) | Node 20에 corepack 번들. 활성화는 §13.5 단계에서 |
| Auth | Clerk | TODO(verify) | Week 10 도입. v1 dev에서는 dummy auth provider |
| 결제 | Stripe | TODO(verify) | Week 10 도입 |
| KMS (dev) | LocalStack KMS 또는 HashiCorp Vault dev mode | TODO(verify) | docker-compose에 포함, prod에서는 클라우드 KMS로 교체 |
| Infra (초기) | 단일 VM (Hetzner CCX 또는 Fly.io) | — | Terraform IaC는 v2 |
| 관측성 | OpenTelemetry + Grafana Cloud (free tier) | TODO(verify) | redaction 처리 후 export |
| 컨테이너 베이스 이미지 | distroless 또는 chainguard, multi-stage build, **non-root 실행** | — | §12.10 |

### 마스터 플랜과의 차이점 (사용자 결정 반영)

1. **LLM**: 마스터 플랜은 "PubMedBERT / BiomedBERT / OpenAI text-embedding-3-large 비교"이지만, 본 프로젝트는 **외부 LLM API 의존을 v1에서 0건으로 유지**한다. 임베딩은 로컬 모델, 구조화 추출도 Ollama 로컬 LLM을 사용한다. 자세한 내용은 ADR 0003.
2. **Brand**: 사용자 결정으로 **Geno Finder** 로 확정 (마스터 플랜 문서 표제는 BioDatasetFinder 였음).
3. **Anthropic Batch / OpenAI Batch API**: v1 비활성. 본 ADR이 다시 머지되기 전까지 외부 LLM SDK를 코드에 추가하지 않는다.

## Consequences

**긍정**
- 외부 LLM 비용 0원으로 v1 운영 가능. T2(LLM 제공자 학습 사용) 위협을 구조적으로 제거.
- 단일 WSL2 환경으로 `make dev` 한 줄에 전 스택 기동 가능 (PostgreSQL, Redis, Qdrant, OpenSearch, LocalStack KMS).
- 마스터 플랜 §0.1을 기록 형태로 강제 — 모든 버전이 1차 출처 URL과 함께 문서화됨.

**부정·리스크**
- 로컬 LLM 품질이 GPT-4 / Claude Sonnet 대비 낮을 수 있음. precision ≥ 0.85 (Week 3 검증 기준)에 미달하면 ADR 0003을 갱신하고 zero-retention 외부 vendor로 fallback 검토.
- Qdrant·OpenSearch server 호환 매트릭스 미확인 — Week 6 임베딩 인덱싱 PR 전에 본 ADR을 갱신해야 함 (`TODO(verify)` 해소).
- Clerk·Stripe 도입을 Week 10 까지 미루므로, 그 전에는 dummy auth/billing provider 인터페이스를 사용. 인터페이스만 일찍 잡고 구현은 후순위.

## References

- [docs/external-apis.md](../external-apis.md) — 외부 API 1차 출처 검증 산출물
- 마스터 플랜 IMPLEMENTATION_PROMPT.md §2, §13
- pysradb 2.5.1: https://pypi.org/project/pysradb/
- oaklib 0.6.23: https://pypi.org/project/oaklib/
- qdrant-client 1.17.1: https://pypi.org/project/qdrant-client/
- opensearch-py 3.2.0: https://pypi.org/project/opensearch-py/
- Ollama: https://ollama.com (본 ADR 머지 시점 미검증 — ADR 0003에서 검증)
