# Migration v2 — Oracle 의존 폐기 + 모델 스택 전면 교체

작성일: 2026-05-13
대상: Geno Finder v0.8 → v1.0 (논문 제출 수준)

## 1. 한 줄 요약

피드백 수용 + Oracle Cloud capacity 안 잡힘 이슈 회피 — **두 개의 연구실 서버로 분업**:
- **A100 서버** (다른 연구실): 1회 batch 처리 — 풀 harvest + LLM 추출 + embedding 인덱싱
- **T1000 서버** (eunjung): 영구 서빙 — 사전 계산된 데이터로 검색/시각화 응답

물리적·LAN·소속 모두 분리. 데이터 이주는 SSH/rsync over public Internet (~500MB compressed).

## 2. 모델 스택 변경 (사용자 결정 반영)

| 분야 | 현재 (v0.8) | 새 스택 (v1.0) | 비고 |
|---|---|---|---|
| Extraction LLM (batch) | Phi-4 mini 3B | **Gemma 3 27B IT** (A100, BF16) | 한국어 instruction following / cohort 정확도 ↑ |
| 서빙 LLM (on-demand 드물게) | Phi-4 mini 3B | **Qwen3-4B** (T1000, Q4 ~2.5GB) | Phi 와 동일 메모리에 한국어 강력. Qwen3 시리즈 통일 |
| Embedding (인덱스) | nomic-embed-text 768d | **Qwen3-Embedding-8B** 4096d → **Matryoshka 1024d truncate** | MTEB Multilingual 1위 (70.58) |
| Embedding (쿼리) | (동일) | **Qwen3-Embedding-0.6B** 1024d native | T1000 GPU fit, 인덱스와 차원 일치 |
| Reranker | ms-marco-MiniLM (영어, 22M) | **Qwen3-Reranker-0.6B Q4** | 한국어 지원 + Apache 2.0, Qwen3 시리즈 통일 |
| **Web framework** | Next.js 15.5.15 | **Next.js 16.2.6** | dev 400% 빠름, Turbopack 기본, Cache Components, React Compiler 안정화 |
| Inference engine | Ollama | Ollama (LLM/Embedding) + sentence-transformers (Reranker) | Qwen3-Reranker 는 community GGUF 만 → ST 사용 |

### 결정 근거
- **Qwen3-Embedding-8B**: MTEB Multi 70.58 (EmbeddingGemma 의 61.15 대비 +9점). 한국어 포함 100+ lang. Apache 2.0.
- **Matryoshka 1024d**: 8B 의 native 4096d → 1024d truncate. retrieval 품질 손실 ~2-3%, 메모리/속도 4배 절감.
- **0.6B 양쪽 모델 가능**: Qwen3-Embedding-0.6B native 가 1024d. 인덱스/쿼리 모두 같은 모델로 단순화하는 옵션도 있으나 인덱스는 한 번이라 8B 의 품질이 더 가치 있음.
- **Qwen3-Reranker-0.6B vs 4B**: 4B 가 BGE 대비 +12.7점 우위인데 0.6B 는 미공개. T1000 4GB VRAM 에 fit 우선해서 0.6B. 평가에서 0.6B 부족하면 4B Q4 (2-3GB) 로 승격 검토.
- **LLM Gemma 3 27B**: 140+ 언어 + 128K context + multimodal. Phi-4 mini 한국어 long-context 깨짐 / cohort 잘못 분류 사례 해소 기대. A100 에서 1회 backfill 시 ~3-5h.

## 3. 인프라 배치

### A100 서버 (다른 연구실 — 스펙 확정 2026-05-13)
**역할**: 1회 batch — corpus 풀 처리 + dump 생성.

**서버 환경 (확정)**:
- Xeon Gold 6342 × 96 vCPU, 503GB RAM, **A100 80GB × 6장 (GPU 3/4/5 비어있음)**
- CUDA 12.4 / Driver 550.163.01 — 즉시 사용 가능
- Ubuntu 22.04 LTS
- **권한 제약**: sudo / docker daemon 없음. **podman rootless v3.4.4 + nvidia-container-toolkit + pip install --user podman-compose 로 우회**
- **디스크**: 로컬 루트 71GB (빠듯) → **모델·DB 데이터는 NFS `/home/sosa8770/...` 마운트 (218TB)** 에

**GPU 배치**: BF16 풀스펙, 단일 GPU (GPU 3) 만 사용 — 다른 사용자 방해 X
- Phase 1 (LLM): Gemma 3 27B BF16 로드 (~54GB) → 추출/번역
- Phase 2 (Embedding): Gemma unload, Qwen3-Embedding-8B BF16 로드 (~16GB) → 임베딩
- Ollama 가 자동 swap 처리 (idle unload + lazy load)

**프로세스 (전체 ~6-10시간 한 사이클)**:
1. NFS 디렉터리 준비 + git clone — 5분
   ```bash
   mkdir -p /home/sosa8770/genofinder/{ollama-models,postgres-data,qdrant-data,opensearch-data}
   git clone <repo> /home/sosa8770/genofinder/code
   pip install --user podman-compose  # 한 번만
   ```
2. **podman-compose** stack bootstrap (postgres / qdrant / opensearch / redis / ollama) — 30분
   - `infra/compose/docker-compose.dev.yml` 그대로, volume path 만 NFS 로 (위 환경변수)
   - GPU 노출: ollama 서비스에 `--device nvidia.com/gpu=3` 추가
3. 모델 pull (NFS 에 저장): `gemma3:27b-it-bf16` (~54GB) + `qwen3-embedding:8b` (~16GB) — 30-60분
   - `OLLAMA_MODELS=/home/sosa8770/genofinder/ollama-models` 환경변수
4. Harvest 4 source — 1-2시간 (NCBI rate-limited)
5. LLM 추출 (modality + ontology + cohort_design) — **2-3시간** (10k × ~0.5-1s on A100 BF16)
6. Embedding (Qwen3 8B → Matryoshka 1024d truncate) — 1-2시간 (10k records)
7. Indexing (Qdrant + OpenSearch) — 30분 (CPU 작업)
8. Translate cache 사전 채우기 (top 100-500 데이터셋 미리 한국어 번역) — 1-2시간
9. Dump: pg_dump + Qdrant snapshot + Redis RDB — 5분, 합쳐 ~500MB compressed

### T1000 서버 (eunjung, 32core / 256GB RAM / T1000 4GB VRAM)
**역할**: 영구 서빙 — 사용자 쿼리 응답, 드물게 on-demand LLM.

**필요한 것**:
- NVIDIA driver 535+ + CUDA 12 (현재 nouveau → admin 도움 필요할 수 있음)
- Docker / docker-compose
- 디스크 ~50GB (개인 1TB 디스크 사용 권장)

**프로세스**:
1. Stack bootstrap (동일 docker-compose)
2. 모델 pull: `phi4-mini` (on-demand 백업용), `qwen3-embedding:0.6b`, `qwen3-reranker:0.6b` — 10분
3. Dump restore: pg_restore + Qdrant snapshot upload + Redis dump load — 30분
4. uvicorn (FastAPI) + pnpm dev (Next.js) 또는 production build
5. 서빙 — 검색 / 코호트 / 다운로드 스니펫 모두 정상

## 4. 데이터 이주 (서로 다른 LAN/연구실)

```bash
# === A100 서버에서 ===
cd ~/genofinder
docker exec genofinder-dev-postgres-1 pg_dump -U genofinder genofinder | gzip > /tmp/db.sql.gz
curl -X POST localhost:6333/collections/datasets_v1/snapshots > /tmp/qdrant-snapshot.json
SNAPSHOT_NAME=$(jq -r .result.name /tmp/qdrant-snapshot.json)
docker cp genofinder-dev-qdrant-1:/qdrant/snapshots/datasets_v1/$SNAPSHOT_NAME /tmp/
docker exec genofinder-dev-redis-1 redis-cli --rdb /data/dump.rdb
docker cp genofinder-dev-redis-1:/data/dump.rdb /tmp/redis-dump.rdb

tar czf /tmp/genofinder-bundle.tar.gz -C /tmp db.sql.gz $SNAPSHOT_NAME redis-dump.rdb

# === 인터넷 통한 이주 (사용자 노트북 경유 권장) ===
# A100 → 노트북 → T1000  (각 LAN 격리)
scp a100-server:/tmp/genofinder-bundle.tar.gz ~/
scp ~/genofinder-bundle.tar.gz t1000-server:/tmp/

# === T1000 서버에서 ===
cd ~/genofinder
docker compose up -d postgres redis qdrant opensearch
tar xzf /tmp/genofinder-bundle.tar.gz -C /tmp

zcat /tmp/db.sql.gz | docker exec -i genofinder-dev-postgres-1 psql -U genofinder genofinder
docker cp /tmp/$SNAPSHOT_NAME genofinder-dev-qdrant-1:/qdrant/snapshots/datasets_v1/
curl -X PUT "localhost:6333/collections/datasets_v1/snapshots/$SNAPSHOT_NAME/recover"
docker cp /tmp/redis-dump.rdb genofinder-dev-redis-1:/data/dump.rdb
docker restart genofinder-dev-redis-1

# OpenSearch 는 source DB 에서 reindex (BM25 라 결정적, ~10초)
cd apps/workers
DATABASE_URL=... uv run python -c "from src.indexer.pipeline import ...; reindex 호출"
```

**총 소요**: dump 5분 + 이주 (인터넷 속도 의존, 500MB → ~10분) + restore 30분 = **1시간 미만**.

## 5. 코드 변경 범위

env var 만으로 처리 가능한 부분 vs 코드 수정 필요한 부분:

### env var 만 (코드 수정 없음)
- `OLLAMA_MODEL_EXTRACTION=gemma3:27b-it-bf16` (A100) / **`qwen3:4b`** (T1000 — Phi-4 mini 에서 교체)
- `OLLAMA_MODEL_EMBED=qwen3-embedding:8b` (A100) / `qwen3-embedding:0.6b` (T1000)
- `RERANKER_MODEL=Qwen/Qwen3-Reranker-0.6B`

### 코드 수정 (단순)
- [`embeddings.py:30`](../apps/workers/src/indexer/embeddings.py#L30) — `EMBED_DIM = 768` → `1024`
- [`lexical.py:22`](../apps/workers/src/indexer/lexical.py) — 영향 없음 (OpenSearch 는 차원 무관)
- Qdrant collection `datasets_v1` drop + recreate (A100 첫 인덱스 시 자동)

### 코드 수정 (Reranker — Qwen3 는 CrossEncoder API 직접)
- [`reranker.py`](../apps/api/src/services/reranker.py) — Qwen3-Reranker 는 sentence-transformers CrossEncoder 또는 transformers AutoModel 직접 사용. 우리 기존 wrapper 와 호환 (sentence-transformers 사용)
- input format: `(query, document)` pair 그대로. instruction prefix 추가 옵션 — 1-5% 향상

### Prompt 호환성 (Gemma 3 / Qwen3-4B)
- 둘 다 instruction-tuned, system prompt 지원. Ollama 가 chat template 자동 적용
- 우리 [`structurer.py`](../apps/workers/src/extractors/structurer.py) / [`cohort_design.py`](../apps/workers/src/extractors/cohort_design.py) / [`cohort_extractor.py`](../apps/api/src/services/cohort_extractor.py) / [`translate.py`](../apps/api/src/services/translate.py) 의 raw prompt 그대로 호환
- 한국어 instruction following 강해서 prompt 한국어화도 옵션 (현재는 영어 system prompt)
- Qwen3 는 thinking mode 옵션 — `enable_thinking=false` 권장 (JSON 출력에는 불필요)

### Next.js 16 마이그레이션 (별도 절차)

1. `cd apps/web && npx @next/codemod@latest` — 자동 호환성 변환
2. `package.json` 의 `next` 버전을 `^16.2.6` 으로
3. `pnpm install` + `pnpm tsc --noEmit` + `pnpm build` 로 검증
4. 점검 포인트:
   - **async params**: 우리 `datasets/[id]/page.tsx` 등이 이미 `params: Promise<{id: string}>` 패턴 사용 → OK
   - **caching semantics**: 모든 client fetch 에 `cache: "no-store"` 명시 → OK
   - **image 컴포넌트**: 우리는 사용 안 함 (Google profile photo 만 remotePatterns) → 영향 없음
   - **Turbopack 기본**: `next dev` 가 자동으로 Turbopack 사용. 우리 HMR cache 충돌 사례 (frontend 코드 변경 미반영) 가 자연 해소 기대
   - **rewrites**: 우리 `next.config.mjs` 의 `/backend/:path*` rewrite 가 16 에서도 동일 동작 (변경 없음)
5. 검증 후 commit + ADR 0006 의 Next.js 16 row 표시

## 6. ADR 갱신

- **ADR 0004 (LLM Models)** → status `Superseded by ADR 0006`
- **ADR 0006 (Model Stack Refresh — Qwen3 + Gemma 3)** 신규
  - 결정: Gemma 3 27B + Qwen3-Embedding (8B/0.6B) + Qwen3-Reranker-0.6B
  - 근거: MTEB 1위, Apache 2.0, 한국어 지원, A100 batch + T1000 serve 분업 fit
  - 대안: EmbeddingGemma / BGE / jina-v4 검토 결과 + 채택 사유

## 7. 평가 (논문 figure / table 후보)

| 평가 항목 | 측정 방법 | 비교 baseline |
|---|---|---|
| Retrieval 정확도 | Top-10 정답 매칭률 (수동 ground truth 30 쿼리) | nomic-embed-text 비교 |
| Reranker 효과 | RRF only vs RRF+rerank top-10 정확도 | ms-marco-MiniLM 비교 |
| 한국어 쿼리 강건성 | 한↔영 쿼리 동일 데이터셋 대상 매칭률 | Phi-4 mini 비교 |
| Cohort 추출 품질 | 20 GSE spot-check (R/NR, case-control 등 정확 분류율) | v1 vs v2 prompt 비교 |
| 한국어 번역 품질 | BLEU / 사람 평가 (top 30 데이터셋) | Phi-4 mini 결과 |
| Latency | search end-to-end ms | v0.8 baseline 유지 또는 ↓ |

## 8. 검증 / 일정 추정

| 단계 | A100 서버 | T1000 서버 | 누적 |
|---|---|---|---|
| 0. 권한 확인 + 환경 setup | 0.5일 | 0.5일 (병렬) | 0.5일 |
| 1. Stack bootstrap + 모델 pull | 1-2시간 | 30분 (병렬) | 0.5일 |
| 2. A100 batch 1 cycle | 6-10시간 | — | 1일 |
| 3. Dump + 이주 | 10분 | 30분 | 1일 |
| 4. T1000 서빙 검증 | — | 1-2시간 | 1.5일 |
| 5. 평가 + 논문 figure | — | 1-2일 | 3-4일 |

총 **3-4일** 으로 v1.0 도달. v0.8 의 모든 기능 유지 + Qwen3 stack + Gemma 3 cohort 추출 품질.

## 9. 남은 의사결정

| 항목 | 상태 |
|---|---|
| ~~A100 VRAM~~ → **80GB 확정, BF16 풀스펙**, 단일 GPU 3 사용 | ✅ 결정 |
| ~~A100 sudo / docker~~ → **podman rootless + podman-compose 로 우회** | ✅ 결정 |
| T1000 서버 NVIDIA driver 설치 (nouveau → 535+CUDA) | 사용자 확인 대기 |
| Translate cache 사전 채우기 범위 (top 100 vs 전체 10k) | 추후 결정 |
| 평가용 ground truth 쿼리 set 30개 | 추후 작성 |

## 10. Rollback plan

만약 A100 batch 결과 품질이 v0.8 보다 나쁘면:
- 모델 stack 만 v0.8 (Phi-4 mini + nomic + ms-marco) 로 환원, env var 한 줄 변경
- DB / Qdrant snapshot 은 둘 다 보관 (v0.8 dump + v1.0 dump)
- 코드는 그대로 둠 (env var 만 다른 set)
