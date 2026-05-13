# ADR 0005 — Auth: Firebase + Hybrid Hosting

| | |
|---|---|
| Status | Accepted |
| Date | 2026-05-07 |
| Deciders | Claude Code (사용자 직접 승인) |
| Related | ADR 0001 (Tech Stack), ADR 0002 (Threat Model T4 — Multi-tenant 격리) |

## Context

마스터 플랜 §13.7 에서 Week 10 Clerk 통합을 가정했지만, 사용자가 다음 요구를 제시했다:

1. **호스팅이 쉬울 것** — Firebase App Hosting 의 git-push 자동 배포 선호
2. **사용자 식별은 구글 로그인** — Firebase Auth Google provider
3. **백엔드 인프라(Postgres/Qdrant/OpenSearch/Ollama/Redis)는 무거우므로 Oracle Cloud Free Tier 의 ARM Ampere VM 1대에 docker-compose 로 배치**

즉 **Firebase = 호스팅 + 인증, Oracle = 백엔드 데이터·연산** 의 하이브리드.

T4 (multi-tenant 격리) 전제는 변하지 않는다 — Postgres RLS 가 여전히 권한 경계의 source of truth 이며, Auth 계층은 그 위에 올라간다.

## Decision

### 인증 흐름

```
Browser (Next.js, Firebase Hosting)
   ├─ Firebase Auth Google sign-in popup → ID token (~1h, JWT)
   └─ fetch(API_BASE_URL/...) with `Authorization: Bearer <id_token>`
        ↓
FastAPI (Oracle VM)
   ├─ HTTPBearer dependency 추출
   ├─ firebase-admin verify_id_token() — 서명·만료·audience 검증 (네트워크 호출 없음, JWK 캐시)
   ├─ Principal { uid, email, email_verified, name, picture } 생성
   └─ uid → tenant_id 매핑 → SET LOCAL app.tenant_id (RLS 활성화)
```

### Provider 채택

- **Firebase Auth (Google sign-in only)** — Apple/email-link 은 보류
- **Firebase App Hosting** — Next.js standalone 배포
- **Oracle Cloud Free Tier (Ampere A1)** — backend docker-compose

### 채택하지 않은 대안

| 대안 | 기각 사유 |
|---|---|
| Clerk | 무료 한도(10K MAU) 충분하지만 self-host 불가, 호스팅 통합 약함 |
| Auth0 | 비용·복잡도 과다 (해커톤 규모) |
| Firebase Auth + Firebase Functions backend | 무거운 백엔드(Qdrant/OpenSearch/Ollama) 가 Functions 에 적합하지 않음 |
| 단일 Oracle VM 자체 호스팅 | 호스팅 자동화·HTTPS·CDN 직접 운영 부담 |

## 보안 사항 (T1, T4, T8 매핑)

### T1 (Auth bypass)
- 백엔드는 모든 보호 엔드포인트에서 `Depends(require_user)` 강제. 미들웨어 누락은 **회귀 테스트** 로 잡는다 (TODO: 다음 PR).
- 익명 검색을 허용하는 엔드포인트는 `optional_user` 사용 — 무효 토큰을 silent fail 로 익명 강등 (timing/error 정보 누설 차단).

### T4 (Cross-tenant)
- Firebase `uid` 는 안정적이지만 **tenant_id 와 1:1 매핑이 아닐 수 있다** (조직 단위 다중 사용자). 현재 v1 은 `uid == tenant_id` 단순 가정. 조직 도입 시 별도 `users.tenant_id` 매핑 테이블로 확장.
- RLS policy 는 변하지 않음 — `app.tenant_id` 세션 변수가 단일 진실 원천.

### T8 (Secret leakage)
- service-account JSON (`*-firebase-adminsdk-*.json`) 은 절대 commit 금지.
  - `.gitignore` 에 `*firebase-adminsdk*.json` 패턴 등록 (이미 적용).
  - 파일 권한 `chmod 600`.
  - 컨테이너에 read-only volume 마운트 (`:ro`), 환경변수에는 컨테이너 내부 경로(`/run/secrets/firebase-admin.json`) 만 노출.
- Firebase Web 설정 7키(NEXT_PUBLIC_FIREBASE_*) 는 **공개 식별자** — 번들에 들어가도 안전. 보안은 Firebase Rules + 백엔드 토큰 검증으로.
- 운영 배포 시 Oracle VM 의 GOOGLE_APPLICATION_CREDENTIALS 는 systemd EnvironmentFile (root:600) 또는 Vault 로 주입.

### 토큰 신선도
- ID 토큰 만료 ~1h. 프론트는 호출 시점마다 `auth.currentUser.getIdToken()` 으로 자동 refresh.
- `check_revoked=True` 는 매 요청마다 Firestore 호출 → latency 증가. 기본 비활성. 보안 사고 시 사용자 강제 로그아웃은 Firebase 콘솔에서 토큰 폐기 후 짧은 만료로 자연 강등.

## 사용 가이드

### 백엔드 라우터에서

```python
from fastapi import APIRouter, Depends
from src.security.firebase_auth import require_user, FirebasePrincipal

router = APIRouter()

@router.get("/me")
async def me(principal: FirebasePrincipal = Depends(require_user)):
    return {"uid": principal.uid, "email": principal.email}
```

### 익명 허용 엔드포인트 (검색 등)

```python
from src.security.firebase_auth import optional_user

@router.get("/search")
async def search(principal: FirebasePrincipal | None = Depends(optional_user), ...):
    if principal:
        # 개인화 (찜 표시 등)
        ...
```

### 프론트엔드에서 백엔드 호출

```ts
import { getCurrentIdToken } from "@/lib/user";

const token = await getCurrentIdToken();
const res = await fetch(`${API_BASE_URL}/me/saved`, {
  headers: token ? { Authorization: `Bearer ${token}` } : undefined,
});
```

## Open Questions

- **uid → tenant_id 매핑** 의 데이터 모델 — Phase B 조직(워크스페이스) 도입 시 결정.
- **Firebase Hosting 의 backend rewrite** vs **Cloudflare Worker proxy** — Oracle VM 의 도메인·HTTPS 전략과 묶어서 별도 ADR.
- **session cookie** 방식 (long-lived, httpOnly) 으로 전환 검토 — 현재는 ID 토큰 직빵.
