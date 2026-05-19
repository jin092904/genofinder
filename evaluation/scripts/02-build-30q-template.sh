#!/usr/bin/env bash
# Expert-curated 30q 빈 template 생성 — 편집자 직접 작성용.
#
# IMPORTANT:
#   - 본 script 는 **빈 schema** 만 생성. **LLM 자동 query 생성 금지.**
#   - 30 query 의 text_en / text_ko / expected_facets 는 편집자 (호진) 직접 작성.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT="$ROOT/data/expert_curated_30"
mkdir -p "$OUT"

# Domain 카테고리 정의 (CONSTRUCTION_PROTOCOL.md 의 매트릭스 1:1 매핑).
SHORT_MODALITY=(
  "scRNA-seq" "bulk-RNA-seq" "ChIP-seq" "ATAC-seq" "WGS-WES"
  "proteomics" "spatial-transcriptomics" "methylation" "microbiome" "metabolomics"
)
MEDIUM_DISEASE=(
  "cancer-solid" "cancer-hematologic" "immune-autoimmune" "neurological" "cardiovascular"
  "infectious-bacterial" "infectious-viral" "metabolic-diabetes" "rare-disease" "reproductive"
)
COMPLEX_DESIGN=(
  "case-control" "treatment-vs-control" "time-series" "dose-response" "knockout"
  "tissue-comparison" "pre-post" "responder-nonresponder" "age-sex-stratification" "multi-omics"
)

# 빈 queries_en.jsonl / queries_ko.jsonl 생성 — text 는 빈 문자열, 편집자가 채움.
EN="$OUT/queries_en.jsonl"
KO="$OUT/queries_ko.jsonl"
FACET="$OUT/facet_judgments.jsonl"

# 기존 파일이 있으면 덮어쓰지 않음 (편집자 작성 보호)
if [ -f "$EN" ] || [ -f "$KO" ] || [ -f "$FACET" ]; then
  echo "⚠ 기존 template 존재 — 덮어쓰지 않음. 수동 삭제 후 재실행."
  exit 1
fi

i=1
{
  for mod in "${SHORT_MODALITY[@]}"; do
    printf '{"_id":"Q%02d","category":"short","modality_slot":"%s","text":"<TODO: short query (1-3 words) for %s>","expected_facets":{"modality":"%s"}}\n' \
      "$i" "$mod" "$mod" "$mod"
    i=$((i+1))
  done
  for dis in "${MEDIUM_DISEASE[@]}"; do
    printf '{"_id":"Q%02d","category":"medium","disease_slot":"%s","text":"<TODO: medium query (1 sentence) for %s>","expected_facets":{"disease":"<TODO>"}}\n' \
      "$i" "$dis" "$dis"
    i=$((i+1))
  done
  for des in "${COMPLEX_DESIGN[@]}"; do
    printf '{"_id":"Q%02d","category":"complex","design_slot":"%s","text":"<TODO: complex query (multi-facet) for %s>","expected_facets":{"design_type":"%s"}}\n' \
      "$i" "$des" "$des" "$des"
    i=$((i+1))
  done
} > "$EN"

# KO 는 EN 의 id / category / slot 미러 — text 만 빈 문자열로 (편집자가 한국어 작성)
python3 - <<'PY'
import json, os
en_path = os.path.join(os.environ.get('OUT', 'data/expert_curated_30'), 'queries_en.jsonl')
ko_path = os.path.join(os.environ.get('OUT', 'data/expert_curated_30'), 'queries_ko.jsonl')
facet_path = os.path.join(os.environ.get('OUT', 'data/expert_curated_30'), 'facet_judgments.jsonl')
with open(en_path) as f, open(ko_path, 'w') as ko_f, open(facet_path, 'w') as facet_f:
    for line in f:
        row = json.loads(line)
        ko_row = {**row, "text": "<TODO: 한국어 (편집자 직접 작성, 기계번역 금지)>"}
        ko_f.write(json.dumps(ko_row, ensure_ascii=False) + "\n")
        facet_f.write(json.dumps({"qid": row["_id"], "expected": row["expected_facets"]}, ensure_ascii=False) + "\n")
PY
OUT="$OUT" python3 - <<'PY'
print("✅ Template 30 queries 생성 완료.")
print("📝 편집자 작업: data/expert_curated_30/queries_{en,ko}.jsonl 의 <TODO> 부분을 직접 채움.")
print("⚠ BCG / bladder cancer 직접 언급은 최대 3건. 도메인 매트릭스 (CONSTRUCTION_PROTOCOL.md) 참조.")
PY
