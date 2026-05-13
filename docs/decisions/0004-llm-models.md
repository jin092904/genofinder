# ADR 0004 — LLM Model Selection

| | |
|---|---|
| Status | **Superseded by [ADR 0006](0006-model-stack-refresh.md)** (2026-05-13) |
| Date | 2026-05-06 |
| Deciders | Claude Code (자율 진행, 사용자 사전 승인 범위 내) |
| Related | ADR 0003 (LLM Vendor — Ollama local-only) · ADR 0006 (Model Stack Refresh) |

## Context

ADR 0003 에서 Ollama 로컬 LLM 사용을 확정했지만, **어떤 모델**을 쓸지는 별도 ADR 로 미뤄두었다. 본 ADR 은 사용자 환경([`docs/runbooks/local-env.md`](../runbooks/local-env.md)) 의 제약 — **GPU 없음, RAM 7.5 GB, 스택 동시 운영** — 위에서 모델 후보를 결정한다.

LLM 은 두 경로에서 사용된다 (마스터 플랜 §12.5):

| 경로 | 입력 데이터 등급 | 용도 |
|---|---|---|
| (a) **ETL 구조화 추출** | L0 Public (NCBI/EBI metadata) | esummary 의 자유 서술 → JSON schema (modality, organism, disease 등) |
| (b) **사용자 쿼리 concept 추출** | L3 Restricted | 자연어 → ontology term 후보 |

**임베딩** 도 동일 모델 인프라(Ollama)에서 생성한다.

## Decision

### 채택 (v1)

| 역할 | 모델 | Ollama tag | 양자화 | RAM 추정 | 출처 |
|---|---|---|---|---|---|
| Generation (구조화 추출 + 쿼리 concept) | **Phi-4 mini** | `phi4-mini:3.8b` | Q4_K_M (default) | ~3 GB | https://ollama.com/library/phi4-mini |
| Text embedding | **nomic-embed-text v1.5** | `nomic-embed-text` | f16 (default) | ~0.5 GB | https://ollama.com/library/nomic-embed-text |

### 선택 근거

**Generation: Phi-4 mini (3.8B)**
1. **CPU-only 환경 적합**: 8-15 tok/s on consumer CPU. Llama 3.1 8B (4-8 tok/s)·Qwen 14B (1-3 tok/s)는 ETL 처리량이 비현실적.
2. **JSON output 신뢰성**: Phi-4 시리즈는 instruction-following 과 structured output 에 강점. Ollama `format='json'` 모드와 잘 맞는다 (검증 출처: Microsoft Phi-4-mini technical report).
3. **메모리 여유**: 7.5 GB RAM 중 Phi-4 mini 3 GB → Postgres/Redis/Qdrant/OpenSearch 동시 운영 가능. 8B Q4 도 가능하지만 OOM 마진이 좁아진다.
4. **라이선스**: MIT. 상업 사용 가능.

**Embedding: nomic-embed-text**
1. **BERT-base 크기, 768-dim**: Qdrant payload 와 OpenSearch BM25 hybrid 에 충분.
2. **biomedical 도메인 호환성**: BiomedBERT/PubMedBERT 도 후보였으나 (a) Ollama 라이브러리에 즉시 등재된 모델이 아님, (b) Week 3 까지의 평가 데이터셋(200건)이 아직 라벨링되지 않아 도메인 fine-tune 효과 검증 불가. 일반 모델로 baseline 확보 후 Week 7 평가에서 nDCG@10 ≥ 0.7 미달 시 도메인 모델로 교체.
3. **컨텍스트 길이 8192 tokens**: GEO esummary 의 title+abstract 가 보통 1k-3k tokens — 충분.

### 보류 / 후순위 (Week 7+ 재평가)

- **BiomedBERT / SapBERT**: 도메인 임베딩이 정밀도를 높일 수 있으나, Ollama 라이브러리 미등재. HuggingFace transformers 직접 호스팅이 필요해 Ollama 단일 인터페이스 원칙(ADR 0003)과 충돌. 평가 결과로 정량적 우위 입증되면 별도 inference 컨테이너 추가하는 ADR 작성.
- **Qwen 2.5 14B**: 구조화 정확도 ↑ 가능성. 단 1-3 tok/s 는 ETL throughput 에 치명적. 별도 GPU 머신 도입 시 재고.
- **bge-m3**: 다국어 임베딩. v1 은 영어 metadata 만 다루므로 우선순위 낮음.

### 계약 (코드 측)

```python
# .env / docker-compose
OLLAMA_MODEL_EXTRACTION=phi4-mini:3.8b
OLLAMA_MODEL_EMBED=nomic-embed-text
```

`apps/workers/src/extractors/llm_client.py` 는 본 환경변수만 읽는다. 모델 변경 시:

1. 본 ADR 갱신 (status=Superseded by 000X)
2. `.env.example` 갱신
3. `extraction_version` 증가 (예: `v0-stub-2026-05-06` → `v1-phi4-2026-XX-XX`)
4. 인덱스 재생성 트리거 (Week 6 배경 작업)

## Consequences

**긍정**
- Phi-4 mini 가 단일 컨테이너 동시운영 환경에 가장 fit. RAM 여유 ~4 GB 로 안전.
- 영문 임베딩은 nomic-embed-text 로 baseline 확보. Week 7 평가에서 부족하면 정량적 근거로 교체 결정.

**부정·리스크**
- bio-domain 정확도가 BiomedBERT·PubMedBERT 대비 떨어질 수 있음 → Week 3 (precision ≥ 0.85) / Week 7 (nDCG@10 ≥ 0.7) 미달 시 본 ADR supersede.
- CPU-only throughput 한계 — 1만 GSE × 평균 1k tokens 추출에 ~수십 시간 예상. Celery beat 스케줄 + 야간 batch 로 운영 (Week 2 운영 노트 추가 예정).
- Phi-4 mini 의 4K context window — esummary 가 길면 chunk 분할 또는 요약 단계 필요. 대부분의 GEO 레코드는 4K 안에 들어와 v1 에서 단순 처리.

## Action Items (자동화 대상)

- [x] `ollama pull phi4-mini` (예상 ~2.5 GB 다운로드)
- [x] `ollama pull nomic-embed-text` (~140 MB)
- [ ] Smoke test — 두 모델로 generate / embed API 호출 응답 검증
- [ ] `apps/workers/src/extractors/llm_client.py` 실제 구현 (httpx 기반 async wrapper)

## References

- ADR 0003 (LLM Vendor)
- [`docs/runbooks/local-env.md`](../runbooks/local-env.md) (CPU-only / 7.5GB 환경)
- Ollama library: https://ollama.com/library
- Phi-4 mini: https://ollama.com/library/phi4-mini
- nomic-embed-text: https://ollama.com/library/nomic-embed-text
