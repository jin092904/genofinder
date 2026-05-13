#!/usr/bin/env bash
# A100 서버 1회 부트스트랩 — podman + NFS + 모델 pull + DB 마이그레이션.
# ADR 0006 + migration_v2.md §3 (A100 서버) 기준.
#
# 실행 (사용자):
#   cd ~/genofinder
#   bash scripts/a100-bootstrap.sh
#
# 전제:
#   - SSH 접속 성공
#   - pip install --user podman-compose 완료
#   - .env 파일 존재 (GENOFINDER_DATA_ROOT, NVIDIA_GPU_DEVICE_ID, 등 정의)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_DIR="$REPO_ROOT/infra/compose"
ENV_FILE="$REPO_ROOT/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "❌ $ENV_FILE 없음. .env.a100.example 참조해서 생성."
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

DATA_ROOT="${GENOFINDER_DATA_ROOT:-/home/sosa8770/genofinder}"
GPU_ID="${NVIDIA_GPU_DEVICE_ID:-3}"

echo "▸ 1/6 NFS 디렉터리 준비 ($DATA_ROOT)"
mkdir -p "$DATA_ROOT"/{ollama-models,postgres-data,qdrant-data,opensearch-data,redis-data,kms-data}
echo "  ✓ 디렉터리 생성/확인"

echo "▸ 2/6 GPU $GPU_ID 가용성 확인"
if ! command -v nvidia-smi >/dev/null 2>&1; then
  echo "  ⚠ nvidia-smi 미설치 — host 측 NVIDIA driver 확인 필요"
else
  nvidia-smi --id="$GPU_ID" --query-gpu=name,memory.free --format=csv,noheader || {
    echo "❌ GPU $GPU_ID 접근 실패 (다른 사용자가 점유 중일 수 있음)"
    exit 1
  }
fi

echo "▸ 3/6 podman-compose 가용성 확인"
if ! command -v podman-compose >/dev/null 2>&1; then
  echo "❌ podman-compose 미설치. 다음 실행:"
  echo "    pip install --user podman-compose"
  exit 1
fi
podman-compose --version

echo "▸ 4/6 스택 기동 (postgres / redis / qdrant / opensearch / ollama / kms)"
cd "$COMPOSE_DIR"
podman-compose \
  --env-file "$ENV_FILE" \
  -f docker-compose.dev.yml \
  -f docker-compose.a100.yml \
  up -d postgres redis qdrant opensearch ollama kms

echo "  postgres healthy 대기..."
for i in $(seq 1 60); do
  status=$(podman inspect --format='{{.State.Health.Status}}' genofinder-dev-postgres 2>/dev/null || true)
  if [ "$status" = "healthy" ]; then
    echo "  ✓ postgres healthy (${i}s)"
    break
  fi
  sleep 1
done

echo "▸ 5/6 Alembic 마이그레이션"
cd "$REPO_ROOT/apps/api"
ALEMBIC_DATABASE_URL="postgresql+asyncpg://genofinder:${POSTGRES_PASSWORD:-devpassword}@localhost:5432/genofinder" \
  uv run alembic upgrade head
echo "  ✓ 마이그레이션 0001~0004 적용"

echo "▸ 6/6 모델 pull (Gemma 3 27B + Qwen3-Embedding 8B + Qwen3-Reranker 0.6B)"
echo "  → Gemma 3 27B IT BF16 (~54GB 다운로드, 10-20분)"
podman exec genofinder-dev-ollama ollama pull gemma3:27b-it-bf16
echo "  → Qwen3-Embedding-8B (~16GB)"
podman exec genofinder-dev-ollama ollama pull qwen3-embedding:8b
# Qwen3-Reranker 는 Ollama 미공식 — sentence-transformers 가 첫 호출 시 자동 다운로드 (~1GB to HF cache)

echo ""
echo "✅ A100 bootstrap 완료. 다음:"
echo "    bash scripts/a100-batch-pipeline.sh"
echo ""
echo "📊 모델 목록 확인: podman exec genofinder-dev-ollama ollama list"
