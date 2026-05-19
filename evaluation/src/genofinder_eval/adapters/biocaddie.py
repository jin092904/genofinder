"""bioCADDIE 2016 Dataset Retrieval Challenge corpus / queries / qrels loader.

Reference:
    Cohen T, Roberts K, et al. "DataMed — an open source discovery index for
    finding biomedical datasets." Database (Oxford), 2017. doi:10.1093/database/bax061
    Roberts K, Demner-Fushman D, Tonelli M, et al. "Overview of the TREC 2016
    Clinical Decision Support Track." TREC, 2017. (관련 bax068)

Data scale (논문 보고치):
    corpus: 794,992 datasets (DataMed internal IDs, 2016-03-24 snapshot,
            GEO + ArrayExpress + BioProject + dbGaP 등 20 repository)
    queries: 15 (test set)
    qrels: 20,000+ manual relevance judgments
    best submission infNDCG: 0.423 (mean, bax068)

Notes:
    - bioCADDIE doc_id 는 DataMed internal ID 라 우리 GSE accession 과 *직접 join 불가*.
    - 본 평가는 *우리 retrieval stack 을 bioCADDIE corpus 위에 올려 실행* 하는 OOD
      generalization 평가. 별도 임시 인덱스 (`biocaddie_2016_eval`) 사용.
    - fetch 실패 시 abort, 사용자 보고. 합성 데이터 fabrication 금지.

TODO (Step 3-1 구현 + 실제 fetch):
- `scripts/01-fetch-biocaddie.sh` 가 호출하는 URL 검증.
- raw bioCADDIE JSON → BEIR-format jsonl 변환 함수.
- row count assertion (논문의 794,992 / 15 / 20,000+ 와 일치 확인).
- PHI-likely fields (이름, MRN 패턴) 발견 시 raise.
"""
from __future__ import annotations

from pathlib import Path


def to_beir_format(
    raw_dir: Path,
    out_dir: Path,
) -> dict[str, int]:
    """bioCADDIE raw 배포본 → BEIR-format 변환.

    raw_dir 의 구조와 정확한 schema 는 fetch 시점에 확인 (paper 의 supplementary materials
    또는 데이터 호스팅 사이트). 따라서 본 함수는 fetch 성공 후에야 구현 가능.

    Returns:
        {"corpus_n": N, "queries_n": M, "qrels_n": K} — assertion 용.
    """
    # TODO(step-3-1, post-fetch): raw 구조 확인 후 구현.
    raise NotImplementedError(
        "bioCADDIE raw → BEIR 변환은 fetch 성공 후 실제 raw 구조를 확인하여 구현. "
        "scripts/01-fetch-biocaddie.sh 가 성공해야 본 함수 작성 가능."
    )


def verify_counts(corpus_n: int, queries_n: int, qrels_n: int) -> None:
    """논문 보고치와 일치 검증.

    bax068 Table 1: corpus 794,992 / queries 15 / qrels 20,000+ (정확한 qrel 수는
    submission 별로 변동하나 일반적으로 20,000-30,000 범위).
    """
    if corpus_n != 794992:
        raise ValueError(
            f"bioCADDIE corpus count mismatch: got {corpus_n}, expected 794992. "
            "다운로드 무결성 확인 필요."
        )
    if queries_n != 15:
        raise ValueError(f"bioCADDIE queries count mismatch: got {queries_n}, expected 15.")
    if qrels_n < 20000:
        raise ValueError(
            f"bioCADDIE qrels count suspicious: got {qrels_n}, expected 20,000+. "
            "qrel 파일이 잘렸을 가능성."
        )
