# Eval Harness

마스터 플랜 §6.4 의 평가 데이터셋과 지표를 관리한다.

- `labeled_queries.jsonl` — 손으로 라벨링한 query → relevant dataset 쌍 200건 (목표).
- 지표: nDCG@10, Recall@50, MRR.
- CI 회귀: ranking 코드 변경 PR 에서 자동 실행.
- Prompt injection 회귀 (`injection_payloads.jsonl`) — 50건 (ADR 0002 T8).

본 패키지는 Week 3 부터 라벨링이 시작되며, Week 8 에 ranking PR 의 CI gate 로 통합된다.
