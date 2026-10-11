# 01 — API contract reconciliation (mobile app ↔ Coglink `/api/v1`)

Auditor: agent 01 of 10. Read-only audit. Date: 2026-10-11.

Scope: every path in `lib/core/api/endpoints.dart`, checked against the backend route handlers in
`/home/user/cogcard/app/api/v1/**/route.ts`, their Zod/inline validation (`lib/validation/card.ts`),
models (`lib/models/*.ts`), response helpers (`lib/api.ts`, `lib/pagination.ts`, `lib/publicCard.ts`)
and the app callers in `lib/features/*/data/*.dart`, `lib/core/auth/*`, `lib/shared/models/*`.

Paths below: **app** = `/home/user/Bizzvot-apps-`, **be** = `/home/user/cogcard`.

---

## 1. Executive summary — top 10 gaps by severity

| # | Sev | Gap | Evidence |
|---|---|---|---|
| 1 | **P0 – blocks all sign-in** | Login, staff login, register, refresh and change-password **remove tokens from the JSON body** and only set httpOnly cookies. The app needs `data.accessToken`/`data.refreshToken`, so every sign-in ends in `NATIVE_SESSION_UNSUPPORTED`. Refresh with a body token is accepted, but the response also has no tokens. The backend ignores `x-bizzvot-client: mobile` (no code reads it). | be `lib/api.ts:15-27` (`jsonOkWithAuth` strips `accessToken`, `refreshToken`); be `app/api/v1/auth/{login,staff-login,register,refresh,change-password}/route.ts`; app `lib/core/auth/auth_repository.dart` `_establish()`, `parseTokens()` |
| 2 | **P0 – owners locked out** | The backend role for an owner is **`"organization"`**, but the app's `UserRole.parse` only maps `owner/org_owner/organization_owner/admin`. An owner who gets past #1 becomes `UserRole.unknown`, and the router sends them to `Routes.unsupported`. | be `lib/types.ts` (`UserRole = "super_admin" \| "organization" \| "staff" \| "individual"`), be `lib/models/User.ts`; app `lib/core/auth/auth_user.dart:10-17`; app `lib/app/router.dart` `homeFor()` |
| 3 | **P0 – staff card flow** | The app calls `GET/PATCH /staff/card` (singular), which does not exist. The backend has `GET /staff/cards` (array of assigned cards), `PATCH /staff/cards/:id` and `GET /cards/:id` (works for an assigned staff member). `/auth/me` returns no `cardId`. Staff can hold **many** cards (`assignedCardIds[]`). | be `app/api/v1/staff/cards/route.ts`, `staff/cards/[id]/route.ts`, `cards/[id]/route.ts`, `auth/me/route.ts`, `lib/models/Staff.ts`; app `lib/core/api/endpoints.dart` `staffCard`, `lib/features/cards/data/cards_repository.dart` `staffCard()/updateStaffCard()` |
| 4 | **P0 – card editor writes fail or are silently lost** | Field names differ (`company`↔`companyName`, `profilePhoto`↔`photo`, `template`/`brandColor`/`sectionOrder`↔`theme.{templateId,primaryColor,sectionOrder}`, `displayToggles`↔`displayOptions`, link `type`↔`platform`). The owner route **silently strips** unknown keys and returns 200. Some patches get a **400**: links without `platform`, a custom link without `label`, `title: null`. The staff schema is `.strict()`, so any unknown key returns 400. | be `lib/validation/card.ts` (`cardWriteSchema`, `socialLinkSchema` requires `platform`, `customLinkSchema` requires `label`, `staffCardWriteSchema …strict()` line 120); app `lib/shared/models/card.dart:67, 256-290`; app `lib/features/cards/domain/card_edit_sections.dart` `buildCardPatch` (blank → `null`) |
| 5 | **P0 – Google review products** | The public review submit sends `{rating, name, comment}`, but the backend requires **`reviewerName`**, so every submission gets a 400. There is also no `googleReviewUrl` field on `Card` at all, yet the Google Review Stand/Card products (₹499/₹350) depend on it. | be `app/api/v1/public/card/[slug]/review/route.ts` (schema), be `lib/models/Card.ts`; app `lib/features/public_card/domain/public_review.dart:58-62` |
| 6 | **P1 – endpoints the spec calls "existing" are missing** | None of these exist anywhere in the backend: `PATCH /organization/cards/status`, `GET /organization/cards/qrcodes`, `POST /cards/:id/media`, `DELETE /cards/:id/library`, `GET/POST /organization/billing`. There is no billing, trial, seat or Stripe code (the backend docs list Stripe as out of scope). | be `find app/api -name route.ts` (full list in §3); be `project-docs/06-Audit/POST-REMEDIATION-AUDIT-2026-08-02.md:19,67`; app `docs/PRODUCT_PLAN.md` §6.3, §11.1 |
| 7 | **P1 – privacy settings silently not applied** | `directoryVisibility` (org) and `visibility` (card) do not exist in the models. The PATCH routes ignore or strip them and return 200, so the app tells the owner the change succeeded. Card `privateDetails` (bloodGroup/fatherName/motherName), `companyPhone`, `gallery/pdfs/videos` and `disabledByBilling` also do not exist and are dropped. | be `lib/models/Organization.ts`, `lib/models/Card.ts`, `organization/profile/route.ts:24` (allow-list), `lib/validation/card.ts`; app `lib/features/directory_visibility/data/directory_visibility_repository.dart` |
| 8 | **P1 – wrong method / body on existing routes** | `GET /cards/:id/qrcode`: the backend is **POST only** (GET returns 405) and responds with JSON `{qrCodeUrl: dataURL, publicUrl}`. `POST /notifications/:id/read`: the backend is **PATCH** (405). `POST /public/track-click` sends `{slug,type,target}`, but the backend needs `{cardId, linkType, linkUrl}`, so it gets a 400 that the app swallows and no clicks are recorded. `reset-password` sends `password`, but the backend needs `newPassword` (400). Register sends no `role`, which the backend requires (400). | be `cards/[id]/qrcode/route.ts`, `notifications/[id]/read/route.ts`, `public/track-click/route.ts` + `lib/validation/card.ts` `trackClickSchema`, `auth/reset-password/route.ts:12`, `auth/register/route.ts:18`; app files in §3 |
| 9 | **P1 – response shapes the app parses as empty** | The dashboard returns `{cards, cardsLimit, staff, staffLimit, reviews, averageRating}`. The app reads `activeCards/totalCards/totalReviews/organization.name` and shows zeros and "My organization". Staff list items are `Staff` docs with `userId:{name,email,phone,status}` populated, but the app reads top-level `name/email`, so it shows "Unnamed" with a blank email. Org reviews populate `cardId` as an object, but the app expects a string or `card`, so the card title is lost. View analytics returns `trend`, which the app does not look for, so the chart is empty. On public cards `photo/companyName/theme/displayOptions` are not read, so there is no photo, no company and the template is always "minimal". | be `organization/dashboard/route.ts`, `organization/staff/route.ts`, `organization/reviews/route.ts`, `analytics/card/[id]/views/route.ts`, `lib/publicCard.ts`; app `lib/shared/models/organization.dart`, `review.dart`, `lib/features/analytics/domain/analytics_models.dart`, `lib/features/public_card/domain/public_card.dart` |
| 10 | **P2 – contract semantics** | (a) Contact exchange is **live** (`POST /public/card/:slug/exchange` returns 201, and the web templates still show an Exchange modal), but the spec says it returns 410. (b) No stable error codes: errors are `{success:false, error:"<string>"}` with no `code` or `Retry-After`. (c) Card list is paginated (default 20) but the app fetches only page 1. Public reviews omit `hasMore/totalPages`, so app pagination stops at page 1. (d) Analytics ignore `range/from/to`. (e) Org profile PATCH with `name:null` causes a Mongoose validation error, returned as a **500**. (f) Logout and change-password bump `tokenVersion`, which signs the user out of **all** devices, and change-password returns no new tokens to the app. | be `public/card/[slug]/exchange/route.ts`, `components/public-card/templates/*Template.tsx`; be `lib/api.ts` `jsonError/handleApiError`; be `lib/pagination.ts`; be `public/card/[slug]/reviews/route.ts`; be `auth/logout/route.ts`, `auth/change-password/route.ts` |

---

## 2. Cross-cutting contract facts (verified)

**Envelope.** Success: `{success:true, data}` (be `lib/api.ts` `jsonOk`). Error: `{success:false, error:"<message string>"}` (be `lib/api.ts` `jsonError`). `error` is **never** an object and there is **no `code`**. Zod failures return `400` with `issues[0].message` (be `lib/api.ts` `handleApiError`). The app handles a string `error` correctly (app `lib/core/api/api_client.dart` `unwrapEnvelope`, `lib/core/errors/app_exception.dart` `_parseErrorBody`), but every `error.code` branch (AUTH-4) is dead code today. Exceptions: `session-status` returns `{ok:boolean}`, `vcard` returns raw `text/vcard`, and `refresh-and-return` and `domain-verification` return redirects or plain text.

**Status codes in use.** 400, 401 (`Unauthorized`, `Invalid or expired token`, `Session revoked`, `Invalid credentials`), 403 (`Forbidden`, `Missing permission`, `Account suspended`, `Organization suspended`), 404, 409 (duplicate email/slug/review/domain), 413 (upload quota), **423** (account locked, be `auth/login/route.ts`), 429 (no `Retry-After` header), 500, and 405 (Next.js default for an unexported method). The app maps 423 and 405 to `unknown` (app `lib/core/errors/app_exception.dart` status switch).

**Auth transport.** `requireAuth` accepts `Authorization: Bearer` **or** the `cogcard_token` cookie (be `lib/auth.ts` `getAccessTokenFromRequest`), so bearer works once tokens are delivered. `x-bizzvot-session` and `x-bizzvot-client` are ignored. Edge middleware does not gate `/api/*` (be `middleware.ts` PROTECTED prefixes only match page routes). Access TTL is 1h and refresh TTL is 30d. Refresh tokens are not rotated or revoked one by one; they are invalidated only by a `tokenVersion` bump (be `lib/auth.ts`, `lib/auth-constants.ts`).

**Roles.** `super_admin | organization | staff | individual` (be `lib/types.ts`). Owner = `organization`.

**Pagination.** `parsePagination` takes `?page&limit` (default 20, max 100) and returns `{items,page,limit,total,totalPages,hasMore}` (be `lib/pagination.ts`). It is used by org cards, org reviews and staff reviews only. Public reviews return `{items,total,page,limit}` (no `hasMore`). Staff list, staff cards and notifications return bare arrays.

**Staff permissions.** Field names **match** exactly: `editCard, viewReviews, replyReviews, manageLinks` (be `lib/types.ts`, `lib/models/Staff.ts`; app `lib/core/auth/auth_user.dart` `StaffPermissions`). Semantics differ:
- Backend defaults on create are `editCard:true, viewReviews:true, replyReviews:false, manageLinks:true` when the app omits them (be `organization/staff/route.ts`). The app always sends all four, so this is fine.
- Staff **review status** changes require `replyReviews`, not a separate moderate permission (be `staff/reviews/[id]/status/route.ts`).
- Staff card PATCH **always requires `editCard`**, plus `manageLinks` when links are touched (be `staff/cards/[id]/route.ts`). The app lets a staff member with `manageLinks` only open the editor and send link-only patches (app `lib/features/cards/domain/card_edit_sections.dart` `forStaff`, `lib/app/router.dart`), which get a 403.
- `POST /cards/:id/qrcode` for staff requires `editCard` (be `cards/[id]/qrcode/route.ts`).

**Card model (be `lib/models/Card.ts`, `lib/validation/card.ts`) vs app `CardModel` (app `lib/shared/models/card.dart`):**

| App field (`toUpdateJson`) | Backend field | Status |
|---|---|---|
| `title` | `title` (min 1, **not nullable**) | MATCH name; app sends `null` on clear, which gets a 400 |
| `designation`, `pronouns`, `bio`, `phone`, `whatsapp`, `email`, `website`, `address`, `mapLink`, `logo`, `coverImage`, `vcardEnabled` | same | MATCH |
| `company` | `companyName` | NAME MISMATCH (stripped on owner PATCH; 400 on staff PATCH) |
| `profilePhoto` | `photo` | NAME MISMATCH |
| `companyPhone` | — | MISSING IN BACKEND |
| `bloodGroup`, `fatherName`, `motherName` / `privateDetails` | — | MISSING IN BACKEND |
| `socialLinks[{type,url,label,_id}]` | `socialLinks[{platform (req), url (req)}]` max 50 | SHAPE MISMATCH, 400 "Required" |
| `customLinks[{type,url,label?,_id}]` | `customLinks[{label (req), url (req), icon?}]` max 50 | SHAPE MISMATCH (400 when label empty; `type` dropped) |
| `gallery` (≤5), `pdfs` (≤10), `videos` (≤5) | — | MISSING IN BACKEND (no fields, no limits) |
| `template` (6 ids incl. `profile_hub`, `cover_card`, `review_card`) | `theme.templateId` enum `minimal\|corporate\|modern_dark` | NAME + ENUM MISMATCH (be `lib/types.ts` `TemplateId`, `lib/themes/templates.ts`) |
| `brandColor` | `theme.primaryColor` | NAME MISMATCH |
| `sectionOrder` (`contact, social, links, gallery, videos, documents, reviews`) | `theme.sectionOrder` enum `bio, contacts, socials, customLinks` (max 8) | NAME + VALUE MISMATCH (app `lib/features/cards/domain/display_sections.dart`) |
| `displayToggles{key:bool}` | `displayOptions{showBio, showSocials, showAddress, showWhatsapp, showCustomLinks, showReviews}` `.strict()` | NAME + KEY MISMATCH |
| `visibility` | — | MISSING IN BACKEND |
| `googleReviewUrl` | — | MISSING IN BACKEND |
| `disabledByBilling` (read) | — | MISSING IN BACKEND |
| `status` (read; written via `/status`) | `status` `active\|disabled`, writable via `PATCH /organization/cards/:id` | Route for writing differs (see table) |
| `staffUserId` / `staffName` (read) | — (only `createdByStaffId`; assignment is on `Staff.assignedCardIds`) | MISSING IN BACKEND |
| `viewCount`, `reviewCount`, `averageRating` (read) | — | Not returned |
| — | `slug` (writable, 409 on duplicate), `type`, `ownerType`, `ownerId`, `qrCodeUrl` (base64 PNG), `createdAt` | App ignores; `qrCodeUrl` makes list payloads heavy |

**Organization model (be `lib/models/Organization.ts`).** Fields: `name, logo, industry, address, gstNumber, planId, planExpiry, maxCards, maxStaff, cardCount, staffCount, status`. **Not present:** `slug`, `email`, `phone`, `website`, `description/about`, `directoryVisibility`, `trial`. PATCH allow-list: `name, logo, industry, address, gstNumber` (be `organization/profile/route.ts:24`), with no validation, so `null` is written through.

---

## 3. Full endpoint table

Legend: **MATCH** · **SHAPE MISMATCH** · **MISSING IN BACKEND** · **PATH DIFFERS** (also used for method differences).

### 3.1 Auth

| App endpoint | Backend route | Status | Details | Required fix |
|---|---|---|---|---|
| `POST /auth/register` | be `app/api/v1/auth/register/route.ts` | SHAPE MISMATCH | Body requires `role: "organization"\|"individual"` (line 18). App sends `{organizationName,name,email,password,phone}` with no role, so it gets a 400. Response: `{user:{id,name,email,role,organizationId,staffId,individualId}}` (201); **tokens are stripped**. Creates a "Free" plan (maxCards 3, maxStaff 2). Optional `industry` is supported but the app does not send it. | **App:** add `'role':'organization'` in `RegisterRequest.toJson` (app `lib/core/auth/auth_repository.dart`). **Backend:** return tokens for native clients (see AUTH-1 fix). |
| `POST /auth/login` | be `auth/login/route.ts` | SHAPE MISMATCH | Body `{email,password}` MATCH. Response has **no tokens** (cookies only). 423 on lockout, 401 "Invalid credentials". Lets **any** role log in (including staff, individual and super_admin). The app relies on the `me()` role check. | **Backend:** native token response. **App:** map 423 (locked) to a friendly message. |
| `POST /auth/staff-login` | be `auth/staff-login/route.ts` | SHAPE MISMATCH | Same as login. Rejects non-staff with 401 "Invalid staff credentials" (no `ACCOUNT_IS_STAFF`-style code). | Same as login. |
| `GET /auth/me` | be `auth/me/route.ts` | SHAPE MISMATCH | Returns flat `{id,name,email,phone,role,organizationId,status,organizationIdToken,staffId,individualId,permissions}`. Problems: (1) `role:"organization"` is unmapped in the app (gap #2). (2) `organizationId` comes from `User.organizationId`, which is **null for owners** (register never sets it); the real id is in `organizationIdToken`. (3) No `organizationName`. (4) No `cardId`/`card` for staff. | **App:** map `organization` to owner, and `individual` to an explicit "unsupported" state (app `lib/core/auth/auth_user.dart`). Read `organizationIdToken` as a fallback. **Backend:** add `organizationId` (resolved), `organizationName`, and for staff `assignedCardIds` (+ primary `cardId`). |
| `POST /auth/refresh` | be `auth/refresh/route.ts` | SHAPE MISMATCH | Accepts body `{refreshToken}` (min 10) or the cookie. Response has **no tokens**, so `buildRefresh` returns null and the session expires after 1h. Tokens are re-issued with the same `tokenVersion` (no single-token revocation). | **Backend:** return `accessToken` + `refreshToken` in `data` for native clients. |
| `POST /auth/logout` | be `auth/logout/route.ts` | SHAPE MISMATCH (semantics) | Reads the Bearer token (works) or the refresh cookie. The body `refreshToken` is **ignored**. It bumps `tokenVersion`, which **logs the user out of every device and the web**. | **Backend:** read body `refreshToken` when the access token is expired. Consider per-session revocation so mobile logout does not kill web sessions. |
| `POST /auth/forgot-password` | be `auth/forgot-password/route.ts` | MATCH | `{email}` → `{message}` (generic). The email link is a web URL `${APP_URL}/?resetToken=…`, so the app cannot capture it unless universal links are set up. | Backend/infra: universal link or app-link for the reset URL (see audit 02). |
| `POST /auth/reset-password` | be `auth/reset-password/route.ts` | SHAPE MISMATCH | Requires `{token, newPassword}` (line 12). App sends `{token, password}` (app `lib/core/auth/auth_repository.dart:149`), so it gets a 400 "Invalid input". | **App:** rename the key to `newPassword`. |
| `POST /auth/change-password` | be `auth/change-password/route.ts` | SHAPE MISMATCH | Body `{currentPassword,newPassword}` MATCH. It bumps `tokenVersion` (revokes the app's bearer token) and returns fresh tokens **only as cookies**, so the app's next call gets a 401 and the refresh also fails ("Session revoked"). Wrong current password returns **401**, which triggers the app's refresh interceptor. | **Backend:** return new tokens in the body for native clients, and use 400/403 (not 401) for a wrong current password. **App:** store the returned tokens and mark this call `noRefresh`. |
| `GET /auth/session-status` | be `auth/session-status/route.ts` | SHAPE MISMATCH (internal-only) | Requires the `MIDDLEWARE_INTERNAL_SECRET` header and returns `{ok}` with no envelope. Not usable by the app; the app does not call it (only declared). | **App:** delete `Endpoints.sessionStatus`. |
| `DELETE /auth/account` (PROPOSED) | — | MISSING IN BACKEND | No account deletion. Org owner deletion must cascade cards, staff, reviews, domains, media and notifications. | **Backend:** implement ACC-1. |

### 3.2 Organization

| App endpoint | Backend route | Status | Details | Required fix |
|---|---|---|---|---|
| `GET /organization/dashboard` | be `organization/dashboard/route.ts` | SHAPE MISMATCH | Returns `{cards,cardsLimit,staff,staffLimit,reviews,averageRating}`. The app (`DashboardSummary.fromJson`, app `lib/shared/models/organization.dart`) reads `activeCards, paidSeats, totalCards, totalReviews, disabledByBilling, organization.name, trial, seats`. Only `averageRating` matches. There is no active/disabled split, no org name and no trial. | **App:** map `cards→totalCards`, `reviews→totalReviews`, `cardsLimit→paidSeats`, `staff/staffLimit`. Get the org name from `/organization/profile`. **Backend:** add `activeCards`, `organization{name,status}` and trial/plan when billing exists. |
| `GET /organization/profile` | be `organization/profile/route.ts` | SHAPE MISMATCH | Returns the raw Organization doc (`_id,name,logo,industry,address,gstNumber,planId,planExpiry,maxCards,maxStaff,cardCount,staffCount,status,…`). App fields `slug,email,phone,website,description,directoryVisibility` are absent. | **Backend:** add `slug` (needed for the directory), contact fields and `directoryVisibility`, or the **app** must hide those inputs. |
| `PATCH /organization/profile` | same | SHAPE MISMATCH | Allow-list `name,logo,industry,address,gstNumber`. Everything else is **silently ignored** and returns 200 (app `lib/features/organization_profile/domain/profile_form_values.dart` sends `email,phone,website,description/about,directoryVisibility`). No validation: `{name:null}` hits the Mongoose `required` error and returns **500**. | **Backend:** Zod schema + new fields; reject unknown keys with 400. **App:** never send `name:null`; send `logo` (supported) and stop sending unsupported keys until they exist. |
| `GET /organization/staff` | be `organization/staff/route.ts` | SHAPE MISMATCH | Bare array of `Staff` docs: `{_id, userId:{_id,name,email,phone,status}, organizationId, permissions, assignedCardIds[], status}`. The app reads top-level `name/email/phone/designation/card` (app `lib/shared/models/organization.dart` `StaffMember.fromJson`), so it shows "Unnamed" with a blank email and no card. No pagination. | **App:** read `userId.{name,email,phone}` and `assignedCardIds`. **Backend:** optionally flatten and embed the assigned card summary. |
| `POST /organization/staff` | same | SHAPE MISMATCH | Body `{name,email,password (≥6),phone?,permissions?,assignedCardIds?}`. `designation` is ignored. It does **not** create a card (the app assumes it does; app `lib/features/staff/domain/staff_draft.dart`). Enforces `maxStaff` (Free = 2); the spec says staff have no seat charge. Response `{staff,user:{id,email,name}}`. `parseStaffMutation` picks `staff` (no name), so it shows "Unnamed". | **App:** create the card via `POST /organization/cards`, then pass `assignedCardIds`. Parse `user` for name/email. **Backend:** decide the staff-limit policy vs the spec (§6.4); optionally create and assign a card atomically. |
| `PATCH /organization/staff/:id` | be `organization/staff/[id]/route.ts` | SHAPE MISMATCH | Accepts only `permissions{4 bools}`, `assignedCardIds[]`, `status active\|suspended`. `name/email/phone/designation` edits from the app are **silently ignored** (200). | **Backend:** allow updating the linked User's `name/phone` (+ email with uniqueness). **App:** hide those inputs until then and expose suspend/activate. |
| `DELETE /organization/staff/:id` | same | MATCH | Hard-deletes User + Staff and revokes sessions; returns `{deleted:true}`. Assigned cards are **not** deleted. | None (document that cards are kept). |
| `GET /organization/cards` | be `organization/cards/route.ts` | SHAPE MISMATCH | Paginated `{items,page,limit,total,totalPages,hasMore}`, default limit **20**. The app requests no page and reads `items` (app `cards_repository.dart` `listCards`), so orgs with more than 20 cards are truncated. Items are full Card docs (field mismatches above, including the base64 `qrCodeUrl`). | **App:** paginate or pass `limit=100`, and map field names. **Backend:** exclude `qrCodeUrl` from the list projection. |
| `GET /organization/cards/:id` | be `organization/cards/[id]/route.ts` | SHAPE MISMATCH | Raw Card doc; field names as in §2. | **App:** map `companyName, photo, theme.*, displayOptions, platform`. |
| `PATCH /organization/cards/:id` | same | SHAPE MISMATCH | Non-strict `cardWriteSchema`: unknown keys are **silently stripped**. 400 for socialLinks without `platform`, customLinks without `label`, or `title:null`. 409 on slug conflict. **Accepts `status`** (owner activate/disable). | **App:** send backend names and shapes (`companyName`, `photo`, `theme:{templateId,primaryColor,sectionOrder}`, `displayOptions:{show*}`, `socialLinks[{platform,url}]`, `customLinks[{label,url,icon?}]`). Never null `title`. **Backend:** add the missing fields (see backend list) and reject unknown keys. |
| `DELETE /organization/cards/:id` | same | MATCH | `{deleted:true}`; cascades via `deleteCardAndRelated`. | — |
| `PATCH /organization/cards/status` | — | MISSING IN BACKEND | No such route. Note: `/organization/cards/status` is routed to `[id]` with `id="status"`, which casts to an ObjectId and is likely a 500/404. No bulk status, no seat/trial check on activation, no `disabledByBilling`. | **App (now):** use `PATCH /organization/cards/:id {status}` per card. **Backend:** add a bulk status route with seat enforcement once billing exists. |
| `GET /organization/cards/qrcodes` | — | MISSING IN BACKEND | Same `[id]` capture issue. | **App (now):** generate QR codes locally from `${publicBase}/card/${slug}` (what the backend encodes, be `cards/[id]/qrcode/route.ts`) or use each card's stored `qrCodeUrl`. **Backend:** optional ZIP/list route. |
| `GET /organization/reviews` | be `organization/reviews/route.ts` | SHAPE MISMATCH | Paginated `{items,…}`. **`?status=` is ignored** (no filter), so the app's Pending/Approved/Hidden tabs all show everything. `cardId` is populated as `{_id,title,slug}`; the app reads `cardId` as a string or `card`, so card id and title are null (app `lib/shared/models/review.dart`). `reviewerEmail` is returned (the app drops it, good). | **Backend:** support `status` (+ `cardId`) filters. **App:** read `cardId` as a Map. |
| `PATCH /organization/reviews/:id/status` | be `organization/reviews/[id]/status/route.ts` | MATCH | `{status: pending\|approved\|hidden}` → review doc (sanitized). | — |
| `POST /organization/reviews/:id/reply` | be `organization/reviews/[id]/reply/route.ts` | MATCH | `{text}` → review doc with `reply{text,repliedBy,repliedAt}`; the app parses `reply` OK. No max length on `text`. | **Backend:** length cap. |
| `GET /organization/billing` | — | MISSING IN BACKEND | No billing route, model, Stripe or trial anywhere (be `project-docs/06-Audit/POST-REMEDIATION-AUDIT-2026-08-02.md:19,67`: Stripe out of scope). The spec's "existing" claim is **false** for this backend. | **Backend:** design billing/seat/trial (see audit 04). **App:** feature-flag billing off. |
| `POST /organization/billing` | — | MISSING IN BACKEND | Same. | Same. |

### 3.3 Cards (shared), media

| App endpoint | Backend route | Status | Details | Required fix |
|---|---|---|---|---|
| `GET /cards/:id/qrcode` | be `cards/[id]/qrcode/route.ts` | PATH DIFFERS (method) | Backend is **POST** only, so GET returns 405. Response `{qrCodeUrl:"data:image/png;base64,…", publicUrl}` (side effect: persists `qrCodeUrl`). `QrCodeEntry.fromJson` reads `qrCodeUrl` into `url` (not `dataUrl`), so `qrEntryImage` treats it as an https URL and returns null. Staff need `editCard`. | **App:** call POST and treat `qrCodeUrl` as a data URL, or generate locally from `publicUrl`. **Backend:** add an idempotent `GET` returning PNG. |
| `GET /cards/:id/vcard` | be `cards/[id]/vcard/route.ts` | MATCH | Public, raw `text/vcard`. 404 JSON when disabled or `vcardEnabled:false`. Phone/email are always included (no toggle). | — |
| `POST /cards/:id/media` | — | MISSING IN BACKEND | No card media library and no PDF support at all. | **Backend:** card media route (PDF ≤ N MB, ownership check) + model fields. **App:** hide documents. |
| `DELETE /cards/:id/library` | — | MISSING IN BACKEND | — | Same. |
| `POST /media/upload` | be `media/upload/route.ts` | MATCH (constraints) | Multipart `file` or JSON `{dataUrl}`. **Images only** (JPEG/PNG/WebP/GIF magic-byte check, re-encoded), max 5 MB, 20/min, 50 MB per-user quota (413). Response `{url, filename}` (201); the app parses `url` OK. | **App:** enforce image-only and 5 MB client-side; map 413. |

### 3.4 Staff

| App endpoint | Backend route | Status | Details | Required fix |
|---|---|---|---|---|
| `GET /staff/card` (PROPOSED) | `GET /staff/cards` (be `staff/cards/route.ts`) / `GET /cards/:id` | PATH DIFFERS | The backend returns an **array** of all assigned cards; `GET /cards/:id` also works for an assigned staff member. There is no singular route. | **App:** use `GET /staff/cards` and pick `[0]`, or show a picker when more than one. **Backend (optional):** `/staff/card` convenience route, or `cardId` in `/auth/me`. |
| `PATCH /staff/card` (PROPOSED) | `PATCH /staff/cards/:id` (be `staff/cards/[id]/route.ts`) | PATH DIFFERS + SHAPE MISMATCH | Needs the card id in the path. `staffCardWriteSchema` is `.strict()`, so any app-only key (`company`, `profilePhoto`, `template`, `brandColor`, `displayToggles`, `companyPhone`, `gallery`, …) gets a 400 "Unrecognized key(s)". `status` is forbidden. Requires `editCard` always, plus `manageLinks` for links. | **App:** `PATCH /staff/cards/:id` with backend field names. Require `editCard` in the UI for any edit. |
| `GET /staff/reviews` | be `staff/reviews/route.ts` | SHAPE MISMATCH | Requires `viewReviews`. Paginated. `?status` ignored. `cardId` populated object (same as org). | Same as org reviews. |
| `POST /staff/reviews/:id/reply` | be `staff/reviews/[id]/reply/route.ts` | MATCH | `{text}`; requires `replyReviews` + assignment. | — |
| `PATCH /staff/reviews/:id/status` | be `staff/reviews/[id]/status/route.ts` | MATCH (permission) | `{status}`; requires **`replyReviews`** (not a moderation flag). | **App:** gate the moderation UI on `replyReviews`. |

### 3.5 Public

| App endpoint | Backend route | Status | Details | Required fix |
|---|---|---|---|---|
| `GET /public/card/:slug` | be `public/card/[slug]/route.ts`, `lib/publicCard.ts` | SHAPE MISMATCH | Flat DTO `{_id,slug,title,pronouns,designation,companyName,photo,coverImage,logo,bio?,phone,email,whatsapp?,website,address?,mapLink?,socialLinks?,customLinks?,theme,vcardEnabled,displayOptions,type,status}`. Hidden sections are stripped server-side (good). The app reads `company`, `profilePhoto`, `template`, `brandColor`, `sectionOrder`, `displayToggles` (app `lib/features/public_card/domain/public_card.dart:174-205`), so those six are lost. There is no organization name/logo, review summary or `googleReviewUrl`. Every app open counts as a view (deduped per 30 min). | **App:** map `companyName`, `photo`, `theme.templateId/primaryColor/sectionOrder`, `displayOptions`, `platform`. **Backend:** add org `{name,logo}`, a review summary, `googleReviewUrl`, and (when built) media lists. |
| `GET /public/card/:slug/reviews` | be `public/card/[slug]/reviews/route.ts` | SHAPE MISMATCH | `{items,total,page,limit}` (limit max 50). **No `hasMore`/`totalPages`**, so `Paged.parse` sets `hasMore=false` and the app never loads page 2. Items include `reviewerEmail` (privacy leak, server-side). | **Backend:** use `paginatedResult` and `.select("-reviewerEmail")`. **App:** derive `hasMore` from `page*limit<total`. |
| `POST /public/card/:slug/review` | be `public/card/[slug]/review/route.ts` | SHAPE MISMATCH | Requires `{reviewerName (1-200), rating int 1-5, reviewerEmail?, comment? (≤5000)}`. App sends `name`, so it gets a 400 "Required". Response: the review doc (status `pending` or `approved` by plan); the app parses status OK. 409 duplicate, 429. | **App:** send `reviewerName` (app `lib/features/public_card/domain/public_review.dart:60`). |
| `POST /public/track-click` | be `public/track-click/route.ts`, `lib/validation/card.ts` `trackClickSchema` | SHAPE MISMATCH | Requires `{cardId, linkType, linkUrl?}`. App sends `{slug,type,target}` (app `lib/features/public_card/data/public_card_repository.dart:98`), which gets a 400 that is silently swallowed, so link analytics stay empty. (OpenAPI says `url`, but the code says `linkUrl`.) | **App:** send `cardId` (from the public DTO `_id`), `linkType`, `linkUrl`. **Backend:** fix the OpenAPI doc. |
| `GET /public/organizations/:slug/directory` (PROPOSED) | — | MISSING IN BACKEND | No org slug, no visibility fields, no route. | **Backend:** VIS-1..3. **App:** feature-flag off. |
| (spec) `POST /public/card/:slug/exchange` should be 410 | be `public/card/[slug]/exchange/route.ts` | SHAPE MISMATCH (should be retired) | **Live**: returns 201 and stores visitor name/email/phone/message in owner Notifications (`exchange_contact`). The web templates still render `ExchangeModal` (be `components/public-card/templates/MinimalTemplate.tsx`, `CorporateTemplate.tsx`, `ModernDarkTemplate.tsx`; pages `app/(dashboard)/{organization,individual}/exchanges`). The app correctly never calls it. | **Backend:** return `410 {success:false,error:"Contact exchange has been retired"}`, remove the web modal and inbox, and purge or expire `exchange_contact` notifications. |

### 3.6 Analytics

| App endpoint | Backend route | Status | Details | Required fix |
|---|---|---|---|---|
| `GET /analytics/card/:id/views` | be `analytics/card/[id]/views/route.ts` | SHAPE MISMATCH | Returns `{views (all-time), uniqueVisitors (all-time), trend:[{_id:"YYYY-MM-DD",count}] (fixed last 7 days)}`. `range/from/to` are **ignored**. The app's series keys do not include `trend`, so the chart is empty (app `lib/features/analytics/domain/analytics_models.dart` `ViewsStats.fromJson`). Owner, assigned staff and individual access OK. | **App:** add `trend` to the series keys. **Backend:** honour `from/to` (or `range`), return a zero-filled series, and return period totals. |
| `GET /analytics/card/:id/reviews` | be `analytics/card/[id]/reviews/route.ts` | SHAPE MISMATCH (minor) | `{count, average, distribution:[{_id:rating,count}]}`, approved only, all-time. The app parses it OK (via `distribution` and `_id`). No series, and the range is ignored, so "new in period" is always 0. | **Backend:** range + daily series. |
| `GET /analytics/card/:id/links` | be `analytics/card/[id]/links/route.ts` | MATCH (shape) / range ignored | Bare `[{_id:linkType,count}]`; the app parses it. All-time only. Always empty for app-originated clicks until track-click is fixed. | **Backend:** range filter. |

### 3.7 Commerce, config, notifications

| App endpoint | Backend route | Status | Details | Required fix |
|---|---|---|---|---|
| `GET /catalog/categories`, `/catalog/services`, `/catalog/products`, `/catalog/plans`, `/catalog/:type/:id` | — | MISSING IN BACKEND | Only `admin/plans` (super_admin) exists; the `Plan` model is `{name,price,maxCards,maxStaff,customDomain,reviewModeration,features}` with no currency or minor units. No product catalogue for the 4 NFC SKUs. | **Backend:** COM-1 (see audit 04). |
| `POST /cart/quote` | — | MISSING IN BACKEND | — | COM-1. |
| `GET/POST /orders`, `GET /orders/:id`, `POST /orders/:id/payment` | — | MISSING IN BACKEND | No orders, payments, Idempotency-Key handling or fulfilment. | COM-1..3. |
| `GET /subscriptions`, `GET /subscriptions/:id`, `POST /subscriptions/:id/renew` | — | MISSING IN BACKEND | Only `Organization.planExpiry` exists. | COM-1. |
| `GET /invoices`, `GET /invoices/:id` | — | MISSING IN BACKEND | — | COM-1. |
| `GET /app/config` | — | MISSING IN BACKEND | The app fails open to defaults (app `lib/core/config/app_config.dart`). | **Backend:** CFG-1. |
| `GET /notifications` | be `notifications/route.ts` | SHAPE MISMATCH | **Exists** (the app and the gap register NOT-1 call it PROPOSED). Bare array (latest 50, no pagination; `page/limit` ignored) of `{_id,userId,type,message,isRead,createdAt,updatedAt}`. The app maps `message→body`, `isRead→readAt` OK, and title falls back to a humanized `type`. Types seen: `new_review`, `staff_added`, `password_reset`, `exchange_contact`. There is no payload or ids for deep links. | **App:** mark as existing in endpoints/gap register. **Backend:** pagination + `payload{cardId,reviewId}` + `title`. |
| `POST /notifications/:id/read` | be `notifications/[id]/read/route.ts` | PATH DIFFERS (method) | Backend is **PATCH**, so POST gets a 405 (app `lib/features/notifications/data/notifications_repository.dart:28`). | **App:** use `_api.patch`. |

---

## 4. Backend routes the app does not use (but probably should, or must consciously avoid)

| Backend route | Why it matters |
|---|---|
| `POST /organization/cards` (be `organization/cards/route.ts`) | The **only way to create a card**. The app has no create call and assumes staff creation makes one. Body = `cardCreateSchema` + `assignToAllStaff`. Enforces `maxCards` (atomic slot). |
| `GET /staff/cards`, `PATCH /staff/cards/:id` | The real staff card endpoints (see 3.4). |
| `GET /cards/:id`, `PATCH /cards/:id`, `DELETE /cards/:id` (be `cards/[id]/route.ts`) | Role-agnostic card read: staff can GET an assigned card. `POST /cards` is a legacy generic create. |
| `GET/PATCH /individual/profile`, `GET/POST /individual/card`, `GET/PATCH/DELETE /individual/card/:id`, `GET /individual/reviews`, `…/reviews/:id/{reply,status}` | Individual accounts (role `individual`) exist and can register via `/auth/register {role:"individual"}`. A ₹999 "Business Digital + Physical NFC Card" buyer without an organization would be an individual. The app currently routes them to "unsupported". Product decision needed. |
| `GET/POST /domains`, `GET/PATCH/DELETE /domains/:id`, `POST /domains/:id/verify` (be `domains/**`) | Custom domain / subdomain per card (plan-gated `customDomain`). NFC tags may be written with custom-domain URLs. |
| `GET /public/resolve-host?host=` (be `public/resolve-host/route.ts`) | Lets the app resolve an NFC/QR URL on a custom host to a card slug (public; rate-limited 60/min). Useful for in-app NFC scan → open card. |
| `GET /auth/refresh-and-return` | **Do not use**: cookie-only browser redirect for the Edge middleware. Native refresh must use `POST /auth/refresh` with body tokens. |
| `GET /public/domain-verification` | Infra only; not for the app. |
| `/admin/**` | Super-admin only; the app correctly blocks `super_admin`. |

---

## 5. Prioritized fix list

### 5.1 Mobile app changes (`/home/user/Bizzvot-apps-`)

**P0**
1. `lib/core/auth/auth_user.dart`: `UserRole.parse` must map `'organization'` to `owner`. Add an `individual` value (route to an explicit unsupported or individual flow). Read `organizationIdToken` as a fallback for `organizationId`.
2. `lib/core/auth/auth_repository.dart`: `RegisterRequest.toJson` must add `'role': 'organization'` (+ optional `industry`). `resetPassword` must send `newPassword`, not `password`. `changePassword` must store returned tokens (once the backend returns them) and pass `noRefresh: true`, because a wrong current password returns 401.
3. `lib/shared/models/card.dart`: rewrite `fromJson`/`toUpdateJson` to the backend contract:
   - `companyName` and `photo`
   - `theme:{templateId,primaryColor,sectionOrder}`
   - `displayOptions:{showBio,showSocials,showAddress,showWhatsapp,showCustomLinks,showReviews}`
   - `socialLinks:[{platform,url}]` and `customLinks:[{label,url,icon?}]`
   - never send `title: null`
   - stop sending `companyPhone`, `bloodGroup/fatherName/motherName`, `gallery/pdfs/videos`, `visibility`, `googleReviewUrl` until they exist on the backend.
   - Restrict `CardTemplate` to the 3 backend ids, or gate the extra 3 behind a backend flag.
4. `lib/features/cards/domain/display_sections.dart`: use backend section keys `bio, contacts, socials, customLinks`.
5. `lib/features/cards/domain/card_edit_sections.dart`: field names as in item 3. In `forStaff`, only allow the links section when `editCard && manageLinks` (the backend requires `editCard` for every staff PATCH). Make the same change in `lib/app/router.dart` (`staffCardEdit` guard).
6. `lib/core/api/endpoints.dart` + `lib/features/cards/data/cards_repository.dart`: replace `staffCard` with `GET /staff/cards` (list) and `PATCH /staff/cards/:id`. Handle zero, one or many assigned cards.
7. `lib/features/public_card/domain/public_review.dart`: `ReviewSubmission.toJson` key `name` becomes `reviewerName`.
8. `lib/features/public_card/data/public_card_repository.dart`: `trackClick` body becomes `{cardId, linkType, linkUrl?}` (pass the card `_id` from the public DTO).
9. `lib/features/public_card/domain/public_card.dart`: read `companyName`, `photo`, `theme.templateId`, `theme.primaryColor`, `theme.sectionOrder`, `displayOptions`, and `platform` for links.

**P1**
10. `lib/features/cards/data/cards_repository.dart`:
    - `setStatus`: use `PATCH /organization/cards/:id {status}` per card.
    - `qrCode`: use **POST** `/cards/:id/qrcode` and decode `data.qrCodeUrl` as a data URL (fix `QrCodeEntry.fromJson` in `lib/features/cards/domain/qr_codes.dart`, which puts `qrCodeUrl` into `url`), or render QR codes locally from `publicUrl`.
    - `allQrCodes`: build QR codes locally from the card list.
    - Remove `uploadCardDocument` and `removeLibraryFile` (or feature-flag them).
    - `listCards`: paginate (`limit=100` + `hasMore`).
    - Add `createCard` (`POST /organization/cards`).
11. `lib/features/notifications/data/notifications_repository.dart`: `markRead` must use PATCH. Drop the paging assumption (the backend returns up to 50 with no pages).
12. `lib/shared/models/organization.dart`:
    - `DashboardSummary.fromJson`: map `cards`, `cardsLimit`, `staff`, `staffLimit`, `reviews`, `averageRating`.
    - `StaffMember.fromJson`: read `userId.{name,email,phone}` and `assignedCardIds`.
    - `OrganizationProfile`: drop or hide `slug/email/phone/website/description` until the backend has them.
13. `lib/features/staff/data/staff_repository.dart` + `lib/features/staff/domain/staff_draft.dart`:
    - Create a staff member as two steps: create the card, then create the staff member with `assignedCardIds`.
    - Parse `user` from the create response.
    - Do not send `name/email/phone/designation` on PATCH (ignored). Expose `status` (suspend).
14. `lib/shared/models/review.dart`: read `cardId` when it is a populated Map `{_id,title,slug}`.
15. `lib/features/reviews/data/reviews_repository.dart`: the `status` filter is ignored server-side. Filter client-side until the backend supports it. Gate staff moderation on `replyReviews`.
16. `lib/features/analytics/domain/analytics_models.dart`: add `trend` to the `ViewsStats` series keys. Label totals "all time" until the backend honours the range.
17. `lib/features/organization_profile/domain/profile_form_values.dart`: never send `name: null` (the backend returns 500). Send `logo`. Remove unsupported keys.
18. `lib/features/directory_visibility/**`, `lib/features/billing/**`, catalog/cart/orders/subscriptions/invoices, `deleteAccount`, `publicDirectory`: put each behind a feature flag defaulting **off**. Show an "unavailable" state instead of a silent 200 or 404. The visibility PATCHes currently report success while nothing is saved.
19. `lib/core/api/endpoints.dart`: delete `sessionStatus` (middleware-internal). Re-label `notifications` as existing. Correct the "existing" comments on `cardStatus`, `allQrCodes`, `cardMedia`, `cardLibrary` and `billing` (they are not in the backend).
20. `lib/core/errors/app_exception.dart`: map 423 (locked) and 413 (quota) explicitly. 405 should be logged as a contract bug.
21. `lib/features/public_card/data/public_card_repository.dart`: compute `hasMore` from `page*limit < total` for public reviews.
22. `docs/API_GAP_REGISTER.md`:
    - Correct AUTH-3 (no `cardId`), CARD-1 (use `/staff/cards`), CARD-2 (no status route), PUB-1 (payload is `{cardId,linkType,linkUrl}`) and NOT-1 (exists, PATCH).
    - Add new gaps: role `organization`, register `role`, reset `newPassword`, review `reviewerName`, the card field mapping, the dashboard shape, and billing/media/library/qrcodes missing.

### 5.2 Backend changes (`/home/user/cogcard`)

**P0**
1. `lib/api.ts` `jsonOkWithAuth` + `app/api/v1/auth/{login,staff-login,register,refresh,change-password}/route.ts`: for native clients, include `accessToken`/`refreshToken` in `data`. Trigger on an explicit, allow-listed client header such as `x-bizzvot-client: mobile`, or use dedicated `/auth/mobile/*` routes. Rotate refresh tokens (store a hashed refresh `jti`). `auth/logout/route.ts`: accept body `refreshToken` and revoke only that session (per-session revocation instead of a global `tokenVersion` bump).
2. `app/api/v1/auth/me/route.ts`: return resolved `organizationId` (for owners from `Organization.ownerUserId`), `organizationName`, and for staff `assignedCardIds` + primary `cardId`.
3. `lib/models/Card.ts` + `lib/validation/card.ts`: add `googleReviewUrl` (required for the Review Stand/Card SKUs) and expose it in `lib/publicCard.ts`. Decide whether to add `companyPhone`, `privateDetails{bloodGroup,fatherName,motherName}` (never in the public DTO or vCard), `gallery≤5`, `pdfs≤10`, `videos≤5` (YouTube ids validated), `visibility: inherit|public|private` and `disabledByBilling`. Extend the `TemplateId` enum (`lib/types.ts`, `lib/themes/templates.ts`) if `profile_hub/cover_card/review_card` ship.
4. `lib/validation/card.ts` `cardWriteSchema`: make the owner PATCH reject unknown keys (`.strict()`), so contract drift becomes a 400 instead of silent data loss.

**P1**
5. New `app/api/v1/organization/cards/status/route.ts` (bulk `{cardIds,status}`) with seat/trial enforcement. **Note:** static segment `status` must take precedence over `[id]`; it does in the Next.js App Router, but today `/organization/cards/status` falls into `[id]`.
6. New `app/api/v1/organization/cards/qrcodes/route.ts` (JSON list or ZIP). Add `GET` to `app/api/v1/cards/[id]/qrcode/route.ts` returning PNG without a DB write. Exclude `qrCodeUrl` from list projections.
7. New `app/api/v1/cards/[id]/media/route.ts` (PDF upload, size and type checks, ownership/assignment checks) and `app/api/v1/cards/[id]/library/route.ts` (DELETE `{url}`). Extend `lib/media/storage.ts` for PDFs.
8. Billing: `app/api/v1/organization/billing/route.ts` (GET summary: plan, trial, seats, active cards; POST start subscription `{quantity≥1, planId?}` → hosted checkout URL) + models. Today there is nothing (Stripe was out of scope).
9. `lib/models/Organization.ts` + `app/api/v1/organization/profile/route.ts`: add `slug` (unique), `directoryVisibility: public|private`, and optional contact fields. Add a Zod schema (reject null `name`, which currently returns 500). Add `GET /public/organizations/[slug]/directory` with server-side filtering (precedence per spec §7.2).
10. `app/api/v1/organization/reviews/route.ts`, `staff/reviews/route.ts`: support `?status=` and `?cardId=` filters.
11. `app/api/v1/public/card/[slug]/reviews/route.ts`: use `paginatedResult`, and stop returning `reviewerEmail` (`.select("-ipAddress -ipHash -reviewerEmail")`).
12. `app/api/v1/public/card/[slug]/exchange/route.ts`: return **410**. Remove `ExchangeModal` from `components/public-card/templates/*.tsx` and the `app/(dashboard)/{organization,individual}/exchanges` pages. Purge or expire `exchange_contact` notifications (they contain visitor PII).
13. `app/api/v1/analytics/card/[id]/{views,reviews,links}/route.ts`: honour `from/to` (ISO dates) and/or `range=7d|30d|90d`. Return zero-filled `series` + period totals.
14. `app/api/v1/organization/dashboard/route.ts`: add `activeCards`, `disabledCards`, `organization{name,status}`, and plan/trial once billing exists.
15. `app/api/v1/organization/staff/route.ts` + `[id]/route.ts`: return a flattened `{id,name,email,phone,status,permissions,assignedCardIds}`. Allow PATCH of `name/phone` (+ email). Decide on the `maxStaff` limit vs the spec ("no separate staff seat charge", PRODUCT_PLAN §6.4). Add a max length on the reply `text` in the review reply routes.
16. `app/api/v1/notifications/route.ts`: pagination, plus `title` and `payload{cardId,reviewId}` for deep links. Keep PATCH for read, or also accept POST.

**P2**
17. `lib/api.ts` `jsonError`: add stable `code` values (`INVALID_CREDENTIALS`, `ACCOUNT_LOCKED`, `ACCOUNT_SUSPENDED`, `NOT_STAFF`, `SESSION_REVOKED`, `PERMISSION_DENIED`, `PLAN_LIMIT`, `DUPLICATE_REVIEW`, `SLUG_TAKEN`, `VALIDATION`). The envelope stays additive: `{success:false, error:string, code?, fields?}`. Set `Retry-After` on 429.
18. `app/api/v1/auth/change-password/route.ts`: wrong current password should return 400/403, not 401.
19. `project-docs/05-API/openapi.yaml`: fix `track-click` (`linkUrl`, not `url`), mark `exchange` as retired, and document the response shapes.
20. New `GET /app/config` (CFG-1) and `DELETE /auth/account` (ACC-1, full cascade).

---

## 6. Host-dependent behaviour for the production base URL `https://www.bizzvot.com/api/v1`

Audited from code only; the sandbox cannot reach the live host. Everything below depends on deployment env vars that I could not see.

| Area | Finding (code) | Impact on the native client | Action |
|---|---|---|---|
| Edge middleware host logic | `middleware.ts`: the custom-host rewrite is skipped for `pathname.startsWith("/api")`. The `PROTECTED` prefixes (`/organization`, `/staff`, …) only match page paths, not `/api/v1/...`. The matcher runs middleware on `/api` but it returns `NextResponse.next()`. | **None** for API calls: no redirects to `/` or to `refresh-and-return`. | — |
| Primary-host detection | `middleware.ts` `getAppHosts()` and `lib/domains.ts` `isPrimaryAppHost()` build the host set from `NEXT_PUBLIC_APP_HOST`, the hostname of `NEXT_PUBLIC_APP_URL`, and `NEXT_PUBLIC_ROOT_DOMAIN` (**default `coglink.local`**) + `www.`. | If the deployment sets only `NEXT_PUBLIC_APP_URL=https://bizzvot.com`, then `www.bizzvot.com` is treated as a **custom host**. Page requests (not `/api`) then go through `resolve-host`, which affects `/card/:slug` links, NFC URLs and any `/.well-known/*` universal-link files (no `apple-app-site-association` or `assetlinks.json` route exists). It can also let a customer claim `www.bizzvot.com` as a custom domain. | **Backend/ops:** set `NEXT_PUBLIC_ROOT_DOMAIN=bizzvot.com` and `NEXT_PUBLIC_APP_HOST=www.bizzvot.com`. Pick one canonical host and 301 the other at the edge. **App:** use the same canonical host in `Env.apiBaseUrl` and in NFC/QR URL parsing. |
| Absolute URLs built from `NEXT_PUBLIC_APP_URL` | QR `publicUrl` and QR content (`cards/[id]/qrcode/route.ts`), local upload URLs `${base}/uploads/…` (`lib/media/storage.ts`), and reset-password links (`auth/forgot-password/route.ts`). `lib/session-cookies.ts` itself notes that "TLS-terminating LBs often set http:// APP_URL". | If `APP_URL` is `http://` or the apex host, uploaded images get `http://` URLs. iOS ATS blocks them, and `CardsRepository.qrEntryImage` rejects non-https. QR codes and NFC tags written from them point at the wrong host permanently. Local disk storage (no `S3_*`) also breaks on multi-replica deploys. | **Ops:** `NEXT_PUBLIC_APP_URL=https://www.bizzvot.com` and S3/CDN storage. **App:** accept only https media and canonicalise the host. |
| Internal header `x-cogcard-internal-secret` | `lib/middleware-internal.ts`. Required by `auth/session-status` and for full `resolve-host` data. In production it is `null` (fail closed) unless `MIDDLEWARE_INTERNAL_SECRET` is ≥16 chars. | The app must **never** send or need it. Without the secret, `session-status` always returns 401 `{ok:false}`, so `Endpoints.sessionStatus` is unusable. Public `resolve-host` still returns `{matched, slug}` (60/min per IP). | **App:** remove `sessionStatus`. Use `resolve-host` without the secret. No other `x-cogcard-*` headers exist. `x-bizzvot-*` headers are ignored by the backend. |
| CORS | No `Access-Control-*` headers and no `OPTIONS` handlers anywhere (`next.config.ts`, `app/api/**`). The CSP has `connect-src 'self'`. | Native Dio on iOS/Android is unaffected (no preflight). A **Flutter web** build or a WebView on another origin would fail. | Only needed if a web build ships. |
| Cookies | `lib/session-cookies.ts`: `cogcard_token`/`cogcard_refresh` are httpOnly, `SameSite=Lax`, `Secure` in production, with **no `Domain` attribute** (host-only). | Tokens exist **only** in these cookies (gap #1). Dio stores no cookies unless a cookie jar is added. Even with a jar, host-only cookies set on `www.bizzvot.com` are not sent to `bizzvot.com`. A cookie-jar workaround would also make the app vulnerable to cookie/bearer mixing. | **Backend:** body tokens for native (fix 5.2-1). **App:** do not add a cookie jar. |
| Client-IP resolution behind the LB | `lib/middleware/ipHash.ts`: when `TRUST_PROXY`/`TRUSTED_PROXY_HOPS` is unset, XFF is ignored, `req.ip` is generally unavailable on Node, and **all clients share the bucket `RATE_LIMIT_UNRESOLVED`**. | Production-critical for mobile. Login 20/min, staff-login 20/min, register 5/min, forgot 5/min, track-click 30/min, and public review **2/min** become **global** limits, so app users would see constant 429s. Even with correct proxy config, carrier CGNAT means many phones share one IP. That causes false "You've already reviewed this card" 409s, because review dedup is per IP hash (`public/card/[slug]/review/route.ts`). The dedup cookie `REVIEW_DEDUP_COOKIE` is not persisted by Dio, so when the IP is unresolved, app reviews are never deduped. | **Ops:** set `TRUST_PROXY=true` + the correct `TRUSTED_PROXY_HOPS` for the www.bizzvot.com LB/CDN. **Backend:** for authenticated routes, rate-limit per user or email, and reconsider IP-based review uniqueness for mobile (e.g. a device id header + per-card limit). |
| Security headers | `next.config.ts` adds HSTS (`includeSubDomains`), `X-Frame-Options: DENY` and the CSP to every path, including `/api`. | Harmless for native clients. HSTS `includeSubDomains` forces https on every `*.bizzvot.com` customer subdomain (`domains` feature). | Make sure subdomain certificates exist. |
