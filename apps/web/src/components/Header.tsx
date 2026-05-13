import type { Locale, T } from "@/lib/i18n";

import { LanguageToggle } from "./LanguageToggle";
import { MobileNav } from "./MobileNav";
import { ThemeToggle } from "./ThemeToggle";
import { TopSearchInput } from "./TopSearchInput";
import { UserMenu } from "./UserMenu";

export function Header({
  initialQuery = "",
  locale,
  t,
  showSearch = true,
}: {
  initialQuery?: string;
  locale: Locale;
  t: T;
  showSearch?: boolean;
}) {
  return (
    <header className="sticky top-0 z-40 w-full border-b border-outline-variant bg-background/85 backdrop-blur-md">
      <div className="flex w-full items-center justify-between gap-3 px-4 py-3 md:px-5">
        {/* 모바일: 햄버거 + 브랜드. md 이상에서는 sidebar 가 브랜드 역할. */}
        <div className="flex items-center gap-2 md:hidden">
          <MobileNav locale={locale} t={t} />
        </div>

        {/* 가운데 검색창 */}
        <div className="hidden min-w-0 flex-1 md:block">
          {showSearch ? (
            <TopSearchInput initialQuery={initialQuery} placeholder={t.topSearch.placeholder} />
          ) : null}
        </div>

        {/* 우측 유틸리티 */}
        <div className="flex shrink-0 items-center gap-2">
          <ThemeToggle locale={locale} />
          <LanguageToggle
            currentLocale={locale}
            switchToLabel={t.languageToggle.switchTo}
            ariaLabel={t.languageToggle.ariaLabel}
          />
          <UserMenu locale={locale} />
        </div>
      </div>
    </header>
  );
}
