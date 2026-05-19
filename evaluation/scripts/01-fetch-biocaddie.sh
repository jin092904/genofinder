#!/usr/bin/env bash
# bioCADDIE 2016 corpus / queries / qrels fetch.
#
# IMPORTANT:
#   - 본 script 는 명확한 공식 출처에서만 fetch. URL 추측 / 임의 mirror 사용 *금지*.
#   - 출처 후보 (모두 실패 시 abort 후 사용자 confirm):
#     1. https://biocaddie.org/benchmark-data (2025 시점 dead-link 가능성)
#     2. paper Cohen et al. 2017 (doi:10.1093/database/bax061) supplementary materials
#     3. 저자 GitHub / institutional repo
#     4. TREC Genomics 미러 (NIST)
#   - 라이선스: bioCADDIE corpus 의 정확한 라이선스는 fetch 시 README 확인. 일반적으로
#     CC-BY-NC 추정 → 본 repo 에 corpus 본체 commit 금지.
#
# Target:
#   $EVAL_BIOCADDIE_CORPUS_DIR (default /var/tmp/genofinder-eval/biocaddie) 에 저장.
#   evaluation/data/biocaddie/ 에는 symlink 만.
#
# TODO (실 fetch, Step 3-1 batch 후):
#   1. 위 출처 후보 차례로 시도. 첫 성공 시 PROVENANCE.md 에 정확한 URL / 응답 시각 / SHA256 기록.
#   2. raw → BEIR format 변환 (Python `adapters.biocaddie.to_beir_format`).
#   3. verify_counts() 통과 확인.
#   4. PHI-likely field 검출 (이름 / MRN 패턴) → 발견 시 abort.

set -euo pipefail

# 환경
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
[ -f "$ROOT/.env" ] && source "$ROOT/.env"
CORPUS_DIR="${EVAL_BIOCADDIE_CORPUS_DIR:-/var/tmp/genofinder-eval/biocaddie}"
DATA_DIR="$ROOT/data/biocaddie"

echo "===== bioCADDIE 2016 corpus fetch ====="
echo "  target dir: $CORPUS_DIR"
echo "  symlink:    $DATA_DIR/corpus.jsonl"
echo
echo "❌ STUB — 실 fetch URL 미확정. Step 3-1 (batch 종료 후) 에서 사용자 confirm 후 진행."
echo "현재 가능한 시도:"
echo "  curl -sIL https://biocaddie.org/benchmark-data"
echo
echo "TODO:"
echo "  1) 위 URL 의 응답 확인 (HTTP code, content-type, content-length)"
echo "  2) 성공 시 데이터 fetch → \$CORPUS_DIR"
echo "  3) PROVENANCE.md 에 정확한 URL / SHA256 / 응답 시각 기록"
echo "  4) python -m genofinder_eval.adapters.biocaddie 로 BEIR 변환 + verify_counts"
exit 0
