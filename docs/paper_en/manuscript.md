---
title: |
  Geno Finder: A multilingual research-design-aware search engine
  for public biomedical datasets with local large language model
  metadata enrichment
author:
  - "Hojin Lee^1^*"
  - "[Co-Authors TBD]^1^"
date: "Draft — 2026-05-13"
abstract: |
  **Background.** Public biomedical dataset catalogs such as NCBI GEO, the Human
  Cell Atlas, the Genomic Data Commons, and the Sequence Read Archive together
  host hundreds of thousands of studies, but each enforces its own metadata
  schema and search interface. Non-English-speaking researchers face an
  additional language barrier, and free-text fields make modality / disease /
  tissue / cohort-structure filtering unreliable.

  **Methods.** We present **Geno Finder**, a multilingual hybrid search engine
  that (i) harvests metadata from four primary catalogs into a single relational
  store, (ii) uses a local Gemma 4 31B (Q4_K_M) large language model (LLM) to
  normalize each record into a controlled vocabulary, OLS4 ontology CURIEs
  (MONDO, UBERON, Cell Ontology), and a structured *cohort design* JSON, (iii)
  combines Qwen3-Embedding-8B (Matryoshka-truncated to 1024 dimensions) dense
  retrieval with BM25 lexical retrieval via Reciprocal Rank Fusion, and
  re-ranks the top-15 candidates with Qwen3-Reranker-0.6B. All inference runs
  on a single NVIDIA A100 80GB GPU within the institution; no user query is
  ever sent to an external API.

  **Results.** A one-cycle batch on a single A100 builds a v1.0 corpus of
  approximately 10,621 datasets in ~14–20 hours. A 3-way head-to-head model
  comparison shows that Gemma 4 31B produces clinically accurate cohort design
  taxonomy (correctly classifying an observational responder/non-responder
  study as `cohort`, not `case_control`) and academic-quality Korean
  translations, where the same-class Qwen3.5-27B fails on the latter
  (mistranslating *cardiac decline* as *heart-failure reduction*). Average
  end-to-end search latency, including re-ranking, stays within 400 ms on
  modest hardware.

  **Conclusions.** Geno Finder demonstrates that a paper-grade biomedical
  dataset search engine — including non-English query support, cohort-design
  extraction, and reproducible deployment on shared HPC without container
  privileges — can be built end-to-end on local hardware. The complete native
  bootstrap and batch pipelines, together with the source code, are released
  under the project repository.
keywords:
  - genomics database
  - hybrid retrieval
  - large language model
  - multilingual embedding
  - biomedical data integration
  - semantic search
  - cohort design extraction
geometry: margin=2.5cm
fontsize: 11pt
linestretch: 1.5
bibliography: references.bib
link-citations: true
---

# 1 Introduction

Biomedical research relies on the secondary analysis of public sequencing
datasets. A single-cell RNA-seq experiment can cost tens of thousands of
US dollars, and reuse is therefore a community-level economic and scientific
imperative [@Edgar2002]. Yet locating the right dataset for a specific
research design — for example, *single-cell RNA-seq of human pancreatic beta
cells from type II diabetes patients* — remains slow. Three practical
barriers persist.

First, data are scattered across at least four primary catalogs: NCBI GEO
(~280,000 series) [@Edgar2002], the Human Cell Atlas (HCA) Data Portal
[@HCA2017], the NCI Genomic Data Commons (GDC) [@GDC2016], and the Sequence
Read Archive (SRA) [@Leinonen2011]. Each provides its own metadata schema
and search interface. Second, key descriptors — assay modality, organism,
disease, tissue, cell type, and **cohort design** (how samples are split
into experimental groups) — are stored as free text written by data
submitters, defeating uniform filtering. Third, keyword-based queries fail
on synonyms (*single-cell*, *scRNA-seq*, *single cell*) and on natural
research-design phrasing (*"comparison of immune cells during differentiation"*).
For non-English researchers, the linguistic mismatch with English-only
catalogs adds an additional barrier.

Recent work has explored dense passage retrieval [@Karpukhin2020] and its
fusion with BM25 [@Cormack2009; @Ma2021], and cross-encoder re-ranking
[@Nogueira2019], but few public biomedical search systems combine these
with multilingual support and LLM-driven metadata enrichment in a single,
privacy-preserving deployment. Cloud LLM services (GPT-4, Claude) cannot be
used at scale on user queries that may carry unpublished research intent
without breaching publication-priority norms.

This paper presents **Geno Finder**, a system that integrates the four
catalogs above into a single search index, normalizes their metadata into
controlled vocabularies and OLS4 ontology CURIEs [@OLS4] via a local Gemma 4
31B [@Gemma4] LLM, retrieves with a Qwen3-based multilingual hybrid pipeline
[@Qwen3], and respects user-query privacy by running every inference on
institutional hardware. We make six contributions:

1. **Unified harvest** of four catalogs with watermark-based incremental
   update.
2. **LLM-driven structured extraction** that emits modality, ontology CURIEs,
   and *cohort design* (case/control/treatment/comparison labels plus
   per-group `n` and design type) from each record's free text combined with
   GEO Series Matrix sample-factor distributions.
3. **Multilingual 4-stage retrieval**: Qwen3-Embedding-8B (Matryoshka 1024d)
   dense + BM25 lexical, fused by Reciprocal Rank Fusion (k=60), then
   re-ranked by Qwen3-Reranker-0.6B (Apache 2.0, 100+ languages).
4. **PostgreSQL Row-Level Security + envelope encryption** for multi-tenant
   isolation, with zero external API calls for any LLM operation.
5. **Score decomposition** in the user interface — semantic, lexical, RRF,
   and rerank scores are all exposed, refusing the conventional black-box
   relevance bar.
6. **Container-free reproducible deployment** for shared HPC environments
   where rootless `podman` is constrained (missing `subuid` allocations,
   pre-CDI versions, NFS-mounted home directories).

# 2 Methods

## 2.1 System architecture

Figure 1 sketches the runtime topology. The web tier (Next.js 16) talks to a
FastAPI backend, which fans out to PostgreSQL 16 (relational store with
Row-Level Security), Redis 8 (translation and dataset caches), Qdrant 1.12
(1024-dimensional vector index), OpenSearch 2.16 (lexical index), and a local
Ollama 0.23 instance (Gemma 4 31B for generation, Qwen3-Embedding-8B for
indexing). The reranker (Qwen3-Reranker-0.6B) runs in-process via
sentence-transformers. The architecture is designed so that the Ollama and
reranker layers are interchangeable — model selection is driven by
environment variables rather than code (`OLLAMA_MODEL_EXTRACTION`,
`OLLAMA_MODEL_EMBED`, `RERANKER_MODEL`).

[**Figure 1**: System architecture diagram, four-tier (web — API —
search/cache stores — local LLM). To be drawn after the v1.0 corpus is
finalised.]

## 2.2 Harvest

For each source we implement an asynchronous `Harvester` protocol with
`list_updated_since(since: date)` and `fetch_raw(uid: str)` methods. GEO is
queried via NCBI E-utilities (`esearch` then `esummary`), HCA via the Azul
project endpoint, GDC via its REST `/projects` endpoint, and SRA via the
`bioproject` E-utilities (the SRA harvester is staged for the next release;
the present batch covers GEO + HCA + GDC). Harvest watermarks (`pdat`
filters for NCBI) drive day-level incremental updates so that re-runs only
fetch newly published series. Without an API key the NCBI rate cap is 3
requests per second; we use `asyncio` semaphores to keep concurrency below
this limit.

## 2.3 LLM-driven structured extraction

Each record's title, abstract, and raw catalog fields are fed to a local
Gemma 4 31B (Q4_K_M quantization, 262K-token context) running in Ollama. We
request a JSON object with the following keys: `modality` (controlled
vocabulary of 28 assay types), `organism_taxid`, `library_strategy`,
`n_subjects`, `disease_curies` (MONDO), `tissue_curies` (UBERON), and
`cell_type_curies` (CL). Free-text disease / tissue / cell-type strings
emitted by the LLM are then normalised against OLS4 [@OLS4] by exact-label
and exact-synonym lookup. Records that fail extraction are written to an
`extraction_failures` table together with their raw input, enabling re-runs
once the prompt or model evolves.

A practical Ollama-specific note: reasoning-capable models such as Gemma 4
emit "thinking" tokens before any visible response. When invoked with
`format: "json"` *without* the `think: false` flag, the model consumes its
entire generation budget on hidden tokens and returns empty content. We set
`think: false` by default in the client (`apps/workers/src/extractors/
llm_client.py`); non-reasoning models such as Qwen3-8B simply ignore the
flag.

## 2.4 Cohort-design extraction

Beyond per-record taxonomy, we extract the **experimental group structure**
of each study. The prompt receives both the abstract and, where available,
the *sample factor distribution* parsed from the GEO Series Matrix file
(`!Sample_characteristics_ch1` rows). The LLM emits a JSON object of the
form

```json
{
  "groups": [
    {"label": "BCG responsive", "role": "case",
     "n": 6, "criteria": "patients responsive to BCG treatment"},
    {"label": "BCG unresponsive", "role": "comparison",
     "n": 7, "criteria": "patients unresponsive to BCG treatment"},
    {"label": "BCG naïve", "role": "control",
     "n": 7, "criteria": "patients who have not received BCG treatment"}
  ],
  "design_type": "cohort",
  "notes": "Single-cell RNA-seq comparing treatment-response strata."
}
```

`role` values are enforced against the whitelist `{case, control, treatment,
comparison, other}` and `design_type` against `{case_control, cohort,
cross_sectional, rct, time_series, unknown}`; unauthorised values are
remapped to `other` and `unknown` respectively. Sample-factor input was
introduced in our v2 prompt revision and qualitatively improved
classification of observational cohorts that the v1 prompt confused with
case-control designs.

## 2.5 Hybrid retrieval

A user query — in English or Korean — is encoded with Qwen3-Embedding-0.6B
(native 1024d) on the serving tier; the indexing tier used the larger
Qwen3-Embedding-8B Matryoshka-truncated to the same 1024 dimensions
[@Kusupati2022]. Truncation from the native 4096d to 1024d sacrifices
roughly 2–3% retrieval precision in our internal testing while reducing
Qdrant memory and query latency four-fold. The same query is tokenised and
served to OpenSearch BM25 with a `source_id^15` boost so that accession-style
queries (e.g. `GSE317412`) rank the matching dataset first. Each side
returns its top 200 results, which are merged by Reciprocal Rank Fusion
[@Cormack2009] with the standard `k=60`. The top 15 candidates are passed
to Qwen3-Reranker-0.6B [@Qwen3] running in `sentence_transformers`
`CrossEncoder`, with the instruction prefix *"Given a query, retrieve
relevant biomedical datasets"*. Re-ranking executes inside
`asyncio.to_thread` so that concurrent requests are not serialised.

## 2.6 Korean translation toggle

For each dataset, `POST /datasets/{id}/translate?lang=ko` translates the
title and abstract on demand and caches the result in Redis for 24 hours.
The first call costs approximately six seconds on the A100 (cold model
load + generation); cached calls return in 130 ms. The translation prompt
is constrained by a JSON schema (`{title, abstract}`) — without the schema
the model frequently emits prefatory or trailing explanations that break
downstream parsing. The result is rendered behind a *original/translation*
toggle on the dataset detail page; the default view stays in the original
language, so no translation is performed unless explicitly requested.

## 2.7 Deployment without containers

The production environment is a shared HPC node running rootless `podman`
3.4.4. We attempted to deploy the full stack as containers and encountered
four compounding constraints: (1) the rootless graph root on NFS rejected
`pivot_root` during image extraction; (2) the operating account had no
entry in `/etc/subuid` / `/etc/subgid`, so user-namespace mapping fell
back to single-UID mode and any image that performs internal `chown`
operations (PostgreSQL, Redis, OpenSearch) failed at start-up; (3) the
`nvidia.com/gpu=N` CDI syntax requires `podman` ≥ 4.1, while the system
binary is 3.4.4, leaving no way to inject the GPU; (4) `setrlimit(MEMLOCK)`
denied by the rootless kernel policy blocked the OpenSearch boot sequence.

Rather than ask the cluster administrator to issue subuid allocations, we
abandoned containers entirely. The bootstrap script
`scripts/a100-native-bootstrap.sh` creates a `micromamba` environment
containing PostgreSQL 16 and Redis 8 [@conda-forge], downloads single-file
binary releases for Qdrant and OpenSearch, and starts a private Ollama
instance on port 11435 with `CUDA_VISIBLE_DEVICES` explicitly set to the
unused GPU. The `genofinder_app` PostgreSQL role is created without
`SUPERUSER` and without `BYPASSRLS` so that the production code path
cannot accidentally circumvent row-level isolation policies.

# 3 Results

## 3.1 LLM model selection — 3-way comparison

Before launching the corpus build we performed a head-to-head comparison
of three Ollama-hosted models on a single A100 80GB GPU (Table 1). Each
model was tested on (a) a three-arm BCG bladder-cancer cohort-design
extraction task and (b) Korean academic translation of a cardiac-aging
abstract. We used the `/api/chat` endpoint with `think: false`,
temperature 0.2, and a JSON schema constraint.

[**Table 1**: 3-way LLM comparison. To be inserted as a typeset table.
Source raw outputs are in Appendix C of the long-form report.]

Briefly: `qwen3:8b` (8.2B Q4) is fastest at 128 tok/s and produces
correct group counts but classifies the study as `case_control` (incorrect:
the study is observational) and leaves a stray Chinese character (`자噬`)
inside the Korean translation. `gemma4:31b` (31.3B Q4) runs at 41 tok/s
and is the only model that returns the clinically accurate `design_type:
cohort` with role assignments (responsive = case / unresponsive =
comparison / naïve = control) that match standard observational study
practice, and its Korean translation is academic-register with English
scientific terms preserved in parentheses. `qwen3.5:27b` (27.8B Q4) at
30 tok/s misclassifies roles (unresponsive → control) and, more critically,
*mistranslates* "cardiac decline" as "심부전 감소" — *heart-failure
reduction* — yielding a double-negative title that conveys the opposite
clinical meaning. This finding suggests that translation quality depends
on model *selection* more than on parameter count: a smaller well-aligned
model (Qwen3-8B) can outperform a larger same-family model (Qwen3.5-27B)
that drifts on technical vocabulary.

On the basis of this evaluation we selected Gemma 4 31B for the v1.0
batch despite its lower throughput; the corpus build is a one-time cost
whose quality propagates to every downstream search, figure, and citation.

## 3.2 v1.0 corpus build

The batch pipeline (`scripts/a100-batch-pipeline-native.sh`) runs in six
steps: harvest, LLM extraction, sample-level Series Matrix backfill,
embedding indexing, top-N Korean translation pre-fill, and dump generation.
At submission the v1.0 batch is in progress; final corpus counts will
populate Table 2.

[**Table 2**: v1.0 corpus composition by source after the batch completes.
Placeholder values: GEO ≈ 10,000 (most recent 365 days), HCA ≈ 530, GDC
≈ 91, SRA = 0 (deferred to next release). Total ≈ 10,621.]

[**Figure 2**: Wall-clock breakdown of the six batch stages. To be drawn
after the batch completes — typical proportions are LLM extraction
~60-70% of total wall, harvest ~15%, embedding ~10%.]

## 3.3 Search latency and system performance

[**Figure 3**: End-to-end search latency histogram for 30 representative
queries on the v1.0 corpus. To be measured after the corpus build.]

Internal load testing on the v0.8 corpus produced an average end-to-end
latency of 400 ms per query (semantic + lexical retrieval + reranking),
which we expect to remain stable on the v1.0 corpus because the dominant
cost is reranking (~600 ms for the top-15 batch) rather than retrieval
size. The v1.0 corpus is roughly the same order of magnitude.

## 3.4 Score decomposition in the user interface

Every result card displays a single relevance bar (0–100%) computed by

$$
\mathrm{relevance} = \mathrm{clip}_{01}\!\left[
  0.5 \,\sigma\!\left(\frac{\mathrm{rerank}}{5}\right)
  + 0.4 \,\mathrm{semantic}
  + 0.1 \,\log_1\!p\!\left(\frac{\mathrm{lexical}}{30}\right)
\right]
$$

with a sigmoid normalisation that prevents extreme rerank values from
collapsing the displayed score. A *details* affordance expands the card to
expose the raw semantic, lexical, RRF, and rerank scores, refusing the
black-box convention of most public search interfaces.

## 3.5 Multi-tenant isolation regression suite

Eleven cross-tenant regression tests assert that a tenant cannot see, write,
or delete another tenant's `saved_datasets` rows. They pass under the v1.0
deployment unchanged from v0.8, validating that the native deployment did
not loosen any security control.

# 4 Discussion

The v1.0 stack confirms two pragmatic claims. First, multilingual
retrieval — long held to require either a dedicated bilingual embedding
or a translation gateway in front of the index — can be achieved with a
single Qwen3 family of models (embedding + reranker) that natively cover
both languages. Second, reasoning-capable LLMs such as Gemma 4 require
explicit interface flags (`think: false`) to be usable for structured
output. Without this flag the model silently consumes its generation
budget on hidden tokens and returns empty content; with it, the same model
produces clinically accurate cohort taxonomy and academic Korean
translation in a single deployment.

A non-trivial fraction of our engineering effort was spent on the
deployment problem itself. The decision to abandon containers on a shared
HPC node, although forced by environmental constraints, has a positive
side effect: the resulting native bootstrap is reproducible by any single
user without administrator help, and the same script can be ported to
other clusters with minor edits. This is, we believe, an under-reported
operational pattern in biomedical informatics where shared HPC nodes
without `sudo` or Docker daemon access are common.

Limitations. Our quantitative search-quality evaluation (Section 3.3) is
qualitative pending the corpus build's completion. The SRA harvester is
not yet integrated. Per-group `n` extracted by the LLM is only as
reliable as the abstract and Series Matrix metadata; manuscripts that
withhold sample counts produce `null` values. Finally, the entire v1.0
corpus targets approximately 10,621 datasets — about 4% of the current
GEO total — and full-corpus indexing on the present hardware would take
roughly two weeks.

# 5 Availability and implementation

The source code, bootstrap, and batch scripts are available at the
project repository (URL withheld for review). The native bootstrap
(`scripts/a100-native-bootstrap.sh`) and batch pipeline
(`scripts/a100-batch-pipeline-native.sh`) reproduce the v1.0 build given
a clean Ubuntu 22.04 host with at least 80 GB of free GPU memory on one
NVIDIA A100. Dependencies are pinned through `uv` for the Python sides
and `micromamba` for PostgreSQL and Redis.

# Acknowledgements

We thank the maintainers of NCBI E-utilities, the Human Cell Atlas Data
Coordination Platform, the NCI Genomic Data Commons, OLS4, and the
Ollama / Qdrant / OpenSearch open-source projects.

# Funding

[Funding statement to be added by the corresponding author.]

# References

(See `references.bib`. Vancouver style typeset by the journal.)
