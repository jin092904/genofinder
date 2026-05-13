# Figure legends (final figures to be drawn after v1.0 batch completes)

## Figure 1. System architecture of Geno Finder.

Four-tier layout. **(a) Client tier**: Next.js 16 single-page application
with Firebase Authentication (Google sign-in) issuing ID tokens.
**(b) API tier**: FastAPI service that verifies tokens, sets the per-request
PostgreSQL `app.tenant_id` for row-level security, and exposes endpoints
for search, dataset detail, cohort extraction (`POST /cohort/extract`),
on-demand Korean translation, and download snippets. **(c) Storage and
search tier**: PostgreSQL 16 (relational, RLS), Redis 8 (translation /
detail cache), Qdrant 1.12 (1024-dimensional dense index), OpenSearch
2.16 (BM25 lexical index). **(d) LLM tier**: a private Ollama 0.23
instance on port 11435 with Gemma 4 31B for generation/translation and
Qwen3-Embedding-8B for indexing, plus a `sentence_transformers`
Qwen3-Reranker-0.6B in-process. All inference is local; no user data is
sent to external APIs.

## Figure 2. Wall-clock breakdown of the six-stage v1.0 batch pipeline.

Horizontal stacked bar chart. Stages: (1) harvest GEO + HCA + GDC,
(2) LLM extraction of modality / ontology / cohort design (Gemma 4 31B),
(3) GEO Series Matrix sample-level backfill, (4) embedding indexing with
Qwen3-Embedding-8B → Matryoshka 1024d truncate, (5) Korean translation
pre-fill for the top-500 datasets, (6) PostgreSQL dump + Qdrant snapshot
+ Redis RDB. The total wall is approximately 14–20 hours for an
approximately 10,621-dataset corpus on a single A100 80GB GPU. The
LLM extraction stage dominates (~60–70% of the wall) and embedding is
the second largest (~10%).

## Figure 3. End-to-end search latency on the v1.0 corpus.

Histogram (or violin) over 30 ground-truth queries (15 English, 15
Korean) covering modality / disease / tissue / cohort-design intents.
For each query we record (a) embedding latency, (b) Qdrant top-200
retrieval latency, (c) OpenSearch top-200 retrieval latency, (d) RRF
fusion, (e) top-15 rerank with Qwen3-Reranker-0.6B. Sub-stage latencies
are stacked. Average end-to-end is expected to remain within 400 ms,
dominated by the reranker step. Korean queries are colour-coded
separately to show the multilingual capability of the Qwen3 stack.

## Figure 4 (supplementary). Cohort-design extraction examples.

Three representative datasets selected from the v1.0 corpus, displayed
as the panel rendered by the *ExperimentDesign* component on the detail
page. For each: (a) abstract; (b) sample-factor distribution parsed
from the GEO Series Matrix; (c) Gemma-4-extracted JSON; (d) UI
rendering with group cards coloured by role (case / control /
treatment / comparison) and per-group `n`. The examples illustrate
(i) a three-arm observational `cohort` (BCG bladder cancer), (ii) a
two-arm `cohort` distinguished by age (`young (12wk)` vs `old (68wk)`
mouse cardiac aging), and (iii) a classical `case_control` design.

## Table 1. 3-way LLM comparison (cohort + Korean translation).

| | qwen3:8b | gemma4:31b | qwen3.5:27b |
| - | - | - | - |
| Parameters | 8.2B | 31.3B | 27.8B |
| GPU VRAM at load | 11 GB | 47 GB | 42 GB |
| Context length | 40k | 262k | 262k |
| Generation rate (warm) | 128 tok/s | 41 tok/s | 30 tok/s |
| Cohort `design_type` | case_control (✗) | **cohort** (✓) | case_control (✗) |
| Cohort role assignment | acceptable | **best** (case / comparison / control) | incorrect |
| Korean translation register | passable; CJK glyph residue | **academic, terms preserved** | semantic error |
| Final selection for v1.0 | — | **Yes** | — |

## Table 2. v1.0 corpus composition (placeholder — to be finalised after batch).

| Source | Datasets in v1.0 | Method |
| - | - | - |
| GEO | ≈ 10,000 | NCBI E-utilities, 365-day watermark |
| HCA | ≈ 530 (entire) | Azul Data Browser API |
| GDC | ≈ 91 (entire) | NCI GDC `/projects` REST |
| SRA | 0 (next release) | — |
| **Total** | **≈ 10,621** | |
