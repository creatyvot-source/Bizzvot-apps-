# Audit 03: Data model, MongoDB and tenant isolation

**Scope.** This was a read-only audit of:

- the Coglink backend at `/home/user/cogcard`: `lib/models/**`, `lib/db/connect.ts`, all 69 `app/api/v1/**/route.ts` files, `lib/publicCard.ts`, `lib/api.ts`, `lib/plans.ts`, `lib/vcard.ts` and `project-docs/04-Database/collections.md`
- the ecommerce repo at `/home/user/nfcwebsiteecom-` (`src/models/**` plus the checkout, payment and Delhivery code), to see what can be reused
- the spec, `docs/PRODUCT_PLAN.md` §6.4, §7, §11, §12, §13 and Appendix B

Every finding below comes from reading the code. Each one cites `file:line`. Unless noted otherwise, paths are relative to `/home/user/cogcard`.

---

## 0. Headline findings

| # | Severity | Finding | Evidence |
|---|---|---|---|
| F1 | **High (privacy)** | `GET /public/card/:slug/reviews` returns **`reviewerEmail`** and `reply.repliedBy` (an internal user id) to anonymous visitors. The response is built by deleting a few fields from the DB object (a deny-list), not from an explicit public DTO. | `app/api/v1/public/card/[slug]/reviews/route.ts:22-31` selects `-ipAddress -ipHash` only. `lib/api.ts:108-113` `sanitizeReview` deletes only `ipAddress` and `ipHash`. |
| F2 | **High (billing/moderation)** | Owners can **re-enable a card that a super-admin disabled**, and this will also work against any future billing disable. `status` is in the owner write schema, and `active`/`disabled` is one field shared by owner pause, admin moderation and billing. | `lib/validation/card.ts:102,146`. It is applied in `app/api/v1/organization/cards/[id]/route.ts:40`, `individual/card/route.ts:125`, `individual/card/[id]/route.ts:39` and `cards/[id]/route.ts:55`. |
| F3 | **High (billing)** | Nothing enforces billing: `planExpiry` is written but never read. A suspended org's cards stay publicly reachable, because the public endpoints check only `card.status`. There are no subscription, entitlement, order, payment or invoice collections. | `grep planExpiry` finds hits only in the admin plan routes. The `Card.findOne({slug, status:"active"})` lookup is at `public/card/[slug]/route.ts:16`, `reviews/route.ts:14`, `review/route.ts:61` and `exchange/route.ts:28`, and `cards/[id]/vcard/route.ts:14-15` does the same. |
| F4 | High (spec gap) | The spec assumes fields and routes that **do not exist** in Coglink: `bloodGroup`, `fatherName`, `motherName`, `disabledByBilling`, `visibility`, `directoryVisibility`, `cards.organizationId`, `cards.staffUserId`, `/organization/billing`, gallery/PDF/YouTube media, and the `profile_hub`, `cover_card` and `review_card` templates. | `lib/models/Card.ts` (full file). `grep -ri "bloodGroup\|billing"` finds no models and no routes. |
| F5 | Medium | There is **no seat count of record**. `Organization.cardCount` is a lazily synced cache. The limit is `org.maxCards ?? plan.maxCards`. A slot is used when a card is *created*, not when it is *activated*, so disabled cards still use slots. Lowering a limit disables nothing, and nothing reconciles the cache. | `lib/models/Organization.ts:13-18`, `lib/plans.ts:29-46,82-131` |
| F6 | Medium | Public slugs can be changed freely and there is no slug history. **An NFC chip or QR code programmed with `/card/{slug}` breaks** when the owner renames the slug. | `lib/cardSlug.ts:9-25` |
| F7 | Medium | Important lookups have no index. `Organization.ownerUserId` has no index and is not unique, yet it runs on every org request. There is no compound `{ownerType, ownerId}` on cards and no `{cardId,status,createdAt}` on reviews. `LinkClick` and `Notification` have no TTL. | `lib/models/Organization.ts:29`, `Card.ts:48`, `Review.ts:49`, `LinkClick.ts`, `Notification.ts` |
| F8 | Low (defence in depth) | Some ownership checks are incomplete. Staff routes trust `assignedCardIds` and do not re-check `card.ownerId == staff.organizationId`. Org checks compare `ownerId` but not `ownerType`. `track-click` writes analytics to **any** card id, including disabled cards. Deleting a card leaves stale ids in `Staff.assignedCardIds`. | Section 4 |
| F9 | Info | MongoDB runs **standalone, not as a replica set**, so multi-document transactions are unavailable. The commerce flow (order → payment → entitlement → nfcTag) needs them. | `docker-compose.yml:1-4`, `lib/plans.ts:9-14` |
| F10 | Info | Parts of the ecom repo can be reused (Counter, GST tax split, address shape, Delhivery client, ShippingZone). Its **order pricing path trusts client-supplied price, subtotal, shipping and tax**, so do not reuse that part. | `nfcwebsiteecom-/src/app/checkout/actions.ts:322,341,352-357` |

---

## 1. Inventory of existing Coglink Mongoose models

DB connection: `lib/db/connect.ts` (cached `mongoose.connect`, `bufferCommands:false`, default `autoIndex`, so indexes are built when the model compiles). There are 12 models, exported from `lib/models/index.ts`.

| Model (collection) | File | Fields | Indexes | Notes |
|---|---|---|---|---|
| **User** (`users`) | `lib/models/User.ts` | name\*, email\* (lowercase, trim), phone, password\* (bcrypt hash), role\* (`super_admin \| organization \| staff \| individual`), organizationId (ref Organization, default null), status (`active \| suspended`), tokenVersion, failedLoginAttempts, lockUntil, timestamps | `email` unique | Has no `customer` role for ecom buyers. Email is unique across the whole platform. `organizationId` stays null for org owners: it is set only for staff, and `auth-tokens.ts:26-38` resolves it at token time. |
| **Organization** (`organizations`) | `lib/models/Organization.ts` | ownerUserId\*, name\*, logo, industry, planId, planExpiry, maxCards, maxStaff (override; null means use the plan), cardCount, staffCount (atomic reservation counters, synced lazily), address (free text), gstNumber, status, timestamps | **none** (only `_id`) | No `slug`, `directoryVisibility`, `trial` or `publicEligible`. `ownerUserId` is not indexed and not unique. Lines 50-61 patch the schema at runtime for stale cached models. |
| **Staff** (`staffs`) | `lib/models/Staff.ts` | userId\*, organizationId\*, permissions{editCard=true, viewReviews=true, replyReviews=false, manageLinks=true}, assignedCardIds[] (ref Card), status, timestamps | `userId` unique; `organizationId` | Permissions default to **true**, but spec §13.3 says they should default to false. Staff-to-card is many-to-many; the spec's model is one card per staff (`cards.staffUserId`). |
| **Individual** (`individuals`) | `lib/models/Individual.ts` | userId\* (unique), planId, planExpiry, maxCards, cardCount, status, timestamps | `userId` unique | This is a B2C tenant type the spec does not mention. |
| **Card** (`cards`) | `lib/models/Card.ts` | type\* (`business \| individual`), ownerType\* (`organization \| individual`), ownerId\* (polymorphic, no ref), createdByStaffId, slug\* (unique, lowercase), title\*, designation, companyName, pronouns, photo, coverImage, logo, bio, phone, whatsapp, email, website, socialLinks[{platform,url}], address, mapLink, theme{templateId enum(minimal, corporate, modern_dark), primaryColor, layout, sectionOrder[]}, customLinks[{label,url,icon}], vcardEnabled, displayOptions{showBio, showSocials, showAddress, showWhatsapp, showCustomLinks, showReviews}, qrCodeUrl (a 512px base64 data URL), status (`active \| disabled`), timestamps | `slug` unique; `ownerId` | **Missing:** organizationId, staffUserId, visibility, disabledByBilling, disabledByAdmin, companyPhone, private fields (bloodGroup, fatherName, motherName), gallery, pdfs, videos, slugHistory, and the 3 newer templates. The QR data URL is stored inside the card, which bloats every list response. |
| **Review** (`reviews`) | `lib/models/Review.ts` | cardId\*, reviewerName\*, reviewerEmail, rating\* (1-5), comment, ipAddress (legacy, `select:false`), ipHash\*, status (`pending \| approved \| hidden`, default approved), reply{text, repliedBy, repliedAt}, timestamps | `cardId`; `{cardId, ipHash}` unique | No `organizationId`. No `{cardId,status,createdAt}` index for the public list query. `reviewerEmail` has no `select:false`. |
| **CardView** (`cardviews`) | `lib/models/CardView.ts` | cardId\*, ipAddress (legacy, select:false), ipHash\*, userAgent, referrer, viewedAt | `cardId`; `{cardId, viewedAt:-1}`; TTL `viewedAt` 180 days | The spec's `cardEvents` covers this collection. |
| **LinkClick** (`linkclicks`) | `lib/models/LinkClick.ts` | cardId\*, linkType\*, linkUrl, ipHash, clickedAt | `cardId` | **No TTL**, so visitor-level data is kept forever (against spec §13.6). |
| **Plan** (`plans`) | `lib/models/Plan.ts` | name\* (unique), price, maxCards, maxStaff, customDomain, reviewModeration, features[], timestamps | `name` unique | No version, billingPeriod, currency, active flag or seat price. The plan is edited in place (`admin/plans/[id]/route.ts:22`), so history changes when it is edited, against spec §13.7. It can be hard-deleted while orgs still reference it. |
| **Notification** (`notifications`) | `lib/models/Notification.ts` | userId\*, type\*, message\* (free text), isRead, timestamps | `userId` | Visitor contact details from exchange (name, email, phone, message) are stored as plain text in `message` (`public/card/[slug]/exchange/route.ts:32`). No organizationId, no structured payload, no TTL. |
| **Domain** (`domains`) | `lib/models/Domain.ts` | hostname\* (unique), type, ownerType, ownerId, cardId, status (`pending \| active \| failed`), verificationToken, verifiedAt, lastError, timestamps | `hostname` unique; `ownerId`; `{ownerType, ownerId}`; `{status, hostname}` | Ownership is checked correctly (Section 4). |
| **PasswordResetToken** | `lib/models/PasswordResetToken.ts` | userId, tokenHash (unique), expiresAt, usedAt | `userId`; `tokenHash` unique; TTL `expiresAt` | OK. |

\* = required. There is **no** audit-log, order, payment, subscription, entitlement, invoice, address, product, shipment or NFC tag collection. Delete cascades are documented in `project-docs/04-Database/collections.md:91-98`. The policy is hard delete with no soft delete ("No soft-delete / audit-trail collection yet").

### 1.1 Ecom repo models (`/home/user/nfcwebsiteecom-/src/models`): what can be reused

| Model | Reusable? | Notes |
|---|---|---|
| `Order.ts` | **Partly: the shapes only** | Good pieces: `orderNumber` unique; `AddressSchema` (incl. `provinceCode`); `taxType` (`IGST \| CGST_SGST \| NO_GST`) plus `taxBreakdown`; `paymentGatewayOrderId` and `paymentGatewayPaymentId` unique and sparse; `timeline[]`; `refunds[]`. Missing: organizationId, buyerUserId (it uses `customerId`/`userEmail`), HSN per line, personalisation, NFC linkage, a fulfilment state machine (status is only `Processing/Shipped/Delivered/Cancelled`), and immutability. AWB and courier live on the order (`trackingNumber`, `carrier`), so one order cannot have several shipments. |
| `Product.ts` and `Product.js` | Concept only | **Two different schemas register the same model name `'Product'`**: `Product.ts:60` and `Product.js:100`. Whichever loads first wins. `strict:false`. Variant ids are strings. It does have `hsnCode`, `gstRate`, `gstType` and variant weight/dimensions, which are useful for Delhivery. |
| `Counter.ts` and `lib/order-number.ts` | **Yes** | Atomic `findOneAndUpdate` with `$inc`-style upsert. Reuse it for order and invoice serials, with one counter key per financial year. |
| `OrderTransaction.ts` | No | It imports Shopify history and has no idempotency or unique gateway ids. Use `paymentAttempts` instead (Section 3). |
| `ShippingZone.ts`, `ShippingProfile.ts` | Yes, for a flat-rate India zone | Price- or weight-based rates per country/state. |
| `TaxRate.ts` | No | One flat rate per region. Indian GST needs a CGST/SGST vs IGST decision based on place of supply. |
| `Customer.ts` (embedded `addresses[]`) | Shape only | Customers are keyed by email, with no tenant. Coglink should hold addresses itself (Section 3.7). |
| `lib/delhivery-service.ts`, `lib/delhivery-sync-order.ts`, `pages/api/webhooks/delhivery.ts` | **Yes, the client and status mapping** | The webhook secret is **optional**: when `DELHIVERY_WEBHOOK_SECRET` is unset, the webhook accepts unauthenticated calls (`webhooks/delhivery.ts:106-114`). Scan status is written onto the order, not into a shipment timeline. |
| `app/checkout/actions.ts` (pricing) | **Do not reuse** | Line price, subtotal, discount, shipping and tax come from the client form (`actions.ts:322,341,352-357`). There is no Razorpay webhook (`pages/api/webhooks` contains only `delhivery.ts`). `payment-service.ts:594-625` `confirmRazorpayPayment` fetches the payment by id and accepts it when it is `captured \| authorized`, without matching `order_id` or amount. Agent 04 covers this in depth. |

---

## 2. Spec §13 collections mapped to existing models

| Spec collection | Status | Existing model | Missing fields and work |
|---|---|---|---|
| 13.1 `organizations` | **PARTIAL** | Organization | `slug` (unique), `directoryVisibility` (`public \| private`), `publicEligible`, `trial{startedAt, endsAt, status}`, `profile{}` (structured address: line1, city, state, **stateCode**, pincode; phone; website; brand colours), `billingSummary` (cached, read-only, see Section 5), `deletedAt`. Indexes: `ownerUserId` unique, `slug` unique, `{status, directoryVisibility}`. |
| 13.2 `users` | **PARTIAL** | User | `customer` role (or a decision to treat ecom buyers as `organization` or `individual`), `emailVerifiedAt`, `phoneVerifiedAt`. `tokenVersion` already fills the role of `authVersion`. Add index `{organizationId, role}`. |
| 13.3 `staffPermissions` | **PARTIAL (embedded)** | `Staff.permissions` | Keep it embedded in Staff. That works: `Staff.userId` is already unique. Change the defaults to `false` (`Staff.ts:20-23`) and add `updatedBy`. A separate collection is not needed. |
| 13.4 `cards` | **PARTIAL** | Card | `organizationId` (denormalised from ownerType/ownerId), `staffUserId`, `visibility` (`inherit \| public \| private`), `disabledByBilling` with `disabledByBillingAt`, `disabledByAdmin` with `disabledReason`, `publishedAt`, `companyPhone`, `private{bloodGroup, fatherName, motherName}` (sub-document with `select:false`), `media{gallery[≤5], pdfs[≤10], videos[≤5]}` holding asset ids, `slugHistory[]` or a `slugAliases` collection, and the templates `profile_hub \| cover_card \| review_card`. Move `qrCodeUrl` out of the document. Indexes: `{organizationId, staffUserId}`, `{organizationId, status, visibility}`, `{ownerType, ownerId, createdAt}`. |
| 13.5 `reviews` | **PARTIAL** | Review | `organizationId`. `reviewerEmail` should get `select:false` or move into `private{}`. Add index `{cardId, status, createdAt:-1}`. The dedupe strategy already exists: unique `{cardId, ipHash}` plus a cookie hash. |
| 13.6 `cardEvents` | **PARTIAL (2 collections)** | CardView and LinkClick | `organizationId`, `eventType` (`view \| click \| vcard \| nfc_tap \| qr_scan \| review_redirect`), `destinationType`, `nfcTagId`. Either merge into `cardEvents` (TTL 180 days) or add a TTL to LinkClick. Add rollups in `cardDailyStats` for long-term analytics. |
| 13.7 `plans` | **PARTIAL** | Plan | `version`, `code`, `billingPeriod`, `currency`, `pricePaise`, `seatPricePaise`, `limits{}`, `active`, `supersedesPlanId`. Plans must be immutable once any subscription references them. |
| 13.7 `services/products` | **MISSING** | none | See Section 3.1 for the design and seed data. |
| 13.8 `orders` | **MISSING** | none (the ecom `Order` is the shape to start from) | Section 3.2 |
| 13.9 `paymentAttempts` | **MISSING** | none | Section 3.3, plus `webhookEvents` |
| 13.10 `subscriptions` | **MISSING** | none (`Organization.planId` and `planExpiry` are all there is) | Section 5 |
| 13.10 `entitlements` | **MISSING** | none (seat limits live in `plan.maxCards`, `org.maxCards` and the `cardCount` cache) | Section 5 |
| 13.11 `invoices` | **MISSING** | none | Section 3.6 |
| 13.12 `notifications` | **PARTIAL** | Notification | `organizationId`, structured `payload{}` (in place of PII in `message`), `readAt` in place of `isRead`. Index `{userId, readAt, createdAt:-1}`. TTL of about 180 days. |
| 13.13 `auditLogs` | **MISSING** | none | Fields: actorUserId, actorRole, organizationId, action, resourceType, resourceId, `changes` (field names only, never private values), ipHash, requestId, createdAt. Index `{organizationId, createdAt:-1}` and `{resourceType, resourceId, createdAt:-1}`. Append-only, so the app user has no update or delete. |
| (new) `shipments`, `nfcTags`, `addresses`, `counters`, `webhookEvents`, `slugAliases`, `mediaAssets` | **MISSING** | none | Section 3 |

---

## 3. New collections for physical NFC commerce

Conventions used throughout:

- Money is in **integer paise** (`amountPaise`). Never use floats.
- Currency is `INR`.
- Every tenant-owned document carries `organizationId` (null for individual buyers) and `buyerUserId`.
- Timestamps are on.
- IDs are ObjectIds and are validated with `mongoose.isValidObjectId` before any query.
- Order, payment, entitlement and NFC tag allocation are written in **one transaction**, which needs a replica set (F9).

### 3.1 `products`

| Field | Type | Notes |
|---|---|---|
| `sku` | string | **unique**, e.g. `BZV-GRS-001` |
| `slug` | string | **unique** |
| `type` | enum | `physical_nfc \| service \| plan_addon` |
| `title`, `shortDescription`, `description` | string | |
| `media[]` | {assetId, url, alt, sort} | |
| `pricePaise` | int | Catalogue price. It is only a **reference**: every order snapshots it. |
| `compareAtPricePaise` | int? | |
| `pricesIncludeTax` | bool | Decision D3 |
| `tax` | {hsnCode, gstRatePct} | Confirm HSN codes with the CA (Section 3.1 seed notes). |
| `variants[]` | {variantId (stable string), sku (unique across products), title, options{}, priceDeltaPaise, weightGrams, dims{l,w,h mm}, active} | |
| `personalisationSchema` | {version, perUnit: bool, fields: [{key, label, type: text \| phone \| email \| url \| image \| select \| card_ref \| google_place, required, maxLength, options[], printed: bool, private: bool}]} | `version` is snapshotted into each order line. `private:true` fields are never shown in admin lists or logs. |
| `nfc` | {chipType: `NTAG213 \| NTAG215 \| NTAG216`, linkTarget: `card \| google_review \| url`, encodeUrlTemplate: `https://{shortHost}/t/{tagCode}`, lockAfterEncode: bool, createsCard: bool, grantsEntitlement?: {type, quantity}} | Chips always encode a **stable redirect URL** and never `/card/{slug}`. This is the fix for F6. |
| `fulfilment` | {requiresShipping: true, productionDays, shippingProfile} | |
| `inventory` | {tracked: bool, onHand, reserved} | Needed only if blanks are stocked. |
| `status` | enum | `draft \| active \| archived` |
| `sort`, `category` | | |

Indexes: `sku` unique; `slug` unique; `variants.sku` unique (partial index, where the field exists); `{status, category, sort}`.

#### Seed data for the 4 products

Prices are in paise and assumed GST-inclusive. Placeholder values are prefixed `TBD_`. HSN/GST must be confirmed with the CA: 8523.52 (smart cards, 18%) is the likely code for NFC PVC cards, and the acrylic review stand may be classified differently.

```json
[
  {
    "sku": "BZV-GRS-001",
    "slug": "google-review-stand",
    "type": "physical_nfc",
    "title": "Google Review Stand (NFC + QR)",
    "shortDescription": "Countertop stand: customers tap or scan to leave a Google review.",
    "pricePaise": 49900,
    "pricesIncludeTax": true,
    "tax": { "hsnCode": "TBD_CONFIRM_CA", "gstRatePct": 18 },
    "variants": [
      { "variantId": "std", "sku": "BZV-GRS-001-STD", "title": "Standard", "options": { "finish": "TBD_black_or_white" },
        "priceDeltaPaise": 0, "weightGrams": "TBD_250", "dims": { "l": "TBD", "w": "TBD", "h": "TBD" }, "active": true }
    ],
    "personalisationSchema": {
      "version": 1, "perUnit": false,
      "fields": [
        { "key": "businessName", "label": "Business name", "type": "text", "required": true, "maxLength": 60, "printed": true },
        { "key": "googlePlace", "label": "Google Business Profile", "type": "google_place", "required": true, "printed": false },
        { "key": "logo", "label": "Logo", "type": "image", "required": false, "printed": true },
        { "key": "tagline", "label": "Tagline", "type": "text", "required": false, "maxLength": 80, "printed": true }
      ]
    },
    "nfc": { "chipType": "NTAG213", "linkTarget": "google_review", "encodeUrlTemplate": "https://TBD_SHORT_HOST/t/{tagCode}",
             "lockAfterEncode": true, "createsCard": false },
    "fulfilment": { "requiresShipping": true, "productionDays": "TBD_3", "shippingProfile": "general" },
    "status": "active", "category": "review", "sort": 10
  },
  {
    "sku": "BZV-GRC-001",
    "slug": "google-review-card",
    "type": "physical_nfc",
    "title": "Google Review NFC Card",
    "shortDescription": "Wallet-size NFC + QR card that opens your Google review page.",
    "pricePaise": 35000,
    "pricesIncludeTax": true,
    "tax": { "hsnCode": "852352_TBD_CONFIRM_CA", "gstRatePct": 18 },
    "variants": [
      { "variantId": "std", "sku": "BZV-GRC-001-STD", "title": "PVC Standard", "options": { "finish": "TBD_matte" },
        "priceDeltaPaise": 0, "weightGrams": "TBD_10", "dims": { "l": 86, "w": 54, "h": 1 }, "active": true }
    ],
    "personalisationSchema": {
      "version": 1, "perUnit": false,
      "fields": [
        { "key": "businessName", "label": "Business name", "type": "text", "required": true, "maxLength": 60, "printed": true },
        { "key": "googlePlace", "label": "Google Business Profile", "type": "google_place", "required": true, "printed": false },
        { "key": "logo", "label": "Logo", "type": "image", "required": false, "printed": true }
      ]
    },
    "nfc": { "chipType": "NTAG213", "linkTarget": "google_review", "encodeUrlTemplate": "https://TBD_SHORT_HOST/t/{tagCode}",
             "lockAfterEncode": true, "createsCard": false },
    "fulfilment": { "requiresShipping": true, "productionDays": "TBD_3", "shippingProfile": "general" },
    "status": "active", "category": "review", "sort": 20
  },
  {
    "sku": "BZV-SID-001",
    "slug": "staff-id-card",
    "type": "physical_nfc",
    "title": "Staff ID Card (card only)",
    "shortDescription": "Printed NFC staff ID card linked to the staff member's digital card. Lanyard/holder not included.",
    "pricePaise": 35000,
    "pricesIncludeTax": true,
    "tax": { "hsnCode": "852352_TBD_CONFIRM_CA", "gstRatePct": 18 },
    "variants": [
      { "variantId": "portrait", "sku": "BZV-SID-001-P", "title": "Portrait", "options": { "orientation": "portrait" },
        "priceDeltaPaise": 0, "weightGrams": "TBD_10", "dims": { "l": 86, "w": 54, "h": 1 }, "active": true },
      { "variantId": "landscape", "sku": "BZV-SID-001-L", "title": "Landscape", "options": { "orientation": "landscape" },
        "priceDeltaPaise": 0, "weightGrams": "TBD_10", "dims": { "l": 86, "w": 54, "h": 1 }, "active": true }
    ],
    "personalisationSchema": {
      "version": 1, "perUnit": true,
      "fields": [
        { "key": "card", "label": "Staff digital card", "type": "card_ref", "required": true, "printed": false },
        { "key": "fullName", "label": "Full name", "type": "text", "required": true, "maxLength": 60, "printed": true },
        { "key": "designation", "label": "Designation", "type": "text", "required": false, "maxLength": 60, "printed": true },
        { "key": "employeeId", "label": "Employee ID", "type": "text", "required": false, "maxLength": 32, "printed": true },
        { "key": "photo", "label": "Photo", "type": "image", "required": true, "printed": true },
        { "key": "bloodGroup", "label": "Blood group (printed only if provided)", "type": "select",
          "options": ["A+","A-","B+","B-","AB+","AB-","O+","O-"], "required": false, "printed": true, "private": true },
        { "key": "emergencyPhone", "label": "Emergency contact", "type": "phone", "required": false, "printed": true, "private": true }
      ]
    },
    "nfc": { "chipType": "NTAG213", "linkTarget": "card", "encodeUrlTemplate": "https://TBD_SHORT_HOST/t/{tagCode}",
             "lockAfterEncode": true, "createsCard": false },
    "fulfilment": { "requiresShipping": true, "productionDays": "TBD_5", "shippingProfile": "general" },
    "status": "active", "category": "id_card", "sort": 30
  },
  {
    "sku": "BZV-BNC-001",
    "slug": "business-digital-nfc-card",
    "type": "physical_nfc",
    "title": "Business Digital + Physical NFC Card",
    "shortDescription": "Digital business card plus a printed NFC card that opens it.",
    "pricePaise": 99900,
    "pricesIncludeTax": true,
    "tax": { "hsnCode": "852352_TBD_CONFIRM_CA", "gstRatePct": 18 },
    "variants": [
      { "variantId": "pvc", "sku": "BZV-BNC-001-PVC", "title": "PVC", "options": { "material": "pvc", "finish": "TBD_matte" },
        "priceDeltaPaise": 0, "weightGrams": "TBD_10", "dims": { "l": 86, "w": 54, "h": 1 }, "active": true }
    ],
    "personalisationSchema": {
      "version": 1, "perUnit": true,
      "fields": [
        { "key": "card", "label": "Link existing digital card (or create new)", "type": "card_ref", "required": false, "printed": false },
        { "key": "fullName", "label": "Name", "type": "text", "required": true, "maxLength": 60, "printed": true },
        { "key": "designation", "label": "Designation", "type": "text", "required": false, "maxLength": 60, "printed": true },
        { "key": "companyName", "label": "Company", "type": "text", "required": false, "maxLength": 60, "printed": true },
        { "key": "phone", "label": "Phone", "type": "phone", "required": true, "printed": true },
        { "key": "email", "label": "Email", "type": "email", "required": false, "printed": true },
        { "key": "logo", "label": "Logo", "type": "image", "required": false, "printed": true }
      ]
    },
    "nfc": { "chipType": "NTAG213", "linkTarget": "card", "encodeUrlTemplate": "https://TBD_SHORT_HOST/t/{tagCode}",
             "lockAfterEncode": true, "createsCard": true,
             "grantsEntitlement": { "type": "card_seat", "quantity": 1, "durationDays": "TBD_DECISION_D2" } },
    "fulfilment": { "requiresShipping": true, "productionDays": "TBD_5", "shippingProfile": "general" },
    "status": "active", "category": "business_card", "sort": 40
  }
]
```

Seed with an idempotent upsert keyed on `sku`, for example `Product.updateOne({sku}, {$setOnInsert:…, $set:{title,…}}, {upsert:true})`, so that re-runs never change historical orders.

### 3.2 `orders`: immutable snapshots

| Field | Notes |
|---|---|
| `orderNumber` | **unique**. Format `BZV-{YY}{seq}`, taken from `counters` (reuse the ecom `Counter` pattern). |
| `buyerUserId`\*, `organizationId` | Tenant keys. Every owner query filters on them. |
| `channel` | `app \| web \| admin` |
| `items[]` | Each item is an **immutable snapshot**: {itemId, productId, sku, variantId, variantSku, title, variantTitle, hsnCode, gstRatePct, unitPricePaise, quantity, discountPaise, taxablePaise, cgstPaise, sgstPaise, igstPaise, lineTotalPaise, personalisationSchemaVersion, `personalisation[]` (one entry per unit when `perUnit`: {unitIndex, values{}, linkedCardId, googlePlaceId, reviewUrl, artworkAssetIds[]}), `proof` {status: `not_required \| pending \| sent \| approved \| rejected`, approvedAt, approvedByUserId}, `nfcTagIds[]`} |
| `totals` | {subtotalPaise, discountPaise, shippingPaise, taxablePaise, cgstPaise, sgstPaise, igstPaise, roundOffPaise, grandTotalPaise}. These are **computed on the server only**. |
| `taxSnapshot` | {sellerGstin, sellerStateCode, placeOfSupplyStateCode, taxType: `CGST_SGST \| IGST`, buyerGstin?, pricesIncludeTax} |
| `shippingAddress`, `billingAddress` | Snapshot of an `addresses` document. Include `stateCode` and `pincode`. |
| `status` | State machine below |
| `paymentStatus` | `unpaid \| pending \| paid \| failed \| refunded \| partially_refunded` |
| `fulfilmentStatus` | `unfulfilled \| in_production \| partially_shipped \| shipped \| delivered \| returned` |
| `idempotencyKey` | Unique together with `buyerUserId`. Sent by the app as `Idempotency-Key` on `POST /orders`. |
| `quoteHash` | Hash of the server quote, which must match at payment time. |
| `expiresAt` | For `pending_payment`; expiry runs as a job, not a TTL delete. |
| `timeline[]` | {at, from, to, actorUserId, actorType: `user \| system \| admin \| gateway \| courier`, note} |
| `cancel` / `refunds[]` | {reason, amountPaise, gatewayRefundId, at} |
| `schemaVersion` | |

Once an order leaves `draft`, only `status`, `paymentStatus`, `fulfilmentStatus`, `timeline`, `refunds`, `items[].proof` and `items[].nfcTagIds` may change. Enforce this with a `pre('save')` and `pre('findOneAndUpdate')` guard that rejects changes to snapshot paths.

Indexes: `orderNumber` unique; `{buyerUserId, idempotencyKey}` unique (partial index, where the key exists); `{organizationId, createdAt:-1}`; `{buyerUserId, createdAt:-1}`; `{paymentStatus, createdAt:-1}`; `{status, expiresAt}`.

**Order state machine** (physical NFC):

```
draft ─► pending_payment ─► paid ─► awaiting_proof ─► in_production ─► programmed ─► ready_to_ship ─► shipped ─► delivered ─► completed
            │   │                        │  (rejected → awaiting_proof)                             │           │
            │   └─► payment_failed ──► pending_payment (retry, new paymentAttempt)                  │           └─► return_requested ─► returned ─► refunded
            └─► expired (no capture within TTL)                                                     └─► rto ─► (reship | refunded)
paid | awaiting_proof ─► cancelled ─► refunded         (no cancellation once in_production, without admin override + audit log)
```

Rules:

- Only the **Razorpay webhook or the server-side signature verify** may move an order from `pending_payment` to `paid`. That step must check the amount, currency and `gatewayOrderId`.
- Moving to `programmed` requires every `nfcTag` on the order to be `programmed`.
- Moving to `shipped` requires a `shipment` with an AWB.

### 3.3 `paymentAttempts`, plus `webhookEvents`

| Field | Notes |
|---|---|
| `orderId` or `subscriptionId` | Exactly one of the two |
| `buyerUserId`, `organizationId` | |
| `gateway` | `razorpay` |
| `gatewayOrderId` | `order_xxx`. Unique together with `gateway`. |
| `gatewayPaymentId` | `pay_xxx`. Unique (partial index, where it exists). |
| `gatewaySignatureVerified` | bool. `verifiedAt`, `verifiedVia`: `checkout_signature \| webhook \| reconcile` |
| `amountPaise`, `currency` | Must equal `order.totals.grandTotalPaise` at creation and at capture. |
| `status` | `created → attempted → authorized → captured`, or `failed`, or `expired`. After capture: `refund_pending → refunded`. |
| `idempotencyKey` | **unique**. The server derives it as `orderId:attemptNo`. |
| `attemptNo` | |
| `failure` | {code, description, source} |
| `rawRefs` | Only {method, bank, vpaMasked}. **Never** store card data or the full payload. |

Indexes: `{gateway, gatewayOrderId}` unique; `gatewayPaymentId` unique and partial; `idempotencyKey` unique; `{orderId, createdAt:-1}`; `{status, createdAt}` for reconciliation.

`webhookEvents` stops replays: {gateway, eventId (the `x-razorpay-event-id` header), eventType, receivedAt, processedAt, status, payloadHash}, with `{gateway, eventId}` **unique**. Processing is an atomic `insert` and an E11000 duplicate is skipped. Give it a TTL of 90 days.

### 3.4 `shipments`

| Field | Notes |
|---|---|
| `orderId`\*, `organizationId`, `buyerUserId` | |
| `courier` | `delhivery \| manual` |
| `awb` | Unique together with `courier` (partial index, where it exists) |
| `courierOrderRef` | The Delhivery ReferenceNo, which equals the orderNumber plus a suffix |
| `items[]` | {orderItemId, quantity, nfcTagIds[]}, which allows split shipments |
| `package` | {weightGrams, l, w, h} |
| `pickupLocation`, `shipTo` | Snapshot |
| `status` | `created → manifested → pickup_scheduled → picked_up → in_transit → out_for_delivery → delivered`. Exceptions: `ndr` (failed attempt) leads to `out_for_delivery`, `rto_initiated` or `cancelled`. RTO path: `rto_initiated → rto_in_transit → rto_delivered`. Also `lost`. |
| `timeline[]` | {at, status, rawStatus, rawStatusCode, location, remarks, source: `webhook \| poll \| admin`, eventHash}. Append-only and deduplicated by `eventHash`. |
| `labelUrl`, `invoiceId`, `costPaise`, `codAmountPaise`: 0 | |
| `lastSyncedAt`, `nextPollAt` | Used by the cron worker that can be reused from the ecom repo (`cron:delhivery`) |

Indexes: `{courier, awb}` unique and partial; `{orderId}`; `{status, nextPollAt}`; `{organizationId, createdAt:-1}`.

The ecom webhook must be made **fail-closed**: a missing secret means reject (`nfcwebsiteecom-/src/pages/api/webhooks/delhivery.ts:106-114`).

### 3.5 `nfcTags`

| Field | Notes |
|---|---|
| `tagCode` | **unique**. A short random public code, 8-10 characters of Crockford base32, that is not guessable and not sequential. It is encoded as `https://{shortHost}/t/{tagCode}`. |
| `chipUid` | Hardware UID in hex. Unique (partial index, where it exists). Captured at encode time. |
| `chipType` | NTAG213/215/216 |
| `productId`, `sku`, `variantSku` | |
| `orderId`, `orderItemId`, `unitIndex` | Where the tag came from. Null for stock or demo tags. |
| `organizationId`, `ownerUserId` | Who controls the tag. Set at allocation and confirmed at activation. |
| `target` | {type: `card \| google_review \| url \| none`, cardId, googlePlaceId, reviewUrl (built on the server from placeId), url (allow-listed https only)} |
| `encodedUrl` | Exactly what was written to the chip. It is **never** changed after encoding. |
| `status` | `allocated → programmed → shipped → delivered → active`. Also `active ↔ suspended` (billing or owner) and `lost`, `retired`. |
| `programming` | {programmedAt, programmedBy (operator userId), lockedAt (write-lock applied), verifiedReadAt} |
| `activation` | {activatedAt, activatedByUserId, method: `auto_on_delivery \| owner_tap_claim \| admin`} |
| `history[]` | {at, actorUserId, action: `allocate \| program \| activate \| retarget \| suspend \| resume \| reassign_owner \| retire`, fromTarget, toTarget, reason}. Append-only. It is also mirrored to `auditLogs`. |
| `scan` | {count, lastScanAt}. These are counters only; individual events go to `cardEvents` with `eventType: nfc_tap`. |

Indexes: `tagCode` unique; `chipUid` unique and partial; `{organizationId, status}`; `{orderId, orderItemId}`; `{"target.cardId":1}`; `{status, createdAt}`.

Rules:

- Resolving `/t/{tagCode}` is public.
  - It checks that `status ∈ {active, delivered}` and that the owner is active and not billing-blocked.
  - It then redirects (302, no-store) to `/card/{currentSlug}` or to the Google review URL.
  - It logs a `cardEvents` entry. It never exposes `chipUid`, the order or the owner.
- Retargeting is owner-only, using `organizationId` from the token. The target card must belong to the same org. A staff member can retarget only to their own assigned card, and only with a new `manageTags` permission.
- Reassigning to another org is admin-only and is audited.

### 3.6 `invoices`: GST numbering

| Field | Notes |
|---|---|
| `invoiceNumber` | **unique**, at most 16 characters, consecutive within a financial year (GST Rule 46). Example: `BZV/26-27/000123`. The serial comes from `counters` with key `invoice:FY2026-27`, and is allocated **only** when the invoice is issued, never in drafts. |
| `type` | `tax_invoice \| credit_note` (`originalInvoiceId` for credit notes) |
| `orderId` or `subscriptionId`, `organizationId`, `buyerUserId` | |
| `seller` | {legalName, gstin, address, stateCode} |
| `buyer` | {name, gstin?, billingAddress, stateCode} |
| `placeOfSupplyStateCode`, `taxType` | `CGST_SGST` (same state) or `IGST` |
| `lines[]` | {description, hsnCode, quantity, unitPricePaise, taxablePaise, gstRatePct, cgstPaise, sgstPaise, igstPaise, totalPaise} |
| `totals` | {taxablePaise, cgstPaise, sgstPaise, igstPaise, roundOffPaise, grandTotalPaise, amountInWords} |
| `status` | `issued \| cancelled`. Invoices are immutable after issue; corrections are made with a credit note. |
| `issuedAt`, `fileAssetId` (PDF), `eInvoice` | {irn, ackNo, qrPayload}, only if turnover requires it |

Indexes: `invoiceNumber` unique; `{orderId}`; `{subscriptionId}`; `{organizationId, issuedAt:-1}`.

### 3.7 `addresses`

The fields are: userId\*, organizationId, label, recipientName, phone (E.164), line1\*, line2, landmark, city\*, district, state\*, **stateCode**\* (the GST 2-digit code, or ISO `IN-KL`), pincode\* (6 digits, validated), country `IN`, gstin (optional, validated with the 15-character regex and checksum), isDefaultShipping, isDefaultBilling, deletedAt.

Indexes: `{userId, deletedAt}`; `{organizationId}`.

Orders store a **snapshot**, so editing an address never changes past orders. Every read and write filters `userId = token.sub`.

### 3.8 Supporting collections

- `counters` {key unique, seq}: reuse the ecom pattern.
- `slugAliases` {slug unique, cardId, createdAt}. When a slug changes, the old slug is inserted here, and `/card/{old}` returns a 301 to the new one. This also stops another tenant from claiming the old slug.
- `mediaAssets` {ownerUserId, organizationId, cardId?, kind, key, mime, bytes, createdAt}. Uploads are currently stored by user without any association to a card (`app/api/v1/media/upload/route.ts:59`). The spec's gallery/PDF limits need this collection.

---

## 4. Tenant isolation review of `app/api/v1/**`

The pattern used everywhere: the tenant is resolved from the JWT `sub` on each request (`Organization.findOne({ownerUserId: sub})`, `Individual.findOne({userId: sub})`, `Staff.findOne({userId: sub, status:"active"})`), and resources are filtered by `ownerType` + `ownerId`. No route accepts an `organizationId` from the client. **I found no route where one tenant can read or write another tenant's data under normal conditions.** The gaps are in public payload privacy, billing and moderation bypass, and defence in depth.

| Area / route | Check | Verdict |
|---|---|---|
| `organization/cards` GET/POST, `organization/cards/[id]` GET/PATCH/DELETE | `{_id, ownerType:"organization", ownerId: org._id}` (`organization/cards/[id]/route.ts:14-18`) | OK. The PATCH can set `status`; see F2. |
| `organization/staff`, `organization/staff/[id]` | `{_id, organizationId: org._id}` (`staff/[id]/route.ts:22`). `assignedCardIds` is limited to org-owned cards (`staff/route.ts:37-41`, `staff/[id]/route.ts:54-58`). | OK |
| `organization/reviews`, `[id]/reply`, `[id]/status` | Review → card → `ownerType` + `ownerId` match (`reviews/[id]/status/route.ts:14-16`) | OK |
| `organization/dashboard`, `profile` | Scoped to `org._id`. The profile PATCH has an allow-list (`profile/route.ts:24`) but no type validation. | OK. Add zod validation. |
| `individual/card`, `individual/card/[id]`, `individual/reviews/*`, `individual/profile` | `{ownerType:"individual", ownerId: ind._id}`, or a set of owned card ids | OK. Status can be self-set; see F2. |
| `staff/cards/[id]` PATCH | Assignment + `ownerType` + `ownerId == staff.organizationId` + permission (`staff/cards/[id]/route.ts:12-18`) | OK, and the best pattern in the codebase |
| `staff/cards` GET | `Card.find({_id: {$in: staff.assignedCardIds}})` with **no org filter** (`staff/cards/route.ts:9`) | Low. It relies on write-time sanitisation. Add `ownerType:"organization", ownerId: staff.organizationId`. |
| `staff/reviews` GET, `[id]/reply`, `[id]/status` | Only `assignedCardIds` (`staff/reviews/route.ts:10`, `reply/route.ts:12`, `status/route.ts:12`) | Low, for the same reason. The status (moderation) route is gated by `replyReviews` (`status/route.ts:9`), which is a permission-semantics gap. |
| `cards/[id]` GET/PATCH/DELETE | Org and individual branches compare `ownerId` only, **without `ownerType`** (`cards/[id]/route.ts:19,24`). The staff branch checks only the assignment, with no org match (`:29`). | Low. ObjectId collisions across collections are improbable, but the check should be strict. |
| `cards/[id]/qrcode` POST | Same as above, missing `ownerType` (`qrcode/route.ts:17,20`). The staff branch is complete (`:22-26`). | Low |
| `analytics/card/[id]/*` | `lib/analytics-access.ts:14,19` are missing `ownerType`. The staff branch has no org match and needs no permission (`:24`). | Low |
| `domains`, `domains/[id]`, `domains/[id]/verify` | `ownerType` + `ownerId`. A rebind validates card ownership (`lib/domains.ts:110-122`). | OK |
| `notifications`, `notifications/[id]/read` | `{_id, userId: sub}` | OK |
| `media/upload` | Keyed by user. There is no card association, and any `https` URL is accepted as `photo`/`logo` (`lib/validation/card.ts:19-32`). | Info. Needs `mediaAssets` ownership for the gallery and PDFs. |
| `public/card/[slug]` | Explicit allow-list DTO. Checks `status:"active"` only, **not** owner status, plan expiry or billing (`route.ts:16`). | F3 |
| `public/card/[slug]/reviews` | **Leaks `reviewerEmail` and `reply.repliedBy`** (`route.ts:22-31`). | **F1** |
| `public/card/[slug]/review` POST | Returns `sanitizeReviewDoc(review)`, including `reviewerEmail`, to the submitter only (`route.ts:108`). | Low. Return a minimal `{id, status}`. |
| `public/card/[slug]/exchange` | Rate-limited. Contact PII goes into a notification as free text (`route.ts:32`). | Info (retention) |
| `public/track-click` | `Card.findById(body.cardId)` takes **any id with no status check** and writes a LinkClick with an arbitrary `linkUrl` (`track-click/route.ts:19-27`). | Low: cross-tenant analytics pollution. Require `status:"active"` and limit `linkUrl` to the card's own links. |
| `cards/[id]/vcard` GET | Public, keyed by `_id`, checks `status` and `vcardEnabled` (`vcard/route.ts:14-15`). It does not check the owner's status. | F3 |
| `public/resolve-host`, `public/domain-verification` | Host-scoped, with internal fields gated by a secret | OK |
| `admin/**` | `roles:["super_admin"]`, global by design | OK. `admin/plans/[id]` DELETE hard-deletes a plan that orgs may still reference (`plans/[id]/route.ts:31`). |

Cascade gap: `lib/cardDelete.ts:25-45` deletes the card and its events and reviews but does **not** `$pull` the card id from `Staff.assignedCardIds`, so stale ids stay behind.

---

## 5. Seat and billing data

**Current state, from the code:**

- The limit is `org.maxCards ?? plan.maxCards ?? 1` (`lib/plans.ts:43`). `org.maxCards` is a super-admin override (`admin/organizations/[id]/limits/route.ts`).
- Usage is the `Organization.cardCount` cache. It is reserved atomically with `findOneAndUpdate({cardCount:{$lt:max}}, {$inc:1})` (`lib/plans.ts:119-131`) and released on delete (`cardDelete.ts:41-45`). It is set by counting only when it is null (`plans.ts:82-91`), and **never reconciled** after that.
- A slot is used on **create**, whatever the `status`. The spec (§6.4) wants slots used on **activation**, with unlimited trial seats.
- Nothing disables a card because of billing. There is no `disabledByBilling`, no grace period and no expiry job, and `planExpiry` is never read.
- `Plan.price` exists, but nothing collects money.

**Answer:** there is **no authoritative seat count** today, only an admin-editable override and a cache, which spec §13.14 explicitly warns against.

**Proposed model:**

1. **`entitlements`** is the source of truth for seats: {organizationId, type: `card_seat \| custom_domain \| review_moderation \| trial_unlimited`, quantity, validFrom, validUntil, source: `subscription \| order \| admin_grant \| trial`, sourceId, status: `active \| revoked \| expired`, revokedReason}. Index `{organizationId, type, status, validUntil}`. Entitlements are created **only** by verified payment, an admin grant (with an audit log) or trial start.
2. **`subscriptions`** fields: {organizationId, planId, planVersion, quantity, status: `pending → active → past_due → grace_period → (active \| expired)`, plus `cancelled`; currentPeriodStart, currentPeriodEnd, nextRenewalAt, graceUntil, cancelAtPeriodEnd, gateway refs}. Index `{organizationId, status}` and `{status, nextRenewalAt}`. Each renewal creates an order, then a payment, then a new entitlement period.
3. Effective seats = the sum of `quantity` over active entitlements where `validFrom ≤ now < validUntil`. `trial_unlimited` means unlimited. Active cards = `Card.countDocuments({organizationId, status:"active", disabledByBilling:false, disabledByAdmin:false})`.
4. `Organization.billingSummary` holds {seats, activeCards, trialEndsAt, subscriptionStatus, computedAt}. It is **derived only**: a reconciler function recomputes it after every entitlement or card change and on a nightly job. No API writes it directly. Retire `cardCount` and `maxCards` as the enforcement source; keep `maxCards` only as a capped admin grant implemented as an `admin_grant` entitlement.
5. Card fields:
   - `status` (owner intent: `active \| disabled`)
   - `disabledByBilling` (bool, written by the server only), with `disabledByBillingAt`
   - `disabledByAdmin` (bool, written by super-admin only), with `disabledReason`
   - Public effective state = `status==="active" && !disabledByBilling && !disabledByAdmin && owner.status==="active"`.
   - Owner activation runs an atomic check against seats inside a transaction. If a free seat exists, it clears `disabledByBilling`; otherwise it returns 402 or 409 with `{code:"SEAT_LIMIT"}`.
6. The expiry and over-quota job runs when `graceUntil` passes. It sets `disabledByBilling=true` on the newest active cards beyond the seat count; whether newest-first or owner-chosen is decision D4. It writes audit logs and sends notifications.

---

## 6. Public DTOs and private data

| Surface | Construction | Private data excluded? |
|---|---|---|
| `lib/publicCard.ts:6-40` `toPublicCardDto` | **Explicit allow-list** (good) | Yes, by construction. Future `private.*`, `organizationId`, `disabledBy*` and `visibility` fields will not leak unless someone adds them. It does expose `_id` (needed by vCard and track-click) and the raw `displayOptions`, `status` and `theme`. `phone` and `email` are always public, because there is no `showPhone` or `showEmail` toggle (`lib/vcard.ts:12-15` says so explicitly). |
| `lib/vcard.ts:4-22` | Explicit field list | Yes. It respects the toggles. |
| Public reviews (`public/card/[slug]/reviews/route.ts:22-31` + `lib/api.ts:108-121`) | **Deny-list** (`select("-ipAddress -ipHash")` + delete) | **No.** `reviewerEmail`, `reply.repliedBy`, `cardId`, `status` and `updatedAt` all leak (F1). |
| Owner and staff card responses (`jsonOk(card)` in the org, individual, staff and admin routes) | Raw Mongoose document | Acceptable internally today. **Once `private.*` is added**, use `select:false` on the `private` path, add an `toOwnerCardDto` that is aware of each role's permissions, and keep private fields out of staff lists unless the staff member is the card's subject. |
| Private fields (bloodGroup, fatherName, motherName) | **Do not exist** in `Card.ts` | Not applicable yet. Add them as `private: { type: {...}, select: false }` so they can never be serialised by accident. Also keep them out of `auditLogs` and order personalisation logs (the seed marks them `private:true`). |

Fix for F1: add `toPublicReviewDto(r) => ({ id: r._id, reviewerName: r.reviewerName, rating: r.rating, comment: r.comment, createdAt: r.createdAt, reply: r.reply ? { text: r.reply.text, repliedAt: r.reply.repliedAt } : undefined })`. Also give `reviewerEmail` `select:false` in `Review.ts`.

---

## 7. Migrations, backfill and indexes

There is no migration tooling today (`scripts/` contains only `seed.ts` and smoke scripts). Proposal:

0. **Preparation**
   - Adopt `migrate-mongo` or a small `scripts/migrations/NNN-*.ts` runner, with a `migrations` collection that records which steps have run.
   - Set `autoIndex:false` in production and run `Model.syncIndexes()` per model inside migrations.
   - Take a `mongodump` before each migration.
   - Move MongoDB to a **replica set** (Atlas, or a single-node `rs.initiate()` in docker-compose) **before** shipping commerce, because transactions are required.
1. **Additive schema** (safe and backward compatible). Mongoose defaults are not persisted to existing docs, so each step also needs an explicit backfill:
   - `organizations`: `directoryVisibility`. The spec's example uses `"public"`, but **I recommend backfilling `"private"`** so that no existing org's staff list goes public without consent (decision D1). Also `publicEligible:false`, then `slug` from `slugify(name)` with a collision suffix, then a unique index.
   - `cards`: `visibility:"inherit"`, `disabledByBilling:false`, `disabledByAdmin:false`. Set `organizationId = ownerId` where `ownerType==="organization"`, and `null` for individual-owned cards. Set `staffUserId` from the Staff whose `assignedCardIds` contains the card *only* when exactly one staff member holds it; otherwise leave it null and report.
   - Legacy `status:"disabled"` cards: who disabled them is unknown, so set `disabledReason:"legacy"` and leave the owner `status` unchanged.
   - `reviews.organizationId`: an aggregation `$lookup` to cards, then `$merge`. `notifications.organizationId` works the same way via users.
   - `staff.permissions`: keep existing values. Change only the **schema default** to false for new staff.
2. **Index plan.** Before creating any unique index, run a duplicate scan and stop if duplicates exist.
   - `organizations`: `{ownerUserId:1}` unique; `{slug:1}` unique; `{status:1, directoryVisibility:1}`.
   - `cards`: `{organizationId:1, staffUserId:1}`; `{organizationId:1, status:1, visibility:1}`; `{ownerType:1, ownerId:1, createdAt:-1}`.
   - `reviews`: `{cardId:1, status:1, createdAt:-1}`; `{organizationId:1, createdAt:-1}`.
   - `linkclicks`: TTL `{clickedAt:1}` with 180 days, after confirming nobody needs older data.
   - `notifications`: `{userId:1, isRead:1, createdAt:-1}` and a TTL.
   - `users`: `{organizationId:1, role:1}`.
   - All new collections: the indexes listed in Section 3.
3. **Seat migration.** Create a `trial` or `admin_grant` entitlement for every org with `quantity = max(currentActiveCards, org.maxCards ?? plan.maxCards)`, so that **no live card is disabled by the migration**. Compute `billingSummary`. Run a shadow-mode reconciler for one release that logs differences against `cardCount` before switching enforcement.
4. **Data hygiene.**
   - `$pull` deleted card ids from `Staff.assignedCardIds`.
   - Clear legacy `ipAddress` from reviews and cardviews (`$unset`).
   - Move `qrCodeUrl` data URLs out of cards (generate them on demand).
   - Seed `products` by upserting on `sku`.
   - Create the counters `order_number` and `invoice:FY2026-27`.
5. **Rollback.** Every step is additive, so the down migration `$unset`s the new fields and drops the new indexes. The seat enforcement switch sits behind a feature flag (`BILLING_ENFORCEMENT=shadow|on`).
6. **Docs.** Update `project-docs/04-Database/collections.md` (its index list, at lines 104-111, is the stale list noted above).

---

## 8. Prioritised fix list

| P | Fix | Files |
|---|---|---|
| **P0** | Replace the public review deny-list with `toPublicReviewDto` and give `reviewerEmail` `select:false`. Make the review POST return `{id,status}` only. | `app/api/v1/public/card/[slug]/reviews/route.ts`, `review/route.ts:108`, `lib/api.ts:107-121`, `lib/models/Review.ts` |
| **P0** | Split card status into `status` (owner), `disabledByAdmin` (admin only) and `disabledByBilling` (server only). Make the owner PATCH unable to clear either flag. Use one shared `isCardPubliclyServable(card, owner)` in every public route, the vCard route, resolve-host and the future `/t/{tagCode}`. | `lib/validation/card.ts:102,146`, `lib/models/Card.ts`, `admin/cards/[id]/status/route.ts`, `public/**`, `cards/[id]/vcard/route.ts` |
| **P0** | Check owner (org/individual) `status` on public card endpoints so that suspension actually takes cards offline. | the same public routes |
| **P1** | Add `entitlements` + `subscriptions` + `billingSummary` reconciler. Use slots on activation. Enforce `planExpiry`/`graceUntil` with a job. Retire `cardCount`/`maxCards` as the source of truth. | `lib/plans.ts`, new models |
| **P1** | Add `orders`, `paymentAttempts`, `webhookEvents`, `invoices`, `addresses`, `counters` and `products` (with seed data) with the indexes and state machines in Section 3. Compute prices on the server only. Do **not** port the ecom client-priced checkout. | new `lib/models/*` |
| **P1** | Add `nfcTags` with a stable `/t/{tagCode}` redirect, plus `slugAliases` so that slug changes never break printed chips or QR codes. | `lib/cardSlug.ts`, new route |
| **P1** | Move MongoDB to a replica set and wrap order, payment, entitlement and tag allocation in transactions. | `docker-compose.yml`, `lib/db/connect.ts` |
| **P1** | Add `organizations.directoryVisibility`, `cards.visibility` and a server-filtered `GET /public/organizations/:slug/directory` (precedence decision D1). | Organization/Card models, new route |
| **P1** | Add an `auditLogs` collection, written for status, visibility, permission, billing, order and tag changes. | new |
| **P2** | Indexes: `Organization.ownerUserId` unique, `{ownerType,ownerId}`, `{cardId,status,createdAt}`, a LinkClick TTL, and a notifications compound index plus TTL. | models |
| **P2** | Add `cards.organizationId`, `reviews.organizationId` and `cardEvents.organizationId` (backfill), so every tenant query can filter on one indexed key. | models + migration |
| **P2** | Defence in depth: add `ownerType` to the `cards/[id]`, `qrcode` and `analytics-access` checks. Add an org filter to `staff/cards` and `staff/reviews*`. Make `track-click` require an active card and one of the card's own URLs. Make `cardDelete` `$pull` from `Staff.assignedCardIds`. Add a separate `moderateReviews` staff permission. | `app/api/v1/cards/[id]/route.ts:19,24,29`, `cards/[id]/qrcode/route.ts:17,20`, `lib/analytics-access.ts:14,19,24`, `staff/cards/route.ts:9`, `staff/reviews/**`, `public/track-click/route.ts:19`, `lib/cardDelete.ts` |
| **P2** | Private card fields go in `private{}` with `select:false`. Add an owner DTO. Keep private fields out of logs and audit logs. | `lib/models/Card.ts`, new `lib/ownerCard.ts` |
| **P2** | Plans: make them versioned and immutable, and block deleting a plan that is referenced. | `lib/models/Plan.ts`, `admin/plans/[id]/route.ts:31` |
| **P3** | Staff permission defaults should be false. Store notification payloads as structured data, not PII in free text. Move QR data URLs out of the card document. Add zod validation to the org profile PATCH. | `lib/models/Staff.ts:20-23`, `exchange/route.ts:32`, `cards/[id]/qrcode/route.ts:34` |
| **P3** | Ecom repo, if any of it is reused: remove the duplicate `Product` model, make the Delhivery webhook secret mandatory, and add a Razorpay webhook with `order_id` and amount matching. | `nfcwebsiteecom-/src/models/Product.{ts,js}`, `pages/api/webhooks/delhivery.ts:106-114`, `lib/payment-service.ts:594-625` |

### Decisions needed

- **D1:** Directory precedence (spec §7.2) and the default `directoryVisibility` for existing orgs. I recommend `private`.
- **D2:** Does the ₹999 Business card include a card-seat entitlement, and for how long? Does the ₹350 Staff ID card need an already active seat for the linked card?
- **D3:** Are catalogue prices GST-inclusive? What are the HSN codes per product (CA)? Seller GSTIN and state.
- **D4:** Which cards get disabled when over quota (newest first, or owner-chosen)? How long is the grace period?
- **D5:** Who can retarget an NFC tag (owner only, or staff with a permission), and is retargeting allowed to another org's card? I recommend never.
- **D6:** Are Individual (B2C) tenants kept in the new commerce and billing model? They get `organizationId:null` and `buyerUserId` only.
