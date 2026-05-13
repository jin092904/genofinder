"use client";

import { useRouter, useSearchParams } from "next/navigation";

export function Pagination({
  page,
  pageSize,
  total,
  locale,
}: {
  page: number;
  pageSize: number;
  total: number;
  locale: "ko" | "en";
}) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const totalPages = Math.max(1, Math.ceil(total / pageSize));

  if (total <= pageSize) return null;

  const navigate = (target: number) => {
    const params = new URLSearchParams(searchParams);
    if (target === 1) params.delete("page");
    else params.set("page", String(target));
    router.push(`/search?${params.toString()}`);
  };

  const labels =
    locale === "ko"
      ? { prev: "이전", next: "다음", page: "페이지" }
      : { prev: "Prev", next: "Next", page: "Page" };

  return (
    <nav className="mt-2 flex items-center justify-between gap-3 border-t border-outline-variant pt-5 text-body-sm">
      <button
        type="button"
        onClick={() => navigate(page - 1)}
        disabled={page <= 1}
        className="rounded-md border border-outline-variant px-4 py-2 font-medium text-on-surface-variant transition-colors hover:border-on-surface-variant/50 hover:text-on-surface disabled:cursor-not-allowed disabled:opacity-40"
      >
        ← {labels.prev}
      </button>
      <span className="font-mono text-on-surface-variant">
        {labels.page} <span className="text-on-surface">{page}</span> / {totalPages}
      </span>
      <button
        type="button"
        onClick={() => navigate(page + 1)}
        disabled={page >= totalPages}
        className="rounded-md border border-outline-variant px-4 py-2 font-medium text-on-surface-variant transition-colors hover:border-on-surface-variant/50 hover:text-on-surface disabled:cursor-not-allowed disabled:opacity-40"
      >
        {labels.next} →
      </button>
    </nav>
  );
}
