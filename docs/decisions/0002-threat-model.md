# ADR 0002 — Threat Model & Control Mapping

| | |
|---|---|
| Status | Accepted |
| Date | 2026-05-06 |
| Deciders | 사용자, Claude Code |
| Related | ADR 0001 (Tech Stack), ADR 0003 (LLM Vendor) |

## Context

Geno Finder가 다루는 사용자 쿼리는 **미공개 연구 가설·표적·코호트 디자인**, 즉 pre-publication intellectual property에 해당한다 (마스터 플랜 §12.0). 일반 SaaS 보안 baseline 위에 IP-등급 기밀성을 더해야 한다. 본 ADR은 마스터 플랜 §12.0 의 위협 표를 채택하고, 각 위협 ID (T1~T10) 에 대응되는 control과 그 **구현 위치**를 코드 경로 단위로 못박는다.

**원칙.**
1. 모든 control은 위협 ID로 역추적 가능해야 한다 — 코드 주석·테스트 이름에 `T<n>` 표기.
2. control이 v1에서 미구현이면 마일스톤(주차)을 명시하고, 그 전까지 해당 위협 표면을 노출하는 기능을 출시하지 않는다.
3. 본 ADR이 머지되기 전까지 사용자 쿼리(L3 데이터)를 다루는 코드를 작성하지 않는다 (§11.7).

## Decision

### Data Classification (마스터 플랜 §12.1 채택)

| 등급 | 예시 | 처리 원칙 |
|---|---|---|
| L0 Public | 인덱싱된 dataset metadata | 일반 처리 |
| L1 Internal | 시스템 로그(쿼리 본문 제외), 메트릭 | 표준 SaaS |
| L2 Confidential | 사용자 계정·결제·이메일 | 암호화 + 접근 통제 |
| **L3 Restricted** | **사용자 쿼리 본문, saved queries, query embeddings, 추출된 concept term, 클릭/피드백 로그** | envelope encryption, tenant scoping, 최소 보존 |

### Threat ↔ Control Mapping

| ID | 위협 | Control 요지 | 구현 위치 (확정) | 마일스톤 |
|---|---|---|---|---|
| **T1** | 운영자/내부자가 평문 쿼리 열람 | tenant당 DEK envelope encryption + KMS audit log | `apps/api/src/security/crypto.py` (`TenantCipher`), `apps/api/src/security/kms.py` (KmsClient adapter), Alembic migration `0002_envelope_encryption.py` | Week 6 구현, Week 1 스켈레톤 |
| **T2** | LLM 제공자가 사용자 쿼리를 학습에 사용 | 로컬 LLM only, 외부 LLM 호출 0건 | `apps/workers/extractors/structurer.py` + ADR 0003 (Ollama 결정) + CI lint rule이 외부 LLM SDK import 차단 | Week 1 — ADR 0003 머지 시점 |
| **T3** | 로그·trace·백업에 쿼리 본문 잔존 | structlog redact processor, OTel span sanitizer, exception value 차단 lint | `apps/api/src/security/redaction.py`, `apps/api/src/security/policies.py` (SENSITIVE_KEYS), `apps/api/src/observability/otel.py`, custom semgrep rule `infra/lint/no-query-in-exception.yml` | Week 7 |
| **T4** | Tenant 간 데이터 누수 | `tenant_id NOT NULL` + PostgreSQL RLS FORCE + ORM tenant scoping mixin + cross-tenant CI test | `apps/api/src/security/tenant.py` (FastAPI middleware: `SET LOCAL app.tenant_id`), `apps/api/src/db/mixins.py` (TenantScoped), Alembic `0001_initial.py` (RLS policies), `apps/api/tests/security/test_cross_tenant.py` | Week 2 (스키마), Week 7 (E2E 테스트) |
| **T5** | 행동 패턴(클릭 로그)으로 연구 주제 역추정 | 보존 기간 단축(기본 30일), 즉시 익명화, raw → 집계 회전, self-serve 삭제 | `apps/workers/aggregations/feedback_rollup.py` (Celery beat), `apps/api/src/routers/me.py` (`DELETE /me/activity`), `apps/api/src/db/retention.py` | Week 8 |
| **T6** | 영장·subpoena 강제 공개 | 평문 쿼리 미보관 + KMS key destruction 옵션 + Customer-Managed Keys (Lab tier) | `apps/api/src/security/cmk.py` (CMK 등록·해지), `apps/api/src/services/account.py` (forget_by_key_destruction), warrant canary는 v2 | Week 11 (Lab tier CMK) |
| **T7** | 임베딩 inversion으로 쿼리 복원 | 사용자 쿼리 임베딩은 ephemeral (메모리 only) + 캐시 키는 hash, 캐시 값에 원문 미포함 | `apps/api/src/services/search.py` (lifecycle), `apps/api/src/services/cache.py` (key=hash(...), TTL 1h) — Qdrant에 user query 임베딩 쓰기 금지 ASSERT | Week 6 |
| **T8** | Prompt injection·악성 입력 | 입력 sanitization, system prompt 분리, JSON schema enforced output, parameterized SQL 의무 | `apps/workers/extractors/sanitizer.py`, `apps/workers/extractors/prompts/system.txt` (사용자 분리 영역 명시), `packages/eval/injection_payloads.jsonl` (50개 회귀), CI: regression suite | Week 8 |
| **T9** | 의존성·공급망 공격 | lockfile + frozen install, 주간 audit, distroless+non-root image, image signing(cosign), SBOM | `pyproject.toml` + `uv.lock`, `apps/web/package.json` + `pnpm-lock.yaml`, `infra/docker/Dockerfile.api` (distroless multi-stage), `.github/workflows/security.yml` (pip-audit, npm audit, trivy, gitleaks) | Week 1 (CI 골격) |
| **T10** | 계정 탈취 → 저장 쿼리 열람 | MFA 강제(Pro+), short-lived JWT(15m) + refresh rotation, step-up auth on sensitive ops | `apps/api/src/security/stepup.py`, Clerk 설정 (`apps/web/src/lib/clerk.ts`), `apps/api/src/middleware/auth.py` | Week 10 |

### Cross-Cutting Controls (위협 ID와 무관하게 v1 출시 전 필수)

| Control | 위치 | 마일스톤 |
|---|---|---|
| `/.well-known/security.txt` | `apps/web/public/.well-known/security.txt` | Week 9 |
| Audit log (append-only, WORM) | `apps/api/src/security/audit.py` (writer) + 별도 PG 인스턴스 또는 immutable object storage | Week 10 |
| GDPR data subject endpoints | `apps/api/src/routers/me.py` (export/delete/portability) | Week 11 |
| 보안 가시성 UI ("내 쿼리는 어떻게 보호되나요") | `apps/web/src/app/security/page.tsx` | Week 9 |

### CI Gates (PR 머지 차단)

다음이 GitHub Actions에서 실패하면 머지 불가 (마스터 플랜 §12.14):

1. Cross-tenant access 통합 테스트 (T4)
2. Log redaction grep 0건 (T3) — 합성 마커 `SECRETMARKER_<uuid>` 추적
3. Envelope encryption round-trip + AAD mismatch 거부 테스트 (T1)
4. Prompt injection regression 50건 우회 0 (T8)
5. `pip-audit` / `npm audit` critical 0건 (T9)
6. `gitleaks` 0건 (T9)

CI workflow 파일: `.github/workflows/security-gates.yml` — Week 1 골격, 각 테스트는 해당 마일스톤에서 채워진다.

## Consequences

**긍정**
- 모든 보안 control이 코드 경로와 마일스톤으로 1:1 mapping. 누락된 control이 PR 리뷰에서 즉시 보임.
- v1에서 외부 LLM 호출이 0이므로 T2가 구조적으로 제거됨 → DPA 협상·zero-retention 검증 부담 없음.
- CI gate가 6개로 명시되어 있어 보안 테스트가 사후 추가가 아닌 처음부터 강제됨.

**부정·리스크**
- v1 timeline이 보안 control 구현으로 길어짐. 특히 Week 6(envelope encryption)·Week 7(redaction E2E) 가 병목.
- 로컬 LLM이 precision ≥ 0.85 미달 시 T2 위협이 다시 살아남 (외부 vendor fallback 불가피). ADR 0003 갱신 절차로 완화.
- Customer-Managed Keys (T6 강한 보장) 는 Lab tier에서만 제공 — free/Pro tier는 KMS key destruction까지만 가능.

## References

- 마스터 플랜 IMPLEMENTATION_PROMPT.md §12.0~§12.15
- ADR 0001 (Tech Stack)
- ADR 0003 (LLM Vendor — 본 ADR과 같은 PR에서 머지)
- OWASP Threat Modeling: https://owasp.org/www-community/Threat_Modeling
- PostgreSQL RLS: https://www.postgresql.org/docs/16/ddl-rowsecurity.html
