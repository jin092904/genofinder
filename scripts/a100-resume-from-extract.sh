#!/usr/bin/env bash
# Full-cycle 중단 (2026-05-15 OpenSearch 413) 후 재개 스크립트.
# 진행 상태:
#   ✅ GEO 283k harvested (Step 2 끝)
#   ⏳ samples 17만 (10k 분량) — 28만 dataset 으로 확장 필요
#   ❌ LLM 추출 3.55% (이전 batch 결과만)
#   ❌ Qdrant 0 points
#   ❌ OpenSearch 0 docs
#
# Step 3 (sample backfill) → 4 (LLM 추출) → 5 (embedding+lexical reindex) → 7 (dump).
# Step 0 (ollama 재시작) / Step 1 (HCA+GDC) / Step 2 (GEO) 는 SKIP — 이미 완료.
set -euo pipefail

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

# 자동 GPU 수 탐지 (full-db-cycle.sh 의 로직 재사용)
FULLCYCLE_TARGET_GPUS="${FULLCYCLE_TARGET_GPUS:-4}"
FULLCYCLE_MIN_FREE_GB="${FULLCYCLE_MIN_FREE_GB:-70}"
MIN_FREE_MIB=$((FULLCYCLE_MIN_FREE_GB * 1024))
GPUS_FREE_LIST=$(nvidia-smi --query-gpu=index,memory.free --format=csv,noheader,nounits | \
  awk -F', ' -v t="$MIN_FREE_MIB" '$2 >= t {print $1}' | head -n "$FULLCYCLE_TARGET_GPUS")
GPUS_COUNT=$(echo "$GPUS_FREE_LIST" | grep -c '.' || echo 0)

MAMBA_ROOT="${MAMBA_ROOT_PREFIX:-/home/sosa8770/micromamba}"
ENV_NAME="${SVC_ENV_NAME:-genofinder-svc}"
SVC_BIN="$MAMBA_ROOT/envs/$ENV_NAME/bin"

cd "$REPO_ROOT/apps/workers"

say() { printf '\n\033[1;36m▸ %s\033[0m\n' "$*"; }
say_warn() { printf '\n\033[1;33m⚠ %s\033[0m\n' "$*"; }

echo "GPU detection: 사용 가능 = $GPUS_COUNT 장 (인덱스: $(echo "$GPUS_FREE_LIST" | paste -sd ,))"
echo "현재 ollama (PID 303263) 는 GPU 5 single-mode — 그대로 사용 (재시작 시 다른 사용자에게 GPU 빼앗길 위험)"

PARALLEL="${PARALLEL:-1}"  # 보수적 single — 기존 ollama 재시작 안 함
echo "→ reextract stride = $PARALLEL"

# ============================================================================
say "3/7 GEO Series Matrix sample-level backfill (concurrency=6)"
echo "  (--limit 1000000 — 28만 datasets, 이미 처리된 것은 자동 skip 됨)"
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
  echo "  single process"
  time uv run python scripts/reextract_with_ontology.py
fi

# ============================================================================
say "5/7 Embedding + OpenSearch reindex (Qwen3-Embedding-8B → 1024d, lexical batched 1000)"
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
echo "✅ Resume-from-extract 완료."
echo "📦 Dump bundle: ${DUMP_DIR}.tar.gz ($(du -h ${DUMP_DIR}.tar.gz | cut -f1))"
