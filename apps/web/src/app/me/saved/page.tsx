import Link from "next/link";

import { AppShell } from "@/components/AppShell";
import { AuthGuard } from "@/components/AuthGuard";
import { MemoryList } from "@/components/MemoryList";
import { getT } from "@/lib/i18n-server";

export default async function SavedPage() {
  const { locale, t } = await getT();
  return (
    <AppShell locale={locale} t={t} showSearch={false}>
      <main className="w-full flex-1 px-6 py-7 md:px-8">
        <AuthGuard locale={locale}>
          <Link
            href="/me"
            className="text-body-sm text-on-surface-variant transition-colors hover:text-on-surface"
          >
            {locale === "ko" ? "← 마이페이지" : "← My page"}
          </Link>
          <h1 className="mt-3 text-headline-md text-on-surface">
            {locale === "ko" ? "찜한 데이터셋" : "Saved datasets"}
          </h1>
          <p className="mt-2 text-body-sm text-on-surface-variant">
            {locale === "ko"
              ? "계정에 저장된 찜 목록입니다. 어떤 기기에서 접속해도 같은 목록이 보입니다."
              : "Bookmarks saved on your account. Synced across devices."}
          </p>
          <div className="mt-7">
            <MemoryList kind="saved" locale={locale} />
          </div>
        </AuthGuard>
      </main>
    </AppShell>
  );
}
