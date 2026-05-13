# External APIs — Single Source of Truth

> 본 문서는 §0.1 절차에 따라 각 외부 API의 1차 출처에서 직접 확인된 사실만 기록한다.
> 검증되지 않은 항목은 `TODO(verify): <원인> — <확인할 URL>` 형식으로 남겨 두고, 코드에 임의 값을 박지 않는다.
> 모든 항목은 다음 4가지를 만족할 때만 코드에서 사용한다: (a) base URL 확정, (b) auth 방식 확정, (c) rate limit 확정, (d) 본 표에 등재.

| Last verified | 2026-05-06 |
|---|---|
| Verifier | Claude Code (initial bootstrap) |
| Re-verification SLA | 분기마다 1회 또는 외부 변경 알림 발생 시 즉시 |

---

## 1. NCBI E-utilities

| 항목 | 값 |
|---|---|
| 공식 문서 | https://www.ncbi.nlm.nih.gov/books/NBK25497/ |
| Base URL | `https://eutils.ncbi.nlm.nih.gov/entrez/eutils/` |
| Auth | `api_key` URL 파라미터 (선택). 미지정 시 IP 기반 limit 적용 |
| Rate limit (no key) | 3 requests/sec |
| Rate limit (with key) | 10 requests/sec (default; 더 높은 한도는 NCBI에 별도 요청) |
| 주요 엔드포인트 | `einfo.fcgi`, `esearch.fcgi`, `epost.fcgi`, `esummary.fcgi`, `efetch.fcgi`, `elink.fcgi`, `egquery.fcgi`, `espell.fcgi`, `ecitmatch.fcgi` |
| 인코딩 규칙 | 공백 → `+`, `"` → `%22`, `#` → `%23` |
| 확인 일자 | 2026-05-06 |

**구현 메모.** 환경변수 `NCBI_EUTILS_API_KEY` 가 있을 때만 10rps, 없으면 3rps로 클라이언트가 자체 토큰버킷 적용. 이 값을 코드에 하드코딩하지 말고 `apps/api/src/config.py` 에서 분리.

---

## 2. EBI ENA Portal API

| 항목 | 값 |
|---|---|
| 공식 문서 | https://www.ebi.ac.uk/ena/portal/api/ (Swagger UI는 JS 렌더링이지만 endpoint는 직접 호출로 검증 완료) |
| Base URL | `https://www.ebi.ac.uk/ena/portal/api/` |
| Auth | 공개 read 무인증 (curl 검증) |
| Rate limit | 공식 명시 없음. harvester는 보수적으로 1 rps 시작 + exponential backoff. 응답에 rate-limit 헤더 없음 |
| `GET /results?format=json` | dataclass 목록 (검증된 16개): `analysis`, `assembly`, `coding`, `noncoding`, `sequence`, `read_experiment`, `read_run`, `sample`, `analysis_study`, `read_study`, `study`, `taxon`, `tls_set`, `tsa_set`, `wgs_set` (record count 포함) |
| `GET /returnFields?result=<dataclass>&format=json` | 해당 dataclass 의 모든 column 정보 (description + type) |
| `GET /search?result=<dataclass>&query=<filter>&fields=<csv>&format=json\|tsv\|xml&limit=<N>` | 메인 검색. query 예시: `tax_eq(9606)`, `country="Korea"`, 시간 필터 등 |
| 응답 포맷 | `format=json` 권장. tsv/xml 도 지원 |
| 확인 일자 | 2026-05-06 (`curl` 으로 results / returnFields / search 직접 검증) |

**구현 메모.** harvester 의 `list_updated_since` 는 ENA 의 `last_updated` 컬럼을 query 에 포함 (e.g. `last_updated>=2026-01-01`). harvester 진입 시 `/results` 를 fetch 해서 dataclass 가 표에 등재되어 있는지 sanity check (검증되지 않은 dataclass 사용 시 fail-fast).

---

## 3. EBI BioStudies (ArrayExpress 후속) REST

| 항목 | 값 |
|---|---|
| 공식 문서 | https://www.ebi.ac.uk/biostudies/help (JS 렌더링) |
| Base URL | `https://www.ebi.ac.uk/biostudies/api/v1/` (curl 검증) |
| Auth | 공개 read 무인증 |
| Rate limit | 공식 명시 없음. 보수적으로 5 rps + exponential backoff |
| `GET /search?type=study&pageSize=<N>&page=<P>` | 검색. 응답: `{page, pageSize, totalHits, isTotalHitsExact, hits[]}` — 각 hit는 `accession`, `type`, `title`, `author`, `links`, `files`, `release_date`, `views`, `isPublic` (검증된 응답: 2026-05-06 기준 totalHits = 3,157,458 studies) |
| `GET /studies/{accession}` | 단일 study 메타데이터. 미존재 시 `{"errorMessage": "Study not found"}` + 404 |
| ArrayExpress | BioStudies 내 collection 으로 통합됨. accession prefix `E-` 또는 `S-EARC-` 등 (TODO(verify): 정확한 collection filter 파라미터) |
| 확인 일자 | 2026-05-06 (`/search` `/studies/{id}` curl 검증) |

**구현 메모.** harvester 는 `pageSize=100` (TODO(verify): max page size) 로 페이지네이션. ArrayExpress 만 필터링하려면 BioStudies query DSL 확인 필요 — 현재 검증 미완료. ArrayExpress 한정 수확이 필요해질 때 본 항목 갱신.

---

## 4. HCA Data Portal — Azul

| 항목 | 값 |
|---|---|
| 공식 문서 | https://data.humancellatlas.org/apis/api-documentation/data-browser-api |
| Base URL | `https://service.azul.data.humancellatlas.org/` |
| Service description | "REST web service for querying metadata associated with both experimental and analysis data" (공식 문구) |
| Auth | TODO(verify): public read 추정, 1차 출처에서 미확인 |
| Rate limit | TODO(verify) |
| 주요 엔드포인트 | TODO(verify): `/index/catalogs`, `/index/projects`, `/index/samples`, `/index/files`, `/repository/files/{uuid}` 가 일반적으로 사용됨. swagger 확인 필요 |
| 응답 특성 | "designed to provide response times that make it suitable for interactive use cases", "set of metadata properties that the Data Browser API exposes for sorting, filtering, and aggregation is limited" (공식 문구) |
| 확인 일자 | 2026-05-06 |

**Action required.** Week 11 HCA harvester 시작 전에 base URL에 직접 GET으로 OpenAPI/Swagger 스펙을 받아 갱신.

---

## 5. Europe PMC REST API

| 항목 | 값 |
|---|---|
| 공식 문서 | https://europepmc.org/RestfulWebService |
| Base URL | `https://www.ebi.ac.uk/europepmc/webservices/rest/` |
| Auth | 미요구 (public API) |
| Rate limit | TODO(verify): 공식 페이지에 명시 없음. 보수적으로 5 rps 시작, 429/5xx에 exponential backoff |
| 주요 엔드포인트 | `search` (예: `?query=p53`), `fields` |
| 추가 자원 | "Articles RESTful API", "Reference lists for more than 19.4 million publications" (공식 문구) |
| 확인 일자 | 2026-05-06 |

---

## 6. OLS4 (Ontology Lookup Service v4)

| 항목 | 값 |
|---|---|
| 공식 문서 | https://www.ebi.ac.uk/ols4/help (JS 렌더링) |
| API root | `http://www.ebi.ac.uk/ols4/api` (HATEOAS root) |
| Auth | TODO(verify): public read 추정 |
| Rate limit | TODO(verify) |
| 주요 엔드포인트 (root에서 확인됨) | `ontologies`, `terms`, `individuals`, `properties`, `profile` |
| 검색/자동완성 | TODO(verify): `search`, `suggest`, `select` 등이 OLS3에서 제공되었으나 OLS4에서의 정확한 경로 1차 출처 확인 필요 |
| 확인 일자 | 2026-05-06 |

**구현 메모.** ontology 매핑은 `oaklib`을 1차 어댑터로 사용 (§7 참조). OLS4 직접 호출은 fallback 또는 `oaklib`이 지원하지 않는 자동완성에만 사용.

---

## 7. OpenAlex API

| 항목 | 값 |
|---|---|
| 공식 문서 | https://developers.openalex.org/ (구 `docs.openalex.org`는 301 redirect) |
| Base URL | `https://api.openalex.org` |
| 7개 핵심 entity | `works`, `authors`, `sources`, `institutions`, `topics`, `publishers`, `funders` (외 `keywords`, `autocomplete`) |
| 가격 모델 (2026-05-06 검증) | **Pay-per-call 크레딧**. 응답 헤더에 명시:<br>`x-ratelimit-cost-usd: 0.0001` (call당)<br>`x-ratelimit-limit-usd: 1` (일일 free)<br>`x-ratelimit-limit: 10000` (일일 free 호출 = $1 / $0.0001) |
| Auth | `api_key=<KEY>` URL 파라미터. 키는 https://openalex.org/settings/api 에서 무료 발급. 키 없이도 동일 한도 적용됨이 확인됨 (mailto 만 사용해도 free $1/day 사용 가능 — 단 누적 사용 추적은 IP 기반) |
| Polite pool (mailto) | `mailto=<email>` URL 파라미터 — 본 프로젝트는 `teamclaudeihojin@gmail.com` 사용. 응답 정상 (curl 검증). 신규 모델에서 mailto 가 별도 풀을 만들지 않으나 **요청자 식별 의무로 계속 권장됨** |
| 응답 헤더 (모니터링) | `x-ratelimit-remaining`, `x-ratelimit-remaining-usd`, `x-ratelimit-reset` (sec until reset). harvester 가 이를 읽어 throttle |
| 핵심 원칙 (인용) | "Names are ambiguous. IDs are not." (entity ID 로 필터링 권장) |
| 확인 일자 | 2026-05-06 (`curl -I api.openalex.org/works?mailto=...` 헤더 직접 확인) |

**구현 메모.** v1에서 OpenAlex는 quality score 의 `citation_count` 추출에만 사용. 일일 10,000 호출이면 부분 sync 가능. 전수 sync 가 필요해지면 **유료 plan 또는 OpenAlex snapshot (S3 dump) 사용**으로 전환 — 그 시점에 본 항목 갱신.

---

## 8. GDC (Genomic Data Commons) API

| 항목 | 값 |
|---|---|
| 공식 문서 | https://docs.gdc.cancer.gov/API/Users_Guide/Getting_Started/ |
| Base URL (latest) | `https://api.gdc.cancer.gov/<endpoint>` |
| Base URL (versioned) | `https://api.gdc.cancer.gov/<version>/<endpoint>` |
| Auth | Open access는 무인증. **Controlled-access 다운로드와 모든 submission**은 토큰 필요. `X-Auth-Token` 헤더로 전송. 토큰은 GDC Data Portal / Submission Portal에서 발급 |
| Rate limit | TODO(verify): 공식 문서 본 페이지에 명시 없음 |
| 주요 엔드포인트 | `cases`, `files`, `projects`, `data`, `status`, `annotations`, `manifest`, `slicing`, `submission` |
| 확인 일자 | 2026-05-06 |

**구현 메모.** v1에서는 **open-access metadata만** 인덱싱. controlled-access 토큰을 서비스가 보유하지 않는다 (§9.3, §12.1 L0 원칙).

---

## 9. Python 의존성 — 검증된 최신 안정 버전

| 패키지 | 최신 버전 | 릴리스 | Python 요구 | 출처 |
|---|---|---|---|---|
| `pysradb` | 2.5.1 | 2025-10-20 | ≥3.9 | https://pypi.org/project/pysradb/ |
| `oaklib` | 0.6.23 | 2025-06-05 | ≥3.9, <4 | https://pypi.org/project/oaklib/ |
| `qdrant-client` | 1.17.1 | 2026-03-13 | ≥3.10 | https://pypi.org/project/qdrant-client/ |
| `opensearch-py` | 3.2.0 | 2026-04-27 | ≥3.10 | https://pypi.org/project/opensearch-py/ |

**Server compatibility (검증 완료, 2026-05-06 docker-compose 기동):**
- `qdrant-client 1.17.1` ↔ **Qdrant server 1.17.1** (`qdrant/qdrant:latest` tag). 동일 버전 매칭. GET / 응답 헤더로 직접 확인.
- `opensearch-py 3.2.0` ↔ **OpenSearch server 2.19.5** (`opensearchproject/opensearch:2` tag). client 3.x ↔ server 2.x 정상 동작. lucene 9.12.3.
- `postgres:16-bookworm` ↔ alembic offline SQL 생성 + asyncpg upgrade head 정상 적용.

---

## 10. 의도적으로 본 표에서 제외된 항목

| 항목 | 사유 |
|---|---|
| Anthropic / OpenAI Batch API | 본 프로젝트는 §13.4 ADR에 따라 **로컬 LLM(Ollama)** 우선. 외부 LLM 호출 0건이 v1 기본값. 외부 LLM 옵션이 활성화될 때 본 표 §11에 추가. |
| dbGaP / EGA | 메타데이터만 처리하더라도 controlled-access 정책이 까다로우므로 v1 범위 제외 (§9.3) |
| Recount3 / ARCHS4 / GREIN | 카탈로그 재가공 서비스 — 본 프로젝트의 차별화 포인트(§1.2)와 중복. 인덱스 비교용 reference로만 사용 |

---

## 11. 갱신 절차

1. 본 파일을 수정하는 PR은 **확인 일자**를 새로 적고, 변경 사항을 ADR(`docs/decisions/`)에 cross-reference한다.
2. `TODO(verify):` 가 남아 있는 API는 해당 source의 harvester PR이 머지되기 전에 모두 해소되어야 한다 (CI에서 grep으로 확인).
3. Rate limit 변경 시 `apps/api/src/config.py` 와 harvester 토큰버킷 설정을 동시 갱신한다.
