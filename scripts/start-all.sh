#!/usr/bin/env bash
# Geno Finder 전체 dev 스택 + retry 시작.
#
# 사용:
#   ~/bioinfo0929/work_7_search/genofinder/scripts/start-all.sh
#
# 무엇을 띄우는가:
#   1. Docker 컨테이너 (postgres + redis + qdrant + opensearch + ollama + kms + workers + beat)
#   2. FastAPI uvicorn (host, 0.0.0.0:8000)
#   3. Next.js dev server (host, 3000)
#   4. OCI capacity retry 스크립트 (백그라운드)
set -u

REPO=/home/hojin/bioinfo0929/work_7_search/genofinder
ENV_FILE="$REPO/.env"
COMPOSE_FILE="$REPO/infra/compose/docker-compose.dev.yml"
ORACLE_KEY=/home/hojin/bioinfo0929/work_7_search/genofinder-55e4a-firebase-adminsdk-fbsvc-656057cd81.json
API_LOG=/tmp/genofinder-api.log
WEB_LOG=/tmp/genofinder-web.log
RETRY_LOG=/home/hojin/bioinfo0929/work_7_search/oci-retry.log
RETRY_SH=$HOME/genofinder-oci-retry/launch.sh

say() { printf '\n\033[1;36m▸ %s\033[0m\n' "$*"; }
ok()  { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
err() { printf '  \033[1;31m✗\033[0m %s\n' "$*"; }

# ---------------------------------------------------------------------------
say '1/4  Docker 스택 기동 (postgres / redis / qdrant / opensearch / ollama / kms / workers / beat)'
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d \
  postgres redis qdrant opensearch ollama kms workers beat \
  2>&1 | tail -10
echo

say '   postgres healthy 까지 대기 (최대 60초)'
for i in $(seq 1 60); do
  status=$(docker inspect --format='{{.State.Health.Status}}' genofinder-dev-postgres-1 2>/dev/null)
  if [ "$status" = "healthy" ]; then
    ok "postgres healthy (${i}s)"
    break
  fi
  sleep 1
done

# ---------------------------------------------------------------------------
say '2/4  API (uvicorn, host 0.0.0.0:8000)'
if ss -tlnp 2>/dev/null | grep -q ':8000'; then
  ok 'API 이미 listen 중 (8000)'
else
  cd "$REPO/apps/api"
  nohup env \
    GOOGLE_APPLICATION_CREDENTIALS="$ORACLE_KEY" \
    ALLOWED_ORIGINS=http://localhost:3000 \
    DATABASE_URL=postgresql+asyncpg://genofinder_app:devpassword@localhost:5432/genofinder \
    ALEMBIC_DATABASE_URL=postgresql+asyncpg://genofinder:devpassword@localhost:5432/genofinder \
    REDIS_URL=redis://localhost:6379/0 \
    QDRANT_URL=http://localhost:6333 \
    OPENSEARCH_URL=http://localhost:9200 \
    OLLAMA_URL=http://localhost:11434 \
    RERANKER_TOP_N=15 \
    uv run uvicorn src.main:app --host 0.0.0.0 --port 8000 \
    > "$API_LOG" 2>&1 &
  disown
  for i in $(seq 1 30); do
    if curl -sf -o /dev/null --max-time 2 http://localhost:8000/api/v1/health; then
      ok "API ready (${i}s)"
      break
    fi
    sleep 1
  done
fi

# ---------------------------------------------------------------------------
say '3/4  Web (next dev, host 3000)'
if ss -tlnp 2>/dev/null | grep -q ':3000'; then
  ok 'Web 이미 listen 중 (3000)'
else
  cd "$REPO/apps/web"
  rm -rf .next  # production build artifact 와 충돌 방지
  nohup pnpm dev > "$WEB_LOG" 2>&1 &
  disown
  for i in $(seq 1 30); do
    if curl -sf -o /dev/null --max-time 2 http://localhost:3000; then
      ok "Web ready (${i}s)"
      break
    fi
    sleep 1
  done
fi

# ---------------------------------------------------------------------------
say '4/4  OCI capacity retry'
if pgrep -f 'genofinder-oci-retry/launch.sh' >/dev/null; then
  ok 'retry 이미 실행 중'
else
  if [ -x "$RETRY_SH" ]; then
    nohup "$RETRY_SH" >> "$RETRY_LOG" 2>&1 &
    disown
    ok "retry 시작 — 로그: $RETRY_LOG"
  else
    err "retry 스크립트 없음 ($RETRY_SH)"
  fi
fi

# ---------------------------------------------------------------------------
echo
say '완료 — 상태 요약'
printf '  Web:   http://localhost:3000\n'
printf '  API:   http://localhost:8000/api/v1/health\n'
printf '  로그:\n'
printf '    API   tail -f %s\n' "$API_LOG"
printf '    Web   tail -f %s\n' "$WEB_LOG"
printf '    Retry tail -f %s\n' "$RETRY_LOG"
