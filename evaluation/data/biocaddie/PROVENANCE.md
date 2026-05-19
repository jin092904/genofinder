# bioCADDIE 2016 Corpus — Provenance Record

본 파일은 bioCADDIE 2016 corpus 다운로드의 정확한 출처 / 시각 / 무결성 기록.
**fetch 실행 시 본 파일을 *실 데이터로* 채워야 함.** 추측 / 합성 / 임의 기재 금지.

## Status

- [ ] fetch 시도 완료
- [ ] fetch 성공
- [ ] BEIR format 변환 완료
- [ ] verify_counts 통과 (corpus=794,992 / queries=15 / qrels≥20,000)

## Reference paper

- Cohen T, Roberts K, et al. *DataMed — an open source discovery index for finding biomedical datasets.*
  Database (Oxford), 2017. doi:10.1093/database/bax061
- bioCADDIE Dataset Retrieval Challenge overview: doi:10.1093/database/bax068

## Fetch attempt log

| 시각 (UTC+9) | URL | HTTP code | content-length | SHA256 | 결과 |
|---|---|---|---|---|---|
| (TBD) | https://biocaddie.org/benchmark-data | — | — | — | not attempted |
| (TBD) | (paper supplementary) | — | — | — | not attempted |
| (TBD) | (저자 GitHub) | — | — | — | not attempted |

## License

bioCADDIE corpus 의 정확한 라이선스는 fetch 시 README / LICENSE 파일 확인.
- 일반 추정: CC-BY-NC (학술 사용 가능, 상업적 사용 제한, 출처 표시 필수)
- 본 repo 에 corpus 본체 **commit 금지**. fetch script 만 commit.

## 변환 결과 (BEIR format)

- corpus.jsonl rows: (TBD)
- queries.jsonl rows: (TBD)
- qrels/test.tsv rows: (TBD)

## PHI 검출

- [ ] 이름 패턴 (e.g. "patient John Doe") grep 결과: (TBD)
- [ ] MRN 패턴 (e.g. /\\bMRN[-:]?\\s*\\d{6,}\\b/) grep 결과: (TBD)
- [ ] 발견 시 abort + 사용자 보고.

## 만약 fetch 실패한다면

다음 옵션 중 하나 선택 (사용자 confirm 필수):
1. bioCADDIE 평가 자체를 skip — EVALUATION_REPORT.md 에 사유 명시
2. 별도 미러 / archive 후보 추적 (사용자가 URL 제시)
3. 다른 표준 dataset retrieval benchmark 로 대체 (예: BEIR `nfcorpus`)
