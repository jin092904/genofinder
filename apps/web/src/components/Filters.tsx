"use client";

import { useRouter, useSearchParams } from "next/navigation";

import type { Facets } from "@/lib/api";
import type { T } from "@/lib/i18n";

const MODALITY_OPTIONS: string[] = [
  "scRNA-seq",
  "bulk RNA-seq",
  "ChIP-seq",
  "ATAC-seq",
  "scATAC-seq",
  "WGS",
  "WES",
  "Hi-C",
  "spatial",
  "smallRNA-seq",
  "methylation",
  "proteomics",
  "CITE-seq",
];

const SOURCE_DB_OPTIONS = ["GEO", "SRA", "ENA", "HCA", "GDC"];

export function Filters({
  selectedModality,
  selectedSourceDb,
  selectedDisease,
  selectedTissue,
  selectedCellType,
  accessPreference,
  mustHaveProcessedData,
  query,
  t,
  facets,
  locale,
  ontologyLabels,
}: {
  selectedModality: string[];
  selectedSourceDb: string[];
  selectedDisease: string[];
  selectedTissue: string[];
  selectedCellType: string[];
  accessPreference: "any" | "open_only";
  mustHaveProcessedData: boolean;
  query: string;
  t: T;
  facets?: Facets;
  locale: "ko" | "en";
  ontologyLabels?: Record<string, string>;
}) {
  const modalityCounts = new Map(
    facets?.modality.map((f) => [f.value, f.count]) ?? [],
  );
  const sourceCounts = new Map(
    facets?.source_db.map((f) => [f.value, f.count]) ?? [],
  );
  const diseaseFacets = facets?.disease_ids ?? [];
  const tissueFacets = facets?.tissue_ids ?? [];
  const cellTypeFacets = facets?.cell_type_ids ?? [];
  const labelOf = (curie: string) => ontologyLabels?.[curie] ?? curie;
  const router = useRouter();
  const searchParams = useSearchParams();

  const apply = (mutate: (params: URLSearchParams) => void) => {
    const params = new URLSearchParams(searchParams);
    mutate(params);
    if (query) {
      params.set("q", query);
    }
    params.delete("page");
    router.push(`/search?${params.toString()}`);
  };

  const toggleArrayParam = (key: string, value: string) => {
    apply((params) => {
      const current = params.getAll(key);
      if (current.includes(value)) {
        params.delete(key);
        for (const v of current) {
          if (v !== value) params.append(key, v);
        }
      } else {
        params.append(key, value);
      }
    });
  };

  const setSingle = (key: string, value: string | null) => {
    apply((params) => {
      if (value == null) params.delete(key);
      else params.set(key, value);
    });
  };

  const clearAll = () =>
    apply((params) => {
      for (const key of [
        "modality",
        "source_db",
        "access",
        "processed",
        "disease",
        "tissue",
        "cell_type",
      ]) {
        params.delete(key);
      }
    });

  const ontoLabels =
    locale === "ko"
      ? { disease: "질병", tissue: "조직", cellType: "세포 타입" }
      : { disease: "Disease", tissue: "Tissue", cellType: "Cell type" };

  return (
    <aside className="sticky top-24 flex flex-col gap-7 rounded-xl border border-outline-variant bg-surface p-6">
      <div className="flex items-center justify-between">
        <h2 className="text-headline-sm text-on-surface">{t.filters.heading}</h2>
        <button
          type="button"
          onClick={clearAll}
          className="text-body-sm font-medium text-secondary transition-opacity hover:opacity-70"
        >
          {t.filters.clearAll}
        </button>
      </div>

      <FilterGroup label={t.filters.modality}>
        {MODALITY_OPTIONS.map((opt) => (
          <Checkbox
            key={opt}
            checked={selectedModality.includes(opt)}
            label={opt}
            count={modalityCounts.get(opt)}
            onChange={() => toggleArrayParam("modality", opt)}
          />
        ))}
      </FilterGroup>

      <FilterGroup label={t.filters.sourceDb}>
        {SOURCE_DB_OPTIONS.map((opt) => (
          <Checkbox
            key={opt}
            checked={selectedSourceDb.includes(opt)}
            label={opt}
            count={sourceCounts.get(opt)}
            onChange={() => toggleArrayParam("source_db", opt)}
          />
        ))}
      </FilterGroup>

      <FilterGroup label={t.filters.access}>
        <Radio
          name="access"
          checked={accessPreference === "any"}
          label={t.filters.accessAny}
          onChange={() => setSingle("access", "any")}
        />
        <Radio
          name="access"
          checked={accessPreference === "open_only"}
          label={t.filters.accessOpen}
          onChange={() => setSingle("access", "open_only")}
        />
      </FilterGroup>

      <FilterGroup label={t.filters.dataAvailability}>
        <Checkbox
          checked={mustHaveProcessedData}
          label={t.filters.hasProcessed}
          onChange={() => setSingle("processed", mustHaveProcessedData ? null : "1")}
        />
      </FilterGroup>

      {diseaseFacets.length > 0 ? (
        <FilterGroup label={ontoLabels.disease}>
          {diseaseFacets.slice(0, 8).map((f) => (
            <Checkbox
              key={f.value}
              checked={selectedDisease.includes(f.value)}
              label={labelOf(f.value)}
              count={f.count}
              onChange={() => toggleArrayParam("disease", f.value)}
            />
          ))}
        </FilterGroup>
      ) : null}

      {tissueFacets.length > 0 ? (
        <FilterGroup label={ontoLabels.tissue}>
          {tissueFacets.slice(0, 8).map((f) => (
            <Checkbox
              key={f.value}
              checked={selectedTissue.includes(f.value)}
              label={labelOf(f.value)}
              count={f.count}
              onChange={() => toggleArrayParam("tissue", f.value)}
            />
          ))}
        </FilterGroup>
      ) : null}

      {cellTypeFacets.length > 0 ? (
        <FilterGroup label={ontoLabels.cellType}>
          {cellTypeFacets.slice(0, 8).map((f) => (
            <Checkbox
              key={f.value}
              checked={selectedCellType.includes(f.value)}
              label={labelOf(f.value)}
              count={f.count}
              onChange={() => toggleArrayParam("cell_type", f.value)}
            />
          ))}
        </FilterGroup>
      ) : null}
    </aside>
  );
}

function FilterGroup({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-2.5">
      <h3 className="text-label-caps uppercase text-on-surface-variant">{label}</h3>
      <div className="flex flex-col gap-2">{children}</div>
    </div>
  );
}

function Checkbox({
  checked,
  label,
  count,
  onChange,
}: {
  checked: boolean;
  label: string;
  count?: number;
  onChange: () => void;
}) {
  return (
    <label className="group flex cursor-pointer items-center justify-between gap-3 py-0.5">
      <span className="flex min-w-0 items-center gap-2.5">
        <input
          type="checkbox"
          checked={checked}
          onChange={onChange}
          className="h-4 w-4 cursor-pointer rounded border-outline-variant text-secondary focus:ring-1 focus:ring-secondary/30"
        />
        <span className="truncate text-body-sm text-on-surface transition-colors group-hover:text-secondary">
          {label}
        </span>
      </span>
      {typeof count === "number" ? (
        <span className="shrink-0 font-mono text-mono-data text-on-surface-variant">{count}</span>
      ) : null}
    </label>
  );
}

function Radio({
  name,
  checked,
  label,
  onChange,
}: {
  name: string;
  checked: boolean;
  label: string;
  onChange: () => void;
}) {
  return (
    <label className="group flex cursor-pointer items-center gap-2.5 py-0.5">
      <input
        type="radio"
        name={name}
        checked={checked}
        onChange={onChange}
        className="h-4 w-4 cursor-pointer border-outline-variant text-secondary focus:ring-1 focus:ring-secondary/30"
      />
      <span className="text-body-sm text-on-surface transition-colors group-hover:text-secondary">
        {label}
      </span>
    </label>
  );
}
