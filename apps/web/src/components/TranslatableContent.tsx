// 한국어 모드에서만 보이는 "번역" 토글. RSC 안전한 Context 패턴.
//
// 구조:
//   - <TranslateProvider> : 클라이언트, dataset_id + 원문 + 번역 state. 부모는 server.
//   - <TranslateToggleButton> : 버튼 (locale=ko 일 때만 표시)
//   - <TranslatableTitle original=...> : 원문 prop 으로 받고, state 켜져 있으면 번역본 표시
//   - <TranslatableAbstract original=...> : 동일
//
// page.tsx (server) 에서는 단순히 컴포넌트들을 그대로 배치하면 됨. 함수 prop / render prop 없음.
"use client";

import { ReactNode, createContext, useContext, useState } from "react";

import type { Translation } from "@/lib/api";
import type { Locale } from "@/lib/i18n";

type Ctx = {
  datasetId: string;
  locale: Locale;
  showTranslated: boolean;
  title: string | null;
  abstract: string | null;
  pending: boolean;
  error: string | null;
  toggle: () => Promise<void>;
};

const TranslateCtx = createContext<Ctx | null>(null);

export function TranslateProvider({
  datasetId,
  locale,
  originalTitle,
  originalAbstract,
  children,
}: {
  datasetId: string;
  locale: Locale;
  originalTitle: string | null;
  originalAbstract: string | null;
  children: ReactNode;
}) {
  const [translated, setTranslated] = useState<{
    title: string | null;
    abstract: string | null;
  } | null>(null);
  const [showTranslated, setShowTranslated] = useState(false);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function toggle() {
    setError(null);
    if (showTranslated) {
      setShowTranslated(false);
      return;
    }
    if (translated) {
      setShowTranslated(true);
      return;
    }
    setPending(true);
    try {
      const resp = await fetch(
        `/api/translate?id=${encodeURIComponent(datasetId)}&lang=ko`,
        { method: "POST" },
      );
      if (!resp.ok) {
        setError("번역 실패 — 잠시 후 재시도");
        return;
      }
      const data = (await resp.json()) as Translation;
      setTranslated({
        title: data.title ?? originalTitle,
        abstract: data.abstract ?? originalAbstract,
      });
      setShowTranslated(true);
    } catch {
      setError("네트워크 오류");
    } finally {
      setPending(false);
    }
  }

  const value: Ctx = {
    datasetId,
    locale,
    showTranslated,
    title:
      showTranslated && translated ? translated.title : originalTitle,
    abstract:
      showTranslated && translated ? translated.abstract : originalAbstract,
    pending,
    error,
    toggle,
  };

  return <TranslateCtx.Provider value={value}>{children}</TranslateCtx.Provider>;
}

function useTranslate(): Ctx {
  const ctx = useContext(TranslateCtx);
  if (ctx === null) {
    throw new Error(
      "useTranslate must be used inside <TranslateProvider>",
    );
  }
  return ctx;
}

export function TranslatableTitle({
  original,
  fallback,
  className,
}: {
  original: string | null;
  fallback: string;
  className?: string;
}) {
  const { title } = useTranslate();
  const display = title ?? original;
  return <h1 className={className}>{display || fallback}</h1>;
}

export function TranslatableAbstract({
  original,
  emptyText,
  className,
  emptyClassName,
}: {
  original: string | null;
  emptyText: string;
  className?: string;
  emptyClassName?: string;
}) {
  const { abstract } = useTranslate();
  const display = abstract ?? original;
  if (!display) {
    return <p className={emptyClassName}>{emptyText}</p>;
  }
  return <p className={className}>{display}</p>;
}

export function TranslateToggleButton() {
  const { locale, showTranslated, pending, error, toggle } = useTranslate();
  if (locale !== "ko") return null;
  return (
    <div className="flex items-center gap-2">
      <button
        type="button"
        onClick={toggle}
        disabled={pending}
        aria-pressed={showTranslated}
        className={`h-7 rounded-md px-2.5 text-body-sm font-medium transition-colors disabled:opacity-50 ${
          showTranslated
            ? "bg-secondary text-on-secondary"
            : "border border-outline-variant bg-surface-container text-on-surface-variant hover:bg-surface-container-high"
        }`}
      >
        {pending
          ? "번역 중… (5-30초)"
          : showTranslated
            ? "원문 보기"
            : "한국어로 번역"}
      </button>
      {error ? <span className="text-body-sm text-error">{error}</span> : null}
      {showTranslated ? (
        <span className="text-body-sm text-on-surface-variant/70">자동 번역</span>
      ) : null}
    </div>
  );
}
