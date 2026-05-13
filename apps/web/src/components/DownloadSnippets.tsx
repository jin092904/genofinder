// 다운로드 코드 스니펫 — R / Python / Bash 탭 + 복사 버튼.
//
// snippets 가 빈 배열이면 source 가 GEO/SRA/HCA/GDC 외이므로 안내 메시지.
"use client";

import { useMemo, useState } from "react";

import type { Snippet, SnippetsResponse } from "@/lib/api";
import type { Locale } from "@/lib/i18n";

const LANG_LABELS: Record<Snippet["language"], string> = {
  R: "R",
  python: "Python",
  bash: "Bash",
};

export function DownloadSnippets({
  data,
  locale,
}: {
  data: SnippetsResponse | null;
  locale: Locale;
}) {
  const t = (ko: string, en: string) => (locale === "ko" ? ko : en);
  const grouped = useMemo(() => {
    const byLang: Record<string, Snippet[]> = {};
    for (const s of data?.snippets ?? []) {
      (byLang[s.language] ||= []).push(s);
    }
    return byLang;
  }, [data]);

  const languages = Object.keys(grouped) as Snippet["language"][];
  const [activeLang, setActiveLang] = useState<Snippet["language"] | null>(
    languages[0] ?? null,
  );

  if (!data || data.snippets.length === 0) {
    return (
      <div className="rounded-md border border-outline-variant bg-surface-container-low/60 px-3 py-2 text-body-sm text-on-surface-variant">
        {t(
          "이 데이터 소스에 대한 다운로드 스니펫은 아직 준비되지 않았습니다.",
          "Download snippets are not yet available for this data source.",
        )}
      </div>
    );
  }

  const active = activeLang ?? languages[0];
  const items = (active && grouped[active]) || [];

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-baseline justify-between gap-3">
        <h3 className="text-label-caps uppercase text-on-surface-variant">
          {t("다운로드 스니펫", "Download snippets")}
        </h3>
        <div role="tablist" className="flex gap-1">
          {languages.map((lang) => (
            <button
              key={lang}
              type="button"
              role="tab"
              aria-selected={lang === active}
              onClick={() => setActiveLang(lang)}
              className={`h-7 rounded-md px-2.5 text-body-sm font-medium transition-colors ${
                lang === active
                  ? "bg-secondary text-on-secondary"
                  : "bg-surface-container text-on-surface-variant hover:bg-surface-container-high"
              }`}
            >
              {LANG_LABELS[lang]}
            </button>
          ))}
        </div>
      </div>

      <div className="flex flex-col gap-3">
        {items.map((s) => (
          <SnippetCard key={s.title} snippet={s} locale={locale} />
        ))}
      </div>
    </div>
  );
}

function SnippetCard({ snippet, locale }: { snippet: Snippet; locale: Locale }) {
  const [copied, setCopied] = useState(false);
  const t = (ko: string, en: string) => (locale === "ko" ? ko : en);

  async function copy() {
    try {
      await navigator.clipboard.writeText(snippet.code);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      // graceful fail
    }
  }

  return (
    <article className="rounded-md border border-outline-variant bg-surface-container-low/40">
      <header className="flex items-start justify-between gap-3 border-b border-outline-variant px-3 py-2">
        <div className="min-w-0">
          <h4 className="truncate text-body-md font-medium text-on-surface">{snippet.title}</h4>
          <p className="mt-0.5 text-body-sm text-on-surface-variant">{snippet.description}</p>
        </div>
        <button
          type="button"
          onClick={copy}
          className="h-7 shrink-0 rounded-md bg-surface-container px-2.5 text-body-sm font-medium text-on-surface transition-colors hover:bg-surface-container-high"
        >
          {copied ? t("복사됨", "Copied") : t("복사", "Copy")}
        </button>
      </header>
      <pre className="overflow-x-auto bg-surface-container-low/80 px-3 py-3 font-mono text-mono-code text-on-surface">
        <code>{snippet.code}</code>
      </pre>
      {snippet.requires.length > 0 ? (
        <footer className="border-t border-outline-variant px-3 py-2 text-body-sm text-on-surface-variant">
          <span className="text-label-caps uppercase">{t("필요", "Requires")}</span>{" "}
          {snippet.requires.join(" · ")}
        </footer>
      ) : null}
    </article>
  );
}
