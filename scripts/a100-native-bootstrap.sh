#!/usr/bin/env bash
# A100 서버 native (no-container) 부트스트랩.
# Background: podman 3.4.4 + subuid 없음 → 컨테이너 stack 불가. 대안으로 user-mode binary 직접 실행.
# 자세한 진단 내역은 docs/runbooks/a100-setup.md 의 트러블슈팅 섹션 참조.
#
# 실행: bash scripts/a100-native-bootstrap.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"
SERVICES_DIR="$REPO_ROOT/services"
DATA_ROOT="${GENOFINDER_DATA_ROOT:-/home/sosa8770/genofinder}"

if [ ! -f "$ENV_FILE" ]; then
  echo "❌ $ENV_FILE 없음"; exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"
DATA_ROOT="${GENOFINDER_DATA_ROOT:-$DATA_ROOT}"
GPU_ID="${NVIDIA_GPU_DEVICE_ID:-3}"

mkdir -p "$SERVICES_DIR" \
         "$DATA_ROOT"/{pgdata,redis-data,qdrant-data,opensearch-data}

MAMBA="${MAMBA_EXE:-/home/sosa8770/.local/bin/micromamba}"
ENV_NAME="genofinder-svc"

say() { printf '\n\033[1;36m▸ %s\033[0m\n' "$*"; }

# ============================================================================
say "1/6 conda env (postgresql 16 + redis-server) via micromamba"
if ! "$MAMBA" env list 2>/dev/null | grep -q " $ENV_NAME "; then
  "$MAMBA" create -y -n "$ENV_NAME" -c conda-forge \
    postgresql=16 redis-server python=3.12
else
  echo "  env $ENV_NAME 이미 존재"
fi

PG_BIN="$MAMBA_ROOT_PREFIX/envs/$ENV_NAME/bin"
"$PG_BIN/postgres" --version
"$PG_BIN/redis-server" --version

# ============================================================================
say "2/6 PostgreSQL initdb + start (port 5432)"
if [ ! -f "$DATA_ROOT/pgdata/PG_VERSION" ]; then
  echo "  initdb..."
  "$PG_BIN/initdb" -D "$DATA_ROOT/pgdata" \
    --auth=md5 --username=genofinder --pwfile=<(echo "${POSTGRES_PASSWORD:-devpassword}")
fi

# 이미 실행 중이면 그대로 사용
if "$PG_BIN/pg_isready" -h 127.0.0.1 -p 5432 -U genofinder >/dev/null 2>&1; then
  echo "  postgres 이미 가동 중"
else
  nohup "$PG_BIN/pg_ctl" -D "$DATA_ROOT/pgdata" \
    -l "$DATA_ROOT/pgdata/postgres.log" \
    -o "-p 5432 -h 127.0.0.1" \
    -w start
fi

# init.sql 적용 (idempotent: ON CONFLICT)
if [ ! -f "$DATA_ROOT/pgdata/.init-applied" ]; then
  PGPASSWORD="${POSTGRES_PASSWORD:-devpassword}" \
    "$PG_BIN/psql" -h 127.0.0.1 -U genofinder -d postgres -c \
    "SELECT 1 FROM pg_database WHERE datname='genofinder'" | grep -q "1 row" || \
  PGPASSWORD="${POSTGRES_PASSWORD:-devpassword}" \
    "$PG_BIN/createdb" -h 127.0.0.1 -U genofinder genofinder

  PGPASSWORD="${POSTGRES_PASSWORD:-devpassword}" \
    "$PG_BIN/psql" -h 127.0.0.1 -U genofinder -d genofinder \
      -f "$REPO_ROOT/infra/compose/postgres-init.sql"
  touch "$DATA_ROOT/pgdata/.init-applied"
fi

# ============================================================================
say "3/6 Redis (port 6379)"
if ss -tlnp 2>/dev/null | grep -q ":6379 "; then
  echo "  redis 이미 가동 중"
else
  nohup "$PG_BIN/redis-server" --port 6379 \
    --dir "$DATA_ROOT/redis-data" \
    --appendonly yes \
    --bind 127.0.0.1 \
    > "$DATA_ROOT/redis-data/redis.log" 2>&1 &
  sleep 1
fi
"$PG_BIN/redis-cli" -p 6379 ping

# ============================================================================
say "4/6 Qdrant (port 6333)"
QDRANT_VER=1.12.1
QDRANT_DIR="$SERVICES_DIR/qdrant"
if [ ! -f "$QDRANT_DIR/qdrant" ]; then
  mkdir -p "$QDRANT_DIR"
  cd "$QDRANT_DIR"
  curl -L -o qdrant.tar.gz \
    "https://github.com/qdrant/qdrant/releases/download/v${QDRANT_VER}/qdrant-x86_64-unknown-linux-musl.tar.gz"
  tar xzf qdrant.tar.gz && rm qdrant.tar.gz
  cd "$REPO_ROOT"
fi
if ss -tlnp 2>/dev/null | grep -q ":6333 "; then
  echo "  qdrant 이미 가동 중"
else
  cat > "$QDRANT_DIR/config.yaml" <<EOF
service:
  http_port: 6333
  grpc_port: 6334
  host: 127.0.0.1
storage:
  storage_path: $DATA_ROOT/qdrant-data
log_level: INFO
EOF
  cd "$QDRANT_DIR"
  nohup ./qdrant --config-path config.yaml > "$DATA_ROOT/qdrant-data/qdrant.log" 2>&1 &
  cd "$REPO_ROOT"
  sleep 2
fi
curl -s http://127.0.0.1:6333/readyz | head -1 || echo "(qdrant 부팅 중)"

# ============================================================================
say "5/6 OpenSearch 2 (port 9200, security disabled, memlock 끔)"
OS_VER=2.16.0
OS_DIR="$SERVICES_DIR/opensearch-${OS_VER}"
if [ ! -d "$OS_DIR" ]; then
  cd "$SERVICES_DIR"
  curl -L -o "opensearch-${OS_VER}.tar.gz" \
    "https://artifacts.opensearch.org/releases/bundle/opensearch/${OS_VER}/opensearch-${OS_VER}-linux-x64.tar.gz"
  tar xzf "opensearch-${OS_VER}.tar.gz" && rm "opensearch-${OS_VER}.tar.gz"
  cd "$REPO_ROOT"
fi

# config — single-node, security off, memlock off, host 127.0.0.1
cat > "$OS_DIR/config/opensearch.yml" <<EOF
cluster.name: genofinder
node.name: a100-node
network.host: 127.0.0.1
http.port: 9200
discovery.type: single-node
plugins.security.disabled: true
bootstrap.memory_lock: false
path.data: $DATA_ROOT/opensearch-data
path.logs: $DATA_ROOT/opensearch-data/logs
EOF

# JVM 1G + memory_lock 끔
cat > "$OS_DIR/config/jvm.options.d/genofinder.options" <<EOF
-Xms1g
-Xmx1g
EOF

if ss -tlnp 2>/dev/null | grep -q ":9200 "; then
  echo "  opensearch 이미 가동 중"
else
  cd "$OS_DIR"
  OPENSEARCH_INITIAL_ADMIN_PASSWORD=ignored \
    DISABLE_SECURITY_PLUGIN=true \
    nohup ./bin/opensearch > "$DATA_ROOT/opensearch-data/opensearch.log" 2>&1 &
  cd "$REPO_ROOT"
fi
echo "  opensearch 부팅 대기..."
for i in $(seq 1 60); do
  if curl -s -m 2 http://127.0.0.1:9200/_cluster/health 2>/dev/null | grep -q '"status"'; then
    echo "  ✓ opensearch ready (${i}s)"
    break
  fi
  sleep 1
done

# ============================================================================
say "6/6 Ollama (port 11435, GPU $GPU_ID)"
OLLAMA_DIR="$SERVICES_DIR/ollama"
if [ ! -f "$OLLAMA_DIR/bin/ollama" ]; then
  echo "  ollama 바이너리 없음 — services/ollama/bin/ollama 다운로드 필요"
  exit 1
fi
if ss -tlnp 2>/dev/null | grep -q ":11435 "; then
  echo "  ollama 이미 가동 중"
else
  cd "$OLLAMA_DIR"
  OLLAMA_HOST=127.0.0.1:11435 \
    OLLAMA_MODELS="$OLLAMA_DIR/data" \
    CUDA_VISIBLE_DEVICES=$GPU_ID \
    LD_LIBRARY_PATH="$OLLAMA_DIR/lib/ollama:${LD_LIBRARY_PATH:-}" \
    nohup ./bin/ollama serve > /tmp/ollama-sosa.log 2>&1 &
  cd "$REPO_ROOT"
  sleep 3
fi
OLLAMA_HOST=127.0.0.1:11435 "$OLLAMA_DIR/bin/ollama" list | head

echo ""
echo "✅ Native stack 가동 완료. 다음:"
echo "    1) source $ENV_FILE && cd apps/api && uv run alembic upgrade head"
echo "    2) bash scripts/a100-batch-pipeline-native.sh 10000 500"
echo ""
echo "📊 상태 확인:"
echo "    ss -tlnp | grep -E '(5432|6379|6333|9200|11435)'"
echo "    nvidia-smi --id=$GPU_ID"
