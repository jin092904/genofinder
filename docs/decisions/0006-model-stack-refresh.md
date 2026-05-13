# ADR 0006 — Model Stack Refresh (Qwen3 + Gemma 3)

| | |
|---|---|
| Status | Accepted |
| Date | 2026-05-13 |
| Deciders | 사용자, Claude Code |
| Supersedes | [ADR 0004](0004-llm-models.md) — Phi-4 mini + nomic-embed-text + ms-marco-MiniLM |
| Related | ADR 0003 (LLM Vendor — Ollama local-only) · [`docs/migration_v2.md`](../migration_v2.md) |

## Context

ADR 0004 의 v1 stack (Phi-4 mini 3B + nomic-embed-text 768d + ms-marco-MiniLM 22M) 은 2026-05-06 의 사용자 환경 (WSL2 7.5GB RAM, GPU 없음) 에서 부트스트랩 가능한 baseline 으로 채택되었다. 그러나 약 1주 운영 후 다음 한계가 드러났다:

1. **Phi-4 mini 한국어 long-context 깨짐** — 한국어 abstract 번역 시 후반부에서 영어 잔존 + 러시아어 글자 섞임 (2026-05-12 GSE317412 검증).
2. **Cohort design 추출 정확도 불안정** — Phi-4 mini 가 abstract 만으로 그룹 구조 추정 시 control/treatment 라벨 오류 빈번 (예: mouse aging study 를 control vs treatment 로 잘못 분류). prompt 에 sample factor 분포 추가 (v2, 2026-05-12) 로 부분 보완.
3. **ms-marco-MiniLM 영어 한정** — 한국어 쿼리 재정렬 약함. 학술 용어 reranking 도 약함.
4. **nomic-embed-text multilingual 약함** — 한국어 ↔ 영어 cross-lingual retrieval 정확도 낮음.

외부 피드백 (2026-05-13): "사용 모델들이 구버전, 최신 오픈 모델 활용 검토 필요". 핵심 추천: Gemma 4 (실제론 Gemma 3 가 최신), EmbeddingGemma, Qwen3-Reranker.

병행하여 인프라 결정 — Oracle Cloud A1.Flex (capacity 270+ fail) 폐기, **A100 80GB × 6 서버 (다른 연구실, 1회 batch 용) + T1000 4GB 서버 (eunjung, 영구 서빙)** 분업으로 변경.

## Decision

### v1.0 stack (확정)

| 역할 | 모델 | 위치 | 정밀도 | VRAM/RAM | 출처 |
|---|---|---|---|---|---|
| **Batch LLM** (extraction + translation + cohort) | **Gemma 3 27B IT** | A100 (1회 batch) | BF16 | ~54GB | https://huggingface.co/google/gemma-3-27b-it |
| **Serve LLM** (on-demand drop-back) | **Qwen3-4B** | T1000 (영구) | Q4 (GGUF) | ~2.5GB | https://ollama.com/library/qwen3:4b |
| **Indexing Embedding** | **Qwen3-Embedding-8B** | A100 (1회) | BF16 + **Matryoshka 1024d truncate** | ~16GB | https://huggingface.co/Qwen/Qwen3-Embedding-8B |
| **Query Embedding** | **Qwen3-Embedding-0.6B** | T1000 (영구) | native (1024d) | ~0.5GB | https://huggingface.co/Qwen/Qwen3-Embedding-0.6B |
| **Reranker** | **Qwen3-Reranker-0.6B** | T1000 (영구) | Q4 | ~0.4GB | https://huggingface.co/Qwen/Qwen3-Reranker-0.6B |
| **Inference engine** | Ollama (LLM, Embedding) + sentence-transformers (Reranker) | — | — | — | Qwen3-Reranker 미공식 Ollama 등재로 ST 사용 |
| **Web framework** | **Next.js 16.2.6** (15.5.15 → major upgrade) | T1000 (영구) | — | — | https://nextjs.org/blog/next-16-2 |

### 차원 결정 — 1024d

- Qwen3-Embedding-0.6B native = **1024d** (T1000 쿼리)
- Qwen3-Embedding-8B native = 4096d, Matryoshka 로 **1024d truncate** (A100 인덱싱)
- 인덱스/쿼리 dim 일치 → Qdrant collection `datasets_v1` schema 단순화
- 1024d × 10,873 docs × 4byte ≈ **44MB Qdrant** (768d 의 33MB 와 차이 미미)
- 더 작게 (512d / 256d Matryoshka) 가능하나 cost 절감 효과 미미, 품질 ~5% ↓

### LLM 분업 근거

| 항목 | A100 batch 측 | T1000 serve 측 |
|---|---|---|
| 사용 빈도 | 1회 (corpus 풀 처리) | 드물게 (on-demand fallback) |
| 호출량 | 10k × 3 task (modality / cohort / translate) | ~매일 N건 (사전 캐시 miss 시) |
| 응답 시간 요구 | batch — 시간 무관 | < 30s/호출 |
| 품질 요구 | 최고 (논문 결과의 baseline) | 적당 (서빙 안정성 우선) |
| 모델 | Gemma 3 27B BF16 (~54GB) | **Qwen3-4B Q4 (~2.5GB)** |

→ **Qwen3-4B** 가 T1000 cold-path 의 LLM. Phi-4 mini (3.8B) 와 동일 메모리이면서 Qwen 공식 claim 으로 *"Qwen2.5-72B 수준 성능"*. T1000 의 serve stack 이 완전 Qwen3 시리즈로 통일됨 — Embedding 0.6B + Reranker 0.6B + LLM 4B = **단일 family, 단일 vendor**. 논문에서 "Qwen3 unified serving stack" 으로 깔끔하게 서술 가능. 한국어 instruction following 강함 (Phi-4 mini 의 한국어 long-context 깨짐 해소).

### Reranker — 0.6B (vs 4B)

| 모델 | VRAM Q4 | MTEB-R bench | T1000 4GB fit |
|---|---|---|---|
| Qwen3-Reranker-0.6B | ~0.4GB | — | ✓ 안전 |
| Qwen3-Reranker-4B | ~2-3GB | 69.76 (BGE 의 +12.7점) | △ 빠듯 |

→ T1000 의 hardware fit 우선. **0.6B 로 시작**. 평가에서 4B 가 의미 있는 품질 우위 보이면 4B Q4 로 승격 검토 (옵션).

## Consequences

### 긍정적
- **MTEB Multilingual 1위 Qwen3-Embedding** (70.58 점, 기존 nomic 의 ~60 보다 +10) — 한국어 검색 강건성 ↑
- **Qwen3-Reranker** Apache 2.0 + 100+ 언어 — 학술 domain + 한국어 쿼리 모두 강화
- **Gemma 3 27B 128K context + 140+ 언어** — 긴 abstract 풀 처리 + 한국어 번역 자연스러움
- 큰 모델 batch 처리 결과를 작은 모델 서빙으로 제공 → cost-aware
- Apache 2.0 (Qwen) + Gemma License — 모두 상업적 사용 가능

### 부정적 / 위험
- A100 batch 의존 — 1회 처리 실패 시 재실행 (다른 연구실 서버 의존)
- 데이터 이주 작업 추가 (pg_dump + Qdrant snapshot, ~500MB 인터넷 통신)
- Qwen3-Reranker 가 sentence-transformers 직접 사용 → Ollama 단일 추론 엔진 → 두 엔진 운영
- Gemma 3 27B BF16 (~54GB) 가 A100 80GB 한 장에 fit 하지만 다른 작업 동시 불가

### Rollback
ADR 0004 의 v1 stack (Phi-4 mini + nomic + ms-marco) 으로 환원 가능 — env var 한 줄:
```bash
OLLAMA_MODEL_EXTRACTION=phi4-mini
OLLAMA_MODEL_EMBED=nomic-embed-text
RERANKER_MODEL=cross-encoder/ms-marco-MiniLM-L-6-v2
```
+ Qdrant collection drop + recreate (차원 768d 으로) + reindex.

DB / Qdrant snapshot 은 두 버전 다 보관.

## Alternatives Considered

### Embedding 후보 비교

| 후보 | MTEB Multi | 차원 | License | 결정 |
|---|---|---|---|---|
| **Qwen3-Embedding-8B** | **70.58 (1위)** | 4096 (Matryoshka) | Apache 2.0 | ✅ 채택 (인덱싱) |
| Qwen3-Embedding-0.6B | (미공개) | 1024 | Apache 2.0 | ✅ 채택 (쿼리) |
| EmbeddingGemma 300M | 61.15 | 768 (Matryoshka) | Gemma License | ❌ MTEB 9점 열세 |
| BGE-M3 568M | ~63 | 1024 | MIT | ❌ Qwen3 통일성 우선 |
| jina-embeddings-v4 | (멀티모달, 우리 도메인 불필요) | 2048 | CC-BY-NC | ❌ NC license, 멀티모달 불필요 |

### Batch LLM 후보 비교 (A100)

| 후보 | params | A100 80GB BF16 fit | 한국어 | 결정 |
|---|---|---|---|---|
| **Gemma 3 27B IT** | 27B | ✓ (54GB) | 140+ lang | ✅ 채택 |
| Gemma 3 12B | 12B | ✓ (24GB) | 140+ lang | ❌ 27B 가능하면 27B |
| Qwen3-32B | 32B | ✓ (~64GB BF16) | 100+ lang | ❌ Gemma 3 의 multimodal 보너스 우위 |
| Phi-4 mini 3B (현재) | 3.8B | over-spec | 약함 | ❌ A100 의 의미 없음 |

### Serve LLM 후보 비교 (T1000 4GB VRAM)

| 후보 | params | GGUF 메모리 | T1000 fit | 한국어 | 결정 |
|---|---|---|---|---|---|
| **Qwen3-4B** | 4B | **2.5GB** | ✓ | 100+ lang 강함 | ✅ 채택 — Qwen 공식 "Qwen2.5-72B 수준" claim |
| Qwen3-1.7B | 1.7B | 1.4GB | ✓ 매우 여유 | 100+ lang | ❌ 4B 가 메모리 동등하면서 강함 |
| Qwen3-0.6B | 0.6B | 0.5GB | ✓ | 100+ lang | ❌ 너무 작음 |
| Phi-4 mini 3B (v0.8) | 3.8B | ~2.5GB | ✓ | 약함 | ❌ Qwen3-4B 와 메모리 동등하면서 한국어 약함 |

### Reranker 후보 비교

| 후보 | params | MTEB-R | T1000 fit | 결정 |
|---|---|---|---|---|
| Qwen3-Reranker-4B | 4B | 69.76 | 빠듯 (Q4 2-3GB) | ❌ 0.6B 평가 후 승격 검토 |
| **Qwen3-Reranker-0.6B** | 0.6B | (미공개) | ✓ 안전 | ✅ 채택 |
| BGE-reranker-v2-m3 | 568M | 57.03 | ✓ | ❌ MTEB-R 12점 열세 |
| ms-marco-MiniLM (현재) | 22M | ~50 (영어 only) | ✓ | ❌ 영어 한정, 5년 된 모델 |

## Action items

- [ ] **A100 서버 podman bootstrap** — pip install --user podman-compose, NFS 디렉터리 + `OLLAMA_MODELS` 환경변수 설정
- [ ] **`infra/compose/docker-compose.dev.yml` podman 호환 patch** — GPU 노출 `--device nvidia.com/gpu=3`, volume path NFS 로
- [ ] **모델 pull**:
  - A100: `gemma3:27b-it-bf16` + `qwen3-embedding:8b`
  - T1000: **`qwen3:4b`** + `qwen3-embedding:0.6b` (+ Qwen3-Reranker-0.6B via sentence-transformers)
- [ ] **코드 변경**:
  - [`apps/workers/src/indexer/embeddings.py:30`](../../apps/workers/src/indexer/embeddings.py#L30) — `EMBED_DIM = 768` → `1024`
  - [`apps/api/src/services/reranker.py:20,50`](../../apps/api/src/services/reranker.py) — `cross-encoder/ms-marco-MiniLM-L-6-v2` → `Qwen/Qwen3-Reranker-0.6B`
  - env var 갱신 (`OLLAMA_MODEL_EXTRACTION=qwen3:4b` T1000, `=gemma3:27b-it-bf16` A100)
- [ ] **Next.js 16.2.6 마이그레이션** — `npx @next/codemod@latest` + 우리 코드 점검 (async params 이미 적용 / `cache: "no-store"` 명시 / image 컴포넌트 미사용 → 위험 낮음)
- [ ] **T1000 NVIDIA driver 설치 가능성 확인** (현재 nouveau)
- [ ] **A100 batch script + dump 절차 작성** ([`docs/migration_v2.md`](../migration_v2.md) §4 기반)
- [ ] **평가 protocol** — 30 ground truth 쿼리 × {old vs new stack} retrieval/rerank accuracy 비교 (논문 figure)
