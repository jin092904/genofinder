#!/usr/bin/env bash
# Figure 1, 2, 3 일괄 생성.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"
[ -d ".venv" ] && source .venv/bin/activate

echo "===== Generate manuscript figures ====="

python -c "from genofinder_eval.figures.figure1_ablation import render; render()"
python -c "from genofinder_eval.figures.figure2_ko_en import render; render()"
python -c "from genofinder_eval.figures.figure3_score_decomp import render; render()"

echo "✅ Done. results/figures/{figure1_ablation,figure2_ko_en,figure3_score_decomp}.{pdf,png}"
