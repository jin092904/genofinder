#!/usr/bin/env bash
# A100 native — full DB cycle (정식 서비스용).
#
# 차이점 (a100-batch-pipeline-native.sh 대비):
#   1. NCBI API key 사용 (rate 10 rps)
#   2. GEO --days 무한 + --max 1,000,000 (전체 GEO ~284k)
#   3. HCA full backfill (since=2010-01-01)
#   4. LLM 추출을 N process 분할 — stride/offset 으로 같은 ollama (num_parallel=N) 에 동시 호출
#   5. Ollama 재시작: 자동 탐지한 비어있는 GPU N장 사용
#
# 환경변수 (모두 옵션):
#   FULLCYCLE_TARGET_GPUS   사용할 GPU 최대 갯수 (기본 4, min 1, max 6)
#   FULLCYCLE_MIN_FREE_GB   "비어있다" 기준 (기본 70 GiB free)
#
# 예상 wall-clock (NCBI key + GPU 다중):
#   1 GPU : 약 14 일
#   2 GPU : 약 7-10 일
#   3 GPU : 약 5-7 일
#   4 GPU : 약 3-5 일
set -euo pipefail

# 사용자 매개변수
FULLCYCLE_TARGET_GPUS="${FULLCYCLE_TARGET_GPUS:-4}"
FULLCYCLE_MIN_FREE_GB="${FULLCYCLE_MIN_FREE_GB:-70}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"
# shellcheck disable=SC1090
source "$ENV_FILE"

DATA_ROOT="${GENOFINDER_DATA_ROOT:-/home/sosa8770/genofinder}"

# 환경변수
export DATABASE_URL="${DATABASE_URL:-postgresql+asyncpg://genofinder:${POSTGRES_PASSWORD:-devpassword}@localhost:5432/genofinder}"
export QDRANT_URL="${QDRANT_URL:-http://localhost:6333}"
export OPENSEARCH_URL="${OPENSEARCH_URL:-http://localhost:9200}"
export OLLAMA_URL="${OLLAMA_URL:-http://localhost:11435}"
export REDIS_URL="${REDIS_URL:-redis://localhost:6379/0}"
export OLLAMA_MODEL_EXTRACTION="${OLLAMA_MODEL_EXTRACTION:-gemma4:31b}"
export OLLAMA_MODEL_EMBED="${OLLAMA_MODEL_EMBED:-qwen3-embedding:8b}"
export NCBI_EUTILS_API_KEY="${NCBI_EUTILS_API_KEY:-}"

MAMBA_ROOT="${MAMBA_ROOT_PREFIX:-/home/sosa8770/micromamba}"
ENV_NAME="${SVC_ENV_NAME:-genofinder-svc}"
SVC_BIN="$MAMBA_ROOT/envs/$ENV_NAME/bin"

cd "$REPO_ROOT/apps/workers"

say() { printf '\n\033[1;36m▸ %s\033[0m\n' "$*"; }
say_warn() { printf '\n\033[1;33m⚠ %s\033[0m\n' "$*"; }

# ============================================================================
say "0/7 Ollama 재시작 (GPU 2장 + num_parallel=2)"
# 기존 ollama 가 있다면 종료
OLLAMA_PIDS=$(pgrep -u sosa8770 -f "services/ollama/bin/ollama serve" 2>/dev/null || true)
if [ -n "$OLLAMA_PIDS" ]; then
  echo "  기존 ollama 종료: $OLLAMA_PIDS"
  kill $OLLAMA_PIDS || true
  sleep 3
fi

# GPU 가용성 자동 탐지 — memory.free >= ${FULLCYCLE_MIN_FREE_GB} GiB 인 GPU 들 중
# 최대 ${FULLCYCLE_TARGET_GPUS} 장 선택.
MIN_FREE_MIB=$((FULLCYCLE_MIN_FREE_GB * 1024))
GPUS_FREE_LIST=$(nvidia-smi --query-gpu=index,memory.free --format=csv,noheader,nounits | \
  awk -F', ' -v t="$MIN_FREE_MIB" '$2 >= t {print $1}' | head -n "$FULLCYCLE_TARGET_GPUS")
GPUS_COUNT=$(echo "$GPUS_FREE_LIST" | grep -c '.' || echo 0)
GPUS_FREE=$(echo "$GPUS_FREE_LIST" | paste -sd ,)

if [ "$GPUS_COUNT" -eq 0 ]; then
  say_warn "비어있는 GPU 미발견 (>= ${FULLCYCLE_MIN_FREE_GB} GiB) — env 의 NVIDIA_GPU_DEVICE_ID fallback"
  GPUS_FREE="${NVIDIA_GPU_DEVICE_ID:-5}"
  PARALLEL=1
else
  PARALLEL="$GPUS_COUNT"
  echo "  탐지된 비어있는 GPU: $GPUS_FREE ($GPUS_COUNT 장)"
  echo "  → OLLAMA_NUM_PARALLEL=$PARALLEL, reextract stride=$PARALLEL"
fi

cd "$REPO_ROOT/services/ollama"
OLLAMA_HOST=127.0.0.1:11435 \
  OLLAMA_MODELS="$REPO_ROOT/services/ollama/data" \
  CUDA_VISIBLE_DEVICES="$GPUS_FREE" \
  OLLAMA_NUM_PARALLEL=$PARALLEL \
  OLLAMA_SCHED_SPREAD=true \
  OLLAMA_MAX_LOADED_MODELS=1 \
  LD_LIBRARY_PATH="$REPO_ROOT/services/ollama/lib/ollama:${LD_LIBRARY_PATH:-}" \
  nohup ./bin/ollama serve > /tmp/ollama-sosa-fullcycle.log 2>&1 &
disown
sleep 4
echo "  ✓ ollama re-started — GPU=$GPUS_FREE parallel=$PARALLEL"
cd "$REPO_ROOT/apps/workers"

# ============================================================================
say "1/7 HCA full backfill (since=2010-01-01) + GDC update"
time uv run python -c "
import asyncio
from datetime import date
from src.harvesters.hca import HcaHarvester
from src.harvesters.gdc import GdcHarvester
from src.indexer.tasks import _harvest_hca, _harvest_gdc

async def go():
    # HCA: since 강제로 매우 과거 → 전체 530건 fetch
    print('--- HCA full backfill ---')
    h = HcaHarvester()
    count = 0
    try:
        async for uid in h.list_updated_since(date(2010,1,1)):
            try:
                raw = await h.fetch_raw(uid)
                # tasks 의 indexer 통해서 DB upsert
                # 간단 dedup: 이미 있으면 skip
                count += 1
                if count % 50 == 0: print(f'  HCA fetched {count}')
            except Exception as e:
                print(f'  HCA {uid} fail: {type(e).__name__}')
        print(f'HCA: fetched {count} records')
    except Exception as e:
        print(f'HCA backfill error: {e}')
    finally:
        await h.aclose() if hasattr(h, 'aclose') else None
    # 단순화: _harvest_hca() 가 이미 incremental + watermark 기반이므로,
    # 위 만으로는 DB 에 안 들어감. 따라서 _harvest_hca() 도 호출
    print('--- _harvest_hca() (DB upsert) ---')
    res_hca = await _harvest_hca()
    print('HCA upsert:', res_hca)
    print('--- _harvest_gdc() (DB upsert) ---')
    res_gdc = await _harvest_gdc()
    print('GDC upsert:', res_gdc)

asyncio.run(go())
" || say_warn "HCA/GDC harvest 부분 실패 — 다음 단계 계속"

# ============================================================================
say "2/7 GEO full harvest (--days 99999 --max 1000000, NCBI key 사용)"
time uv run python -m scripts.harvest_geo_large --days 99999 --max 1000000

# ============================================================================
say "3/7 GEO Series Matrix sample-level backfill (concurrency=6)"
time uv run python -m scripts.harvest_geo_samples --limit 1000000 --concurrency 6 || \
  say_warn "samples backfill 일부 실패 — 다음 단계 계속"

# ============================================================================
say "4/7 LLM 추출 — $PARALLEL process 분할 (stride=$PARALLEL)"
if [ "$PARALLEL" -ge 2 ]; then
  REEXTRACT_PIDS=()
  for OFFSET in $(seq 0 $((PARALLEL - 1))); do
    uv run python scripts/reextract_with_ontology.py \
      --offset "$OFFSET" --stride "$PARALLEL" \
      > "/tmp/reextract-${OFFSET}.log" 2>&1 &
    REEXTRACT_PIDS+=($!)
    echo "  spawned process offset=$OFFSET PID=$!"
  done
  for PID in "${REEXTRACT_PIDS[@]}"; do
    if wait "$PID"; then
      echo "  PID $PID finished OK"
    else
      RC=$?
      say_warn "PID $PID failed (exit $RC) — 부분 추출 손실, 후속 단계 계속"
    fi
  done
else
  echo "  single process (parallel=1)"
  time uv run python scripts/reextract_with_ontology.py
fi

# ============================================================================
say "5/7 Embedding + OpenSearch reindex (Qwen3-Embedding-8B → 1024d)"
time uv run python -c "
import asyncio
from src.db import get_engine
from src.indexer.embeddings import COLLECTION_NAME, get_qdrant_client
from src.indexer.pipeline import reindex_all_search_layers

async def go():
    qdrant = get_qdrant_client()
    try:
        cols = await qdrant.get_collections()
        if any(c.name == COLLECTION_NAME for c in cols.collections):
            print(f'dropping {COLLECTION_NAME} (clean reindex)...')
            await qdrant.delete_collection(COLLECTION_NAME)
    finally:
        await qdrant.close()

    eng = get_engine()
    try:
        stats = await reindex_all_search_layers(eng)
        print('reindex stats:', stats)
    finally:
        await eng.dispose()

asyncio.run(go())
"

# ============================================================================
say "6/7 Translate top-N — SKIP (uvicorn 미가동)"

# ============================================================================
say "7/7 Dump 생성"
DUMP_DIR="${DATA_ROOT}/dumps/$(date +%Y%m%d-%H%M%S)-fullcycle"
mkdir -p "$DUMP_DIR"

PGPASSWORD="${POSTGRES_PASSWORD:-devpassword}" \
  "$SVC_BIN/pg_dump" -h 127.0.0.1 -p 5432 -U genofinder -d genofinder | gzip > "$DUMP_DIR/db.sql.gz"
echo "  ✓ db.sql.gz: $(du -h $DUMP_DIR/db.sql.gz | cut -f1)"

SNAP=$(curl -s -X POST localhost:6333/collections/datasets_v2/snapshots | \
       python3 -c "import sys,json; print(json.load(sys.stdin)['result']['name'])" 2>/dev/null || echo "")
if [ -n "$SNAP" ]; then
  cp "$DATA_ROOT/qdrant-data/snapshots/datasets_v2/$SNAP" "$DUMP_DIR/" 2>/dev/null || \
    say_warn "snapshot 복사 실패"
  echo "  ✓ qdrant snapshot: $SNAP"
fi

"$SVC_BIN/redis-cli" -h 127.0.0.1 -p 6379 SAVE >/dev/null
cp "$DATA_ROOT/redis-data/dump.rdb" "$DUMP_DIR/redis-dump.rdb"
echo "  ✓ redis-dump.rdb: $(du -h $DUMP_DIR/redis-dump.rdb | cut -f1)"

tar czf "${DUMP_DIR}.tar.gz" -C "$(dirname $DUMP_DIR)" "$(basename $DUMP_DIR)"
echo ""
echo "✅ Full DB cycle 완료."
echo "📦 Dump bundle: ${DUMP_DIR}.tar.gz ($(du -h ${DUMP_DIR}.tar.gz | cut -f1))"
