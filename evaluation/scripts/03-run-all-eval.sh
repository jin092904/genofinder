#!/usr/bin/env bash
# 전체 evaluation 일괄 실행 — Step 7-8 batch 종료 후 사용.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

# venv activate
if [ -d ".venv" ]; then
  # shellcheck disable=SC1091
  source .venv/bin/activate
else
  echo "❌ .venv 미생성. uv venv && uv pip install -e \".[dev]\" 먼저."
  exit 1
fi

echo "===== Geno Finder Eval — Full Pipeline ====="

echo "[Pre-flight 1/3] GPU 가용성 점검"
nvidia-smi --query-gpu=index,memory.free,utilization.gpu --format=csv,noheader | head

echo "[Pre-flight 2/3] Ollama 상태"
OLLAMA_HOST=127.0.0.1:11435 ~/genofinder/services/ollama/bin/ollama ps 2>&1 || \
  echo "⚠ ollama unreachable"

echo "[Pre-flight 3/3] Geno Finder API 상태 (FastAPI uvicorn)"
curl -sf http://localhost:8000/api/v1/health || {
  echo "❌ Geno Finder API down. 다음 실행 후 재시도:"
  echo "    cd $ROOT/../apps/api && uv run uvicorn src.main:app --port 8000 &"
  exit 1
}

echo "[1/4] bioCADDIE corpus fetch (이미 fetch 됐으면 skip)"
if [ ! -f "data/biocaddie/corpus.jsonl" ]; then
  bash scripts/01-fetch-biocaddie.sh
fi

echo "[2/4] Run bioCADDIE evaluation (15q × 4 mode = 60 search)"
python -m genofinder_eval.runners.run_biocaddie

echo "[3/4] Run expert-curated 30q evaluation (30q × 4 mode × 2 lang = 240 search)"
python -m genofinder_eval.runners.run_expert_curated

echo "[4/4] Generate figures"
bash scripts/04-generate-figures.sh

echo
echo "✅ Done. results/aggregated/*.csv + results/figures/*.{pdf,png}"
