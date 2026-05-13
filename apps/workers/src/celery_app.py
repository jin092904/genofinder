"""Celery app — broker/backend 는 Redis (compose service 'redis').

본 모듈은 task discovery 의 단일 진입점이며 beat 스케줄도 정의한다.

ADR 0002 T3: 본 app 의 logging 은 redaction processor 가 적용된 structlog 로 통합되어야 한다.
현재는 placeholder — 실제 구성은 보안 모듈 구현 PR (Week 7) 에서.

Beat 스케줄 (UTC 기준):
- 02:00 GEO incremental
- 02:30 HCA incremental
- 03:00 GDC incremental
- 04:00 reindex_all (전체 다시 임베딩 + Qdrant + OS)

각 source 별 incremental 은 watermark 기반 (마지막 성공 시각 이후 갱신된 records).
"""
from __future__ import annotations

import os

from celery import Celery
from celery.schedules import crontab

REDIS_URL = os.environ.get("REDIS_URL", "redis://redis:6379/0")

app = Celery(
    "genofinder_workers",
    broker=REDIS_URL,
    backend=REDIS_URL,
    include=[
        "src.indexer.tasks",
    ],
)

app.conf.update(
    task_acks_late=True,
    task_reject_on_worker_lost=True,
    task_default_retry_delay=30,
    worker_prefetch_multiplier=1,  # heavy task 라 1개씩만
    broker_connection_retry_on_startup=True,
    timezone="UTC",
    enable_utc=True,
)

app.conf.beat_schedule = {
    "harvest-geo-daily": {
        "task": "src.indexer.tasks.harvest_geo_incremental",
        "schedule": crontab(hour=2, minute=0),
    },
    "harvest-hca-daily": {
        "task": "src.indexer.tasks.harvest_hca_incremental",
        "schedule": crontab(hour=2, minute=30),
    },
    "harvest-gdc-daily": {
        "task": "src.indexer.tasks.harvest_gdc_incremental",
        "schedule": crontab(hour=3, minute=0),
    },
    "reindex-nightly": {
        "task": "src.indexer.tasks.reindex_all",
        "schedule": crontab(hour=4, minute=0),
    },
}
