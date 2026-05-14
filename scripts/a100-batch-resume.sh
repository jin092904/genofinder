#!/usr/bin/env bash
# A100 native batch — Step 1 (GEO harvest) 이미 완료된 상태에서 재개.
#
# 2026-05-13 의 첫 batch 는 harvest 후 자동 reindex 단계에서 Qdrant dim
# mismatch (1024 vs 4096) 로 crash. embed truncate_dim 패치 후 재개.
#
# 실행 흐름:
#   1. HCA + GDC harvest (Step 1 의 나머지)
#   2. LLM modality + ontology 추출 (Gemma 4 31B)
#   3. GEO Series Matrix sample-level backfill
#   4. Embedding + OpenSearch reindex (Qwen3-Embedding-8B Matryoshka 1024d)
#   5. Dump 생성
#
# Step 5 (Translate top N) 는 API uvicorn 미가동으로 SKIP.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"
# shellcheck disable=SC1090
source "$ENV_FILE"

GEO_LIMIT="${1:-10000}"
DATA_ROOT="${GENOFINDER_DATA_ROOT:-/home/sosa8770/genofinder}"

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

# ============================================================================
say "1.5/6 HCA + GDC harvest (Step 1 잔여)"
time uv run python -c "
import asyncio
from src.indexer.tasks import _harvest_hca, _harvest_gdc
async def go():
    print('HCA:', await _harvest_hca())
    print('GDC:', await _harvest_gdc())
asyncio.run(go())
" || echo "  ⚠ HCA/GDC harvest 부분 실패 — 다음 단계 계속"

# ============================================================================
say "2/6 LLM 추출 (model=$OLLAMA_MODEL_EXTRACTION) — modality + ontology"
time uv run python scripts/reextract_with_ontology.py --limit "$GEO_LIMIT"

# ============================================================================
say "2.5/6 GEO Series Matrix sample-level backfill (concurrency=6)"
time uv run python -m scripts.harvest_geo_samples --limit "$GEO_LIMIT" --concurrency 6 || \
  echo "  ⚠ samples backfill 일부 실패 — 다음 단계 계속"

# ============================================================================
say "3/6 Embedding + OpenSearch reindex (Qwen3-Embedding-8B → Matryoshka 1024d)"
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
say "5/6 Translate top-N — API 미가동시 SKIP"
echo "  (resume script 에서는 skip — API uvicorn 별도 가동 후 수동 실행 권장)"

# ============================================================================
say "6/6 Dump 생성"
DUMP_DIR="${DATA_ROOT}/dumps/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$DUMP_DIR"

PGPASSWORD="${POSTGRES_PASSWORD:-devpassword}" \
  "$SVC_BIN/pg_dump" -h 127.0.0.1 -p 5432 -U genofinder -d genofinder | gzip > "$DUMP_DIR/db.sql.gz"
echo "  ✓ db.sql.gz: $(du -h $DUMP_DIR/db.sql.gz | cut -f1)"

SNAP=$(curl -s -X POST localhost:6333/collections/datasets_v2/snapshots | \
       python3 -c "import sys,json; print(json.load(sys.stdin)['result']['name'])" 2>/dev/null || echo "")
if [ -n "$SNAP" ]; then
  cp "$DATA_ROOT/qdrant-data/snapshots/datasets_v2/$SNAP" "$DUMP_DIR/" 2>&1 || \
    echo "  ⚠ snapshot 복사 실패"
  echo "  ✓ qdrant snapshot: $SNAP"
fi

"$SVC_BIN/redis-cli" -h 127.0.0.1 -p 6379 SAVE >/dev/null
cp "$DATA_ROOT/redis-data/dump.rdb" "$DUMP_DIR/redis-dump.rdb"
echo "  ✓ redis-dump.rdb: $(du -h $DUMP_DIR/redis-dump.rdb | cut -f1)"

tar czf "${DUMP_DIR}.tar.gz" -C "$(dirname $DUMP_DIR)" "$(basename $DUMP_DIR)"
echo ""
echo "✅ Native batch resume 완료."
echo "📦 Dump bundle: ${DUMP_DIR}.tar.gz ($(du -h ${DUMP_DIR}.tar.gz | cut -f1))"
