# API gap register

Items the mobile app needs that are **not** in the current `/api/v1` contract, or whose
request/response shapes the app had to assume. Each must be approved (or corrected) by
the backend team before release (plan §1, §14.3, §22). Status: **Open** unless noted.

| ID | Area | Gap | App assumption | Plan ref |
|---|---|---|---|---|
| AUTH-1 | Auth | Login/register/refresh set HTTP-only cookies only; native app needs tokens | `data.accessToken` + rotating `data.refreshToken` (also accepts `data.tokens.*`); client sends header `x-bizzvot-client: mobile`; requests carry `Authorization: Bearer` + `x-bizzvot-session: org`. Without tokens the app shows "Sign-in is not available on mobile yet" (`NATIVE_SESSION_UNSUPPORTED`). | §4.2 |
| AUTH-2 | Auth | Refresh/logout request bodies for native | `POST /auth/refresh {refreshToken}`, `POST /auth/logout {refreshToken}` (server revokes) | §4.3 |
| AUTH-3 | Auth | `/auth/me` payload for staff must include assigned `cardId` and `permissions` | Accepts flat user or `{user, organization}`; reads `cardId` or `card._id` | §3.2 |
| AUTH-4 | Auth | Stable error codes (e.g. `ACCOUNT_IS_STAFF`, `INVALID_CREDENTIALS`) | UI uses `error.code` when present, else HTTP status | §14.1 |
| CARD-1 | Cards | Staff access to own card | **PROPOSED** `GET/PATCH /staff/card` (permission-filtered server-side) | §3.2, §17.2 |
| CARD-2 | Cards | Status endpoint body | `PATCH /organization/cards/status {cardIds: [id], status}` | §6.3 |
| CARD-3 | Cards | Upload response | `POST /media/upload` multipart field `file` → `{url}` | §6.3 |
| VIS-1 | Visibility | `directoryVisibility` on organization profile | `public` \| `private` via `PATCH /organization/profile` | §7.5 |
| VIS-2 | Visibility | `visibility` on cards | `inherit` \| `public` \| `private` via `PATCH /organization/cards/:id` | §7.5 |
| VIS-3 | Visibility | Public directory | **PROPOSED** `GET /public/organizations/:slug/directory`, server-filtered | §7.5 |
| VIS-4 | Visibility | Precedence decision | Org private wins for the directory; card `private` never listed; direct link/QR unaffected | §7.2, §22.1–2 |
| PUB-1 | Public | `track-click` payload | `{slug, type, target?}` fire-and-forget | §8.5 |
| PUB-2 | Public | Public card must expose card id (for vCard) **without** private fields | Public DTO allow-list in app; server must also exclude by construction | §8, §16 |
| AN-1 | Analytics | Date range params and series shape | `range=7d|30d|90d` (+ `from`/`to`); tolerant parsing of several shapes | §10 |
| COM-1 | Commerce | Entire catalogue / cart / orders / payments / subscriptions / invoices API | **PROPOSED** routes in `lib/core/api/endpoints.dart`; `Idempotency-Key` header on order, payment and renew writes | §12.5 |
| COM-2 | Commerce | Money representation | Integer minor units + ISO currency (decimal strings also accepted) | §13.8 |
| COM-3 | Commerce | Hosted checkout | Payment start returns an `https` checkout URL; final state only from `GET /orders/:id` | §12.3 |
| COM-4 | Commerce | App-store classification per item | `paymentPolicy` field per catalogue item; `inAppDigital` items blocked until IAP decision | §12.6 |
| CFG-1 | Config | Server-driven app config | **PROPOSED** `GET /app/config` (anonymous): `{version:{min,latest}, maintenance:{active,message}, links:{privacyPolicy,terms,analyticsDisclosure}, support:{email,phone}, store:{android,ios}, features:{shop,directory,notifications,accountDeletion}}`. App fails open to defaults if unreachable. | §15.3, App. A |
| ACC-1 | Account | In-app account deletion (App Store 5.1.1(v)) | **PROPOSED** `DELETE /auth/account {password, confirm:'DELETE', reason?}` for owners; server cancels subscriptions, revokes sessions, deletes org data per retention policy. Staff are removed by their owner. | §16 Privacy ops |
| NOT-1 | Notifications | In-app notifications API | **PROPOSED** `GET /notifications`, `POST /notifications/:id/read` | §13.12 |

Feature agents append newly discovered gaps below.

## Additional gaps found during implementation
