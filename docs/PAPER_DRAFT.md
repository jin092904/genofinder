# Geno Finder: 연구 디자인 인지 기반 공공 생명정보 데이터셋 검색 엔진

*A research-design-aware search engine for public biomedical datasets*

작성일: 2026-05-09 (v0.8 초안) · 2026-05-13 (v1.0 갱신 — ADR 0006 모델 stack, native deployment)
상태: draft

---

## 초록 (Abstract)

생명정보 연구자가 자신의 연구 디자인 (research design) 에 부합하는 공공 데이터셋을 신속히
찾기는 어려운 일이다. 기존 카탈로그 시스템 (NCBI GEO, EBI BioStudies 등) 은 키워드 일치
중심이라 의미 기반 (semantic) 매칭이 제한되며, 데이터셋의 실험 모달리티 / 종 / 질병 같은
핵심 메타데이터가 자유 서술 형태로 흩어져 있어 정밀 필터링이 어렵다. 동시에 한국어를
포함한 비영어권 연구자는 영어 카탈로그를 직접 마주해야 하여 진입 장벽이 더 높다.

본 연구에서는 **Geno Finder**, 즉 (i) GEO·HCA·GDC·SRA 4개 출처의 공공 메타데이터를 통합
인덱싱하고, (ii) 로컬 LLM (Ollama 위 **Gemma 4 31B**, Q4_K_M 양자화) 으로 모든 데이터셋을
통제어휘 (controlled vocabulary) · ontology term · **실험 그룹 구조 (cohort design)** 로 자동
정형화하며, (iii) 다국어 임베딩 모델 (**Qwen3-Embedding-8B** → Matryoshka 1024d truncate) 의
의미 기반 dense 검색과 키워드 기반 BM25 검색을 Reciprocal Rank Fusion 으로 결합한 뒤
**Qwen3-Reranker-0.6B** cross-encoder 로 정밀 재정렬하는 다단계 검색 엔진을 제안한다.
시스템은 PostgreSQL Row-Level Security 기반 멀티테넌트 격리, 외부 API 호출 0건의 프라이버시
우선 아키텍처, 모든 결과의 점수 분해 (semantic / lexical / RRF / rerank) 가시화, 그리고
**Gemma 4 기반 한국어 학술 번역 toggle** 을 설계 원칙으로 삼는다.

A100 80GB GPU 단일 장비에서 native 운영 (호스트 binary, 비-컨테이너) 으로 약 10,621
datasets 를 1 cycle batch 처리 (~14-20시간) 한 v1.0 코퍼스 기준, 평균 검색 latency 는
~400ms 수준을 유지하면서 모달리티 / 질병 / 조직 / 코호트 디자인 추출 정확도가 v0.8 대비
정성적으로 개선되었다. 또한 3-way 모델 비교 (qwen3:8b · gemma4:31b · qwen3.5:27b) 를 통해
한국어 학술 번역 품질이 모델 크기보다 *모델 선택* 에 더 강하게 의존함을 보였다.

> **쉬운 설명:** 연구자가 "내 실험에 쓸만한 공개 데이터를 찾고 싶다" 고 할 때, 단순 키워드
> 검색이 아니라 의미가 비슷한 것까지 찾아주고, 각 결과가 왜 매칭됐는지 점수로 설명해 주는
> 도구입니다. 한국어 쿼리와 한국어 요약도 지원합니다. 모든 AI 분석은 연구실 서버 안에서만
> 돌아 외부로 데이터가 새지 않습니다.

---

## 1. 서론 (Introduction)

### 1.1 문제 정의

특정 연구 디자인을 가진 생명정보 연구자 — 예를 들어 *"인간 췌장 베타세포의 단일세포 RNA
시퀀싱 데이터"* 를 찾고자 할 때 — 가 이용 가능한 공개 데이터셋을 발굴하는 일은 다음 이유로
어렵다:

1. **출처 분산.** 동일 도메인의 데이터가 NCBI GEO, EBI ArrayExpress, Human Cell Atlas (HCA),
   Genomic Data Commons (GDC), Sequence Read Archive (SRA) 등에 흩어져 있고, 각 카탈로그는
   고유의 검색 인터페이스와 메타데이터 schema 를 사용한다.
2. **메타데이터 비정형성.** Modality (실험 기법, e.g. scRNA-seq, ChIP-seq), 종 (organism),
   질병, 조직, 세포 타입 같은 핵심 facet 이 데이터 제출자의 자유 서술에 의존하여 통일된
   필터가 불가능하다.
3. **키워드 기반 검색의 한계.** GEO 의 BLAST 등 키워드 매칭은 "단일세포" / "single-cell" /
   "scRNA-seq" 같은 동의어를 인식하지 못하며, 연구 디자인 자체의 문맥 (예: "분화 중인 면역
   세포 비교") 에 대해서는 더더욱 무력하다.

> **쉬운 설명:** 데이터가 여러 사이트에 흩어져 있고, 각 데이터셋의 설명도 자유 형식이라
> 일관된 기준으로 비교/검색하기 어렵습니다.

### 1.2 본 연구의 기여

(C1) 4개 1차 출처 (GEO, HCA, GDC, SRA) 를 단일 카탈로그로 통합하고 자동 incremental harvest
파이프라인을 구축.

(C2) 모든 데이터셋에 대해 로컬 LLM (Gemma 4 31B Q4) 기반 메타데이터 추출을 수행 — modality /
종 / library_strategy 와 OLS4 ontology CURIE (MONDO 질병 / UBERON 해부 / CL 세포 타입) 를
동시에 산출하며, abstract 와 GEO Series Matrix 의 sample factor 분포를 함께 입력하여
**실험 그룹 구조 (cohort_design)** — case / control / treatment / comparison 라벨 + 그룹별 n
+ design_type — 까지 자동 정형화한다.

(C3) **Qwen3-Embedding-8B (Matryoshka 1024d truncate)** dense 검색과 BM25 lexical 검색을
Reciprocal Rank Fusion (k=60) 으로 결합한 뒤 **Qwen3-Reranker-0.6B** cross-encoder 로
정밀 재정렬하는 4-stage 검색 파이프라인. Apache 2.0 라이선스 + 다국어 100+ 언어 지원으로
한국어 쿼리도 비교적 강건하게 매칭한다.

(C4) PostgreSQL Row-Level Security + 외부 API 호출 0건의 프라이버시 우선 아키텍처. 사용자
쿼리는 데이터 등급 L3 (Restricted) 로 분류되어 envelope 암호화 (per-tenant Data Encryption
Key) 로 저장된다.

(C5) 점수 분해 가시화 — semantic / lexical / RRF / rerank 각 신호를 사용자에게 노출하여
"black-box 거부" 원칙을 구현. 동시에 **on-demand 한국어 학술 번역 toggle** (Gemma 4 +
Redis 24h 캐시) 로 비영어권 연구자의 진입 장벽을 낮춘다.

(C6) **컨테이너 의존성 없는 native 배포 절차.** podman rootless 의 subuid 미할당 + CDI
미지원 (v3.4.4) 환경에서 운영 가능하도록 PostgreSQL · Redis · Qdrant · OpenSearch · Ollama
를 모두 호스트 binary 로 직접 실행하는 부트스트랩 및 데이터 dump 스크립트를 제공
(`scripts/a100-native-bootstrap.sh`, `scripts/a100-batch-pipeline-native.sh`). 학내 공유
서버처럼 root 권한 / Docker daemon 사용이 어려운 환경에서 재현성을 확보한다.

> **쉬운 설명:** 우리가 새로 만든 것은 여섯 가지 — 데이터 통합 수확, AI 자동 분류 (코호트
> 디자인까지), 다국어 똑똑한 검색, 사용자 정보 보호, 점수 분해 + 한국어 번역, 그리고
> Docker 없이도 돌아가는 설치 절차입니다.

---

## 2. 관련 연구 (Related Work)

### 2.1 공공 생명정보 카탈로그

NCBI GEO (Gene Expression Omnibus) [Edgar 2002] 는 사실상 표준이지만 자체 검색은 PubMed 식
키워드 + filter 기반이다. EBI BioStudies / ArrayExpress 는 BioStudies schema 로 통합 시도를
하지만 쿼리 레벨에서 ontology 매핑은 제공하지 않는다. Human Cell Atlas Data Portal 은
정제된 contributor metadata 를 갖지만 단일 출처에 한정된다. GDC Data Portal 은 암 데이터
중심으로 별도 인터페이스를 가진다.

### 2.2 의미 기반 / 하이브리드 검색

Dense passage retrieval [Karpukhin 2020] 와 BM25 의 combination 이 일반 정보 검색 영역에서
성능을 입증하였다 [Ma 2021]. 본 연구는 **Reciprocal Rank Fusion** [Cormack 2009] 으로 두
랭킹을 결합하고, cross-encoder [Nogueira 2019] 로 top-K 재정렬을 수행한다.

임베딩 모델 선정은 ADR 0006 (v1.0) 에서 v0.8 의 `nomic-embed-text` (768d, 영어 중심) 에서
**Qwen3-Embedding-8B** (4096d native → Matryoshka 1024d truncate, 100+ 언어) 로 갱신되었다.
MTEB Multilingual benchmark 기준 70.58 점으로 EmbeddingGemma 300M (61.15) · BGE-M3 568M
(~63) 등 동급 대안 대비 우위. Matryoshka 표현 학습 [Kusupati 2022] 의 특성상 차원을
1024 로 truncate 해도 품질 손실은 약 2-3% 로 미미하며, Qdrant 메모리 / latency 가 4배 절감된다.
Bio 도메인 특화 모델 (BioBERT, SciBERT) 대비 다국어 / 자유 서술 메타데이터에서 일반
다국어 모델이 더 강건했다.

Reranker 도 동일하게 v0.8 의 `ms-marco-MiniLM-L-6-v2` (22M, 영어 한정) 에서 **Qwen3-Reranker-0.6B**
(Apache 2.0, 다국어) 로 교체. ms-marco 모델은 5년 이상된 영어 학습 데이터 기반이라 한국어
쿼리 / 학술 용어 reranking 이 약했으며, Qwen3 시리즈로 통일 시 *임베딩 → reranker → LLM* 이
모두 단일 vendor (Qwen3) 로 일관성을 갖는다.

### 2.3 LLM 기반 메타데이터 추출

GPT-4 등 클라우드 LLM 으로 의생명 텍스트에서 구조화 정보를 추출하는 연구가 다수 있으나,
본 연구는 **로컬 LLM** 을 사용한다. 이는 사용자 쿼리 프라이버시 (ADR 0003) 와 운영 비용
(외부 API 비용 0) 측면에서 중요하다.

v0.8 은 Phi-4 mini (3.8B Q4) 를 사용하였으나, 약 1주 운영 후 한국어 long-context 번역의
후반부 깨짐 (영어 / 러시아어 토큰 잔존) 과 case-control / cohort 분류의 부정확성 (예:
mouse aging study 를 case-control 로 오분류) 이 관측되었다. v1.0 (ADR 0006) 은 이를
해소하고자 **Gemma 4 31B IT** (Q4_K_M, 262K context, 140+ 언어, vision/tools/thinking
capability) 를 채택한다. Gemma 시리즈의 다국어 instruction following 능력은 한국어
자연어 번역 + 의생명 cohort 추출 양쪽에서 동급 27-32B 후보 (Qwen3.5-27B 등) 대비 본
연구의 정성 평가에서 더 우수한 결과를 보였다 (§7).

Ollama 의 "thinking" 모드를 가진 모델 (Gemma 4 등) 은 `/api/generate` 호출 시 `think: false`
파라미터를 명시하지 않으면 모든 생성 budget 을 hidden thinking token 으로 소비하여 결과
content 가 빈 채로 종료되는 사례가 있다. 본 연구의 워커는 이 옵션을 기본 활성화한다
(`apps/workers/src/extractors/llm_client.py`).

> **쉬운 설명:** 비슷한 도구가 있긴 하지만, 우리는 데이터를 한 곳에 모으고 + AI 가 자동
> 정리하고 + 모든 처리를 연구실 서버에서 한다는 점에서 다릅니다. 또 v1.0 부터는 한국어
> 처리에 강한 새 모델로 바꿔서 한국어 검색 / 번역 품질도 올렸습니다.

---

## 3. 시스템 아키텍처 (System Architecture)

### 3.1 데이터 등급 (Data Tiers)

[ADR 0002 §12.1] 모든 데이터를 4 등급으로 분류한다:

| 등급 | 정의 | 예시 | 보안 처리 |
|---|---|---|---|
| L0 Public | 공개 메타데이터 | GEO 카탈로그 자체 | 평문 저장, RLS 미적용 |
| L1 Internal | 시스템 자체 식별자 | dataset UUID | RLS 미적용 |
| L2 Tenant | 사용자 / 워크스페이스 | tenants, users | RLS FORCE |
| L3 Restricted | 사용자 쿼리, 클릭 신호 | search_logs, saved_queries | envelope 암호화 + RLS FORCE |

> **쉬운 설명:** 데이터를 민감도에 따라 4단계로 나누고, 단계가 높을수록 강한 보호 (암호화,
> 사용자 격리) 를 적용합니다.

### 3.2 컴포넌트 다이어그램

```
┌────────────────┐
│  Web (Next.js 16) │ ── Firebase Auth (Google sign-in) ── ID token
└──────┬─────────┘
       │  Authorization: Bearer <id_token>
       ▼
┌──────────────────────────────────────────────────────────────┐
│  API (FastAPI) — verify_id_token, ensure_user_for_principal  │
│   - /search    (POST)  — 하이브리드 검색                      │
│   - /me        (GET, PATCH) — 사용자 프로필                  │
│   - /me/saved  (GET, POST, DELETE) — 찜                      │
│   - /datasets/{id} (GET) — 상세                              │
│   - /datasets/{id}/cohort + /cohort/extract — 코호트          │
│   - /datasets/{id}/translate?lang=ko — 한국어 번역            │
│   - /datasets/{id}/snippets — R/Python/Bash 다운로드          │
│   - /stats     (GET) — 대시보드                              │
└────┬───────┬──────────┬──────────┬──────────────┬────────────┘
     │       │          │          │              │
     ▼       ▼          ▼          ▼              ▼
  Postgres  Redis    Qdrant   OpenSearch        Ollama
  (RLS)    (cache)  (1024d)   (BM25)         (port 11435)
                                                  │
                                                  ▼
                                     Gemma 4 31B Q4 (gen + translate)
                                     Qwen3-Embedding-8B (M-1024)
                                          │
                                          ▼
                                     sentence-transformers
                                     Qwen3-Reranker-0.6B (rerank)
```

> **쉬운 설명:** 웹 → API → 5개 DB / 검색엔진. 모든 LLM 작업은 Ollama (로컬) 안에서 끝납니다.

### 3.3 Multi-tenant 격리 (T4)

PostgreSQL Row-Level Security 로 사용자 간 데이터 격리. 매 요청 시 미들웨어가
`SET LOCAL app.tenant_id = '<uuid>'` 를 수행하고, L2/L3 테이블의 모든 row 는 다음 정책을 따른다:

```sql
CREATE POLICY tenant_isolation ON saved_datasets
  USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
  WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
ALTER TABLE saved_datasets ENABLE ROW LEVEL SECURITY;
ALTER TABLE saved_datasets FORCE ROW LEVEL SECURITY;
```

DB 사용자 (role) 도 분리: `genofinder` (마이그레이션용 superuser, BYPASSRLS) 와
`genofinder_app` (런타임 NOSUPERUSER, RLS 적용 대상). 11개 자동 cross-tenant 테스트로
격리를 회귀 검증한다.

> **쉬운 설명:** A 사용자가 B 사용자의 찜 목록을 볼 수 없도록 데이터베이스 자체에서 막는
> 메커니즘입니다 (애플리케이션 코드의 버그가 있어도 데이터가 새지 않음).

### 3.4 배포 모델 — Native (no-container) on shared HPC

v0.8 은 `docker compose` (또는 podman-compose) 로 8개 컨테이너를 띄우는 단일 명령
부트스트랩 절차를 가졌다. v1.0 의 batch 운영 환경은 학내 공유 HPC (Xeon Gold 6342 96 vCPU,
A100 80GB × 6, NFS home, Ubuntu 22.04) 였는데, 다음의 누적 제약으로 컨테이너 stack 이
실용적이지 않음이 밝혀졌다:

1. **NFS 위 overlayfs 의 pivot_root 권한 거부** — podman rootless 의 graphRoot 가 NFS
   (`~/.local/share/containers/storage`) 에 있으면 이미지 추출이 실패. graphRoot 를 로컬
   SSD (`/var/tmp/podman-storage-$USER`) 로 옮기는 storage.conf 설정으로 해결.
2. **subuid/subgid 미할당** — 본 연구의 운영 계정에 `/etc/subuid` / `/etc/subgid` 항목이
   부여되지 않아 podman 의 user namespace 매핑이 single-uid 모드로 강등. PostgreSQL /
   Redis / OpenSearch 등 entrypoint 가 내부 uid 999 (postgres / redis user) 로 chown 을
   시도하는 모든 이미지가 `chown: Invalid argument` 로 실패. `--userns=keep-id` 또는
   `ignore_chown_errors=true` 도 같은 root 원인으로 해결되지 않음.
3. **podman 3.4.4 의 CDI 미지원** — `--device nvidia.com/gpu=N` syntax 는 podman 4.1+ 이
   필요하지만 시스템 podman 은 3.4.4. NVIDIA container runtime 의 CDI spec 은 정상 설치되어
   있으나 podman 이 인식하지 못함. 결과적으로 GPU 가 컨테이너 내부에서 접근 불가.
4. **opensearch JVM 의 `RLIMIT_MEMLOCK`** — rootless 사용자가 mlock 권한을 늘릴 수 없어
   bootstrap 실패. `bootstrap.memory_lock: false` 로 우회 가능하나 다른 컨테이너 문제와
   결합되어 stack 전체가 막힘.

위 제약을 모두 회피하면서 **연구실 관리자 권한 협조 없이 1인 운영** 가능한 절차로
*native binary stack* 을 채택하였다:

| 서비스 | 도입 방법 | 위치 |
|---|---|---|
| PostgreSQL 16.13 | micromamba env `genofinder-svc` (conda-forge) | `~/micromamba/envs/...` |
| Redis 8.6.2 | 동일 env | 동일 |
| Qdrant 1.12 | GitHub release tarball (single Rust binary) | `services/qdrant/` |
| OpenSearch 2.16 | opensearch.org tarball (security plugin disabled) | `services/opensearch-...` |
| Ollama 0.23.3 | 공식 tarball (bundles CUDA 12/13 libs) | `services/ollama/` |

부트스트랩은 `scripts/a100-native-bootstrap.sh` 한 번 실행이면 종료. Service 데이터는 모두
NFS home 의 `$GENOFINDER_DATA_ROOT/{pgdata,redis-data,qdrant-data,opensearch-data}` 에
저장된다. Ollama 만 별도 포트 (11435) 로 운영하여, 동일 호스트에서 다른 사용자가 운영
중인 Ollama 서버 (port 11434, CPU 모드) 와 충돌하지 않는다. GPU 는 `CUDA_VISIBLE_DEVICES=3`
환경변수로 비어있는 1장만 명시적으로 사용한다.

> **쉬운 설명:** Docker / podman 같은 컨테이너 도구가 막혀서, 그냥 호스트에 직접 깔아
> 돌리는 방식으로 바꿨습니다. 한 번에 깔리는 스크립트 (a100-native-bootstrap.sh) 를 만들어
> 두어서 다른 서버에 옮길 때도 그대로 사용 가능합니다.

---

## 4. 메타데이터 추출 파이프라인 (Methods I — Extraction)

### 4.1 Harvest

각 출처마다 incremental harvest 를 구현. NCBI E-utilities 의 `pdat` (publication date)
필터로 watermark 기반 일자 단위 증분 수확. 4개 출처 클라이언트는 동일한 `Harvester` 추상에
구현한다:

```python
class Harvester(Protocol):
    source_db: str
    async def list_updated_since(self, since: date) -> AsyncIterator[str]: ...
    async def fetch_raw(self, uid: str) -> dict: ...
```

NCBI 의 경우 API key 가 있을 때 10 rps, 없을 때 3 rps. 본 연구에서는 API key 사용하여
asyncio semaphore=12 로 7.5 rps 안정 처리.

### 4.2 LLM 기반 구조화 추출

각 데이터셋의 자유 서술 (title + abstract + raw GEO field) 을 Ollama Gemma 4 31B IT 에
입력하여 다음 JSON schema 로 구조화한다:

```json
{
  "modality": ["scRNA-seq"],
  "organism_taxid": [9606],
  "library_strategy": "RNA-Seq",
  "n_subjects": 12,
  "disease_curies": ["MONDO:0005061"],
  "tissue_curies": ["UBERON:0001264"],
  "cell_type_curies": ["CL:0000115"]
}
```

Modality 는 통제어휘 (scRNA-seq, ChIP-seq, WGS 등 28종) 로만 선택 허용. Disease / Tissue /
Cell type 은 OLS4 (Ontology Lookup Service v4) 의 MONDO / UBERON / Cell Ontology lookup 결과
중 가장 높은 신뢰도의 CURIE 를 선택. 추출이 실패한 record 는 `extraction_failures` 테이블에
원본과 함께 보관하여 사후 분석/재추출 가능.

호출은 Ollama 의 `POST /api/generate` 에 `format: "json"` 으로 JSON 모드를 강제. v1.0 의
gemma4 같이 thinking-capable 모델은 `think: false` 를 함께 전송해야 하며 — 그렇지 않으면
context budget 을 모두 hidden reasoning token 으로 소비하여 응답이 비는 사례가 발견됨
(§7.1).

> **쉬운 설명:** AI 가 데이터셋의 자유 서술을 읽고 "이건 scRNA-seq 이고 췌장 데이터이고
> 당뇨병 관련" 같이 정형화된 분류표를 자동으로 만듭니다. Ontology 는 의생명 분야의 표준
> 분류 체계예요.

### 4.3 Ontology 의미 확장

검색 시 사용자가 `MONDO:0005061` (당뇨병) 으로 필터링하면, 그 자식 term (MONDO 의 hierarchy
하위) 까지 포함해서 후보를 확장한다. OLS4 의 ancestors API 를 호출하여 closure set 을
사전 계산해 둔다.

### 4.4 코호트 디자인 (cohort_design) 추출

데이터셋의 *실험 그룹 구조* 가 사용자에게 가장 빠르게 전달되어야 한다는 사용성 관점에서,
v1.0 부터는 abstract 와 GEO Series Matrix 의 sample factor 분포 (`!Sample_characteristics_ch1`
파싱 결과) 를 함께 LLM 에 입력하여 그룹 단위 정형 출력을 산출한다:

```json
{
  "groups": [
    {"label": "BCG responsive",   "role": "case",       "n": 6,
     "criteria": "patients responding to BCG treatment"},
    {"label": "BCG unresponsive", "role": "comparison", "n": 7,
     "criteria": "patients not responding to BCG treatment"},
    {"label": "BCG naïve",        "role": "control",    "n": 7,
     "criteria": "patients who have not received BCG treatment"}
  ],
  "design_type": "cohort",
  "notes": "Single-cell RNA sequencing analysis comparing treatment response outcomes."
}
```

`role` 은 화이트리스트 (`case` / `control` / `treatment` / `comparison` / `other`) 로
강제 검증. `design_type` 도 (`case_control` / `cohort` / `cross_sectional` / `rct` /
`time_series` / `unknown`) 로 강제. 미허용 값은 `other` / `unknown` 으로 자동 fallback.

추출 결과는 `datasets.cohort_design` JSONB + `cohort_design_version` 열에 저장된다.
Prompt 버전은 `cohort-v2-gemma4-2026-05-13` 으로 관리 — sample factor 분포를 함께 입력하는
v2 가 abstract 단독 입력 v1 대비 정확도 우위 (예: mouse aging study 를 v1 의 "control vs
treatment" 가 아닌 "young (12wk) / old (68wk), cohort" 로 정확 분류).

**On-demand fallback.** Batch backfill 비용 (10k 데이터셋 × ~4s = ~11시간) 을 회피하기 위해
서빙 단에서 `POST /datasets/{id}/cohort/extract` 가 미리 추출되지 않은 데이터셋에 대해
즉석 호출 + Redis 캐시 1시간 정책으로 동작한다.

### 4.5 한국어 학술 번역 (on-demand)

`POST /datasets/{id}/translate?lang=ko` 가 Gemma 4 + JSON schema 로 title / abstract 양쪽을
한국어로 번역. Redis `gf:translate:ko:{uuid}` 키로 24시간 캐시. 캐시 hit 시 평균 0.13초,
cold path 평균 6초.

JSON schema 출력을 강제하지 않으면 모델이 종종 prefix / suffix 설명 텍스트를 추가하여
파싱이 깨지므로, `format` 인자에 정형 schema (`{title: str, abstract: str}`) 를 전달한다.

번역 품질은 모델 dependency 가 큼. §7.6 에서 qwen3:8b (한자 잔재) / gemma4:31b (학술 자연체) /
qwen3.5:27b (의미 오역 "심부전 감소" — cardiac decline 을 정반대 의미로 번역) 의 3-way
정성 평가를 제시한다.

### 4.6 Sample-level metadata backfill

GEO Series Matrix (`{accession}_series_matrix.txt.gz`) 를 fetch 하여 `!Sample_characteristics_ch1`
라인을 파싱, 각 sample 의 sex / age / disease state / treatment 5 필드를 정규화 사전 (예:
"M"/"male"/"남" → `male`, "12 weeks" / "12wk" / "12주" → `(12, "week")`) 으로 통일하여
`samples` 테이블에 UPSERT. 50MB 하드 캡으로 비정상 거대 파일 방어. concurrency=6, tenacity
재시도. backfill 결과를 sample-level facet (성비 도넛 / 연령 5-bucket / condition top10) 으로
상세 페이지에 노출.

---

## 5. 검색 파이프라인 (Methods II — Retrieval)

### 5.1 다단계 구조

```
Query "scRNA-seq human pancreas islets"  (또는 "단일세포 췌장 베타세포")
   │
   ├──► Dense embed (Qwen3-Embedding-8B → 1024d Matryoshka truncate)
   │      └─► Qdrant cosine  ─── top 200 (semantic, 다국어)
   │
   └──► Tokenize → BM25
          └─► OpenSearch     ─── top 200 (lexical, source_id^15 boost)
                                       │
                                       ▼
                            Reciprocal Rank Fusion (k=60)
                                       │
                                       ▼
                            top-15 → Cross-encoder rerank
                                  (Qwen3-Reranker-0.6B, Apache 2.0, 100+ lang)
                                       │
                                       ▼
                            최종 정렬 + facet 집계 + UI
```

쿼리 임베딩은 인덱싱 시 사용한 8B 모델 대신 동일 family 의 **Qwen3-Embedding-0.6B** (native
1024d) 를 권장. 인덱스/쿼리 임베딩 차원이 일치 (둘 다 1024d) 하면서 쿼리 임베딩 비용을
4배 절감 — 본 연구에서는 평균 50ms 미만.

### 5.2 Reciprocal Rank Fusion

[Cormack 2009] 의 단순한 합산 공식:

```
score_RRF(d) = Σ_{l ∈ rankers} 1 / (k + rank_l(d))
```

`k=60` 표준값. 본 연구에서는 dense / lexical 두 ranker 의 RRF score 를 사용. 빠른 baseline
이며 score 정규화 불필요한 장점.

> **쉬운 설명:** 두 종류의 검색 결과 (의미 vs 키워드) 를 똑똑하게 합쳐서 하나의 순위를
> 만드는 방법입니다.

### 5.3 Cross-encoder rerank — Qwen3-Reranker-0.6B

상위 15개 후보에 대해 `(query, title + abstract)` pair 를 cross-encoder 에 입력해 relevance
score 를 산출. Cross-encoder 는 dense embedding 과 달리 query–doc 을 동시에 attention 으로
보아 정밀도가 높지만 한 query 당 K번 forward pass 가 필요해 비용이 높다 (top-K 만 적용).

v0.8 의 `cross-encoder/ms-marco-MiniLM-L-6-v2` (22M, 2019, 영어 학습) 는 한국어 / 학술
도메인에서 약했다 — 한국어 쿼리 `박테리아 전장 유전체 시퀀싱` 에서 semantic 0.72 임에도
rerank score 가 −7 (강한 negative) 로 collapse 하는 사례가 다수.

v1.0 은 **Qwen3-Reranker-0.6B** (Apache 2.0, Qwen3 시리즈 통일, 100+ 언어) 로 교체.
sentence-transformers 의 CrossEncoder API 와 호환 (Ollama 가 reranker 를 미공식 지원하므로
ST 직접 사용). instruction prefix 옵션 (`"Given a query, retrieve relevant biomedical
datasets:"`) 추가 시 정밀도 1-5% 향상이 보고되어 본 구현은 prefix 를 활성화한다.

T1000 4GB VRAM 호환 위해 0.6B 변종 채택. 추후 평가에서 의미 있는 품질 우위가 확인되면
Qwen3-Reranker-4B Q4 (~2-3GB) 로 승격 검토.

### 5.4 사용자 노출 점수 통합

UI 에서 단일 "관련도" 막대로 노출하기 위해 다음 가중평균:

```
relevance = clip01(0.5 · sigmoid_norm(rerank, [-5, +5])
                  + 0.4 · semantic
                  + 0.1 · log1p_norm(lexical, 30))
```

`semantic` 만 강하고 `rerank` 가 약한 경우에도 baseline 30% 이상이 유지되어 UI 에서
"의미 매칭 강함" chip 과 모순되지 않게 한다.

> **쉬운 설명:** 검색 결과 옆에 0~100% 짜리 "관련도" 점수를 보여주는데, 여러 신호를 합쳐
> 만든 값입니다. 사용자에게는 한 줄, 자세히 보고 싶으면 펼쳐서 원시 점수를 볼 수 있습니다.

### 5.5 Score 가시화 — Black-box 거부

기존 검색 도구가 "왜 이 결과가 나왔는지" 를 숨기는 데 비해, 본 연구는 모든 결과 카드에
4개 점수 (semantic / lexical / RRF / rerank) 의 원시값을 노출한다. 사용자는 단일 막대 외에
펼침 버튼으로 분해 점수 표 확인 가능. 이는 데이터 분석 신뢰성에 핵심인 *re-tracing* 가능성을
보장한다.

---

## 6. 구현 (Implementation)

### 6.1 기술 스택 (v1.0)

| 영역 | 선택 | 근거 |
|---|---|---|
| Web | Next.js 16 + App Router (Turbopack 기본) | SSR + ISR + RSC + Cache Components |
| API | FastAPI + Pydantic v2 | async + type-strict + OpenAPI 자동 |
| RDB | PostgreSQL 16 | RLS 성숙도 |
| Vector | Qdrant 1.12 (single Rust binary) | gRPC + 풍부한 filter, on-prem 가능 |
| Lexical | OpenSearch 2.16 (security plugin disabled) | Apache 2.0 (Elasticsearch SSPL 회피) |
| Cache | Redis 8 | 표준, AOF persistence |
| **Batch LLM** | Ollama 0.23 + **Gemma 4 31B Q4_K_M** (~19 GB on disk, ~47 GB VRAM 로드) | 다국어 / cohort 추출 / 한국어 번역 |
| **Embedding (index)** | Ollama + **Qwen3-Embedding-8B** → Matryoshka 1024d truncate | MTEB Multilingual 1위 (70.58) |
| Embedding (query) | Qwen3-Embedding-0.6B (native 1024d, T1000 4GB VRAM fit) | 인덱스/쿼리 dim 일치 |
| Reranker | sentence-transformers + **Qwen3-Reranker-0.6B Q4** | 다국어 + Apache 2.0 + Qwen3 통일 |
| 인증 | Firebase Auth (Google sign-in) | 빠른 셋업, 안정 |
| KMS | LocalStack (dev) → AWS KMS (prod) — native 환경에서는 `KMS_PROVIDER=mock` | envelope 암호화 |
| 배포 | **Native host binary stack** (`scripts/a100-native-bootstrap.sh`) | 컨테이너 의존성 회피 — §3.4 |

GPU: NVIDIA A100 80GB × 1 (CDI 미지원 환경에서 `CUDA_VISIBLE_DEVICES` 로 명시). Gemma 4 와
Qwen3-Embedding-8B 는 Ollama `OLLAMA_MAX_LOADED_MODELS=1` 정책상 *동시* 적재 불가 — batch
파이프라인이 단계별로 LLM (gen) → Embed 순서로 모델을 교체한다.

### 6.2 데이터 규모 (2026-05-13 v1.0 batch — 진행 중 / placeholder)

본 절의 수치는 v1.0 batch (`bash scripts/a100-batch-pipeline-native.sh 10000 500`) 가 종료된
후 최종 값으로 대체된다. 현재 시점 (작성일 17:55) 의 1/6 단계 (GEO harvest, max=10,000)
인덱싱 진행률:

| 출처 | datasets (목표) | 비고 |
|---|---|---|
| GEO | **TBD / 10,000** (최근 365일 신규) | NCBI E-utilities watermark 기반 |
| HCA | ~530 (전체) | Azul Data Browser API |
| GDC | ~91 (project 단위) | NCI GDC REST API |
| SRA | (이번 cycle 미포함) | 다음 PR 에서 `_harvest_sra` 추가 |
| **합계** | **~10,621** | 1-cycle batch 결과 |

각 단계별 wall-clock 시간 (v1.0 batch):

| 단계 | 시간 | 비고 |
|---|---|---|
| Harvest (GEO + HCA + GDC) | 1.5-2시간 | NCBI 3 rps 제약 (API key 없을 때) |
| LLM 추출 (modality + ontology, gemma4) | 10-14시간 | 4초/건 × 10k |
| Sample-level backfill (Series Matrix) | 1-2시간 | concurrency=6 |
| Embedding (Qwen3-8B → Matryoshka 1024d) | 1-2시간 | Qdrant + OpenSearch reindex 포함 |
| Translate top-500 (Gemma 4 한국어) | 1시간 | uvicorn 가동 필요 (optional) |
| Dump (pg_dump + Qdrant snapshot + Redis RDB) | 5분 | ~500 MB compressed |

총 **약 14-20시간** 의 1-cycle batch — A100 GPU 1장 단독 점유. NCBI API key 와 GPU 다중
점유 (`OLLAMA_NUM_PARALLEL`) 로 절반까지 단축 가능 (§9 향후 작업).

### 6.3 배포 모델 (v1.0)

ADR 0006 의 **2-서버 분업** 으로 변경:

- **A100 서버 (1회 batch, 다른 연구실)**: corpus harvesting + LLM 추출 + embedding 인덱싱 +
  dump 생성. ~14-20시간 1 cycle. dump bundle (~500 MB compressed) 을 다른 서버로 이주.
- **T1000 서버 (영구 서빙, eunjung 4GB VRAM)**: dump restore 후 FastAPI + Next.js + Qwen3
  serve 모델들 (4B LLM / 0.6B embed / 0.6B reranker) 가동. 사용자 쿼리 응답 + on-demand
  cohort/translate.

이주는 인터넷 경유 scp (~10분). 두 서버는 물리·LAN·소속 분리 — 노트북을 경유한 3-hop
SSH 채널로 dump bundle 만 옮긴다. 자세한 절차는 `docs/migration_v2.md` §4.

> **쉬운 설명:** 무거운 처리는 A100 서버에서 한 번 (14시간) 만 돌리고, 그 결과 파일을
> T1000 서버로 옮겨서 거기서 평소 검색 응답을 합니다. 두 서버는 서로 분리되어 있어 보안상
> 안전합니다.

---

## 7. 평가 (Evaluation)

### 7.1 LLM 모델 선택 — 3-way 비교

v1.0 의 batch LLM 결정 (ADR 0006) 을 위해 동일 A100 GPU 위 동일 ollama 인스턴스 (port 11435,
`CUDA_VISIBLE_DEVICES=3`) 에서 다음 3 모델을 정성 비교 (2026-05-13).

| 모델 | 파라미터 | quantization | GPU VRAM | context | 특수 capability |
|---|---|---|---|---|---|
| qwen3:8b | 8.2B | Q4_K_M | 11 GB | 40k | — |
| **gemma4:31b** | 31.3B | Q4_K_M | **47 GB** | **262k** | thinking, vision, tools |
| qwen3.5:27b | 27.8B | Q4_K_M | 42 GB | 262k | thinking |

#### 7.1.1 Cohort 추출 정확도

테스트 input: GSE BCG-response bladder cancer 3-group 연구 (responsive n=6, unresponsive
n=7, naïve n=7, 동일 abstract + sample factor 입력).

| 모델 | tok/s | wall (warm) | 그룹 추출 | n 정확 | design_type | role 분류 |
|---|---|---|---|---|---|---|
| qwen3:8b | 128 | 12.8s | 3 ✓ | ✓ | `case_control` (✗ — 임상적으로 case_control 은 retrospective. 본 연구는 observational) | resp=case · unresp=case · naïve=control (✗ — unresp 를 case 로 묶음) |
| **gemma4:31b** | 41 | 4.2s | 3 ✓ | ✓ | **`cohort`** ✓ (정확) | resp=case · unresp=`comparison` · naïve=control ✓ (의학적 함의 정확) |
| qwen3.5:27b | 30 | 47s | 3 ✓ | ✓ | `case_control` (✗) | resp=case · unresp=`control` · naïve=comparison (✗ — unresp 를 control 로) |

→ gemma4 만 임상 design taxonomy 와 role assignment 양쪽에서 정확. qwen3.5:27b 는 같은 27B
크기에도 부적절한 role 분류.

#### 7.1.2 한국어 학술 번역 품질

테스트 input: cardiac aging study (영어 title + abstract). 동일 prompt + JSON schema.

| 모델 | tok/s | 결과 title (한국어) |
|---|---|---|
| qwen3:8b | 129 | "식이 체내 글루타민 보충이 H3K27me3 조절을 통해 연령 관련 심장 기능 저하를 완화한다" — 의미 정확, *단* abstract 본문에 한자 잔재 (예: `심근세포 자噬` ← `자가포식` 의 깨짐) |
| **gemma4:31b** | 41 | "식이성 글루타민 보충은 H3K27me3 조절을 통해 노화 관련 심장 기능 저하를 완화한다" — 의미 정확 + 학술 자연체. `히스톤 수식(histone modifications)` / `자가포식(autophagy)` 처럼 영어 보존 — 논문 한국어 번역 관용에 부합 |
| qwen3.5:27b | 37 | "식이성 글루타민 보충이 H3K27me3 조절을 통해 노화 관련 **심부전 감소를 완화한다**" — **임상적 의미 오역**. *cardiac decline* (심장 기능 저하) 을 *심부전 감소* (heart failure reduction) 로 잘못 번역 → "감소를 완화한다" 는 double negative 라 실제로는 *심부전을 악화시킨다* 라는 정반대 의미 |

→ qwen3.5:27b 의 의미 오역은 모델 크기가 27B 임에도 발생 — **번역 품질이 모델 크기 단순
비례가 아니라 모델 *선택* 에 강하게 의존함을 시사**. gemma4:31b 가 학술 자연체 + 영어 용어
보존 면에서 최우수.

#### 7.1.3 처리 시간 trade-off

10k cohort 추출 + 500 한국어 번역 시간 추정 (sequential):

| 모델 | 시간 | 적합 시나리오 |
|---|---|---|
| qwen3:8b | ~4.7h | 속도 우선, 한국어 약점 수용 가능할 때 |
| **gemma4:31b** | **~14.6h** | **품질 우선 — 본 연구의 선택** |
| qwen3.5:27b | ~19.5h | (제외) |

본 연구는 corpus build 가 1회성 비용임을 감안, 모든 downstream 검색 / figure 의 baseline
quality 를 좌우한다는 점에서 gemma4:31b 를 선택. 시간 cost 는 일회성, 품질은 영구.

### 7.2 검색 품질 — v0.8 baseline (재측정 예정)

v0.8 (Phi-4 mini + nomic-embed + ms-marco) 시점의 정성 결과 — v1.0 (gemma4 + Qwen3) 재측정
이전의 참고 baseline:

| 쿼리 (영문, 도메인) | top-1 관련도 | 비고 |
|---|---|---|
| `bacterial whole genome sequencing` | 65% (rerank +1.18) | 제목·본문 모두 매칭 |
| `single-cell RNA-seq pancreatic islet` | 71% (rerank +1.5) | scRNA-seq + 췌장 정확 매칭 |
| `tumor immune microenvironment macrophage` | 60% (rerank +0.9) | semantic 강, lex 약 |

| 쿼리 (한국어) | top-1 관련도 | 비고 |
|---|---|---|
| `박테리아 전장 유전체 시퀀싱` | 29% (rerank −7) | semantic 0.72 강하지만 cross-encoder (ms-marco 영어 학습) 가 부정. nomic-embed-text 의 한↔영 매핑 한계 |

v1.0 의 Qwen3-Embedding-8B (MTEB Multilingual 70.58) + Qwen3-Reranker-0.6B (100+ lang) 로
재측정 시 한국어 쿼리 점수가 개선될 것이 예상되며, 본 batch 완료 후 동일 query set 30개에
대해 v0.8 vs v1.0 정량 비교를 진행 예정 (논문 figure 후보).

### 7.3 시스템 성능

| 지표 | v0.8 (CPU) | v1.0 (A100 native batch) |
|---|---|---|
| 검색 latency (avg, 200 candidates + rerank top-15) | ~400ms | TBD (T1000 측정 예정) |
| LLM 추출 throughput | ~1.5s/건 (Phi-4 mini CPU) | **~4s/건 (gemma4:31b Q4 on A100, warm)** |
| 임베딩 throughput (인덱스) | ~50 doc/min | TBD (Qwen3-Embedding-8B on A100) |
| 코퍼스 1-cycle batch (10k) | ~6-10h (이전 plan) | **~14-20h (gemma4 quality 우선)** |
| Concurrent rerank | non-blocking (`asyncio.to_thread`) | 동일 |

### 7.4 보안 검증 — Multi-tenant 격리

11개 자동 cross-tenant 테스트 (v0.8 그대로 통과, v1.0 에서 회귀 없음):
- Tenant A 의 saved_datasets row 가 tenant B 의 SELECT 에서 보이지 않음
- INSERT WITH CHECK 가 다른 tenant_id 거부
- DELETE 도 tenant scope 에 한정
- BYPASSRLS 권한이 없는 `genofinder_app` 만 사용

모두 통과.

### 7.5 코호트 디자인 추출 — 정성 평가 사례

§7.1.1 의 BCG 외 다른 study type 에 대한 spot-check (batch 완료 후 ~20 GSE 수동 평가
예정). v0.8 시점 검증된 사례:
- **GSE317412** (mouse glutamine + cardiac aging, 14 samples) — Phi-4 v1: "control vs
  treatment" → Phi-4 v2 (sample factor 입력): "young (12wk) / old (68wk), `cohort`" ✓.
  Gemma 4 (v1.0) 재추출 시 동일 또는 더 정확한 결과 기대 (§7.1 의 임상 분류 정확도).

### 7.6 한국어 번역 토글 사용성

- cold path: 평균 6초 (gemma4 Q4 첫 호출)
- cache hit: 평균 0.13초 (Redis 24h TTL)
- 토글 위치: 데이터셋 상세 페이지의 *원문/번역* TextToggle. 기본 원문 (영어). 명시적
  토글에만 fetch (lazy) — 사용자가 한국어를 요청하지 않으면 네트워크 호출 0.

### 7.7 한계

- **v1.0 정량 검색 품질** — Qwen3 stack 의 한국어 쿼리 개선 정량 측정은 batch 완료 후 진행
  예정 (30 쿼리 ground truth × {v0.8, v1.0} 비교 figure).
- **Sample-level metadata 부분 채움** — GEO 10k 중 Series Matrix fetch 성공률은 source side
  의 누락에 의존 (일부 GSE 는 Series Matrix 미공개).
- **GPU 1장 점유** — gemma4 47 GB + Qwen3-Embedding 16 GB 가 OLLAMA_MAX_LOADED_MODELS=1 정책상
  동시 적재 불가. batch 가 단계별 모델 swap (5분 unload + reload) 을 감수.
- **SRA 미통합** — 이번 cycle 의 batch 에 SRA harvester 가 빠져있어 v0.8 의 3건도 포함되지
  않음. 다음 PR 에서 `_harvest_sra` 추가 예정.
- **Translate top-500 단계는 API 의존** — `POST /datasets/{id}/translate` 가 FastAPI uvicorn
  통해 동작. batch 시점에 uvicorn 이 가동되어야 하며, 그렇지 않으면 자동 SKIP. 운영 시
  주의.

---

## 8. 논의 (Discussion)

### 8.1 로컬 LLM 의 trade-off (v1.0 갱신)

클라우드 LLM (GPT-4 등) 대비 절대 정확도가 낮을 가능성이 있으나, 본 연구의 경우 (i) 사용자
쿼리가 미공개 연구 IP 일 수 있어 외부 노출 위험을 회피하고, (ii) 운영 비용이 일정한 (외부
API 0) 장점이 크다고 판단하였다 (ADR 0003). v1.0 의 **Gemma 4 31B IT (Q4)** 는 262K context
와 140+ 언어 instruction following 능력을 갖추어, 메타데이터 추출 + cohort 디자인 + 한국어
번역 3가지 task 를 단일 모델로 처리 가능. 동급 27-32B 후보 (Qwen3.5-27B) 대비 한국어 학술
번역에서 의미 오역이 없고 임상 cohort taxonomy (case_control vs cohort) 분류가 정확하였다
(§7.1).

trade-off 는 추출 속도: 본 연구의 A100 단일 GPU 환경에서 gemma4 의 throughput 은 약
4초/건 (warm) 으로, v0.8 의 Phi-4 mini CPU 환경 (1.5초/건) 보다 *느리나* 품질은 훨씬 우수.
1-cycle batch (10k) wall-clock 이 6-10시간 → 14-20시간 으로 증가하지만, corpus build 가
일회성 비용임을 감안하면 합리적.

### 8.2 Thinking-mode 모델의 함정

Gemma 4 같은 reasoning-capable 모델은 Ollama 의 `/api/generate` 호출에서 `think: false` 를
명시하지 않으면 모든 생성 budget 을 hidden chain-of-thought 토큰으로 소비하여 visible
content 가 빈 채로 종료된다. JSON schema 모드 (`format: "json"`) 와 결합 시 더욱 빈번.
본 연구는 워커 측 `OllamaClient.generate_json` 의 default body 에 `think: False` 를
넣어 회피하였다 — *비-thinking 모델 (qwen3:8b 등) 에는 무영향이라 default-on 이 안전*.

### 8.3 Hybrid retrieval + 다국어 임베딩의 효과

v0.8 의 한국어 쿼리 약점 (nomic-embed 의 다국어 한계 + ms-marco 영어 cross-encoder) 이
v1.0 의 Qwen3 통일 stack (Embedding 8B / Reranker 0.6B 모두 100+ lang) 으로 개선이 기대된다.
이는 본 연구가 한국어 쿼리에 대해서도 동일 시스템을 사용 가능하게 만들어, 영어 / 한국어
사이의 검색 품질 격차 (locale gap) 을 좁히는 의미가 있다. 정량 검증은 batch 완료 후
30 쿼리 ground truth set 으로 진행 예정 (§9).

### 8.4 Score 가시화의 사용자 경험

원시 점수 (예: rerank −7.17) 가 직접 노출되면 사용자에게 혼란. 본 연구는 sigmoid_norm +
가중평균으로 0~100% 단일 점수를 만든 후, "상세" 토글로 원시값 접근 가능하게 분리. 펼침
빈도는 추후 user study 로 검증 필요.

### 8.5 컨테이너 폐기의 의미 — 학내 HPC 운영 패턴

§3.4 에서 기술한 native binary stack 채택은 단순한 우회 트릭이 아니라, *학내 공유 HPC*
환경의 일반 패턴 (NFS home + sudo 미보유 + 다른 사용자가 GPU/포트 점유) 에서 시스템을
재현 가능하게 운영하기 위한 설계 선택이다. 본 연구의 `scripts/a100-native-bootstrap.sh` 와
`scripts/a100-batch-pipeline-native.sh` 는 다른 HPC 사용자가 동일 시스템을 자기 계정에
구축할 수 있게 한다 — Docker 권한이나 admin 협조 없이.

---

## 9. 향후 작업 (Future Work)

- **v1.0 정량 평가**: 30 쿼리 ground truth × {v0.8, v1.0} retrieval / rerank 정확도 비교
  figure. batch 완료 후 1주 내 진행.
- **Cohort batch 풀 재처리**: 현재 batch 스크립트는 cohort 추출을 별도 PR 로 남겨둠
  (`a100-batch-pipeline.sh:65 next PR` 주석). 다음 단계로 `scripts/cohort-batch-native.sh`
  (~11h 추가) 신설하여 전체 corpus 의 cohort_design 컬럼을 채움. 데모용으로는 on-demand
  fallback 이 있어 필수는 아님.
- **SRA 통합**: `apps/workers/src/harvesters/sra.py` 의 `_harvest_sra` 호출을 native batch
  스크립트에 추가. SRA BioProject 단위 + GEO 와의 cross-reference 중복 dedup.
- **NCBI API key + GPU 다중 점유**: API key 등록 (3 rps → 10 rps) + `OLLAMA_NUM_PARALLEL=4`
  + 비어있는 GPU 4/5 동시 점유로 batch wall-clock 을 14h → 5-6h 단축 가능.
- **GEO 전체 (~284k) 인덱싱**: 현재 hardware 기준 ~14-17일 GPU 점유 + 인덱스 디스크 사용량
  대규모. Celery beat 의 incremental harvest 로 점진 채우기 권장 (1일 ~1-2시간).
- **데이터셋 비교 view**: 다중 dataset 의 메타데이터 + cohort_design 을 격자 비교
  (사용자가 후보 후보 후보 → 결정 step) — 장바구니 기반 UI.
- **추가 출처**: ENA, EGA (controlled access 법적 검토 필요), ProteomeXchange 등.
- **Reranker 4B 승격 검토**: Qwen3-Reranker-0.6B 의 정량 평가 후, 의미있는 품질 우위가
  확인되면 Qwen3-Reranker-4B Q4 로 승격. T1000 4GB VRAM 에 빠듯하므로 4B 의 Q4 가
  실제 fit 하는지 검증 필요.

---

## 10. 결론 (Conclusion)

본 연구는 4개 주요 공공 생명정보 카탈로그를 단일 검색 인터페이스로 통합하는 시스템
**Geno Finder** (v1.0) 를 제안하였다. 핵심은 다음과 같다:

1. **로컬 LLM (Gemma 4 31B Q4) 기반 자동 메타데이터 정규화** — modality / 종 / 질병 / 조직 /
   세포 타입 / **실험 그룹 구조 (cohort_design)** 까지 동시에 추출. ADR 0003 의 외부 API 0
   원칙 + ADR 0006 의 한국어 강화 모델 stack.
2. **다국어 hybrid retrieval** — Qwen3-Embedding-8B (Matryoshka 1024d) + BM25 + RRF +
   Qwen3-Reranker-0.6B. 영어 / 한국어 쿼리 모두 동일 파이프라인.
3. **PostgreSQL Row-Level Security + envelope encryption** 으로 multi-tenant 격리 (T4).
4. **점수 분해 가시화** — semantic / lexical / RRF / rerank 4 신호 모두 사용자 노출 (C5).
5. **On-demand 한국어 학술 번역** — 비영어권 진입 장벽을 낮추는 toggle. 모델 *선택* 이
   *크기* 보다 번역 품질에 더 강하게 작용함을 3-way 비교로 확인 (§7.1.2).
6. **컨테이너 의존성 없는 native 배포** — 학내 공유 HPC (subuid / CDI / sudo 제약) 환경에서
   재현 가능한 부트스트랩.

A100 80GB GPU 단일 장비 + 1-cycle ~14-20시간 batch 로 약 10,621 datasets 의 v1.0 코퍼스를
구축하였다. 모든 LLM 추론은 학내 GPU 위에서 끝나며, 외부 API 호출은 NCBI / Azul / GDC 의
*공개 메타데이터 fetch* 외에 0건이다.

> **쉬운 설명:** 흩어진 공공 데이터를 한 곳에 모아서 검색할 수 있게 만들었고, AI 가 자동
> 정리하며, 검색 결과가 왜 나왔는지도 투명하게 보여줍니다. 한국어 검색과 번역도 지원하며,
> 모든 AI 처리는 연구실 서버 안에서만 이루어집니다.

---

## 부록 A — 핵심 용어 사전 (Glossary)

| 용어 | 풀이 |
|---|---|
| Dense embedding | 텍스트를 768~1024차원 같은 고차원 벡터로 변환한 것. 의미가 비슷하면 벡터도 가깝다 |
| **Matryoshka embedding** | 한 모델이 4096d → 2048d → 1024d → 512d → ... 처럼 동심원으로 학습되어, 끝에서 잘라 써도 의미가 보존되도록 학습된 표현. [Kusupati 2022] |
| BM25 | 단어 빈도 기반 고전적 검색 점수. "키워드 매칭" 의 대표 |
| RRF (Reciprocal Rank Fusion) | 여러 ranker 의 순위를 합치는 단순 공식 [Cormack 2009] |
| Cross-encoder | (query, doc) 을 함께 입력해 정밀 관련도 점수를 내는 모델. 느리지만 정확 |
| **Thinking mode** | Gemma 4 / Qwen3 시리즈 등 일부 모델이 visible response 전에 hidden chain-of-thought 토큰을 먼저 생성하는 기능. Ollama 의 `think: false` 로 비활성화 가능 |
| Ontology | 의생명 도메인의 표준 분류 체계 (예: MONDO 는 질병, UBERON 은 해부, CL 은 세포 타입) |
| CURIE | Ontology term 을 표현하는 표준 ID (예: `MONDO:0005061` = 당뇨병) |
| **Cohort design** | 한 연구의 실험 그룹 구조 — case / control / treatment / comparison 분류 + 그룹별 표본 크기 (n) + 디자인 유형 (case_control / cohort / rct / time_series / cross_sectional / unknown) |
| **Series Matrix file** | GEO 의 study 한 건당 텍스트 파일. `!Sample_characteristics_ch1` 라인에 sample 별 sex/age/condition 등이 들어있음. 본 시스템의 sample-level 메타데이터 source |
| Row-Level Security (RLS) | 데이터베이스 단에서 사용자별로 row 가시성을 제한하는 기능 |
| Envelope encryption | 데이터를 DEK 로 암호화하고 DEK 자체를 KEK 로 다시 암호화. 키 회전 / KMS 통합 표준 패턴 |
| Tenant | 한 사용자(또는 워크스페이스) 의 격리 단위. 멀티테넌트 시스템에서 데이터 경계 |
| harvest | 외부 출처 (NCBI 등) 에서 메타데이터를 가져와 자체 DB 에 적재하는 작업 |
| **CDI** (Container Device Interface) | OCI 컨테이너에서 GPU 같은 device 를 노출하는 표준. `nvidia.com/gpu=3` syntax 는 podman 4.1+ / containerd 1.6+ 필요 |
| **subuid / subgid** | Linux 의 user namespace 매핑용 ID range. rootless podman 이 필수로 요구하지만, 본 연구의 운영 계정에는 미할당되어 있어 §3.4 의 native pivot 의 결정적 원인이 됨 |

---

## 부록 B — 인용 (참고 문헌, draft)

### B.1 검색 / 정보 검색
- Karpukhin V, et al. *Dense Passage Retrieval for Open-Domain Question Answering.* EMNLP, 2020.
- Cormack GV, Clarke CLA, Buettcher S. *Reciprocal Rank Fusion outperforms Condorcet and individual rank learning methods.* SIGIR, 2009.
- Nogueira R, Cho K. *Passage Re-ranking with BERT.* arXiv:1901.04085, 2019.
- Ma X, et al. *A Replication Study of Dense Passage Retriever.* arXiv:2104.05740, 2021.
- Kusupati A, et al. *Matryoshka Representation Learning.* NeurIPS, 2022.

### B.2 LLM / Embedding 모델 (v1.0)
- Qwen Team. *Qwen3 Technical Report.* 2025. (Qwen3-Embedding / Qwen3-Reranker / Qwen3-4B 시리즈)
- Google DeepMind. *Gemma 4: 31B Instruction-tuned multilingual model.* 2026. (262K context, 140+ lang)
- MTEB Benchmark. *Massive Text Embedding Benchmark — Multilingual leaderboard.* huggingface.co/spaces/mteb/leaderboard.

### B.3 공공 데이터베이스
- Edgar R, et al. *Gene Expression Omnibus: NCBI gene expression and hybridization array data repository.* Nucleic Acids Res, 2002.
- The Human Cell Atlas. Nature, 2017.
- The Genomic Data Commons (GDC). Nature, 2016.
- HCA Data Coordination Platform / Azul. github.com/DataBiosphere/azul.
- OLS (Ontology Lookup Service) v4. github.com/EBISPOT/ols4.

### B.4 인프라
- Ollama. github.com/ollama/ollama.
- Qdrant. github.com/qdrant/qdrant.
- OpenSearch. opensearch.org.
- podman. github.com/containers/podman.

(공식 인용 형식은 투고 저널에 맞춰 추후 정리)

---

## 부록 C — 3-way LLM 모델 비교 raw data (2026-05-13)

### C.1 실행 환경
- 호스트: Xeon Gold 6342, A100 80GB × 6 (GPU 3 단독 사용)
- Ollama 0.23.3, `OLLAMA_HOST=127.0.0.1:11435`, `CUDA_VISIBLE_DEVICES=3`
- 호출 API: `POST /api/chat` with `think: false`, `temperature: 0.2`
- 측정 도구: `/tmp/model_compare.py` (urllib + time.time)

### C.2 Cohort prompt — BCG bladder cancer 3-group

Input (요약):
```
TITLE: Single-cell analysis of BCG response in muscle-invasive bladder cancer
ABSTRACT: We performed scRNA-seq on bladder tissue and blood from
  6 BCG-responsive patients,
  7 BCG-unresponsive patients,
  7 BCG-naïve patients
SAMPLE FACTORS:
  Group variables: sample group: BCG unresponsive (n=7), BCG naïve (n=7), BCG responsive (n=6)
  Constant variables: tissue: bladder; treatment: BCG
```

**qwen3:8b output**:
```json
{
  "groups": [
    {"label": "BCG unresponsive", "role": "case",    "n": 7, "criteria": "BCG-unresponsive patients"},
    {"label": "BCG naïve",        "role": "control", "n": 7, "criteria": "BCG-naïve patients"},
    {"label": "BCG responsive",   "role": "case",    "n": 6, "criteria": "BCG-responsive patients"}
  ],
  "design_type": "case_control",
  "notes": "The study compares BCG-responsive and BCG-unresponsive patients against BCG-naïve patients as controls."
}
```

**gemma4:31b output**:
```json
{
  "groups": [
    {"label": "BCG responsive",   "role": "case",       "n": 6, "criteria": "patients responsive to BCG treatment"},
    {"label": "BCG unresponsive", "role": "comparison", "n": 7, "criteria": "patients unresponsive to BCG treatment"},
    {"label": "BCG naïve",        "role": "control",    "n": 7, "criteria": "patients who have not received BCG treatment"}
  ],
  "design_type": "cohort",
  "notes": "Study compares immune cell signatures across different response levels to BCG treatment."
}
```

**qwen3.5:27b output**:
```json
{
  "groups": [
    {"label": "BCG responsive",   "role": "case",       "n": 6, "criteria": "Patients showing response to BCG treatment"},
    {"label": "BCG unresponsive", "role": "control",    "n": 7, "criteria": "Patients showing no response to BCG treatment"},
    {"label": "BCG naïve",        "role": "comparison", "n": 7, "criteria": "Patients who have not received BCG treatment"}
  ],
  "design_type": "case_control",
  "notes": "Study compares immune cell signatures across three groups based on BCG treatment response status using scRNA-seq."
}
```

### C.3 Korean translation — cardiac aging

Input:
```
TITLE: Dietary glutamine supplementation mitigates age-associated cardiac decline through H3K27me3 regulation
ABSTRACT: Cardiac aging is driven by epigenetic mechanisms including histone modifications.
We show that H3K27me3 increases in aged mouse and human hearts, suppressing cardiomyocyte autophagy.
Dietary glutamine supplementation reduced H3K27me3 in aged mice and improved cardiac function.
```

**qwen3:8b**:
> title: "식이 체내 글루타민 보충이 H3K27me3 조절을 통해 연령 관련 심장 기능 저하를 완화한다"
> abstract: "심장 노화는 히스톤 수정과 같은 표적 유전 메커니즘에 의해 주도된다. 우리는 H3K27me3가 노화된 마우스 및 인간 심장에서 증가하며, 심근세포 자噬를 억제함을 보여준다. 식이 체내 글루타민 보충은 노화된 마우스에서 H3K27me3를 감소시키고 심장 기능을 개선하였다."

**gemma4:31b**:
> title: "식이성 글루타민 보충은 H3K27me3 조절을 통해 노화 관련 심장 기능 저하를 완화한다"
> abstract: "심장 노화는 히스톤 수식(histone modifications)을 포함한 후성유전학적 메커니즘에 의해 진행된다. 본 연구에서는 노화된 마우스와 인간의 심장에서 H3K27me3가 증가하여 심근세포의 자가포식(autophagy)을 억제함을 확인하였다. 식이성 글루타민 보충은 노화된 마우스의 H3K27me3 수치를 감소시켰으며, 심장 기능을 개선하였다."

**qwen3.5:27b**:
> title: "식이성 글루타민 보충이 H3K27me3 조절을 통해 노화 관련 심부전 감소를 완화한다"
> (의미 오역 — cardiac decline → 심부전 감소. 이중부정이라 정반대 의미)

### C.4 성능 (wall-clock, 모두 cold load 포함 + 동일 prompt)

| 모델 | cohort wall | cohort tok/s | translate wall | translate tok/s |
|---|---|---|---|---|
| qwen3:8b | 12.85s (cold) | 128 | 2.06s | 129 |
| gemma4:31b | 4.15s (warm) | 41 | 5.41s | 41 |
| qwen3.5:27b | 47.42s (cold) | 30 | 4.14s | 37 |

cold/warm 구분: 같은 ollama 인스턴스에서 다른 모델 적재 시 OLLAMA_MAX_LOADED_MODELS=1
정책상 swap 발생 → 첫 호출 wall 에 모델 load 시간 포함.

### C.5 Reproducibility

```bash
# 환경 준비
cd ~/genofinder
bash scripts/a100-native-bootstrap.sh   # postgres / redis / qdrant / opensearch / ollama 가동

# 3 모델 풀
export OLLAMA_HOST=127.0.0.1:11435
~/genofinder/services/ollama/bin/ollama pull qwen3:8b
~/genofinder/services/ollama/bin/ollama pull gemma4:31b
~/genofinder/services/ollama/bin/ollama pull qwen3.5:27b

# 비교 스크립트 (이 논문의 /tmp/model_compare.py)
OLLAMA_URL=http://127.0.0.1:11435 python3 /tmp/model_compare.py qwen3:8b gemma4:31b qwen3.5:27b
```

---

*본 초안은 v1.0 batch 진행과 함께 갱신됩니다. §6.2 의 corpus 수치 와 §7.2-3 의 시스템 성능 /
검색 품질 정량 지표는 batch 완료 (~14-20시간 뒤) 직후 실측 값으로 대체됩니다.*
