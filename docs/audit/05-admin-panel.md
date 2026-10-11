# 05 — Super-admin / admin panel audit

Auditor: agent 05 of 10 · Date: 2026-10-11 · Mode: read-only (no code changed)

Repos examined:
- **Coglink / Bizzvot backend + web** — `/home/user/cogcard` (Next.js App Router, MongoDB/Mongoose, JWT cookie + Bearer auth)
- **Ecommerce storefront + admin** — `/home/user/nfcwebsiteecom-` (Next.js 16, `pages/api` + App Router admin UI, NextAuth). It is currently branded **Enkilum Entekrishna** (`src/app/layout.tsx:102`), a jewellery store (default HSN `7113` in `src/pages/api/admin/orders/[id]/gst-invoice.ts:86`). It has no Bizzvot or NFC code, and it uses a separate database and user base.
- **Mobile app spec** — `/home/user/Bizzvot-apps-/docs/PRODUCT_PLAN.md` (§2.2: super-admin is out of scope for the mobile app, so admin stays on web), `docs/API_GAP_REGISTER.md` (CFG-1 `GET /app/config`, COM-1..4, NOT-1)

---

## 1. Summary

1. **The Coglink super-admin can only moderate a digital-card SaaS. It cannot run a physical-goods business.** It has 9 pages and 20 API handlers in 19 route files: list and suspend orgs and individuals, assign plans, override limits, enable or disable cards, moderate reviews, list and remove domains, and plan CRUD. It has no products, orders, fulfilment, NFC tags, payments, invoices, subscriptions, coupons, app config, broadcast or audit log. Coglink has no commerce models at all (`lib/models/` holds 12 models, none for commerce).
2. **Coglink admin API authorization is consistent.** Every handler under `app/api/v1/admin/**` passes `{ roles: ["super_admin"] }` to `withApi` (`lib/withApi.ts:20-23`). That runs `requireAuth` (JWT plus a live `tokenVersion`/status check, `lib/auth.ts:149-161`) and then `requireRole` (`lib/auth.ts:163-167`). The page group is also gated in `middleware.ts:11-16,210-229`. No admin handler is missing a role check. The real problems are elsewhere:
   - there is a single all-powerful role;
   - no admin action is audited;
   - an admin "disable card" can be undone by the card's owner (§4.1 AZ-1);
   - there is no MFA, and the seed credentials are known.
3. **The ecommerce repo has a fairly complete Shopify-style admin**: orders, Delhivery AWB/label/pickup/NDR/RTO, GST invoice PDF, Razorpay refunds, discounts, gift cards, inventory, reports and an activity-log model. **17 of its `pages/api/admin/**` endpoints have no authentication** (§4.2 E-1). These include unauthenticated product bulk-delete, gift-card minting, store-settings overwrite and a customer order/PII lookup by email. The `proxy.ts` matcher excludes `api/`, so nothing protects these routes globally. This is a live risk for the current store and blocks reuse of the code.
4. **Recommendation:** build the Bizzvot operations admin inside the Coglink backend (`/super-admin` → "Bizzvot Admin"), because the mobile app's commerce API (COM-1) has to live on the same `/api/v1` backend and identity. **Port** (don't link to) the proven ecom modules: Delhivery service, GST invoice, refund flow, discounts and inventory. Fix ecom E-1 first in any case. Add NFC-specific workflow (design proof → print → NFC programming with tag-UID capture → QC → ship), an NFC tag registry, subscriptions/entitlements, `/app/config`, RBAC admin roles and an audit log.

---

## 2. Inventory of existing admin capabilities

### 2.1 Coglink super-admin pages (`/home/user/cogcard`)

Every page is a thin client wrapper: `useRequireRole("super_admin")` around a panel component in `components/dashboard/admin/`. Navigation is in `components/DashboardShell.tsx:37-47`.

| Route | Page file | Panel / component | APIs used | Capability |
|---|---|---|---|---|
| `/super-admin` | `app/(dashboard)/super-admin/page.tsx` | inline + `QuickLinks` | `GET /api/v1/admin/dashboard` | Counts: users, orgs, individuals, cards, reviews, pending reviews |
| `/super-admin/analytics` | `app/(dashboard)/super-admin/analytics/page.tsx` | `AdminAnalyticsPanel.tsx` | same dashboard API | Same counts as a bar chart (duplicate of the home page) |
| `/super-admin/health` | `app/(dashboard)/super-admin/health/page.tsx` | `AdminHealthPanel.tsx` | same dashboard API | Review approval rate only. No infrastructure health (already noted as F4 in `project-docs/06-Audit/POST-REMEDIATION-AUDIT-2026-08-02.md:42`) |
| `/super-admin/organizations` | `.../organizations/page.tsx` | `AdminOrganizationsPanel.tsx` | `GET admin/organizations`, `GET admin/plans`, `PATCH admin/organizations/:id/{status,plan,limits}` | List (first 20 only), suspend/activate, assign plan, override maxCards/maxStaff |
| `/super-admin/individuals` | `.../individuals/page.tsx` | `AdminIndividualsPanel.tsx` | `GET admin/individuals`, `PATCH admin/individuals/:id/{status,plan,limits}` | List (first 20), suspend/activate, assign plan, maxCards override |
| `/super-admin/cards` | `.../cards/page.tsx` | `AdminCardsPanel.tsx` | `GET admin/cards`, `GET admin/cards/:id`, `PATCH admin/cards/:id/status` | List (first 20), raw JSON detail, enable/disable |
| `/super-admin/reviews` | `.../reviews/page.tsx` | `AdminReviewsPanel.tsx` | `GET admin/reviews`, `PATCH admin/reviews/:id/status` | List (first 20; shows name and rating only), approve/hide |
| `/super-admin/domains` | `.../domains/page.tsx` | `AdminDomainsPanel.tsx` | `GET admin/domains`, `DELETE /api/v1/domains/:id` | List (cap 200), remove |
| `/super-admin/plans` | `.../plans/page.tsx` | `AdminPlansPanel.tsx` | `GET/POST admin/plans`, `PATCH/DELETE admin/plans/:id` | Plan CRUD (name, price, maxCards, maxStaff, two feature flags) |

### 2.2 Coglink admin APIs (`app/api/v1/admin/**`)

| Method + path | File | Auth (`withApi` opts) | Behaviour |
|---|---|---|---|
| GET `/admin/dashboard` | `app/api/v1/admin/dashboard/route.ts:9-31` | `roles:["super_admin"]` (l.30) | 7 `countDocuments` |
| GET `/admin/organizations` | `app/api/v1/admin/organizations/route.ts:6-21` | super_admin (l.20) | Paginated (default 20), no search/filter |
| GET `/admin/organizations/:id` | `app/api/v1/admin/organizations/[id]/route.ts:5-12` | super_admin (l.11) | Org + owner. **Not used by the UI** |
| PATCH `/admin/organizations/:id/status` | `.../organizations/[id]/status/route.ts:22-94` | super_admin (l.93) | Two-phase suspend/activate of staff and users, `tokenVersion` bump |
| PATCH `/admin/organizations/:id/plan` | `.../organizations/[id]/plan/route.ts:7-27` | super_admin (l.26) | Sets `planId`, `planExpiry`; in-app notify |
| PATCH `/admin/organizations/:id/limits` | `.../organizations/[id]/limits/route.ts:15-42` | super_admin (l.41) | maxCards/maxStaff override (validated ints) |
| GET `/admin/individuals` | `app/api/v1/admin/individuals/route.ts:6-21` | super_admin (l.20) | Paginated |
| PATCH `/admin/individuals/:id/status` | `.../individuals/[id]/status/route.ts:7-25` | super_admin (l.24) | Suspend + `bumpTokenVersion` |
| PATCH `/admin/individuals/:id/plan` | `.../individuals/[id]/plan/route.ts:7-27` | super_admin (l.26) | Plan + expiry; notify |
| PATCH `/admin/individuals/:id/limits` | `.../individuals/[id]/limits/route.ts:15-40` | super_admin (l.39) | maxCards override |
| GET `/admin/cards` | `app/api/v1/admin/cards/route.ts:6-16` | super_admin (l.15) | Paginated, no filter/search |
| GET `/admin/cards/:id` | `app/api/v1/admin/cards/[id]/route.ts:5-12` | super_admin (l.11) | Full card doc |
| PATCH `/admin/cards/:id/status` | `.../cards/[id]/status/route.ts:5-15` | super_admin (l.14) | active/disabled |
| GET `/admin/reviews` | `app/api/v1/admin/reviews/route.ts:6-23` | super_admin (l.22) | Paginated; `?status=` filter; strips IP fields |
| PATCH `/admin/reviews/:id/status` | `.../reviews/[id]/status/route.ts:5-19` | super_admin (l.18) | pending/approved/hidden, or `status:"delete"` = hard delete |
| GET `/admin/plans` · POST `/admin/plans` | `app/api/v1/admin/plans/route.ts:5-26` | super_admin (l.7, l.25) | List and create |
| PATCH · DELETE `/admin/plans/:id` | `app/api/v1/admin/plans/[id]/route.ts:15-36` | super_admin (l.26, l.35) | Allow-listed update; hard delete |
| GET `/admin/domains` | `app/api/v1/admin/domains/route.ts:8-23` | super_admin (l.22) | Latest 200 + card |

Non-admin routes that grant super_admin cross-tenant power:

| Route | File | super_admin power |
|---|---|---|
| GET/PATCH/DELETE `/api/v1/cards/:id` | `app/api/v1/cards/[id]/route.ts:16,64,74` | Read, **edit all content**, **delete** any tenant's card (`deleteCardAndRelated`). No UI exposure, no audit |
| GET/DELETE `/api/v1/domains/:id` | `app/api/v1/domains/[id]/route.ts:18,61,69` | Read and delete any domain |
| GET `/api/v1/cards/:id/qrcode` | `app/api/v1/cards/[id]/qrcode/route.ts:27` | QR for any card |
| Analytics read | `lib/analytics-access.ts:11` | Any card's analytics |

### 2.3 Ecommerce admin (`/home/user/nfcwebsiteecom-`) — reusable modules

UI is at `src/app/admin/**` (83 pages), APIs at `src/pages/api/admin/**` (82 files). Page access is gated by `src/proxy.ts:71-85` (NextAuth role `admin|staff`).

| Module | Pages | APIs (selection) | Reuse value for Bizzvot |
|---|---|---|---|
| Orders | `admin/orders`, `orders/[id]`, `orders/[id]/edit`, `orders/new` | `orders/index.ts`, `orders/[id].ts`, `orders/bulk.ts`, `orders/[id]/timeline.ts`, `orders/[id]/tracking.ts` | High (list/detail/timeline). Status enum is only `Processing/Shipped/Delivered/Cancelled` (`src/models/Order.ts:39`). No production stages |
| Delhivery shipping | `settings/shipping/**` | `orders/[id]/create-delhivery-shipment.ts`, `delhivery-label.ts`, `delhivery-pickup.ts`, `cancel-delhivery-shipment.ts`, `fetch-delhivery-status.ts`, `bulk-create-delhivery-shipments.ts`, `shipping/delhivery/{check-pincode,ndr-action,reverse-pickup,shipment-history,stats,logs,test}.ts`, `webhooks/delhivery.ts`; lib `src/lib/delhivery-service.ts` (868 lines) | **Very high.** Port as-is |
| GST invoice | — | `orders/[id]/gst-invoice.ts` (PDF, HSN column, IGST vs CGST/SGST) | High. Needs Bizzvot GSTIN, NFC HSN codes and sequential invoice numbering |
| Refunds / returns | — | `orders/[id]/refunds.ts` (Razorpay, ₹1 minimum), `payment/refund.ts`, `returns/*`; lib `return-service.ts` | High |
| Products / variants / inventory | `products/**`, `products/[id]/variants/**`, `inventory` | `products/bulk.ts`, `inventory/bulk-adjust.ts`; `Product.hsnCode` (`src/models/Product.ts:32`), variants and SKU | Medium. No personalization schema or NFC attributes |
| Discounts / gift cards | `discounts/**`, `gift-cards/**` | `discounts/*`, `gift-cards/*`, `shipping-promotions.ts` | Medium–high |
| Customers / segments | `customers/**`, `segments/**` | `customers/*`, `segments/*` | Medium |
| Reports / analytics | `reports/{sales,customers,inventory}`, `analytics` | `reports/*.ts`, `analytics/*.ts` | Medium |
| Settings | `settings/**` | `settings/{index,payment-gateway,delhivery,tax-rates,shipping-zones,gmail}.ts` | Medium |
| Activity log | `admin/activity` | `activity-log.ts`; lib `src/lib/activity-log.ts` | Model only. **`logActivity()` is never called anywhere**, so the log is always empty |
| CMS (blog, pages, menus, metaobjects, banners, translate, jobs) | many | many | Low for operations |

---

## 3. Authorization findings

### 3.1 Coglink (`/home/user/cogcard`)

**Coverage check:** 20/20 handlers under `app/api/v1/admin/**` declare `roles: ["super_admin"]` (line refs in §2.2). `withApi` always runs `requireAuth` when `roles` is set (`lib/withApi.ts:20-23`). `requireAuth` re-validates `tokenVersion` and account status on each request through Redis or the DB (`lib/auth.ts:121-161`), so a suspended admin is locked out within about 30 s. **No missing role checks.**

| ID | Severity | Finding | Evidence | Fix |
|---|---|---|---|---|
| AZ-1 | **High** | **Admin card disable is not a moderation lock.** The owner can re-enable it. `cardWriteSchema` accepts `status` and `CARD_WRITE_FIELDS` includes it, so the org/individual owner `PATCH /api/v1/cards/:id {status:"active"}` reverses an admin takedown. | `lib/validation/card.ts:102,146`; `app/api/v1/cards/[id]/route.ts:40-65`; admin sets plain `status` at `app/api/v1/admin/cards/[id]/status/route.ts:10` | Add `moderation: {state:'none'\|'disabled_by_admin', reason, by, at}`. Owner writes must not clear it. Public render must check it. Same pattern for the planned `disabledByBilling` (plan §13.4) |
| AZ-2 | **High** | **There is one all-powerful role.** `UserRole` is only `super_admin\|organization\|staff\|individual` (`lib/types.ts:1`, `lib/models/User.ts:27-31`). Every ops, fulfilment, support or finance person would need full super_admin: plan pricing, suspending tenants, deleting cards, and (in future) refunds. | `lib/types.ts:1` | Add `adminRole` + permission set (§5, row R-1). Keep `super_admin` as the JWT role and add `adminPerms` checked by a new `withAdmin(perm)` wrapper |
| AZ-3 | **High** | **No admin action is audited.** There is no `AuditLog` model in `lib/models/`. Suspensions, plan changes, review hard-deletes (`reviews/[id]/status/route.ts:8-10`), plan deletes (`plans/[id]/route.ts:29-36`) and cross-tenant card edit/delete through `app/api/v1/cards/[id]/route.ts:64,74` leave no record. | grep: no audit code in `lib/` or `app/` | `auditLogs` collection (plan §13.13) written by `withAdmin` for every mutating admin call (actor, action, resource, before/after diff with safe fields, IP hash, UA) |
| AZ-4 | Medium | **Admin account hardening.** No MFA/TOTP exists anywhere (grep). `scripts/seed.ts:73-74` defaults to `admin@coglink.local` / `Admin@12345`. `scripts/seed.ts:30-36` runs `deleteMany({})` on users, orgs, cards, plans and domains with no production guard. | `scripts/seed.ts` | TOTP MFA required for admin roles. Refuse to seed when `NODE_ENV=production` or the DB is non-empty. Force a password change on first admin login. Allow-list admin IPs or require SSO (optional) |
| AZ-5 | Medium | **Cookie-authenticated admin mutations have no CSRF/Origin check.** The only defence is `SameSite=lax` (`lib/session-cookies.ts:29`). Customer card subdomains under the root domain (`middleware.ts:33-37`) count as *same-site*, so Lax does not protect against requests from them. | `lib/withApi.ts` (no Origin check) | Check `Origin`/`Sec-Fetch-Site` on non-GET admin requests, or serve admin from a dedicated host (`admin.bizzvot.com`) with `SameSite=strict` cookies |
| AZ-6 | Medium | **Plan writes are unvalidated.** `POST/PATCH admin/plans` copy the body straight in: negative or string `price`, arbitrary `features[]`, no `runValidators`. | `app/api/v1/admin/plans/route.ts:12-22`, `plans/[id]/route.ts:17-22` | Zod schema; integer paise; immutable plan versions (plan §13.7) |
| AZ-7 | Low | **Super_admin can silently edit or delete tenant card content** through the generic owner route. This is impersonation by API, with no reason captured. | `app/api/v1/cards/[id]/route.ts:16` | Restrict super_admin on generic routes to read. Expose admin-specific moderation endpoints with a required `reason` and audit |
| AZ-8 | Low | `PATCH admin/reviews/:id/status {status:"delete"}` returns `{deleted:true}` even when the id doesn't exist, and hard-deletes with no soft-delete or reason. | `app/api/v1/admin/reviews/[id]/status/route.ts:8-10` | Soft delete + 404 + audit |

### 3.2 Ecommerce repo (`/home/user/nfcwebsiteecom-`) — must fix before any reuse

| ID | Severity | Finding | Evidence |
|---|---|---|---|
| E-1 | **Critical** | **17 admin API handlers have no authentication at all.** `src/proxy.ts:91-96` excludes `api/` from the matcher, so only per-handler checks protect these routes, and these handlers have none. See the table below. | handler lines below |
| E-2 | High | **RBAC collapses to admin vs customer.** NextAuth maps every non-`admin` user to `customer` (`src/lib/auth/nextauth-options.ts:33`), so the `staff`/`viewer` roles in `src/models/User.ts:8` and `src/lib/auth/roles.ts:1-5` never take effect. Where `staff` is honoured, it gets the same access as admin, including payment-gateway settings (`src/pages/api/admin/settings/payment-gateway.ts:11`). `orders/[id]/tracking.ts:21-25` requires `admin` only, which is inconsistent with the rest. | cited |
| E-3 | Medium | The activity log is never written. `logActivity()` (`src/lib/activity-log.ts:16`) has no callers, and its read endpoint is unauthenticated (E-1). | grep |
| E-4 | Medium | There is no Razorpay webhook, only `src/pages/api/webhooks/delhivery.ts`, so payment state depends on client-initiated verify calls (`payment/razorpay/verify*.ts`). Settlement reconciliation is impossible. | `ls src/pages/api/webhooks` |

E-1 handlers without any session or role check:

| File:line (handler) | Methods | Impact |
|---|---|---|
| `src/pages/api/admin/products/bulk.ts:6` | POST `delete/publish/unpublish/update/export` | **Anyone can delete or alter all products** (`deleteMany` l.24) |
| `src/pages/api/admin/gift-cards/index.ts:15` | GET, POST | **Anyone can mint gift cards** (l.59-75) and list all codes |
| `src/pages/api/admin/gift-cards/[code].ts:5` | GET, PUT, DELETE | Read and alter gift-card balances |
| `src/pages/api/admin/gift-cards/redeem.ts:5` | POST | Redeem arbitrary codes |
| `src/pages/api/admin/settings/index.ts:6` | GET, PUT | **Overwrite store settings** with mass assignment `{...payload}` (l.24), including GSTIN |
| `src/pages/api/admin/customers/[id]/orders.ts:5` | GET | **Customer PII leak:** any email → all orders with addresses and phones (l.18-23) |
| `src/pages/api/admin/media/upload.ts:18` | GET, POST | Unauthenticated file upload to R2 |
| `src/pages/api/admin/pages/[id].ts:5` | GET, PUT, DELETE | CMS page defacement |
| `src/pages/api/admin/metaobjects/definitions/index.ts:5` · `definitions/[id].ts:6` · `entries/[id].ts:6` | GET, POST, PUT, DELETE | Content tampering |
| `src/pages/api/admin/reports/sales.ts:5` · `reports/customers.ts:6` · `reports/inventory.ts:6` | GET | Revenue and customer data exposure |
| `src/pages/api/admin/analytics/summary.ts:7` · `analytics/top-products.ts:5` | GET | Revenue exposure |
| `src/pages/api/admin/activity-log.ts:5` | GET | Admin emails, IPs |

---

## 4. Functional defects in the existing Coglink admin

| ID | Severity | Defect | Evidence |
|---|---|---|---|
| F-1 | High | **`planExpiry` is stored but never enforced.** Nothing reads it outside the admin plan routes, so plans never expire. The UI never sends it either. | grep `planExpiry` → only `lib/models/{Organization,Individual}.ts` and the admin plan routes |
| F-2 | Medium | **Deleting a plan orphans accounts.** Accounts don't fall back to "Free" (the confirm text in `AdminPlansPanel.tsx:121` is wrong). `Plan.findById` returns null, so limits fall to `maxCards 1 / maxStaff 0` and all features turn off (`lib/plans.ts:37-44`). There is no "in use" check in `plans/[id]/route.ts:29-36`. | cited |
| F-3 | Medium | **List pages silently show only the first 20 rows**, with no pager or search (APIs default `limit=20`, `lib/pagination.ts:9`). `AdminCardsPanel.tsx:74` additionally slices to 50. Also F3 in the prior audit. | cited |
| F-4 | Medium | **No billing or subscription concept.** There is no trial, seats, subscription, entitlement or `GET/POST /organization/billing` route (`app/api/v1/organization/` has only cards, dashboard, profile, reviews, staff), although PRODUCT_PLAN §11.1 assumes they exist. | `ls app/api/v1/organization` |
| F-5 | Low | The Health page measures review moderation, not system health. Analytics duplicates the dashboard. | `AdminHealthPanel.tsx`, `AdminAnalyticsPanel.tsx` |
| F-6 | Low | Assigning a plan always clears `planExpiry`: the API sets `null` when the field is absent (`organizations/[id]/plan/route.ts:18`) and the UI never sends it. | cited |

---

## 5. Missing capabilities to operate the Bizzvot business

All proposed APIs live under `/api/v1/admin/**` in the Coglink backend, guarded by a new `withAdmin(permission)` that also writes the audit log. Pages live under `/super-admin/**` (rename the group to "Bizzvot Admin"). Severity: **P0** = cannot take or fulfil orders without it; **P1** = needed in the first weeks; **P2** = scale or quality.

| # | Sev | Gap | Why it matters | Proposed pages | Proposed APIs |
|---|---|---|---|---|---|
| R-1 | **P0** | **Role-based admin users** (owner, ops, fulfilment, support, finance, moderator) | Fulfilment and support staff must not hold pricing, refund or suspend powers (AZ-2) | `/super-admin/team` (invite, role, MFA status, disable, last login) | `GET/POST /admin/team`, `PATCH /admin/team/:id {adminRole, perms[], status}`, `POST /admin/team/:id/reset-mfa`; `User.adminRole`, `adminPerms[]`, `mfa{secret,enabledAt}` |
| R-2 | **P0** | **Audit log for every admin action** | Accountability for refunds, re-points and suspensions. Required by plan §13.13 | `/super-admin/audit` (filter by actor, resource, action, date; diff view) | `GET /admin/audit-logs?actor&resourceType&resourceId&from&to`; written automatically by `withAdmin` |
| R-3 | **P0** | **Product & price management for the 4 NFC SKUs** — Google Review Stand ₹499, Google Review Card ₹350, Staff ID Card (card only) ₹350, Business Digital + Physical NFC Card ₹999 | The app must fetch prices from the backend (plan §11.3, COM-1/2). There is no catalogue today | `/super-admin/products`, `/products/:id` (variants, media, personalization schema, tax, stock, `paymentPolicy` per COM-4, active flag, "includes digital entitlement" link to plan) | `GET/POST /admin/products`, `PATCH /admin/products/:id`, `POST /admin/products/:id/variants`, `PATCH /admin/variants/:id`; public `GET /catalog/products` |
| R-4 | **P0** | **Variants, stock, HSN/GST** | GST invoices need HSN and rate per SKU. Stock-outs of NFC blanks and stands stop fulfilment | Stock tab on product; `/super-admin/inventory` (blanks: NTAG chips, PVC cards, acrylic stands; reorder level) | `PATCH /admin/variants/:id {sku, priceInclGstPaise, gstRate, hsn, stock, reorderLevel}`, `POST /admin/inventory/adjust {variantId, delta, reason}`. HSN e.g. `8523 52` for smart cards; confirm with the CA |
| R-5 | **P0** | **Order management**: list, filter (status, product, payment, date, pincode, org), search (order no, phone, email, AWB), detail, notes, timeline | Core ops view. Nothing exists in Coglink | `/super-admin/orders`, `/orders/:id` (items, personalization data, payment attempts, shipments, NFC tags, invoices, timeline) | `GET /admin/orders?status&product&payment&q&from&to&page`, `GET /admin/orders/:id`, `POST /admin/orders/:id/notes`, `GET /admin/orders/export.csv` |
| R-6 | **P0** | **Order/unit state machine with guarded transitions** | Physical NFC goods go through stages a generic ecom flow lacks. Status is needed per **unit** (each card has its own tag) | Status stepper + bulk actions on the orders list | `POST /admin/orders/:id/transition {to, reason}`, `POST /admin/order-units/:id/transition`. States: `pending_payment → paid → awaiting_details → proof_pending → proof_sent → (changes_requested ↔ proof_sent) → proof_approved → printing → printed → nfc_programming → programmed → qc_passed\|qc_failed → packed → shipped → in_transit → out_for_delivery → delivered`; side states `cancelled`, `rto`, `ndr`, `replacement_requested`, `refunded` |
| R-7 | **P0** | **Design proof upload & customer approval** | Personalised print (name, photo, logo, QR, Google business name) must not print without sign-off. Avoids reprints | Proof panel on order unit: upload PDF/PNG versions, see customer comments, mark approved on the customer's behalf (with reason) | `POST /admin/order-units/:id/proofs` (multipart), `GET .../proofs`; customer side `GET /orders/:id/proofs`, `POST /orders/:id/proofs/:pid/{approve,request-changes}`; reminder after N hours |
| R-8 | **P0** | **Printing queue** | Batch work for the print vendor | `/super-admin/fulfilment/print` (approved units grouped by product/variant; export print sheet ZIP/CSV; mark printed) | `GET /admin/queues/print`, `POST /admin/queues/print/batch {unitIds}` → batchId, `POST /admin/print-batches/:id/complete` |
| R-9 | **P0** | **NFC programming queue with tag UID capture and URL to write** | Every tag must be bound to the right card or Google review link. Without the UID there is no lost-tag disable or re-point | `/super-admin/fulfilment/nfc` (per unit: URL to write, copy/QR; scan/enter UID; verify read-back; lock flag) — usable on an Android phone browser with Web NFC, or on a desktop with a USB reader in keyboard-wedge mode | `GET /admin/queues/nfc`, `POST /admin/order-units/:id/nfc {tagUid, chipType, locked, verifiedUrl}`. The server generates the **URL to write as an indirection short link** `https://bizzvot.com/t/{code}`, never the raw Google or card URL, so the target can be re-pointed later. UID is unique-indexed |
| R-10 | **P0** | **QC step** | Catch misprints and wrong encodes before shipping | QC checklist per unit (print OK, tap test resolves to the expected target, packaging); fail → back to print/NFC | `POST /admin/order-units/:id/qc {passed, checks{}, notes, photoUrl?}` |
| R-11 | **P0** | **Shipping label / AWB via Delhivery, pickup, tracking, delivery confirmation** | Fulfilment. The ecom repo already has this logic | Ship panel: pincode serviceability, create shipment, print label, schedule pickup, NDR actions, RTO/reverse pickup; `/super-admin/shipments` | Port `src/lib/delhivery-service.ts`: `POST /admin/orders/:id/shipments`, `GET /admin/shipments/:id/label`, `POST /admin/shipments/pickup`, `POST /admin/shipments/:id/{cancel,ndr-action,reverse-pickup}`, webhook `POST /webhooks/delhivery` (signed) → auto `in_transit/delivered`, customer push |
| R-12 | **P0** | **Payment visibility & Razorpay webhook** | Orders must become paid only on server-verified events (plan §12.3) | Payments tab on order (attempts, gateway ids, signature verified, webhook events) | `POST /webhooks/razorpay` (HMAC-verified, idempotent), `GET /admin/payments?status&from&to`, `GET /admin/payments/:id` |
| R-13 | P1 | **Refunds, cancellations, RMA, replacements** | Wrong print, dead chip, transit damage. Replacements must issue a new unit/tag and disable the old one | Refund dialog (full/partial, reason, Razorpay refund id); RMA list `/super-admin/returns` (request → approve → reverse pickup → received → replace/refund) | `POST /admin/orders/:id/cancel`, `POST /admin/orders/:id/refunds {amountPaise, reason, lineItems}`, `GET/PATCH /admin/rmas/:id`, `POST /admin/order-units/:id/replace` (clones unit, links old tag → `replaced`) |
| R-14 | P1 | **Invoices & GST reports** | Legal requirement (B2B GSTIN on orgs exists: `Organization.gstNumber`, `lib/models/Organization.ts:21`). Credit notes on refunds | `/super-admin/invoices` (list, regenerate, void, credit notes); `/super-admin/reports/gst` (GSTR-1 style B2B/B2C, HSN summary, IGST vs CGST/SGST by state) | `GET /admin/invoices`, `GET /admin/invoices/:id.pdf`, `POST /admin/invoices/:id/credit-note`, `GET /admin/reports/gst?month=YYYY-MM&format=csv\|json`. Gap-free invoice series per FY |
| R-15 | P1 | **Payment reconciliation (Razorpay settlements vs orders)** | Detect paid-but-not-fulfilled, refunded-but-active and fee/TDS variance | `/super-admin/finance/reconciliation` (settlement list, matched/unmatched, variance) | Nightly job pulling Razorpay settlements/payments → `settlements` collection; `GET /admin/reconciliation?from&to&state=unmatched`, `POST /admin/reconciliation/:id/resolve` |
| R-16 | **P0** | **Subscriptions / seats / entitlements admin** (grant, extend trial, grace periods, comp seats) | The ₹999 Business card bundles a digital card. Seats gate active cards. Plan §11, §13.10 requires server-side entitlements and reconciliation. Today there is only `planId` with an unenforced `planExpiry` (F-1) | Org detail → Billing tab: subscription, seats, trial end, grace until, entitlement ledger; actions: grant seats, extend trial, set grace, cancel at period end, comp plan (all require a reason) | `GET /admin/organizations/:id/subscription`, `POST /admin/organizations/:id/entitlements {type, quantity, validUntil, reason}`, `POST /admin/subscriptions/:id/{extend-trial,set-grace,cancel,resume}`; scheduler for expiry → `disabledByBilling` on cards |
| R-17 | P1 | **Coupons / discounts** | Launch promotions and B2B bulk pricing (e.g. 10+ staff cards) | `/super-admin/coupons` (code, %/flat, min order, product scope, usage limits, validity, per-customer limit) | `GET/POST /admin/coupons`, `PATCH /admin/coupons/:id`; server-side validation in `POST /cart/quote`. Port the ecom `Discount` model |
| R-18 | P1 | **Customer support view** (read-only, impersonation-free 360° org view) | Support must answer "where is my card / why is my tag not working" without logging in as the user or editing their data | `/super-admin/organizations/:id` tabs: profile, owner and staff, cards (public preview), tags, orders, subscription, reviews, notifications sent, audit trail. Everything read-only; actions only through explicit audited buttons | `GET /admin/organizations/:id/overview` (aggregated; private fields masked unless `support.pii` permission), `GET /admin/individuals/:id/overview`; global search `GET /admin/search?q=` (email, phone, order no, AWB, tag UID, slug) |
| R-19 | **P0** | **NFC tag registry** (re-point, disable lost tags, history) | Lost staff ID cards must be disabled immediately. Review stands move to a new Google place. Ex-employees leave | `/super-admin/tags` (search by UID or code; status `unassigned/programmed/active/lost/disabled/replaced`; target; tap count; history); owners also see their tags in-app | `GET /admin/tags?q&status`, `GET /admin/tags/:id`, `PATCH /admin/tags/:id {target, status, reason}`, `POST /admin/tags/:id/disable`; public resolver `GET /t/:code` → 302 to the current target, or a "tag disabled" page. Pre-registration of blank stock via CSV import |
| R-20 | P1 | **Mobile app config** — the app expects `GET /app/config` (CFG-1) | Force-update, maintenance banner, feature kill-switches (shop, directory, notifications, accountDeletion), legal links and store links | `/super-admin/app-config` (form + JSON preview + change history; per-platform min/latest version) | Public `GET /api/v1/app/config` (anonymous, cached, ETag) returning the CFG-1 shape exactly; `GET/PUT /admin/app-config` (audited, versioned) |
| R-21 | P1 | **Push / in-app notification broadcast** | Order-stage updates, proof-approval nags, renewal reminders, maintenance notices. Today `Notification` is one user + message (`lib/models/Notification.ts:3-21`) with no device tokens or segments | `/super-admin/notifications` (compose; audience: all, plan, org, role, platform, app version; schedule; preview; delivery stats); template editor for transactional events | `POST /admin/broadcasts {title, body, deepLink, audience, channels:['inapp','push'], scheduleAt}`, `GET /admin/broadcasts/:id/stats`; `POST /devices` (FCM/APNs token registration from the app); `GET /notifications` (NOT-1) |
| R-22 | P1 | **Platform review moderation upgrade** | The current UI hides review text and card (`AdminReviewsPanel.tsx:16,64-81`). There is no reported/abuse queue and no filtering by org | `/super-admin/reviews` with text, card/org, rating, date, status filter, bulk actions, reason | Extend `GET /admin/reviews?status&orgId&cardId&rating&q`, `PATCH /admin/reviews/bulk`; soft delete (AZ-8) |
| R-23 | P1 | **Analytics / revenue dashboard** | Run the business: GMV, net revenue after refunds, AOV, orders by stage, SLA (paid → shipped), proof turnaround, MRR/seats, churn, NFC taps, app installs/versions | `/super-admin` rebuilt: KPI tiles + trends; `/super-admin/reports/{sales,fulfilment,subscriptions}` | `GET /admin/metrics/overview?from&to`, `/admin/metrics/fulfilment-sla`, `/admin/metrics/subscriptions` (pre-aggregated daily) |
| R-24 | P2 | **System health** | Replace F-5 | `/super-admin/health`: Mongo, Redis, SMTP, storage, Razorpay/Delhivery reachability, webhook lag, job queue | `GET /admin/health` |
| R-25 | P2 | **Customer/account lifecycle** | Account deletion requests (ACC-1), data export, GSTIN edits, manual order creation for B2B/offline sales | `/super-admin/requests` | `GET /admin/deletion-requests`, `POST /admin/orders` (manual/B2B, payment link) |

---

## 6. UX / quality issues in the existing admin UI

1. **No pagination, search or filters** on any list (F-3). Admins can't find a specific org, card or review once there are more than 20.
2. **Actions fire immediately with no confirmation or reason.** The plan `<select>` assigns on `onChange` (`AdminOrganizationsPanel.tsx:160-171`, `AdminIndividualsPanel.tsx:150-161`), and suspend/disable toggles have no confirm (`AdminCardsPanel.tsx:91`, `AdminOrganizationsPanel.tsx:209`). One mis-click suspends a whole org and logs out all its staff.
3. **The plan select doesn't show the current plan.** It shows `defaultValue=""` "Assign…", and there's no way to set `planExpiry`.
4. **Card detail is a raw `JSON.stringify` dump** (`AdminCardsPanel.tsx:116-128`). It also exposes private fields without masking and uses a hard-coded light background `#f3f6f9` that breaks a dark theme.
5. **The reviews table shows reviewer name and rating only.** No comment, card, org or date, and no status filter (the API supports `?status=` but the UI doesn't use it). Moderators approve blind.
6. **No detail pages.** Orgs and individuals are only rows. `GET /admin/organizations/:id` exists but nothing uses it.
7. **Messages and errors stack.** `msg` and `error` are never cleared on success in most panels, so a stale error persists next to a success message. Errors use inline hard-coded colour `#f06548`, which is not a token.
8. **Inline styles everywhere and no shared table, pager or empty-state components.** Each new admin page has to re-implement them. Introduce shared `AdminTable` (server pagination, sort, filters, bulk select), `ConfirmDialog` (with a reason field), `DetailDrawer` and `StatusStepper` before building §5.
9. **Analytics and Health duplicate the dashboard data** and add nothing (F-5).
10. **Plan delete confirm text is misleading** (F-2).
11. **Client-side role gate** relies on `localStorage.role` (`lib/useRequireRole.ts:19`). That's fine because middleware and APIs enforce access, but the page can flash before a redirect.

---

## 7. Architecture recommendation

- **One backend and one identity.** The mobile app's commerce routes (COM-1: `/catalog`, `/cart/quote`, `/orders`, `/subscriptions`, `/invoices`) and `GET /app/config` must be on the Coglink `/api/v1` backend with Bearer auth (AUTH-1). The admin must operate on the same collections, so build it in `/home/user/cogcard`, not in the ecom repo.
- **Port, don't federate, the ecom modules.** Bring over `delhivery-service.ts`, `gst-invoice.ts`, the refund flow, `Discount`, the `Product` variant/HSN fields and `ActivityLog`. Adapt them to Coglink conventions (`withApi`/zod/pagination, integer paise per COM-2, immutable price and tax snapshots per plan §13.8).
- **Introduce `withAdmin(perm)`.** It wraps `withApi({roles:['super_admin']})`, adds a permission check against `adminPerms`, an Origin check (AZ-5), and audit logging (AZ-3). Migrate all 20 existing handlers to it.
- **Model the order unit as first class** (`orderUnits`: one per physical item). It carries proofs, print batch, NFC tag, QC and shipment link. That's what makes replacements, lost-tag disable and per-item status possible.
- **Use indirection for NFC URLs.** Always write `https://bizzvot.com/t/{code}` to tags. The registry holds the target (card slug or Google review URL from a Place ID). That's what makes re-pointing and disabling possible with no physical access to the tag. Coordinate with audit 04 (commerce) and 06 (public NFC links).
- **Consider serving admin on a separate host** (`admin.bizzvot.com`) with strict cookies, MFA and an optional IP allow-list.

---

## 8. Prioritized build plan

**Phase 0 — Security hygiene (before anything else, about 2–3 days)**
1. Ecom repo: add `getServerSession` + `canAccessAdmin` to the 17 E-1 handlers (or a shared `withAdminApi` wrapper), and fix the mass assignment in `settings/index.ts`. This protects the live store whether or not the code is reused.
2. Coglink: AZ-1 moderation lock on cards; production guard on `scripts/seed.ts`; rotate the seeded admin password; AZ-8 review soft delete.
3. Coglink: `AuditLog` model + `withAdmin(perm)` wrapper + Origin check; migrate the existing 20 handlers (AZ-3, AZ-5).

**Phase 1 — Sell & fulfil the 4 NFC products (P0, about 3–4 weeks)**
4. RBAC admin team + MFA (R-1, AZ-4) and audit log page (R-2).
5. Catalogue: products, variants, HSN/GST, stock, personalization schema, `paymentPolicy` (R-3, R-4) + public `GET /catalog/products`.
6. Orders + order units + state machine + Razorpay webhook (R-5, R-6, R-12).
7. Fulfilment workbench: proof upload/approval (R-7) → print queue (R-8) → NFC programming with UID capture and short-link URL (R-9) → QC (R-10).
8. NFC tag registry + `/t/:code` resolver with disable and re-point (R-19).
9. Delhivery port: AWB, label, pickup, webhook tracking, delivery confirmation (R-11).
10. Subscriptions/seats/entitlements admin, including the entitlement granted by the ₹999 bundle; enforce expiry and grace (R-16, F-1, F-4).

**Phase 2 — Money, support, app operations (P1, about 2–3 weeks)**
11. Refunds, cancellations, RMA, replacements (R-13).
12. Invoices with an FY series, credit notes, GST monthly report (R-14).
13. `GET /app/config` + admin editor (R-20). This is cheap and unblocks app release gating, so it can be pulled into Phase 1.
14. Read-only org 360° support view + global search (R-18); admin list pagination/search/filters across the board (F-3, UX 1–6).
15. Coupons (R-17); review moderation upgrade (R-22).
16. Push device registration + broadcast + transactional templates (R-21).

**Phase 3 — Insight & scale (P2)**
17. Razorpay settlement reconciliation job + finance page (R-15).
18. Revenue/fulfilment/subscription dashboards (R-23); real system health (R-24).
19. Account deletion queue, manual B2B orders and payment links (R-25).

---

## 9. Decisions needed (for product/backend owners)

1. Are prices GST-inclusive (₹499/₹350/₹999 shown to customers) or exclusive? What are the HSN codes and rates per SKU? (Confirm with the CA.)
2. What does the ₹999 Business Digital + Physical card include: one seat for how long, and does it renew at what price?
3. For the Staff ID Card (card only, ₹350): does it require an existing paid seat, or does it ship bound only to an existing staff card?
4. Proof SLA and auto-approve policy: auto-approve after X days, or never?
5. NFC chip type (NTAG213/215/216) and whether to permanently lock tags after write. Locking only works safely because of the `/t/{code}` indirection.
6. Which admin roles exist on day one, and who holds refund and price-change permissions?
7. Is the ecom repo meant to become the Bizzvot storefront, or is it only reference code? This audit assumes reference code: port into Coglink.
