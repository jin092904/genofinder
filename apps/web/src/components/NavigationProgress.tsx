"use client";

// 라우트 변경 시 상단에 잠깐 흐르는 진행 막대.
// pathname/searchParams 가 바뀌면 짧게 표시 후 사라진다.
// (Next App Router 의 정확한 라우터 transition 이벤트는 노출되지 않으므로
//  완벽한 동기화는 아니지만, 사용자에게 "지금 무언가 진행 중" 신호를 주는 데 충분.)
import { usePathname, useSearchParams } from "next/navigation";
import { useEffect, useRef, useState } from "react";

export function NavigationProgress() {
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const key = `${pathname}?${searchParams?.toString() ?? ""}`;

  const [active, setActive] = useState(false);
  const [progress, setProgress] = useState(0);
  const firstRender = useRef(true);
  const fadeTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const tickTimer = useRef<ReturnType<typeof setInterval> | null>(null);

  useEffect(() => {
    if (firstRender.current) {
      firstRender.current = false;
      return;
    }
    setActive(true);
    setProgress(15);
    if (tickTimer.current) clearInterval(tickTimer.current);
    tickTimer.current = setInterval(() => {
      setProgress((p) => {
        // 80%까지 천천히, 그 뒤에는 멈춰서 실제 페이지 렌더 완료 신호를 기다림.
        if (p < 80) return p + (80 - p) * 0.15;
        return p;
      });
    }, 120);
    return () => {
      if (tickTimer.current) clearInterval(tickTimer.current);
    };
  }, [key]);

  // 새 페이지 첫 렌더가 끝나면 100%로 채우고 페이드아웃.
  useEffect(() => {
    if (!active) return;
    const finishTimer = setTimeout(() => {
      setProgress(100);
      if (fadeTimer.current) clearTimeout(fadeTimer.current);
      fadeTimer.current = setTimeout(() => {
        setActive(false);
        setProgress(0);
      }, 220);
    }, 80);
    return () => {
      clearTimeout(finishTimer);
      if (fadeTimer.current) clearTimeout(fadeTimer.current);
    };
  }, [key, active]);

  return (
    <div
      aria-hidden
      className="pointer-events-none fixed inset-x-0 top-0 z-[100] h-0.5"
    >
      <div
        className="h-full bg-secondary transition-[width,opacity] duration-150 ease-out"
        style={{
          width: `${progress}%`,
          opacity: active ? 1 : 0,
        }}
      />
    </div>
  );
}
