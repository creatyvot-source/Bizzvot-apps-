# Audit 02: Authentication and native sessions

Scope: backend auth in Coglink (`/home/user/cogcard`, Next.js 15, MongoDB, `jsonwebtoken`), and the Flutter app's auth layer (`/home/user/Bizzvot-apps-`). This was a read-only audit. Every claim below comes from reading the cited code at backend commit `78cc311` and app commit `9eadaca`.

---

## 1. Summary

1. **The mobile app cannot sign anyone in today.** Every token-issuing route goes through `jsonOkWithAuth` (`lib/api.ts:15-27`). That helper deliberately removes `accessToken` and `refreshToken` from the JSON body and sends them only as `Set-Cookie`. The app's `parseTokens` (`lib/core/auth/auth_repository.dart:14-23`) looks for tokens in the body, finds none, and throws `NATIVE_SESSION_UNSUPPORTED`.
2. **Even with tokens, every real owner would see the "unsupported role" screen.** The backend calls owners `organization` (`lib/types.ts:1`). `UserRole.parse` does not recognise `organization` and returns `unknown`. `homeFor()` then sends the user to `Routes.unsupported`. The backend's fourth role, `individual`, is not handled by the app at all.
3. **Two app request bodies don't match the backend, so both flows always fail.** Register omits the required `role` field, so it always gets a 400. Reset-password sends `password`, but the backend expects `newPassword`, so it also always gets a 400.
4. **Several backend half-measures that help a native client already exist:**
   - `requireAuth` accepts `Authorization: Bearer` (`lib/auth.ts:55-63`).
   - `/auth/refresh` accepts `{refreshToken}` in the body.
   - `tokenVersion` revocation is solid.

   The minimal change is a token mode, switched on by the `x-bizzvot-client: mobile` header the app already sends. Token mode returns tokens in JSON, never reads cookies, and stores refresh tokens server-side with rotation and reuse detection. The design is in §5.
5. **Refresh tokens today are stateless 30-day JWTs.** They are not rotated in any meaningful sense: old ones stay valid. There is no reuse detection and no per-device revocation. `logout` bumps `tokenVersion`, which signs the user out **on every device**, web included. The app's logout body (`refreshToken`) is ignored. If the access token has expired, the server revokes nothing.
6. **Owner and staff logins are not properly separated, and `super_admin` is not rejected.**
   - `/auth/login` accepts every role, including `super_admin` and `staff`.
   - The web admin console signs in through `/auth/login`, so a separate admin route is needed before `super_admin` can be blocked there.
   - Lock state and suspension are revealed *before* the password is checked (423 and 403), which lets anyone check whether an account exists or is locked.
   - Unknown emails skip bcrypt, which leaks account existence through response timing.
7. **Change-password logs the mobile user out.** It bumps `tokenVersion` and puts the new session in cookies only. The app's stored tokens die, and the next refresh fails.
8. **Forgot-password is solid on the server but cannot reach the app.**
   - Server side is good: 1-hour TTL, SHA-256 hash at rest, atomic single use, per-email cooldown and daily cap.
   - The emailed link is `${APP_URL}/?resetToken=…` on the web root, not `/reset-password?token=`.
   - Android App Links only cover `/card/` and `/directory/`. iOS has no Associated Domains entitlement.
   - A successful reset does not clear the account lockout.
9. **There is no account-deletion endpoint.** `DELETE /auth/account` does not exist.
10. **Rate limits cover login, staff-login, register, forgot and reset, per IP only.** Refresh, logout, me and change-password have none. Responses never include `Retry-After`, and errors carry no machine-readable codes.

---

## 2. Current state (backend)

### 2.1 Token primitives

| Item | Value | Source |
|---|---|---|
| Access token | HS256 JWT signed with `JWT_SECRET`, TTL **1h** | `lib/auth-constants.ts:1-2`, `lib/auth.ts:30-32` |
| Refresh token | HS256 JWT signed with a *separate* `JWT_REFRESH_SECRET`, TTL **30d**, same payload as access | `lib/auth-constants.ts:3-4`, `lib/auth.ts:34-36` |
| Claims | `sub, email, role, organizationId, staffId, individualId, tokenVersion` (no `jti`, `sid`, `typ`, `aud`) | `lib/auth-tokens.ts:47-55`, `lib/types.ts:16-25` |
| Verify | `jwt.verify(token, secret)` with no `algorithms` pin | `lib/auth.ts:38-44` |
| Secrets | Production refuses weak or missing secrets (at least 16 chars, not `change-me*`) | `lib/jwt-secret.ts:18-27` |
| Revocation | `User.tokenVersion` is compared on every `requireAuth`. A Redis cache `tv:{userId}` = `{version}:{status}` lives 30s, and DB is the fallback. `bumpTokenVersion` rewrites the cache. | `lib/auth.ts:65-161` |
| Bumped by | logout, change-password, reset-password, admin suspend of an individual or organization (bulk `$inc` + cache invalidation), staff suspend or delete | `app/api/v1/auth/logout/route.ts:39`, `change-password/route.ts:30`, `reset-password/route.ts:49`, `app/api/v1/admin/organizations/[id]/status/route.ts:47-54`, `admin/individuals/[id]/status/route.ts:17`, `organization/staff/[id]/route.ts:66,87` |
| Token extraction | `Authorization: Bearer` first, then cookie `cogcard_token` | `lib/auth.ts:55-63` |

`tokenVersion` revocation applies per user and is all-or-nothing. No server-side session record exists, so there is no device list, no per-device logout, and no way to tell a refresh token from a replay of an older one.

### 2.2 Cookies (web transport)

`lib/session-cookies.ts`:
- `cogcard_token`: httpOnly, `maxAge` 1h.
- `cogcard_refresh`: httpOnly, 30d.
- `cogcard_role`: readable by JavaScript, UI chrome only.
- All three are `SameSite=Lax`, `Path=/`, and `Secure` in production (`secureCookiesEnabled`, lines 13-23).

`jsonOkWithAuth` (`lib/api.ts:11-27`) sets these cookies and returns `{success, data: {user}}` **with no tokens**. The comment states this is intentional, to stop XSS from stealing tokens.

### 2.3 Routes

| Route | Behaviour today | Notes |
|---|---|---|
| `POST /auth/register` (`app/api/v1/auth/register/route.ts`) | Zod body: `{name≥2, email, password≥6, phone?, role: "organization"\|"individual", organizationName?, industry?}`. Returns 409 `"Email already registered"`. Creates the User and the Organization or Individual, then `jsonOkWithAuth(..., 201)`. | `role` is **required**. Rate limit 5/min/IP. The 409 confirms which emails are registered. |
| `POST /auth/login` (`login/route.ts`) | Order of checks: rate limit 20/min/IP, then find user (unknown → 401 `"Invalid credentials"` with **no bcrypt run**), then **locked → 423**, then **suspended → 403**, then bcrypt (bad → `recordFailedLogin` + 401), then `clearFailedLogin`, then issue. | Accepts **every role**: super_admin, staff, individual, organization. |
| `POST /auth/staff-login` (`staff-login/route.ts`) | Same flow. Unknown user or a non-staff role gives 401 `"Invalid staff credentials"` before the password check. Also checks that the `Staff` doc is active. | Separate rate-limit key. Same lockout counter as `/auth/login`. |
| `POST /auth/refresh` (`refresh/route.ts`) | Takes `body.refreshToken`, **or the cookie**. Verifies the JWT, re-issues tokens, and rejects when `tokenVersion` doesn't match (`issueTokensForUser` also rejects inactive user, org, staff or individual). Responds with cookies only. | **The old refresh JWT stays valid** until it expires. No rate limit. |
| `GET /auth/refresh-and-return` | Middleware's silent-renew redirect for web pages. Cookie only. | Web only. |
| `POST /auth/logout` (`logout/route.ts`) | Takes the user ID from the Bearer or cookie access token, falling back to the **cookie** refresh token, never the body. Calls `bumpTokenVersion` and clears cookies. | This is **logout-all**. A body `refreshToken` is ignored. |
| `GET /auth/me` (`me/route.ts`) | `withApi({auth:true})`. Returns `{id, name, email, phone, role, organizationId, status, organizationIdToken, staffId, individualId, permissions}`. `permissions` is only present for active staff. | For owners, `organizationId` is the *User* field, which register never sets, so it is `null`. The real org ID is in `organizationIdToken`. There is no `cardId`, `assignedCardIds` or organization name. |
| `GET /auth/session-status` | Internal to Edge middleware. Requires the `x-cogcard-internal-secret` header (`lib/middleware-internal.ts`). Uniform `{ok:false}` 401 on failure. | **Not usable by clients.** |
| `POST /auth/forgot-password` | Generic `"If that email exists…"` response. 5/min/IP, plus one token issued per email per 15 min and 5 per day (`lib/password-reset.ts`). Token is a 32-byte base64url value, stored as SHA-256, TTL **1h**. Earlier unused tokens are deleted when a new one is issued. Link is `${NEXT_PUBLIC_APP_URL}/?resetToken=<raw>`. | The link points at the web root, not an app route. Email subject still says "Coglink". |
| `POST /auth/reset-password` | `{token, newPassword≥6}`. Claims the token atomically with `findOneAndUpdate(usedAt:null, expiresAt>now)`, sets the password, burns the user's other tokens, and calls `bumpTokenVersion`. 10/min/IP. | Does **not** clear `lockUntil` or `failedLoginAttempts`. Does not check user status. |
| `POST /auth/change-password` | `withApi({auth:true})`, `{currentPassword, newPassword≥6}`. Wrong current password gives **401**. Then the password is set, reset tokens are burned, **`bumpTokenVersion`** runs, and fresh tokens go out **as cookies only**. | No rate limit, and wrong attempts don't count toward lockout. A stolen access token can therefore brute-force the current password. |

### 2.4 Lockout

`lib/login-lockout.ts`: 5 failures lock the account for 15 minutes, then the counter resets. The counter is shared by `/login` and `/staff-login`. Three problems:
- Anyone can lock any account by sending 5 bad passwords (no per-IP-and-account scoping).
- The lock is revealed through the 423 status before the password is checked.
- A password reset doesn't unlock the account.

### 2.5 CSRF, SameSite, headers

- **There is no CSRF token and no Origin or Referer check anywhere.** `grep csrf|origin|sec-fetch` returns nothing. Web cookie auth relies on `SameSite=Lax` alone. Lax blocks cross-site POSTs from carrying cookies, but not same-site subdomain requests. Audit 07 should check whether user-controlled content can be served from `*.{ROOT_DOMAIN}`.
- No CORS headers are configured (`next.config.ts`), so cross-origin JavaScript cannot read API responses. That doesn't matter for native clients.
- **Bearer-authenticated requests are inherently CSRF-immune.** That is why native token mode must never fall back to cookies.
- **Custom headers:** the backend reads only `x-cogcard-internal-secret`, a server-to-server middleware secret. **No backend code reads `x-bizzvot-session`, `x-bizzvot-client`, or any `x-cogcard-session` header.** The app's `x-bizzvot-session: org` (`api_client.dart:227`) and `x-bizzvot-client: mobile` (`auth_repository.dart:55`) are ignored.
- The Edge middleware (`middleware.ts`) gates only page routes (`/super-admin`, `/organization`, `/staff`, `/individual`). API routes enforce auth themselves through `withApi` and `requireAuth`.

### 2.6 Rate limits (auth)

`rateLimit()` in `lib/api.ts:90-96` uses Redis when it is configured and falls back to an in-memory map per instance. The IP comes from `getRateLimitIdentity` (`lib/middleware/ipHash.ts`). If the IP can't be resolved, every request falls into one shared `"unresolved"` bucket.

| Endpoint | Limit | Per-account | `Retry-After` |
|---|---|---|---|
| login | 20/min/IP | lockout only | no |
| staff-login | 20/min/IP | lockout only | no |
| register | 5/min/IP | n/a | no |
| forgot-password | 5/min/IP | 1 per 15 min, 5 per day | no |
| reset-password | 10/min/IP | n/a | no |
| refresh | **none** | none | n/a |
| logout | **none** | none | n/a |
| me | **none** | none | n/a |
| change-password | **none** | **none** | n/a |

Risks:
- Mobile users behind carrier-grade NAT share IPs, so a 20/min IP limit can hit real users.
- If `TRUST_PROXY` or `TRUSTED_PROXY_HOPS` is misconfigured, login is capped at 20/min for **everyone**, because all traffic lands in the shared `"unresolved"` bucket.

### 2.7 Account deletion

There is none. No `app/api/v1/auth/account` route exists, and no user self-delete exists anywhere (`find app/api -type d | grep account` returns nothing). The app's `DELETE /auth/account` (`lib/features/account/data/account_repository.dart`) will get a 404 from Next.js.

### 2.8 Stale backend docs and scripts

- `project-docs/05-API/openapi.yaml:41` says register returns `accessToken + refreshToken`. That is no longer true.
- `scripts/smoke-menus.sh:31` reads `j.data.accessToken`. It is broken since `jsonOkWithAuth` started stripping tokens.

---

## 3. Current state (app)

| File | Behaviour |
|---|---|
| `lib/core/api/api_client.dart` | `AuthInterceptor.onRequest` adds `Authorization: Bearer` and `x-bizzvot-session: org` to every non-anonymous request, for staff as well as owners. `onError`: a 401 that isn't anonymous, `noRefresh`, already retried, or on the refresh path triggers one shared in-flight refresh and a single retry. **Any** refresh exception, including a network error, leads to `_expire()`, which wipes tokens. |
| `lib/core/auth/auth_repository.dart` | `parseTokens` accepts `data.{accessToken\|access_token\|token}` or `data.tokens.*`. Login sends `{email, password}`, which is correct. Register sends `{organizationName, name, email, password, phone}` **with no `role`**. Reset sends `{token, password}`, **but the backend expects `newPassword`**. Logout sends `{refreshToken}`, which is ignored, and is `noRefresh`. Change-password ignores the response. After login, if `super_admin`, it clears local tokens only and leaves the server session alive. `buildRefresh` posts `{refreshToken}` and keeps the old refresh token if the server doesn't rotate it. |
| `lib/core/auth/auth_user.dart` | `UserRole` has `owner/staff/customer/superAdmin/unknown`. **`organization` and `individual` both become `unknown`.** Reads `organizationId`, `organizationName`, `cardId` and `permissions`. |
| `lib/core/auth/session_controller.dart` | Restore: if tokens exist, call `me()`. A network error leaves the user `SignedOut` but keeps the tokens. Any other error triggers logout and `SignedOut(expired)`. |
| `lib/core/secure_storage/token_store.dart` | Keychain (`first_unlock_this_device`) or Keystore through `flutter_secure_storage`. Writes are not atomic: two keys written one after the other. |
| `lib/app/router.dart:91-95` | `homeFor`: `owner` goes to the dashboard, `staff` to their card, **anything else to the unsupported screen**. |
| `lib/features/auth/domain/auth_errors.dart` | Generic invalid-credential message for 401, 403 and 423. This is the correct UI behaviour. Portal and admin detection uses `error.code` (which the backend never sends) or regexes on the message. |
| `lib/core/utilities/validators.dart:18-22` | Password minimum is 8. The backend minimum is 6. |
| `android/app/src/main/AndroidManifest.xml:33-39` | App Links only for `https://bizzvot.com/card/` and `/directory/`. |
| `ios/` | No `.entitlements` file and no `applinks:` entry. |
| `test/core/auth_test.dart:55,65` | Fixtures use `role: 'owner'`, which the backend never sends, so the role bug is invisible to tests. |

---

## 4. Gap table

Severity: **C** blocks release, **H** security or major functional issue, **M** should fix before GA, **L** hygiene.

| # | Sev | Area | Gap (verified) | Fix | Owner |
|---|---|---|---|---|---|
| G1 | C | Native session | Tokens are stripped from JSON (`lib/api.ts:15-27`). The app cannot establish a session. | Token mode (§5): `x-bizzvot-client: mobile` returns `data.tokens`, no cookies. | Backend |
| G2 | C | Roles | Backend role `organization` maps to `UserRole.unknown`, so owners see the unsupported screen (`auth_user.dart:10-17`, `router.dart:91`). | Map `'organization'` to `owner`. Add `UserRole.individual`. Fix the test fixtures. | App |
| G3 | C | Register | App omits the required `role`, so the result is always 400 (`register/route.ts:18` vs `auth_repository.dart:40-46`). | Send `'role': 'organization'`. | App |
| G4 | C | Reset password | App sends `password`, backend reads `newPassword`, so the result is always 400 "Invalid input" (`reset-password/route.ts:10-13` vs `auth_repository.dart:149`). | Rename the field to `newPassword`. | App |
| G5 | H | Refresh | Stateless refresh JWT. Old tokens stay valid for 30 days, there is no reuse detection, no per-device revocation, and no rate limit (`refresh/route.ts`). | `RefreshSession` collection with rotation, family revocation on reuse, rate limit (§5). | Backend |
| G6 | H | Logout | Logout calls `bumpTokenVersion` = logout on every device, web included. A body `refreshToken` is ignored. With an expired access token the server revokes nothing (`logout/route.ts:18-40`). | Token mode: revoke only the presented refresh family. Add `POST /auth/logout-all`. | Backend |
| G7 | H | Change password | Bumps `tokenVersion` and sends new tokens as cookies only, so the mobile user is force-logged-out (`change-password/route.ts:30-38`). | Token mode: return new `data.tokens` and revoke the *other* sessions. App stores the returned tokens. | Both |
| G8 | H | super_admin | `/auth/login` accepts `super_admin`. The app's check happens after the server session is created and never revokes it (`auth_repository.dart:97-105`). The web admin also uses `/auth/login` (`app/page.tsx:103`). | Add `/auth/admin-login` for web. `/auth/login` returns 403 `ADMIN_LOGIN_REQUIRED` *after* the password check. App calls `logout()` before wiping. | Both |
| G9 | H | Enumeration | 423 (locked) and 403 (suspended) are returned **before** the password check. Unknown users skip bcrypt (timing). Register 409 confirms registered emails. | Run a dummy bcrypt for unknown users. Return generic 401 `INVALID_CREDENTIALS` for unknown, locked and bad-password cases. Only reveal suspension after a correct password. Register: accept the 409 under rate limit, or move to email verification. | Backend |
| G10 | H | Lockout | Anyone can lock any account for 15 minutes. Reset doesn't unlock. Change-password failures aren't counted and aren't rate limited. | Key the lock on account plus IP, or use progressive delay. Clear the lock on a successful reset. Rate-limit change-password (5 per 15 min per user) and count its failures. | Backend |
| G11 | H | Reset deep link | Email link is `/?resetToken=` on the web root. App route is `/reset-password?token=`. No App Link or Universal Link covers that path. The live portal is `https://www.bizzvot.com` (`docs/audit/README.md`), but the manifest only claims `bizzvot.com`, without `www`. | Link to `https://www.bizzvot.com/reset-password?token=…`. Claim **both** `bizzvot.com` and `www.bizzvot.com` with an Android intent-filter path and iOS `applinks:`, publish AASA and assetlinks on both hosts, and add a web fallback page at that path. | Both |
| G12 | H | Account deletion | `DELETE /auth/account` doesn't exist. App Store 5.1.1(v) requires in-app deletion. | Implement it (§5.8). | Backend |
| G13 | M | `/auth/me` | Owner `organizationId` is `null` (the real value is in `organizationIdToken`). No `cardId` or `assignedCardIds`, no org name. | Return the resolved `organizationId`, `organization:{id,name,slug,status}`, `assignedCardIds`, `cardId`. App: fall back to `organizationIdToken` and `assignedCardIds[0]`. | Both |
| G14 | M | Individual accounts | The backend supports `individual` registration and login. The app has no role for it and no product decision. | Decide: block in the app (403 `UNSUPPORTED_ACCOUNT_TYPE` in token mode), or add an individual home. Until then, map it to a clear "use the web" screen. | Product, App |
| G15 | M | Refresh resilience | The app wipes tokens on **any** refresh error, including offline (`api_client.dart:288-290`). | Expire only on a 401 or 403 from refresh. Rethrow network errors and keep the tokens. | App |
| G16 | M | Redundant refresh | Parallel 401s that land after the shared refresh finishes start a second refresh. With rotation and reuse detection this raises the risk of false reuse alerts. | Before refreshing, compare the request's bearer with the stored access token. If they differ, retry with the stored token. | App |
| G17 | M | Error codes | Errors are `{success:false, error:"<string>"}` with no codes. The app reads `code` only from an `error` object. AUTH-4's `ACCOUNT_IS_STAFF` isn't in the app's code sets. | Backend: add a top-level `code` (non-breaking for web, which reads `json.error`). App: also read `body['code']`. Agree on the code list (§5.6). | Both |
| G18 | M | Rate limits | refresh, me, logout and change-password have none. No `Retry-After`. IP-only limits misfire on carrier-grade NAT, and the "unresolved" bucket is global. | Add limits (§5.7). Send `Retry-After` on 429. Add per-account keys. Verify `TRUST_PROXY` in production. | Backend |
| G19 | M | Wrong current password = 401 | The interceptor treats it as session expiry, so it refreshes and retries for nothing. | Backend: 400 `INVALID_CURRENT_PASSWORD`. App: send change-password with `noRefresh`. | Both |
| G20 | M | Headers | `x-bizzvot-session: org` is unused by the backend and is also sent for staff. | Drop it, or have the backend define it. Keep `x-bizzvot-client: mobile` as the token-mode switch. | Both |
| G21 | M | Owner/staff separation | Staff can sign in through `/auth/login`. The app shows no portal guidance. | Token mode `/auth/login`: staff gets 403 `USE_STAFF_LOGIN` after the password check. `/staff-login`: a non-staff user with a correct password gets 403 `USE_OWNER_LOGIN`. | Backend |
| G22 | M | CSRF (web) | Only `SameSite=Lax` protects cookie auth. No Origin check. | Check Origin/`Sec-Fetch-Site` on cookie-authenticated unsafe methods. Token mode ignores cookies. | Backend |
| G23 | L | Password policy | Backend minimum 6 (web form 6), app minimum 8. No maximum length (bcrypt truncates at 72 bytes). | Backend minimum 8, maximum 128, everywhere. | Backend |
| G24 | L | JWT hygiene | No `algorithms` pin, no `typ`, `aud` or `jti`. Access TTL of 1h is long for mobile. | `algorithms:['HS256']`, `typ:'access'`, `aud`, `sid`. Mobile access TTL 15 minutes. | Backend |
| G25 | L | `sessionStatus` endpoint in app | It requires the internal secret, so the app can never use it. | Remove `Endpoints.sessionStatus`. | App |
| G26 | L | Token store | Two-key write isn't atomic, so a crash mid-rotation can store a mismatched pair. | Store a single JSON blob under one key. | App |
| G27 | L | Stale docs | OpenAPI and `smoke-menus.sh` still assume tokens in JSON. | Update them after §5. | Backend |
| G28 | L | Branding | Reset email says "Coglink password reset". | Use Bizzvot branding. | Backend |

---

## 5. Backend design: native token mode

Goal: give the native app Bearer access tokens and rotating refresh tokens, without weakening the web cookie model and without new paths for the existing flows.

### 5.1 Mode selection

New file `lib/client-mode.ts`:
```ts
import type { NextRequest } from "next/server";
/** Native token mode: tokens in JSON, cookies never read or set. */
export function isNativeClient(req: NextRequest): boolean {
  return req.headers.get("x-bizzvot-client") === "mobile";
}
```
Rules in token mode:
- **Never read** `cogcard_*` cookies.
- **Never set** them.
- Always respond with `Cache-Control: no-store`.

This keeps XSS on the web origin from turning the cookie refresh into a readable token: a script adding the header still gets nothing without a body `refreshToken`. Web behaviour does not change.

### 5.2 Storage model

New file `lib/models/RefreshSession.ts`:
```ts
const RefreshSessionSchema = new Schema({
  userId:        { type: ObjectId, ref: "User", required: true, index: true },
  familyId:      { type: String, required: true, index: true },   // = `sid`, stable per device login
  tokenHash:     { type: String, required: true, unique: true },  // sha256(raw)
  parentId:      { type: ObjectId, default: null },
  replacedBy:    { type: ObjectId, default: null },
  rotatedAt:     { type: Date, default: null },                   // set when this token is used
  revokedAt:     { type: Date, default: null },
  revokeReason:  { type: String, enum: ["logout","logout_all","password_change","password_reset",
                                        "reuse_detected","admin","account_deleted","suspended"], default: null },
  tokenVersion:  { type: Number, required: true },                // User.tokenVersion at issue
  familyCreatedAt: { type: Date, required: true },                // absolute lifetime cap
  expiresAt:     { type: Date, required: true },                  // sliding 30d
  lastUsedAt:    Date,
  device:        { platform: String, model: String, appVersion: String, name: String },
  ipHash:        String,
}, { timestamps: true });
RefreshSessionSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 7 * 86400 }); // keep 7d for reuse forensics
RefreshSessionSchema.index({ userId: 1, revokedAt: 1 });
```
- Raw token: `rt_` followed by `randomBytes(32).toString("base64url")`. It is opaque, not a JWT, so it can't be verified offline or confused with an access token.
- Lifetimes: access **15 min** in token mode. Refresh sliding **30 d**. Family absolute cap **90 d**, after which the user signs in again.

### 5.3 Library

New file `lib/refresh-sessions.ts` (sketch):
```ts
const GRACE_MS = 20_000; // tolerate app killed mid-rotation / duplicate in-flight refresh

export async function createSession(user, req, device) { /* new familyId=randomUUID(); insert; return {raw, familyId} */ }

export async function rotate(raw: string, req: NextRequest) {
  const tokenHash = sha256(raw);
  const now = new Date();
  const cur = await RefreshSession.findOneAndUpdate(
    { tokenHash, rotatedAt: null, revokedAt: null, expiresAt: { $gt: now } },
    { $set: { rotatedAt: now, lastUsedAt: now } },
    { new: true }
  );
  if (!cur) {
    const prior = await RefreshSession.findOne({ tokenHash });
    if (!prior || prior.revokedAt || prior.expiresAt <= now)
      throw new AuthError("Session expired", 401, "INVALID_REFRESH");
    // Already rotated: reuse.
    const child = prior.replacedBy && await RefreshSession.findById(prior.replacedBy);
    if (now.getTime() - prior.rotatedAt!.getTime() < GRACE_MS && child && !child.rotatedAt && !child.revokedAt) {
      await revoke(child._id, "reuse_detected");          // drop the lost child only
      return issueChild(prior, now, req);                 // re-issue a sibling
    }
    await revokeFamily(prior.familyId, "reuse_detected"); // token theft signal
    await notify(prior.userId, "security", "A sign-in on another device was ended for your safety.");
    throw new AuthError("Session expired", 401, "REFRESH_REUSED");
  }
  const user = await User.findById(cur.userId).select("status tokenVersion");
  if (!user || user.status !== "active" || user.tokenVersion !== cur.tokenVersion ||
      now.getTime() - cur.familyCreatedAt.getTime() > 90 * 86400_000) {
    await revokeFamily(cur.familyId, "logout_all");
    throw new AuthError("Session expired", 401, "SESSION_REVOKED");
  }
  return issueChild(cur, now, req); // insert child {familyId, parentId:cur._id}, set cur.replacedBy
}

export async function revokeFamily(familyId: string, reason: string) {
  await RefreshSession.updateMany({ familyId, revokedAt: null }, { $set: { revokedAt: new Date(), revokeReason: reason } });
  await redisSetEx(`sidrev:${familyId}`, 15 * 60, "1"); // kill outstanding access tokens fast
}
export async function revokeAllForUser(userId: string, reason: string, exceptFamilyId?: string) { /* updateMany + per-family redis flag */ }
```

### 5.4 Changes to existing files

- **`lib/types.ts`**: add `sid?: string; typ?: "access" | "refresh"` to `JwtPayload`.
- **`lib/auth.ts`**:
  - `signAccessToken(payload, ttl = ACCESS_TTL)` adds `typ:"access"`.
  - Verify with `{ algorithms: ["HS256"] }`.
  - Inside `requireAuth`: if `payload.sid` is set, reject when `redisGet("sidrev:"+sid)` is set. If Redis is unavailable, fall back to a DB check of `RefreshSession.exists({familyId:sid, revokedAt:null})`, cached for 30s.
  - Add an optional `code` to `AuthError`.
- **`lib/api.ts`**:
  - `handleApiError` passes `{ code }` through `jsonError` extra. The envelope becomes `{success:false, error:"…", code:"…"}`, which is non-breaking for web.
  - New `jsonOkWithTokens(data, tokens, status)`, which sets no cookies and adds `Cache-Control: no-store`.
  - New `respondAuth(req, issued, extra)` that calls `jsonOkWithTokens` in token mode and `jsonOkWithAuth` otherwise.
  - 429 responses carry `Retry-After`.
- **`lib/auth-tokens.ts`**: `issueTokensForUser(userId, { sid?, accessTtl? })` adds `sid`. In token mode, skip `signRefreshToken`.
- **`login/route.ts`, `staff-login/route.ts`**:
  1. Rate limit per IP and per `sha256(email)`.
  2. Look up the user. If not found, run `verifyPassword(pw, DUMMY_HASH)` and return 401 `INVALID_CREDENTIALS`.
  3. If locked, still run bcrypt and return 401 `INVALID_CREDENTIALS`. Do not return 423.
  4. Bad password: `recordFailedLogin`, then 401 `INVALID_CREDENTIALS`.
  5. Then check status: 403 `ACCOUNT_SUSPENDED`.
  6. Then check role:
     - `/login`: `super_admin` gets 403 `ADMIN_LOGIN_REQUIRED` "Use the admin sign-in page". In token mode, `staff` gets 403 `USE_STAFF_LOGIN` and `individual` gets 403 `UNSUPPORTED_ACCOUNT_TYPE` (until the product decision in G14).
     - `/staff-login`: a non-staff user gets 403 `USE_OWNER_LOGIN`.
  7. `clearFailedLogin`. In token mode, `createSession` then `respondAuth`.
- **New `app/api/v1/auth/admin-login/route.ts`**: the super_admin-only twin used by `app/page.tsx` for the admin console. Ship it before tightening `/login`.
- **`register/route.ts`**: in token mode, call `createSession` and return tokens. Raise the password minimum to 8.
- **`refresh/route.ts`**: in token mode, the body `refreshToken` is required (cookie ignored), then `rotate()`. Rate limit 30/min per IP and 10/min per family. The web path stays as it is.
- **`logout/route.ts`**: in token mode, take `{refreshToken}`, call `revokeFamily(familyId,"logout")`, and **do not** bump `tokenVersion`. Always return 200, even for an unknown token. New `logout-all/route.ts` calls `bumpTokenVersion` and `revokeAllForUser`.
- **`change-password/route.ts`**:
  - Wrong current password: 400 `INVALID_CURRENT_PASSWORD` and count it toward lockout.
  - Rate limit 5 per 15 min per user.
  - On success: `bumpTokenVersion`, `revokeAllForUser(sub,"password_change", exceptFamily = payload.sid)`.
  - In token mode, issue a new access token and re-stamp the current family's `tokenVersion` by rotating it, then return `data.tokens`.
- **`reset-password/route.ts`**:
  - Also call `revokeAllForUser(...,"password_reset")` and `clearFailedLogin(user)`.
  - Reject if user status isn't active (generic 400).
  - Raise the minimum to 8.
  - Return code `INVALID_RESET_TOKEN` on a bad token.
- **`forgot-password/route.ts`**:
  - `resetUrl = ${PUBLIC_WEB_URL}/reset-password?token=${raw}`, a path both the web and the app claim.
  - Add a web page `app/reset-password/page.tsx` as the fallback.
  - Keep TTL at 1h and single use.
  - Bizzvot branding.
- **New `sessions/route.ts`** (GET, list the user's active families with device and last-used) and **`sessions/[id]/route.ts`** (DELETE, revoke one). Optional for v1, but cheap.

### 5.5 Wire contract (token mode)

All requests send `x-bizzvot-client: mobile` and `Content-Type: application/json`.

`POST /api/v1/auth/login` (and `/staff-login`, `/register` with 201):
```json
// request
{ "email": "a@b.co", "password": "••••••••",
  "device": { "platform": "ios", "model": "iPhone15,2", "appVersion": "1.0.0", "name": "Anil's iPhone" } }
// 200
{ "success": true,
  "data": {
    "user": { "id": "…", "name": "…", "email": "…", "role": "organization",
              "organizationId": "…", "staffId": null, "individualId": null },
    "tokens": { "tokenType": "Bearer", "accessToken": "eyJ…", "expiresIn": 900,
                "accessTokenExpiresAt": "2026-10-11T10:15:00Z",
                "refreshToken": "rt_…", "refreshTokenExpiresAt": "2026-11-10T10:00:00Z",
                "sessionId": "5b0c…" } } }
// 401
{ "success": false, "error": "The email or password is incorrect.", "code": "INVALID_CREDENTIALS" }
// 403
{ "success": false, "error": "Use the admin sign-in page", "code": "ADMIN_LOGIN_REQUIRED" }
// 429 + Retry-After: 60
{ "success": false, "error": "Too many requests", "code": "RATE_LIMITED" }
```
`POST /api/v1/auth/refresh`: request `{ "refreshToken": "rt_…" }`. The 200 response has the same `data.tokens` shape plus `user`. A 401 carries code `INVALID_REFRESH`, `REFRESH_REUSED` or `SESSION_REVOKED`.

`POST /api/v1/auth/logout`: request `{ "refreshToken": "rt_…" }` (Bearer optional). Response is always `200 { success:true, data:{message:"Logged out"} }`.

`POST /api/v1/auth/change-password` (Bearer): request `{ "currentPassword": "…", "newPassword": "…" }`. Response 200 `{ data: { message, user, tokens } }`, or 400 `INVALID_CURRENT_PASSWORD`.

`POST /api/v1/auth/reset-password`: request `{ "token": "…", "newPassword": "…" }`. Response 200, or 400 `INVALID_RESET_TOKEN`.

`GET /api/v1/auth/me` (Bearer), extended:
```json
{ "success": true, "data": {
  "id": "…", "name": "…", "email": "…", "phone": "…", "role": "organization|staff|individual",
  "status": "active", "organizationId": "<resolved for owners too>",
  "organization": { "id": "…", "name": "Acme", "slug": "acme", "status": "active" },
  "staffId": null, "individualId": null,
  "assignedCardIds": ["…"], "cardId": "…",
  "permissions": { "editCard": true, "viewReviews": true, "replyReviews": false, "manageLinks": true } } }
```
Keep `organizationIdToken` for one release for web compatibility.

### 5.6 Error code list

`INVALID_CREDENTIALS`, `ACCOUNT_SUSPENDED`, `USE_STAFF_LOGIN`, `USE_OWNER_LOGIN`, `ADMIN_LOGIN_REQUIRED`, `UNSUPPORTED_ACCOUNT_TYPE`, `EMAIL_TAKEN`, `RATE_LIMITED`, `INVALID_REFRESH`, `REFRESH_REUSED`, `SESSION_REVOKED`, `UNAUTHENTICATED`, `INVALID_RESET_TOKEN`, `INVALID_CURRENT_PASSWORD`, `PASSWORD_TOO_WEAK`, `VALIDATION_FAILED`.

### 5.7 Rate limits (target)

| Endpoint | Per IP | Per account or key |
|---|---|---|
| login / staff-login / admin-login | 20/min | 10 per 15 min per email hash, plus soft lock with progressive delay (no hard 15-min lock that anyone can trigger) |
| register | 5/min | 3/day per email hash |
| refresh | 30/min | 10/min per family |
| change-password | n/a | 5 per 15 min per user |
| forgot / reset | as today | as today |
| account delete | n/a | 5/hour per user |

All 429 responses include `Retry-After`.

### 5.8 Account deletion

`DELETE /api/v1/auth/account`, Bearer. Request body `{ password, confirm: "DELETE", reason? }`.

Who can call it:
- `organization` and `individual` users.
- `staff` gets 403 `STAFF_CANNOT_SELF_DELETE`, because staff are removed by the owner.
- `super_admin` gets 403.

What it does:
1. Verifies the password. Failures count toward the change-password limit.
2. Marks `User.status = "deleted"` and `deletionRequestedAt`. Mark the organization or individual and its staff as suspended.
3. Disables public cards.
4. Calls `bumpTokenVersion` and `revokeAllForUser(...,"account_deleted")`.
5. Cancels renewals per policy.
6. Queues a purge job per the retention policy.
7. Returns `202 { data: { deletionScheduledAt } }`.

Data scope and retention belong to audits 03 and 07.

### 5.9 Tests to add (backend, vitest)

- Rotation issues a new token. Reusing the old one inside the grace window issues a sibling. Reusing it after the grace window revokes the family, and the access token carrying `sid` is rejected.
- Logout in token mode leaves a second device's session working.
- Change-password keeps the current device signed in and revokes the others.
- Locked, unknown and wrong-password cases all return an identical 401 body.
- `super_admin` is rejected on `/login` and accepted on `/admin-login`.
- Token mode ignores cookies on refresh.
- 429 includes `Retry-After`.

---

## 6. Exact app-side changes

1. **`lib/core/auth/auth_user.dart`**
   - `UserRole.parse`: add `'organization' => UserRole.owner` and a new `UserRole.individual` (`'individual'`).
   - `organizationId`: `str(j['organizationId']) ?? str(j['organizationIdToken']) ?? …`.
   - `cardId`: also read `(j['assignedCardIds'] as List?)?.firstOrNull`.
   - Read `organization.name` (already supported once the backend sends it).
2. **`lib/app/router.dart` `homeFor`**: route `UserRole.individual` to a dedicated "use the web dashboard" screen until the product decides (G14), rather than the generic unsupported screen.
3. **`lib/core/auth/auth_repository.dart`**
   - `RegisterRequest.toJson`: add `'role': 'organization'`. Add an optional `industry`.
   - `resetPassword`: body `{'token': token, 'newPassword': password}`.
   - `changePassword`: pass `noRefresh: true`, parse the response with `parseTokens` and `_store.write()` when tokens are present.
   - `_establish`: when the role is `superAdmin` (or `individual`, if blocked), call `logout()` (server revoke) and not only `_store.clear()`.
   - Login and register bodies: add `device: {platform, model, appVersion}`.
   - Keep `_nativeHeaders = {'x-bizzvot-client': 'mobile'}`. This is now the agreed switch.
   - `buildRefresh`: on 401 or 403 return `null`. On any other `DioException`, **rethrow as `AppException(network)`** without clearing tokens. Drop the "keep old refresh token" fallback once rotation is guaranteed, and treat a missing `refreshToken` in the response as an error.
4. **`lib/core/api/api_client.dart`**
   - Remove `options.headers['x-bizzvot-session'] = 'org'` (G20), unless the backend formally adopts it.
   - In `onError`, before refreshing: if `opts.headers['Authorization'] != 'Bearer ${current.accessToken}'`, retry immediately with the stored token (G16).
   - In `_refreshOnce`, call `_expire()` only when `refresh` returned `null` (a definitive 401 or 403), not on a network exception (G15).
   - `AppException._parseErrorBody`: also read the top-level `data['code']` (G17).
5. **`lib/features/auth/domain/auth_errors.dart`**:
   - Add `ACCOUNT_IS_STAFF` to `_staffCodes`, or better, align the register to the §5.6 list.
   - Map `INVALID_RESET_TOKEN` in `isInvalidResetToken`.
   - Map `UNSUPPORTED_ACCOUNT_TYPE` to a dedicated message.
6. **`lib/core/secure_storage/token_store.dart`**: store one JSON value (`{a, r, exp}`) under a single key so rotation writes are atomic (G26). Optionally keep `accessTokenExpiresAt` to refresh ahead of time.
7. **`lib/core/api/endpoints.dart`**:
   - Remove `sessionStatus`.
   - Add `logoutAll = '/auth/logout-all'`, and later `sessions`.
   - Keep `deleteAccount = '/auth/account'`, now specified in §5.8.
8. **Deep links**:
   - `android/app/src/main/AndroidManifest.xml`: add `<data android:scheme="https" android:host="bizzvot.com" android:pathPrefix="/reset-password"/>`, plus the same entry for `www.bizzvot.com`. The existing `/card/` and `/directory/` entries also need `www`.
   - iOS: add `Runner.entitlements` with `com.apple.developer.associated-domains = [applinks:bizzvot.com, applinks:www.bizzvot.com]`.
   - Web: publish `/.well-known/assetlinks.json` and `apple-app-site-association` including `/reset-password*`. Coordinate with audit 06.
9. **Tests**:
   - `test/core/auth_test.dart`: replace the `role: 'owner'` fixtures with real backend payloads (`role: 'organization'`, `organizationIdToken`, `assignedCardIds`).
   - Add cases: register body includes `role`, reset body uses `newPassword`, a network error during refresh keeps tokens, change-password stores the returned tokens.
10. **Validators**: keep the minimum of 8, and match the backend once G23 lands.

---

## 7. Quick answers to the brief

- **Can a native app authenticate today?** Only by scraping `Set-Cookie`. Login responses do carry `cogcard_token` and `cogcard_refresh` headers, `requireAuth` accepts Bearer, and `/refresh` accepts a body token. PRODUCT_PLAN §4.2 forbids client workarounds, and that path still has non-rotating, logout-everywhere semantics. As built, the app cannot sign in.
- **Minimal backend change:** token mode on the existing routes, switched by `x-bizzvot-client: mobile`, plus the `RefreshSession` collection and a `sid` claim (§5). That is roughly 2 new libraries, 1 model, 1 new admin-login route, and edits to 8 auth routes, `lib/api.ts`, `lib/auth.ts` and `lib/auth-tokens.ts`.
- **`x-bizzvot-session: org`:** not used by the backend. Nothing reads any `x-bizzvot-*` or `x-cogcard-*` client header. The only custom header is the server-to-server `x-cogcard-internal-secret`.
- **Account deletion:** does not exist.
