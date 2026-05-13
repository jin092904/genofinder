import { AppShell } from "@/components/AppShell";
import { Filters } from "@/components/Filters";
import { Pagination } from "@/components/Pagination";
import { ResultCard } from "@/components/ResultCard";
import { fetchOntologyLabels, postSearch, type SearchRequest } from "@/lib/api";
import { getT } from "@/lib/i18n-server";

type SearchPageProps = {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

const PAGE_SIZE = 20;

function asArray(v: string | string[] | undefined): string[] {
  if (v == null) return [];
  return Array.isArray(v) ? v : [v];
}

export default async function SearchPage({ searchParams }: SearchPageProps) {
  const [{ locale, t }, params] = await Promise.all([getT(), searchParams]);
  const query = (typeof params.q === "string" ? params.q : "").trim();
  const modality = asArray(params.modality);
  const sourceDb = asArray(params.source_db);
  const disease = asArray(params.disease);
  const tissue = asArray(params.tissue);
  const cellType = asArray(params.cell_type);
  const accessPreference = (params.access === "any" ? "any" : "open_only") as
    | "any"
    | "open_only";
  const mustHaveProcessedData = params.processed === "1";
  const page = Math.max(1, parseInt((params.page as string) ?? "1", 10) || 1);

  let response: Awaited<ReturnType<typeof postSearch>> | null = null;
  let errorMessage: string | null = null;
  if (query) {
    const reqBody: SearchRequest = {
      query_text: query,
      modality: modality.length ? modality : undefined,
      disease_ids: disease.length ? disease : undefined,
      tissue_ids: tissue.length ? tissue : undefined,
      cell_type_ids: cellType.length ? cellType : undefined,
      access_preference: accessPreference,
      must_have_processed_data: mustHaveProcessedData,
      page,
      page_size: PAGE_SIZE,
    };
    try {
      response = await postSearch(reqBody);
    } catch (err) {
      errorMessage = err instanceof Error ? err.message : "Unknown search error";
    }
  }

  const filteredResults =
    response && sourceDb.length
      ? response.results.filter((r) => sourceDb.includes(r.source_db))
      : response?.results ?? [];

  // facet curie + 선택된 ontology + 결과별 disease/tissue/cell_type id → 라벨 lookup
  const allOntologyCuries: string[] = [...disease, ...tissue, ...cellType];
  if (response) {
    allOntologyCuries.push(
      ...response.facets.disease_ids.map((f) => f.value),
      ...response.facets.tissue_ids.map((f) => f.value),
      ...response.facets.cell_type_ids.map((f) => f.value),
    );
    for (const r of response.results) {
      if (r.disease_ids) allOntologyCuries.push(...r.disease_ids);
      if (r.tissue_ids) allOntologyCuries.push(...r.tissue_ids);
      if (r.cell_type_ids) allOntologyCuries.push(...r.cell_type_ids);
    }
  }
  const ontologyLabels: Record<string, string> = await fetchOntologyLabels(allOntologyCuries).catch(
    () => ({}),
  );

  return (
    <AppShell locale={locale} t={t} initialQuery={query}>
      <main className="grid w-full grid-cols-1 gap-7 px-6 py-7 md:grid-cols-12">
        <div className="md:col-span-3">
          <Filters
            selectedModality={modality}
            selectedSourceDb={sourceDb}
            selectedDisease={disease}
            selectedTissue={tissue}
            selectedCellType={cellType}
            accessPreference={accessPreference}
            mustHaveProcessedData={mustHaveProcessedData}
            query={query}
            t={t}
            facets={response?.facets}
            locale={locale}
            ontologyLabels={ontologyLabels}
          />
        </div>
        <section className="flex flex-col gap-4 md:col-span-9">
          <header className="mb-1">
            <h1 className="text-headline-md text-on-surface">
              {query ? (
                <>
                  {t.search.titlePrefix}{" "}
                  <span className="text-secondary">&ldquo;{query}&rdquo;</span>
                </>
              ) : (
                t.search.titleEmpty
              )}
            </h1>
            {response ? (
              <p className="mt-2 text-body-sm text-on-surface-variant">
                {filteredResults.length === response.results.length ? (
                  <>
                    <span className="font-mono font-medium text-on-surface">
                      {response.total_estimated}
                    </span>{" "}
                    {t.search.summaryCandidates}
                  </>
                ) : (
                  <>
                    <span className="font-mono font-medium text-on-surface">
                      {filteredResults.length}
                    </span>{" "}
                    {t.search.summaryFilteredOf}
                    {response.results.length}
                    {t.search.summaryFilteredOfSuffix}
                  </>
                )}{" "}
                <span className="text-on-surface-variant/60">
                  · <span className="font-mono">{response.latency_ms}ms</span>
                </span>
              </p>
            ) : !query ? (
              <p className="mt-2 text-body-md text-on-surface-variant">{t.search.placeholderHelp}</p>
            ) : null}
          </header>

          {errorMessage ? (
            <div className="rounded-xl border border-error/30 bg-error-container/40 p-5 text-on-error-container">
              <p className="font-medium">{t.search.errorTitle}</p>
              <p className="mt-1 font-mono text-body-sm">{errorMessage}</p>
              <p className="mt-2 text-body-sm">{t.search.errorHint}</p>
            </div>
          ) : null}

          {response && filteredResults.length === 0 && !errorMessage ? (
            <div className="rounded-xl border border-outline-variant bg-surface p-10 text-center">
              <p className="text-body-md text-on-surface-variant">{t.search.noResults}</p>
              <p className="mt-2 text-body-sm text-on-surface-variant/70">{t.search.noResultsHint}</p>
            </div>
          ) : null}

          {filteredResults.map((r) => (
            <ResultCard
              key={r.dataset_id}
              result={r}
              t={t}
              locale={locale}
              ontologyLabels={ontologyLabels}
            />
          ))}

          {response && filteredResults.length > 0 ? (
            <Pagination
              page={response.page}
              pageSize={response.page_size}
              total={response.total_estimated}
              locale={locale}
            />
          ) : null}
        </section>
      </main>
    </AppShell>
  );
}
