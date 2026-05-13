#!/usr/bin/env bash
# A100 batch pipeline — corpus 풀 처리 + dump 생성.
# ADR 0006 + migration_v2.md §3 §4
#
# 흐름:
#   1. Harvest (GEO + HCA + GDC + SRA)  ~1-2시간
#   2. LLM 추출 (modality + ontology + cohort)  ~2-3시간
#   3. Embedding 인덱싱 (Qwen3-8B Matryoshka 1024d)  ~1-2시간
#   4. OpenSearch BM25 인덱스 빌드  ~30분
#   5. Translate cache 사전 채우기 (top N)  ~1-2시간
#   6. Dump 생성  ~5분
#
# 전제: a100-bootstrap.sh 가 성공한 상태.
# 실행:
#   bash scripts/a100-batch-pipeline.sh [GEO_LIMIT] [TRANSLATE_TOP_N]
#     GEO_LIMIT (기본 10000)
#     TRANSLATE_TOP_N (기본 500 — 인기 데이터셋 사전 번역)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"
# shellcheck disable=SC1090
source "$ENV_FILE"

GEO_LIMIT="${1:-10000}"
TRANSLATE_TOP_N="${2:-500}"

# 환경변수 — Gemma 3 27B BF16 + Qwen3-Embedding-8B
export DATABASE_URL="postgresql+asyncpg://genofinder:${POSTGRES_PASSWORD:-devpassword}@localhost:5432/genofinder"
export QDRANT_URL="http://localhost:6333"
export OPENSEARCH_URL="http://localhost:9200"
export OLLAMA_URL="http://localhost:11434"
export REDIS_URL="redis://localhost:6379/0"
export OLLAMA_MODEL_EXTRACTION="gemma3:27b-it-bf16"
export OLLAMA_MODEL_EMBED="qwen3-embedding:8b"
export NCBI_EUTILS_API_KEY="${NCBI_EUTILS_API_KEY:-}"

cd "$REPO_ROOT/apps/workers"

say() { printf '\n\033[1;36m▸ %s\033[0m\n' "$*"; }

# ---------------------------------------------------------------------------
say "1/6 GEO harvest (max=$GEO_LIMIT)"
time uv run python -m scripts.harvest_geo_large --days 365 --max "$GEO_LIMIT"

# HCA, GDC, SRA 도 함께 — 기존 reextract 스크립트 또는 task 호출
say "  HCA + GDC + SRA harvest (incremental tasks)"
time uv run python -c "
import asyncio
from src.indexer.tasks import _harvest_hca, _harvest_gdc
async def go():
    print('HCA:', await _harvest_hca())
    print('GDC:', await _harvest_gdc())
asyncio.run(go())
"

# ---------------------------------------------------------------------------
say "2/6 LLM 추출 (Gemma 3 27B BF16) — modality + ontology + cohort"
say "  → reextract_with_ontology (전체 corpus 재처리)"
time uv run python scripts/reextract_with_ontology.py --limit "$GEO_LIMIT"

say "  → GEO Series Matrix sample backfill"
time uv run python -m scripts.harvest_geo_samples --limit "$GEO_LIMIT" --concurrency 6

# Cohort 추출은 API endpoint POST /cohort/extract 가 처리. 전체 corpus loop 호출.
# A100 batch 측에서는 별도 batch script 필요 — 다음 PR.

# ---------------------------------------------------------------------------
say "3/6 Embedding 인덱싱 (Qwen3-Embedding-8B Matryoshka 1024d → Qdrant)"
say "  Qdrant collection 'datasets_v2' drop + recreate + embed"
time uv run python -c "
import asyncio
from sqlalchemy import text
from src.db import get_engine
from src.indexer.embeddings import COLLECTION_NAME, get_qdrant_client
from src.indexer.pipeline import reindex_all_search_layers

async def go():
    qdrant = get_qdrant_client()
    try:
        # 기존 v1 또는 v2 collection 있으면 drop (clean reindex)
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

# ---------------------------------------------------------------------------
say "4/6 OpenSearch BM25 인덱스 빌드 (datasets_v2)"
# reindex_all_search_layers 가 이미 호출함 — 별도 작업 불필요

# ---------------------------------------------------------------------------
say "5/6 Translate cache 사전 채우기 (top $TRANSLATE_TOP_N 데이터셋)"
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
                if r.status_code == 200:
                    success += 1
                else:
                    fail += 1
            except Exception as e:
                fail += 1
                print(f'  fail {did}: {type(e).__name__}')
            if (i+1) % 50 == 0:
                print(f'  {i+1}/{len(ids)} success={success} fail={fail}')
    print(f'translate done: success={success} fail={fail}')

asyncio.run(go())
"

# ---------------------------------------------------------------------------
say "6/6 Dump 생성 (pg_dump + Qdrant snapshot + Redis RDB)"
DUMP_DIR="${GENOFINDER_DATA_ROOT}/dumps/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$DUMP_DIR"

podman exec genofinder-dev-postgres \
  pg_dump -U genofinder genofinder | gzip > "$DUMP_DIR/db.sql.gz"
echo "  ✓ db.sql.gz: $(du -h $DUMP_DIR/db.sql.gz | cut -f1)"

# Qdrant snapshot
SNAP=$(curl -s -X POST localhost:6333/collections/datasets_v2/snapshots | jq -r .result.name)
podman cp genofinder-dev-qdrant:/qdrant/snapshots/datasets_v2/$SNAP "$DUMP_DIR/"
echo "  ✓ qdrant snapshot: $SNAP"

# Redis RDB (translate cache)
podman exec genofinder-dev-redis redis-cli SAVE >/dev/null
podman cp genofinder-dev-redis:/data/dump.rdb "$DUMP_DIR/redis-dump.rdb"
echo "  ✓ redis-dump.rdb: $(du -h $DUMP_DIR/redis-dump.rdb | cut -f1)"

# 합본
tar czf "${DUMP_DIR}.tar.gz" -C "$(dirname $DUMP_DIR)" "$(basename $DUMP_DIR)"
echo ""
echo "✅ Batch pipeline 완료."
echo "📦 Dump bundle: ${DUMP_DIR}.tar.gz ($(du -h ${DUMP_DIR}.tar.gz | cut -f1))"
echo ""
echo "다음: 서빙 시작 또는 dump 를 다른 서버로 이주"
