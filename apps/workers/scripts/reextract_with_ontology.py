"""one-shot 재처리: 전체 DB → Phi-4 추출 + OLS4 ontology 매핑 → DB UPDATE → 양 인덱스 재생성.

사용:
    cd apps/workers
    DATABASE_URL=... QDRANT_URL=... OPENSEARCH_URL=... OLLAMA_URL=... \\
        uv run python scripts/reextract_with_ontology.py [--limit N]

OpenSearch 인덱스는 strict mapping 이므로 drop + recreate. Qdrant 는 payload schema-less,
재 upsert 만으로 충분하지만 일관성을 위해 collection 도 drop + recreate.
"""
from __future__ import annotations

import argparse
import asyncio
from collections import Counter

from sqlalchemy import text

from src.db import get_engine
from src.extractors.llm_client import OllamaClient
from src.extractors.ontology_extractor import extract_with_ontology
from src.indexer.embeddings import (
    COLLECTION_NAME,
    ensure_collection,
    get_qdrant_client,
    upsert_many as qdrant_upsert_many,
)
from src.indexer.lexical import (
    INDEX_NAME,
    ensure_index,
    get_os_client,
    upsert_many as os_upsert_many,
)
from src.ontology.mapper import OntologyMapper


async def reextract(limit: int | None = None) -> None:
    eng = get_engine()
    async with eng.connect() as conn:
        q = text("SELECT id, source_db, source_id, title, abstract FROM datasets WHERE title IS NOT NULL")
        result = await conn.execute(q)
        rows = list(result.fetchall())
    if limit:
        rows = rows[:limit]
    print(f"reextracting {len(rows)} records...")

    counters = Counter()
    failed = 0
    async with OllamaClient() as ollama, OntologyMapper() as mapper:
        async with eng.connect() as conn:
            async with conn.begin():
                for i, r in enumerate(rows, 1):
                    out = await extract_with_ontology(ollama, mapper, r.title, r.abstract)
                    if not out["modality"] and not out["disease_ids"]:
                        failed += 1
                    for k in ("modality", "disease_ids", "tissue_ids", "cell_type_ids"):
                        counters[f"{k}.nonempty"] += int(bool(out[k]))
                        counters[f"{k}.total_terms"] += len(out[k])
                    await conn.execute(
                        text("""
                            UPDATE datasets SET
                                modality           = :m,
                                disease_ids        = :d,
                                tissue_ids         = :t,
                                cell_type_ids      = :c,
                                extraction_version = :v
                            WHERE id = :id
                        """),
                        {"m": out["modality"], "d": out["disease_ids"],
                         "t": out["tissue_ids"], "c": out["cell_type_ids"],
                         "v": out["extraction_version"], "id": r.id},
                    )
                    if i % 20 == 0:
                        print(f"  {i}/{len(rows)} done — diseases nonempty={counters['disease_ids.nonempty']} "
                              f"tissues nonempty={counters['tissue_ids.nonempty']} "
                              f"cell_types nonempty={counters['cell_type_ids.nonempty']}")
    print(f"finished. records w/ no extraction: {failed}")
    print("counters:", dict(counters))

    # Reindex — drop + recreate (schema 갱신)
    qdrant = get_qdrant_client()
    os_client = get_os_client()
    try:
        # Qdrant: collection delete + create
        cols = await qdrant.get_collections()
        if any(c.name == COLLECTION_NAME for c in cols.collections):
            await qdrant.delete_collection(COLLECTION_NAME)
            print(f"dropped qdrant collection {COLLECTION_NAME}")
        await ensure_collection(qdrant)

        # OpenSearch: index delete + create
        if await os_client.indices.exists(index=INDEX_NAME):
            await os_client.indices.delete(index=INDEX_NAME)
            print(f"dropped opensearch index {INDEX_NAME}")
        await ensure_index(os_client)

        async with eng.connect() as conn:
            res = await conn.execute(text("""
                SELECT id, source_db, source_id, title, abstract, modality, organism_taxid,
                       disease_ids, tissue_ids, cell_type_ids,
                       access_type, has_processed_data, submission_date,
                       n_samples, n_subjects, platform, library_strategy, extraction_version
                  FROM datasets
                  ORDER BY submission_date DESC NULLS LAST
            """))
            all_rows = [dict(r._mapping) for r in res.fetchall()]

        async with OllamaClient() as ollama:
            n_q = await qdrant_upsert_many(qdrant, ollama, all_rows)
        n_os = await os_upsert_many(os_client, all_rows)
        print(f"reindexed: qdrant={n_q} opensearch={n_os} total_db={len(all_rows)}")
    finally:
        await qdrant.close()
        await os_client.close()
        await eng.dispose()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=None,
                        help="optional cap (test runs)")
    args = parser.parse_args()
    asyncio.run(reextract(limit=args.limit))


if __name__ == "__main__":
    main()
