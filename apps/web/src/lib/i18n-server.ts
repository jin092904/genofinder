// Server-only — `next/headers` 는 server component / route handler 에서만 import 가능.
import "server-only";

import { cookies } from "next/headers";

import { LOCALE_COOKIE, translations, type Locale, type T } from "./i18n";

export async function getLocale(): Promise<Locale> {
  const c = (await cookies()).get(LOCALE_COOKIE);
  return c?.value === "en" ? "en" : "ko";
}

export async function getT(): Promise<{ locale: Locale; t: T }> {
  const locale = await getLocale();
  // `translations` 는 `as const` 라 ko / en 의 literal 타입이 다름 — runtime 동등성은 보장되니 cast.
  return { locale, t: translations[locale] as unknown as T };
}
