# ADR 0003 — LLM Vendor: Local-Only via Ollama

| | |
|---|---|
| Status | Accepted |
| Date | 2026-05-06 |
| Deciders | 사용자, Claude Code |
| Related | ADR 0001 (Tech Stack), ADR 0002 (Threat Model — T2) |

## Context

Geno Finder는 두 경로에서 LLM을 사용한다 (마스터 플랜 §12.5 분류):

- **(a) ETL 단계의 공개 metadata 구조화 추출** — 데이터 등급 L0(Public). 외부 vendor 사용해도 위협 없음.
- **(b) 사용자 자연어 쿼리에서 concept 추출** — L3(Restricted). 외부로 나가면 T2 위협(LLM 제공자 학습 사용) 발생.

마스터 플랜 §13.4는 "**이 ADR이 머지되기 전에 LLM 호출 코드를 작성하지 말 것**"을 강제한다.

사용자 결정 (2026-05-06): **"구독형 API보다는 로컬 API를 일단 사용해보는게 좋을 것 같아."**

## Decision

### v1: Local-only LLM via Ollama (외부 호출 0건)

(a)·(b) 모두 단일 로컬 Ollama 인스턴스로 처리. 외부 LLM SDK(Anthropic / OpenAI / Google / Cohere)는 v1 코드베이스에 추가하지 않으며, CI lint rule이 이를 강제한다 (ADR 0002 의 T2 control).

### Ollama 런타임 — 1차 출처 검증 사실 (2026-05-06)

| 항목 | 값 | 출처 |
|---|---|---|
| 설치 (Linux) | `curl -fsSL https://ollama.com/install.sh \| sh` | https://ollama.com/ |
| Default API base | `http://localhost:11434` | https://github.com/ollama/ollama/blob/main/docs/api.md |
| 인증 | **없음** (기본). 외부 노출 시 보안 위험 — §아래 Ollama 보안 운영 참조 | 동일 |
| `POST /api/generate` | `model`, `prompt`, `format` (`json` 또는 JSON schema), `stream`, `options`, `keep_alive` | 동일 |
| `POST /api/chat` | `model`, `messages`, `tools` (function calling), `format`, `stream`, `keep_alive` | 동일 |
| Embeddings | `POST /api/embed` (current) — `/api/embeddings` 는 deprecated 후속 | 동일 |
| OpenAI 호환 경로 | 1차 출처에서 미언급 — 본 프로젝트는 native API만 사용 | 동일 |
| Latest version | TODO(verify): ollama.com 첫 페이지에 버전 정보 미노출. `ollama --version` 으로 설치 후 본 ADR 갱신 | — |

### 모델 선택은 별도 ADR

다음을 ADR 0004 (예정, Week 3) 에서 벤치마크 후 결정:

- **구조화 추출용** (instruct, JSON output): 후보 — Llama 3.1 8B Instruct, Qwen 2.5 14B Instruct, Phi-4. 평가 메트릭은 `packages/eval/` precision ≥ 0.85 (마스터 플랜 Week 3 기준).
- **임베딩용**: 후보 — `nomic-embed-text`, `mxbai-embed-large`, `bge-m3`. 평가 메트릭은 nDCG@10 (마스터 플랜 Week 7 기준 ≥ 0.7).
- **bio-domain 모델** (선택사항): BioMistral, Med-Llama 시리즈가 Ollama 라이브러리에 등재되어 있는지 확인 후 검토.

본 ADR은 모델 후보를 좁히기만 하고 **실제 채택은 Week 3 ADR 0004 머지 시점**에 한다. 그 전까지 모델 이름을 코드에 하드코딩하지 않는다 — `OLLAMA_MODEL_EXTRACTION`, `OLLAMA_MODEL_EMBED` 환경변수로 분리.

### Ollama 보안 운영 (T2·T9·T10 부수 통제)

1. **외부 노출 금지.** docker-compose에서 Ollama 컨테이너의 `11434` 포트를 **호스트로 publish 하지 않는다**. internal docker network 안에서 `apps/workers`·`apps/api` 만 접근.
2. **Bind address 강제.** Ollama 컨테이너는 `OLLAMA_HOST=127.0.0.1:11434` 로 시작 (또는 컨테이너 내부 0.0.0.0이라도 docker network 격리). 추가로 reverse proxy를 두지 않는다.
3. **사용자 식별자·tenant_id 를 prompt에 포함하지 않는다** (마스터 플랜 §12.5 (4)). prompt builder에 lint rule 적용.
4. **로깅 redaction.** Ollama 호출의 request/response 본문은 일반 로그·OTel span에 절대 기록하지 않는다 — 길이·해시·model명·latency만 (ADR 0002 T3).
5. **dependency**: 시스템 프롬프트와 user 입력은 XML 태그로 분리하며, output은 `format=json` (JSON schema 지정) 으로 강제. parse 실패 시 결과 폐기 (ADR 0002 T8).

### v1.5+ 외부 vendor fallback 조건 (사전 합의)

다음 조건이 **모두** 만족되어야 외부 LLM vendor 사용을 검토한다:

1. 로컬 모델로 precision ≥ 0.85 (Week 3 평가) 미달, **그리고**
2. Zero-retention DPA 가능한 vendor만 후보 (Anthropic 표준 API 정책, OpenAI ZDR 등을 1차 출처에서 검증), **그리고**
3. (b) 경로(사용자 쿼리)에는 절대 사용하지 않음 — (a) 경로의 ETL 구조화에만 한정, **그리고**
4. 사용자 명시 승인 + 본 ADR을 superseding 하는 새 ADR.

**위 4개 중 하나라도 미충족 시 외부 LLM 통합 코드를 머지하지 않는다.**

## Consequences

**긍정**
- T2 위협이 v1 출시 시점에서 구조적으로 제거됨. DPA 협상·zero-retention 검증·비용 산정 부담 0.
- 사용자 쿼리 본문이 인터넷 경계를 넘지 않음 — pre-publication IP 보호의 가장 강한 형태.
- API key·요금·할당량 0 — 개발 환경이 단순.

**부정·리스크**
- 로컬 모델 품질이 GPT-4 / Claude Sonnet 대비 떨어질 가능성 — Week 3 평가에서 검증.
- WSL2 단일 머신의 GPU/RAM 제약. 14B+ 모델은 양자화(Q4_K_M 등) 적용 또는 별도 GPU 머신 필요. Week 3 전에 사용자 환경의 VRAM 확인 필요 (`nvidia-smi`).
- Ollama 자체에 인증이 없으므로 운영 환경에서는 컨테이너 격리·네트워크 정책으로만 보호됨. 인스턴스 외부 노출 시 model exfiltration 가능 — 위 보안 운영 항목 위반 시 즉시 사고.
- 임베딩 모델을 자체 호스팅하므로 Qdrant 인덱스 재계산 비용을 우리가 부담. 마스터 플랜 §9.2 "재계산은 model 변경 시에만" 준수.

## Action Items (이 ADR 머지 직후)

- [ ] Ollama 설치: `curl -fsSL https://ollama.com/install.sh | sh` 후 `ollama --version` 으로 본 ADR 의 `Latest version` TODO 해소
- [ ] `nvidia-smi` 결과를 `docs/runbooks/local-env.md` 에 기록 (모델 크기 결정 입력값)
- [ ] `apps/workers/extractors/llm_client.py` 인터페이스 스켈레톤 (Ollama HTTP client wrapper, 모델은 환경변수)
- [ ] `infra/lint/no-external-llm.yml` semgrep rule: `import anthropic`, `import openai`, `import google.generativeai`, `import cohere` 등 차단

## References

- 사용자 결정 (2026-05-06): 로컬 API 우선
- 마스터 플랜 §12.5 (LLM 제공자 통제), §13.4 (LLM 벤더 ADR 의무)
- ADR 0002 T2
- Ollama: https://ollama.com/
- Ollama API: https://github.com/ollama/ollama/blob/main/docs/api.md
- ADR 0004 (예정 — 모델 선택, Week 3)
