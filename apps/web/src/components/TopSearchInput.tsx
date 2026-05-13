"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

export function TopSearchInput({
  initialQuery = "",
  placeholder,
}: {
  initialQuery?: string;
  placeholder: string;
}) {
  const router = useRouter();
  const [q, setQ] = useState(initialQuery);

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        const trimmed = q.trim();
        if (!trimmed) return;
        router.push(`/search?${new URLSearchParams({ q: trimmed }).toString()}`);
      }}
      className="relative flex items-center"
    >
      <input
        type="text"
        value={q}
        onChange={(e) => setQ(e.target.value)}
        placeholder={placeholder}
        className="h-9 w-72 rounded-full border border-outline-variant bg-surface-container-low pl-4 pr-10 text-body-sm text-on-surface placeholder-on-surface-variant transition-colors focus:border-secondary focus:bg-surface focus:outline-none focus:ring-2 focus:ring-secondary/20 lg:w-96"
      />
      <button
        type="submit"
        aria-label="search"
        className="absolute right-1.5 flex h-7 w-7 items-center justify-center rounded-full text-on-surface-variant transition-colors hover:bg-surface-container-high hover:text-secondary"
      >
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
          <path d="M5 12h14M13 5l7 7-7 7" />
        </svg>
      </button>
    </form>
  );
}
