"""Celery tasks — 정기 incremental harvest + 글로벌 reindex.

각 task 는:
1. watermark 확인 (마지막 성공 시각)
2. lock 획득 (다른 worker 동시 실행 방지)
3. harvester.list_updated_since(watermark) 로 신규 records fetch
4. DB UPSERT
5. 성공 시 watermark 갱신

reindex_all 은 별도 nightly 태스크 — embed + Qdrant/OS upsert.

ADR 0002 T2/T3:
- 각 task 는 외부 LLM 안 호출 (LLM 추출은 별도 nightly batch)
- 본문 redaction 은 task 시작 시 configure_structlog
"""
from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone
from typing import Any

from src.celery_app import app
from src.db import get_engine
from src.scheduling.watermark import (
    get_watermark,
    set_watermark,
    source_lock,
)

logger = logging.getLogger(__name__)


def _run(coro):
    """sync Celery task 안에서 async 실행."""
    return asyncio.run(coro)


# ---------- GEO ----------

@app.task(bind=True, max_retries=2, default_retry_delay=600)
def harvest_geo_incremental(self) -> dict[str, Any]:
    return _run(_harvest_geo())


async def _harvest_geo() -> dict[str, Any]:
    from src.harvesters.geo import GeoHarvester
    from src.indexer.geo import index_geo_record

    async with source_lock("GEO") as acquired:
        if not acquired:
            logger.info("GEO harvest skipped — lock held by another worker")
            return {"skipped": "locked"}
        since = await get_watermark("GEO")
        eng = get_engine()
        inserted = 0
        skipped = 0
        try:
            async with GeoHarvester() as h:
                async with eng.connect() as conn:
                    async with conn.begin():
                        async for uid in h.list_updated_since(since):
                            try:
                                payload = await h.fetch_raw(uid)
                                await index_geo_record(conn, payload, uid)
                                inserted += 1
                            except Exception as e:
                                skipped += 1
                                logger.warning("GEO uid=%s failed: %s", uid, type(e).__name__)
            await set_watermark("GEO", when=datetime.now(timezone.utc))
        finally:
            await eng.dispose()
        logger.info("GEO incremental: inserted=%d skipped=%d since=%s", inserted, skipped, since.date())
        return {"source": "GEO", "inserted": inserted, "skipped": skipped, "since": since.isoformat()}


# ---------- HCA ----------

@app.task(bind=True, max_retries=2, default_retry_delay=600)
def harvest_hca_incremental(self) -> dict[str, Any]:
    return _run(_harvest_hca())


async def _harvest_hca() -> dict[str, Any]:
    from src.harvesters.hca import HcaHarvester
    from src.indexer.hca import index_hca_record
    from src.ontology.mapper import OntologyMapper

    async with source_lock("HCA") as acquired:
        if not acquired:
            return {"skipped": "locked"}
        since = await get_watermark("HCA")
        eng = get_engine()
        inserted = 0
        skipped = 0
        try:
            async with HcaHarvester() as h, OntologyMapper() as mapper:
                async with eng.connect() as conn:
                    async with conn.begin():
                        async for pid in h.list_updated_since(since):
                            try:
                                raw = await h.fetch_raw(pid)
                                await index_hca_record(conn, raw, pid, mapper=mapper)
                                inserted += 1
                            except Exception as e:
                                skipped += 1
                                logger.warning("HCA pid=%s failed: %s", pid, type(e).__name__)
            await set_watermark("HCA", when=datetime.now(timezone.utc))
        finally:
            await eng.dispose()
        return {"source": "HCA", "inserted": inserted, "skipped": skipped}


# ---------- GDC ----------

@app.task(bind=True, max_retries=2, default_retry_delay=600)
def harvest_gdc_incremental(self) -> dict[str, Any]:
    return _run(_harvest_gdc())


async def _harvest_gdc() -> dict[str, Any]:
    from src.harvesters.gdc import GdcHarvester
    from src.indexer.gdc import index_gdc_record
    from src.ontology.mapper import OntologyMapper

    async with source_lock("GDC") as acquired:
        if not acquired:
            return {"skipped": "locked"}
        eng = get_engine()
        inserted = 0
        skipped = 0
        try:
            async with GdcHarvester() as h, OntologyMapper() as mapper:
                async with eng.connect() as conn:
                    async with conn.begin():
                        # GDC 는 since 필터 미지원 — 항상 전체 91 projects 스캔.
                        # UPSERT 라 cost 작음.
                        async for pid in h.list_updated_since(datetime(2000, 1, 1, tzinfo=timezone.utc)):
                            try:
                                raw = await h.fetch_raw(pid)
                                await index_gdc_record(conn, raw, pid, mapper=mapper)
                                inserted += 1
                            except Exception as e:
                                skipped += 1
                                logger.warning("GDC pid=%s failed: %s", pid, type(e).__name__)
            await set_watermark("GDC", when=datetime.now(timezone.utc))
        finally:
            await eng.dispose()
        return {"source": "GDC", "inserted": inserted, "skipped": skipped}


# ---------- Global reindex ----------

@app.task(bind=True, max_retries=1, default_retry_delay=3600)
def reindex_all(self) -> dict[str, Any]:
    return _run(_reindex_all())


async def _reindex_all() -> dict[str, Any]:
    from src.indexer.pipeline import reindex_all_search_layers

    async with source_lock("REINDEX", ttl_s=60 * 60 * 6) as acquired:
        if not acquired:
            return {"skipped": "locked"}
        eng = get_engine()
        try:
            stats = await reindex_all_search_layers(eng)
        finally:
            await eng.dispose()
        return {"reindex_stats": stats}
