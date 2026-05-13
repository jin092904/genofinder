"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

export function HeroSearch({
  placeholder,
  submitLabel,
  tryLabel,
  suggestions,
}: {
  placeholder: string;
  submitLabel: string;
  tryLabel: string;
  suggestions: readonly string[];
}) {
  const router = useRouter();
  const [q, setQ] = useState("");

  const submit = (text: string) => {
    const trimmed = text.trim();
    if (!trimmed) return;
    router.push(`/search?q=${encodeURIComponent(trimmed)}`);
  };

  return (
    <div className="mx-auto w-full max-w-3xl">
      <form
        onSubmit={(e) => {
          e.preventDefault();
          submit(q);
        }}
        className="relative w-full"
      >
        <input
          type="text"
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder={placeholder}
          autoFocus
          className="block w-full rounded-2xl border border-outline-variant bg-surface py-5 pl-6 pr-32 text-body-lg text-on-surface placeholder-on-surface-variant shadow-card transition-all hover:shadow-card-hover focus:border-secondary focus:outline-none focus:ring-2 focus:ring-secondary/20"
        />
        <button
          type="submit"
          className="absolute inset-y-0 right-2.5 my-auto flex h-12 items-center gap-1.5 rounded-xl bg-secondary px-5 text-body-md font-medium text-on-secondary transition-colors hover:bg-secondary/90"
        >
          {submitLabel}
        </button>
      </form>
      <div className="mt-7 flex flex-wrap items-center justify-center gap-2 text-body-sm">
        <span className="text-on-surface-variant">{tryLabel}</span>
        {suggestions.map((s) => (
          <button
            key={s}
            type="button"
            onClick={() => {
              setQ(s);
              submit(s);
            }}
            className="rounded-full border border-outline-variant bg-surface px-3.5 py-1.5 text-on-surface-variant transition-colors hover:border-secondary hover:bg-secondary-container/40 hover:text-on-secondary-container"
          >
            {s}
          </button>
        ))}
      </div>
    </div>
  );
}
