#!/usr/bin/env bash
# A100 native (no-container) batch pipeline.
# Background: scripts/a100-batch-pipeline.sh 는 podman exec / podman cp 에 의존.
# native 환경에서는 호스트의 pg_dump / redis-cli 직접 호출 + qdrant 의 NFS storage 경로 직접 cp.
#
# 전제: scripts/a100-native-bootstrap.sh 성공 + .env 의 OLLAMA_MODEL_EXTRACTION 설정.
# 실행:
#   bash scripts/a100-batch-pipeline-native.sh [GEO_LIMIT] [TRANSLATE_TOP_N]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"
# shellcheck disable=SC1090
source "$ENV_FILE"

GEO_LIMIT="${1:-10000}"
TRANSLATE_TOP_N="${2:-500}"
DATA_ROOT="${GENOFINDER_DATA_ROOT:-/home/sosa8770/genofinder}"

# Service env vars (native, all localhost)
export DATABASE_URL="${DATABASE_URL:-postgresql+asyncpg://genofinder:${POSTGRES_PASSWORD:-devpassword}@localhost:5432/genofinder}"
export QDRANT_URL="${QDRANT_URL:-http://localhost:6333}"
export OPENSEARCH_URL="${OPENSEARCH_URL:-http://localhost:9200}"
export OLLAMA_URL="${OLLAMA_URL:-http://localhost:11435}"
export REDIS_URL="${REDIS_URL:-redis://localhost:6379/0}"
export OLLAMA_MODEL_EXTRACTION="${OLLAMA_MODEL_EXTRACTION:-qwen3:8b}"
export OLLAMA_MODEL_EMBED="${OLLAMA_MODEL_EMBED:-qwen3-embedding:8b}"
export NCBI_EUTILS_API_KEY="${NCBI_EUTILS_API_KEY:-}"

# Native binary paths
MAMBA="${MAMBA_EXE:-/home/sosa8770/.local/bin/micromamba}"
MAMBA_ROOT="${MAMBA_ROOT_PREFIX:-/home/sosa8770/micromamba}"
ENV_NAME="${SVC_ENV_NAME:-genofinder-svc}"
SVC_BIN="$MAMBA_ROOT/envs/$ENV_NAME/bin"

cd "$REPO_ROOT/apps/workers"

say() { printf '\n\033[1;36m▸ %s\033[0m\n' "$*"; }

# ============================================================================
say "1/6 GEO harvest (max=$GEO_LIMIT)"
time uv run python -m scripts.harvest_geo_large --days 365 --max "$GEO_LIMIT"

say "  HCA + GDC harvest"
time uv run python -c "
import asyncio
from src.indexer.tasks import _harvest_hca, _harvest_gdc
async def go():
    print('HCA:', await _harvest_hca())
    print('GDC:', await _harvest_gdc())
asyncio.run(go())
"

# ============================================================================
say "2/6 LLM 추출 (model=$OLLAMA_MODEL_EXTRACTION) — modality + ontology + cohort"
time uv run python scripts/reextract_with_ontology.py --limit "$GEO_LIMIT"

say "  → GEO Series Matrix sample backfill"
time uv run python -m scripts.harvest_geo_samples --limit "$GEO_LIMIT" --concurrency 6

# ============================================================================
say "3/6 Embedding 인덱싱 (model=$OLLAMA_MODEL_EMBED → Qdrant)"
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
            print(f'dropping {COLLECTION_NAME}...')
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
say "4/6 OpenSearch BM25 인덱스 빌드 — reindex_all_search_layers 에 포함됨"

# ============================================================================
say "5/6 Translate cache 사전 채우기 (top $TRANSLATE_TOP_N 데이터셋)"
# 주의: 이 단계는 API 서버 (uvicorn) 가 도는 상태여야 동작. 별도로 띄우기 어려우면 SKIP.
if curl -s -m 2 http://localhost:8000/api/v1/health >/dev/null 2>&1; then
  time uv run python -c "
import asyncio, httpx
from sqlalchemy import text
from src.db import get_engine

API_BASE = 'http://localhost:8000'
LIMIT = $TRANSLATE_TOP_N

async def go():
    eng = get_engine()
    async with eng.connect() as conn:
        result = await conn.execute(text('''
            SELECT id FROM datasets
             WHERE source_db='GEO' AND title IS NOT NULL AND abstract IS NOT NULL
             ORDER BY submission_date DESC NULLS LAST
             LIMIT :lim
        '''), {'lim': LIMIT})
        ids = [str(r[0]) for r in result.fetchall()]
    await eng.dispose()
    print(f'translating {len(ids)} datasets...')

    success, fail = 0, 0
    async with httpx.AsyncClient(timeout=180) as c:
        for i, did in enumerate(ids):
            try:
                r = await c.post(f'{API_BASE}/api/v1/datasets/{did}/translate?lang=ko')
                if r.status_code == 200: success += 1
                else: fail += 1
            except Exception as e:
                fail += 1
            if (i+1) % 50 == 0:
                print(f'  {i+1}/{len(ids)} success={success} fail={fail}')
    print(f'translate done: success={success} fail={fail}')

asyncio.run(go())
"
else
  echo "  ⚠ api 서버 :8000 미가동 — translate cache 단계 SKIP"
  echo "    (필요 시 별도 'uv run uvicorn ...' 후 다시 실행)"
fi

# ============================================================================
say "6/6 Dump 생성 — native pg_dump + qdrant snapshot + redis SAVE"
DUMP_DIR="${DATA_ROOT}/dumps/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$DUMP_DIR"

# pg_dump (native)
PGPASSWORD="${POSTGRES_PASSWORD:-devpassword}" \
  "$SVC_BIN/pg_dump" -h 127.0.0.1 -p 5432 -U genofinder -d genofinder | gzip > "$DUMP_DIR/db.sql.gz"
echo "  ✓ db.sql.gz: $(du -h $DUMP_DIR/db.sql.gz | cut -f1)"

# qdrant snapshot — POST + 로컬 storage_path 에서 복사 (no podman cp)
SNAP=$(curl -s -X POST localhost:6333/collections/datasets_v2/snapshots | \
       python3 -c "import sys,json; print(json.load(sys.stdin)['result']['name'])" 2>/dev/null || echo "")
if [ -n "$SNAP" ]; then
  cp "$DATA_ROOT/qdrant-data/snapshots/datasets_v2/$SNAP" "$DUMP_DIR/" 2>&1 || \
    echo "  ⚠ snapshot 복사 실패 — qdrant storage path 확인 필요"
  echo "  ✓ qdrant snapshot: $SNAP"
else
  echo "  ⚠ qdrant snapshot 생성 실패 (collection 없음?)"
fi

# Redis SAVE + 직접 RDB 복사
"$SVC_BIN/redis-cli" -h 127.0.0.1 -p 6379 SAVE >/dev/null
cp "$DATA_ROOT/redis-data/dump.rdb" "$DUMP_DIR/redis-dump.rdb"
echo "  ✓ redis-dump.rdb: $(du -h $DUMP_DIR/redis-dump.rdb | cut -f1)"

# 합본
tar czf "${DUMP_DIR}.tar.gz" -C "$(dirname $DUMP_DIR)" "$(basename $DUMP_DIR)"
echo ""
echo "✅ Native batch pipeline 완료."
echo "📦 Dump bundle: ${DUMP_DIR}.tar.gz ($(du -h ${DUMP_DIR}.tar.gz | cut -f1))"
