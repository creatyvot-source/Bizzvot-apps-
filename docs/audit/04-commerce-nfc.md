# 04 — Commerce, NFC products, payments & fulfilment

Auditor: agent 04 of 10 · Date: 2026-10-11 · Scope: read-only review of
`/home/user/cogcard` (Coglink), `/home/user/nfcwebsiteecom-`, `/home/user/nfc-landing-page`,
`/home/user/Bizzvot-apps-` (commerce feature modules, which were **still being written while
this audit ran**; file references are a snapshot at 07:40 UTC) against
`docs/PRODUCT_PLAN.md` §11, §12, §13.7–13.11, §16 Payments, §17.4, Appendix B.

Products in scope (all physical, INR):

| # | Product | Price | Opens when tapped | Digital entitlement? |
|---|---|---|---|---|
| P1 | Google Review Stand | ₹499 | Google review link (or Bizzvot review page) | No |
| P2 | Google Review Card | ₹350 | Google review link (or Bizzvot review page) | No |
| P3 | Staff ID Card (card only) | ₹350 | The staff member's existing Bizzvot digital card | No; needs a seat that is already paid |
| P4 | Business Digital + Physical NFC Card | ₹999 | The buyer's Bizzvot digital card | **Yes**: bundles one card seat or subscription |

---

## 1. Summary

1. **No backend sells these four products today.** Coglink (`cogcard`) has no commerce,
   billing, plan-expiry, tag or order code. Its `Plan` model is a static limits record
   (`cogcard/lib/models/Plan.ts:16-27`), and no `billing` route exists under `cogcard/app/api/v1`,
   although the plan (§11.1) lists `GET/POST /organization/billing` as existing. All commerce
   routes in `lib/core/api/endpoints.dart` (lines 76-91) are marked PROPOSED.
2. **Two commerce codebases exist, and the useful one is the smaller one.**
   - `nfc-landing-page` is a live, launch-hardened storefront for the **Google Review Card and
     Stand**. It already uses the exact ₹350 and ₹499 prices (`data/products.ts:65-129`). It
     reprices on the server, verifies Razorpay with a signature check, a payment fetch, a
     captured-status check and an amount match, handles refunds in its webhook, auto-refunds late
     captures on cancelled orders, encrypts gateway secrets, numbers invoices in sequence per
     financial year, splits GST-inclusive prices, supports COD and creates Delhivery shipments
     by hand. Its weaknesses: a JSON-file database, a single product, personalisation per order
     only, no customer accounts and no link to Bizzvot cards. **Its logic should be ported; its
     storage should not.**
   - `nfcwebsiteecom-` is a fork of a Shopify-migrated **jewellery store** ("Enkilum Ente
     Krishna", `START-HERE.md`; default HSN `7113` = jewellery in
     `src/pages/api/admin/orders/[id]/gst-invoice.ts:86,116`). It contains no NFC logic. Its
     Delhivery integration, GST PDF invoice and admin order tools are reusable as references. Its
     checkout is **not safe to reuse**: the server trusts prices, discount, shipping and tax sent
     by the client.
3. **Critical security findings in `nfcwebsiteecom-`:**
   - The checkout trusts client prices (`src/app/checkout/actions.ts:297-363`, `545-730`).
   - The unauthenticated `create-intent` endpoint accepts any amount
     (`src/pages/api/payment/create-intent.ts:49-115`).
   - The amount check in `link-order` is "best-effort" and does not stop the link
     (`razorpay/link-order.ts:97-114`).
   - `verify-payment` never compares the captured amount (`razorpay/verify-payment.ts:82-104`).
   - **Real customer PII is committed** in `orders_export_1.csv` (506 rows, 304 with email,
     plus names, addresses and phones) and `transactions_export_1.csv`.
   - Razorpay key and webhook secrets are stored in plaintext and **returned in full** to admin
     and staff by `GET /api/admin/settings/payment-gateway` (line 55).
4. **The NFC fulfilment lifecycle is missing everywhere.** No codebase has design-proof
   approval, a printing or production queue, a record of NFC chip programming, QC, tag
   activation or claim, tag re-pointing, or replacement (RMA) for a defective tag. The product
   plan does not mention NFC products at all.
5. **Tag URL recommendation:** never write `/card/{slug}` onto a chip. Coglink slugs can be
   changed (`cogcard/app/api/v1/cards/[id]/route.ts:53`) and no slug history is kept, so a renamed
   or deleted card breaks the tag. Worse, a released slug can be claimed by another tenant, and
   the physical tag would then open a stranger's card. Instead, write a permanent, unguessable
   redirect `https://bizzvot.com/t/{tagCode}` (§4). The tag stays re-pointable, and the chip can
   be locked at QC.
6. **Mobile app commerce design is ahead of the backend and mostly sound.**
   - It sends no prices. It uses `Idempotency-Key`. Its final state comes only from
     `GET /orders/:id`.
   - It already models per-unit personalisation, delivery address, GSTIN and a fulfilment
     timeline (`lib/features/catalog/domain/physical_models.dart`).
   - It lacks: COD, proof approval, post-order "assign later", tag activation or re-pointing,
     cancel/return/replace, PIN serviceability, print-grade logo upload, and a view of the
     entitlement granted by the bundle. The checkout screen is still a stub
     (`cart_checkout/presentation/checkout_screen.dart`).
7. **App-store risk is concentrated in P4 and in seat purchases, not in P1–P3.**
   - P1–P3 are physical goods. Apple 3.1.3(e) and Google Play's physical-goods exemption allow
     Razorpay.
   - P4's included digital card subscription, and its renewals, are the IAP trigger.
   - The app's default `PaymentPolicy` for plans is `externalDigitalService`
     (`catalog/domain/catalog_models.dart:71-73`, with a TODO). That default is risky; see §7.
8. **GST compliance:**
   - The landing page excludes COD surcharge and shipping from the GST base
     (`nfc-landing-page/lib/invoice.ts:109`). Under §15(2)(c) of the CGST Act, incidental charges
     made by the supplier are generally part of the taxable value. Confirm with the CA.
   - When the store is not "tax-ready", its fallback invoice number `INV-NFC-<32 hex>` is longer
     than the 16-character limit in Rule 46.
   - Neither codebase separates HSN (goods) from SAC (the digital service in P4).

Recommendation in one line: **build commerce as a module of the Coglink API** (same MongoDB,
same native auth, same `organizationId`). Port the payment, invoice, COD and cancel/refund logic
from `nfc-landing-page`, and the Delhivery service, cron and webhook from `nfcwebsiteecom-`. Add
first-class `tags`, `fulfilmentUnits` and `entitlements` collections. Retire both legacy stores,
or make them clients of the new API.

---

## 2. End-to-end lifecycle (target)

```
 CATALOGUE                    PERSONALISE                         QUOTE
 GET /catalog/products ──▶ per unit: target (card | google_review | review_page | assign_later)
   P1..P4 with                print name/designation/photo/logo        POST /cart/quote
   personalization spec,      design template + notes          ──▶  server prices (incl. 18% GST),
   paymentPolicy, HSN/SAC                                             HSN/SAC lines, PIN serviceability,
                                                                      shipping by PIN, COD eligibility
        │
        ▼
 ORDER (POST /orders, Idempotency-Key) ── status: pending_payment ── stock reserved (TTL 30 min)
        │
        ▼
 PAYMENT  POST /orders/:id/payment ─▶ Razorpay order (amount = server total, notes.orderId)
          app opens Razorpay SDK / hosted page ─▶ POST /payments/razorpay/verify (advisory)
          POST /webhooks/razorpay (HMAC raw body, event-id ledger) ── authoritative
          checks: signature · payment.order_id match · status=captured · amount==order total · currency
        │ paid (exactly once: conditional update pending_payment→paid)
        ├──▶ invoice allocated (INV/FY/seq), email + WhatsApp + in-app notification
        ├──▶ P4: entitlement(card_seat ×qty, source=orderItem) created idempotently
        ▼
 PRODUCTION (per fulfilmentUnit)
   awaiting_details ─(customer assigns)─▶ proof_pending ─(admin uploads proof)─▶ proof_sent
        ▲                                                        │ approve │ request changes (≤3)
        └──────────────────── changes_requested ◀────────────────┘         ▼
                                                                    proof_approved  (cancel cut-off)
   printing ─▶ programming (write https://bizzvot.com/t/{tagCode}, record chip UID, lock)
           ─▶ qc_passed (tap-test resolves to expected target) ─▶ packed
        ▼
 SHIPMENT  Delhivery: serviceability → create AWB (manual or batch) → label → pickup
           webhook /webhooks/delhivery + 15-min cron sync → in_transit → out_for_delivery
           → delivered | ndr (reattempt / reschedule) | rto_initiated → rto_delivered
        ▼
 ACTIVATION  first tap of an unassigned tag → /t/{code} → "Activate in Bizzvot app" (universal link)
             app: POST /tags/claim {code, claimPin} → choose card / review URL → tag active
             P4: activating the bundled card consumes the bundled seat; validity clock starts
        ▼
 AFTER-SALE  re-point tag (PATCH /organization/tags/:id) · disable lost tag · reprint/replace (RMA:
             request → approve → reverse pickup or self-dispose → replacement unit re-enters printing)
             cancellation (before proof_approved: full refund; after: per policy) · refunds + credit notes
```

Separate state machines are required. Appendix B's single order state cannot express a
5-unit order in which 3 units have shipped and 2 still await details:

| Machine | States |
|---|---|
| `order.status` | `pending_payment` → `paid` → `in_fulfilment` → `partially_shipped` → `shipped` → `delivered` → `completed`; `payment_failed`, `expired`, `cancelled`, `refunded`, `partially_refunded` |
| `order.paymentStatus` | `pending`, `authorized`, `paid`, `failed`, `refund_pending`, `partially_refunded`, `refunded` (COD adds `cod_pending` → `cod_collected`) |
| `fulfilmentUnit.status` | `awaiting_details`, `proof_pending`, `proof_sent`, `changes_requested`, `proof_approved`, `printing`, `programming`, `qc_failed`, `qc_passed`, `packed`, `shipped`, `delivered`, `activated`, `replaced`, `cancelled` |
| `shipment.status` | `created`, `manifested`, `picked_up`, `in_transit`, `out_for_delivery`, `delivered`, `ndr`, `rto_initiated`, `rto_delivered`, `lost`, `cancelled` |
| `tag.status` | `generated`, `programmed`, `assigned_to_unit`, `shipped`, `unclaimed`, `active`, `disabled`, `replaced` |

The app's `FulfilmentStep` enum (`physical_models.dart:368-398`) already matches the customer-
facing projection: placed → paid → design & proof → printing → NFC programmed → shipped →
delivered. Add `activated`, plus side states for `changes_requested`, `ndr`, `rto` and `replacement`.

### 2.1 Per-product lifecycle differences

| Step | P1 Review Stand ₹499 | P2 Review Card ₹350 | P3 Staff ID Card ₹350 | P4 Digital+Physical ₹999 |
|---|---|---|---|---|
| Tag target | Google review URL (`https://search.google.com/local/writereview?placeid=…`) or the org's Bizzvot review page | same | Staff member's card (`cardId`) | Buyer's card (created or linked) |
| Per-unit personalisation | Optional (multi-branch packs need a different place per unit) | Optional (same) | **Required per unit**: card, name, designation, photo, employee ID | Per unit: card, name, designation, logo |
| Print | Business name, logo, "Tap or scan to review" CTA, QR fallback | same | Photo, name, designation, employee ID, org logo, QR; front and back | Name, designation, logo, QR |
| Seat check at quote | None | None | Linked card must belong to the org, be `active` and hold a paid seat | Seat comes **from** the order |
| Entitlement on payment | None | None | None | `card_seat` ×qty (§6) |
| Policy class | physical | physical | physical | physical + included digital service (§7) |
| COD | Allowed for non-personalised packs only (recommendation) | same | No: personalised, so RTO units are scrap | No (also entitlement abuse) |
| Cancel cut-off | Until `proof_approved` | same | same | same; entitlement revoked on refund |

Packs: the landing page sells Card ×3 ₹899, Card ×5 ₹1,199, Stand combo ×3 ₹1,099 and ×5 ₹1,699
(`nfc-landing-page/data/products.ts:74-129`). Model these as variants with a `unitCount`, so one
order line expands into N `fulfilmentUnits`.

---

## 3. What exists today: reuse assessment

### 3.1 Capability matrix

| Capability | `nfc-landing-page` | `nfcwebsiteecom-` | `cogcard` | Verdict |
|---|---|---|---|---|
| Catalogue | One product with packages in code + admin-editable landing JSON (`data/products.ts`, `app/api/admin/landing/route.ts`) | Full Shopify-style products, variants, collections; `hsnCode`, `gstRate` on product (`src/models/Product.ts:31-41`); `strict:false` | none | Rebuild in Coglink with the §13.7 fields plus `personalization`, `hsn`/`sac`, `paymentPolicy`, `includesEntitlement`, `unitCount`, weight/dimensions |
| Cart | Client zustand store (`lib/cart-store.ts`) | localStorage `plymart-cart` (`src/context/CartContext.tsx:39`) | none | App keeps its own cart; server `POST /cart/quote` |
| Server-side pricing | **Yes**: `resolveCheckoutLineItems` (`app/api/checkout/route.ts:69-81`) | **No**: client price, discount, shipping and tax are trusted (`src/app/checkout/actions.ts:297-363`) | n/a | Port the landing approach |
| GST | Inclusive 18% split (`lib/pricing.ts:10-63`), IGST vs CGST+SGST by seller/buyer state (`lib/invoice.ts:150-165`), HSN `8523` default (`lib/seller.ts:49`) | Per-product GST (`pages/api/checkout/calculate-tax.ts`) using **client-sent prices** (line 43), IGST vs CGST/SGST | none | Port the landing logic; add per-line HSN/SAC; tax COD and shipping |
| Shipping rates | Delhivery rate fetched at AWB time (`lib/delhivery.ts:71`) | Delhivery rate by PIN, with fallback to country/state zones (`pages/api/checkout/calculate-shipping.ts:80-129`; `src/models/ShippingZone.ts`) | none | Quote with a Delhivery PIN rate + serviceability; flat fallback slab |
| COD | Yes, +30% surcharge (`lib/pricing.ts:4`); COD marked paid by admin or by Delhivery sync (`lib/delhivery-fulfillment.ts:25-79`) | No | none | Port, but restrict to non-personalised items; revisit the 30% |
| Payment gateway | Razorpay (`lib/razorpay.ts`) | Razorpay + Stripe/PayPal/Square stubs + "mock" (`src/lib/payment-service.ts:22,95`) | none | Razorpay only |
| Client verify | Signature + `payments.fetch` + `captured` + amount match + auto-refund on mismatch or cancel (`app/api/checkout/verify/route.ts`) | Signature only, no amount check (`razorpay/verify-payment.ts:66-104`) | none | Port the landing verify (advisory; the webhook is authoritative) |
| Webhook | Signature over raw body; handles `payment.captured`, `order.paid`, `payment.failed`, `refund.processed`, `refund.failed`; state-based idempotency (`app/api/webhooks/razorpay/route.ts`) | Signature over raw body with timing-safe compare; captured/failed only; no amount check; no refund events (`razorpay/verify.ts`) | none | Port the landing webhook; add an `x-razorpay-event-id` ledger |
| Orders | JSON-file `data/db.json` with in-process + lockfile serialisation (`lib/db.ts:25-60`); explicit transition table (`lib/order-status.ts:27-36`) | Mongo `Order` with coarse status `Processing/Shipped/Delivered/Cancelled` (`src/models/Order.ts:39`); line items have **no personalisation field** (lines 3-17) | none | New Mongo `orders` + `fulfilmentUnits` |
| Invoices | HTML tax invoice, `INV-{FY}-{seq}` allocated under lock (`lib/invoice.ts:34,65`), seller GSTIN/state readiness check | PDFKit GST invoice, admin-only, invoice no. = order no., HSN default `7113` (`gst-invoice.ts:54,86`) | none | Port the landing numbering + PDFKit rendering; add credit notes |
| Cancel / refund | Cancel with refund, fulfilment hold, refund-failed block (`lib/order-cancel.ts`; `PlacedOrder.fulfillmentHoldAt`, `refundFailedAt` in `lib/checkout.ts:79-87`) | Admin refund calls the gateway but does not update the order (`pages/api/payment/refund.ts:47`); separate admin refunds route; customer cancel (`account/orders/[id]/cancel.ts`) | none | Port the landing logic |
| Returns / RMA | none | `ReturnRequest` model + `returns/create.ts` (authorised only by knowing orderId + email) | none | New RMA flow tailored to defective or misprinted tags |
| Delhivery | Manual AWB, track sync, COD-collected detection (`lib/delhivery.ts`, `app/api/admin/delhivery/route.ts`) | Most complete: serviceability, rate, create, label, pickup, cancel, NDR action, reverse pickup, bulk create, webhook, 15-min cron sync + hourly retry worker (`src/lib/delhivery-service.ts`, `pages/api/admin/orders/[id]/*delhivery*`, `pages/api/webhooks/delhivery.ts`, `scripts/enkilum-entekrishna-cron-delhivery-worker.ts`) | none | **Port `nfcwebsiteecom-` Delhivery**, but remove auto-create-on-payment (§3.3) |
| Admin order management | Orders, delivery, invoices bulk, abandoned, reports/P&L, expenses (`app/admin/(protected)/*`) | Rich admin: orders, timeline, refunds, tracking, bulk ops, customers, discounts, reports | Super-admin for orgs/plans/cards only | Build a production-queue admin in the Coglink super-admin (cross-ref audit 05) |
| Notifications | SMTP + Creatyvot WhatsApp on confirm, shipped email (`lib/notify-order.ts`) | Nodemailer/Gmail, WhatsApp templates (`src/lib/whatsapp.ts`) | Nodemailer | Port; add in-app notifications (NOT-1) |
| Personalisation capture | One `mapsUrl` (Google Maps, not a review link) + one `logoUrl` per order (`lib/validation.ts:76-122`); logo upload with signed ticket, PNG/JPEG/WebP ≤2 MB (`app/api/upload/logo/route.ts`) | `ProductCustomization.tsx` exists but is **not used anywhere** | Card media upload, re-encoded raster ≤5 MB | New per-unit personalisation + print-asset upload |
| NFC tags / programming / activation | none | none | none | **Build** (§4) |
| Customer identity | None (signed order-access token, `lib/order-access.ts`) | next-auth cookie sessions, separate `Customer`/`User` | Org/Individual/Staff + JWT cookies (native tokens are an open gap, AUTH-1) | Use Coglink identity; orders belong to `organizationId` |

### 3.2 Security and code-quality risks in the legacy stores

| Sev | Repo / file | Issue | Impact |
|---|---|---|---|
| Critical | `nfcwebsiteecom-/src/app/checkout/actions.ts:297-363`, `545-730` | `items[].price`, `subtotal`, `discountAmount`, `shipping` and `tax` come from FormData. The only check is internal consistency (`calculatedTotalWithFees == totalAmount`). `ProductModel` is read only for stock (line 977). | Anyone can buy at ₹1 and pay a valid ₹1 Razorpay order. **Do not reuse this checkout.** |
| Critical | `nfcwebsiteecom-/src/pages/api/payment/create-intent.ts:49-115` + `razorpay/link-order.ts:97-114` + `razorpay/verify-payment.ts:82-104` | Unauthenticated creation of a Razorpay order for any amount. `link-order` checks the amount but continues if the fetch fails ("best-effort"). `verify-payment` and the webhook (`verify.ts:94-123`) mark the order paid without comparing amount or currency. | Underpayment and wrong-order capture are possible |
| High | `nfcwebsiteecom-/orders_export_1.csv`, `transactions_export_1.csv` (both tracked by git) | Real Shopify exports: 506 order rows, 304 emails, billing and shipping names, addresses, phones, payment references | DPDP Act 2023 exposure. Remove, purge history, notify per policy. Cross-ref audit 07 |
| High | `nfcwebsiteecom-/src/pages/api/admin/settings/payment-gateway.ts:55`; `src/models/PaymentGatewaySettings.ts:225-236` | Gateway key secret and webhook secret stored in plaintext in Mongo; `GET` returns the whole document to `admin` **and** `staff` (`src/lib/auth/roles.ts:3-5`) | Secret theft by any staff account or XSS. Rotate keys if this was ever deployed |
| Medium | `nfcwebsiteecom-/src/lib/order-fulfillment.ts:21-35, 265-274` | Delhivery AWB creation is check-then-act (no atomic claim). Both the webhook and verify call `runPostPaymentFulfillment` | Duplicate AWBs. Also, auto-shipping on payment is wrong for made-to-order NFC items |
| Medium | `nfcwebsiteecom-/src/pages/api/webhooks/delhivery.ts:105-114` | Shared-secret check is optional (enforced only when `DELHIVERY_WEBHOOK_SECRET` is set) | Forged "Delivered" updates |
| Medium | `nfcwebsiteecom-/src/pages/api/payment/refund.ts:22-59` | Refunds any `paymentIntentId` and never writes the refund back to the order | Ledger drift; double refunds |
| Low | `nfcwebsiteecom-/src/pages/api/orders/[orderId]/track-delhivery.ts:24-45` | Public, unauthenticated tracking proxy for any waybill; also triggers an order sync | Exposes shipment scan data |
| Low | `nfcwebsiteecom-/src/pages/api/returns/create.ts:11-80` | Return authorised only by knowing orderId + email | Abuse vector |
| Low | `nfcwebsiteecom-` repo hygiene | Many status `*.md` files, Shopify scrapers, `"latest"` dependency pins (`package.json`), jewellery branding and HSN, `src/models/Product.js` duplicate of `.ts` | Signals a template fork, not a product codebase |
| Medium | `nfc-landing-page/lib/db.ts:25-60` | JSON-file DB with a lockfile; README requires a single Node process | Cannot scale or be shared with the app; data loss risk |
| Medium | `nfc-landing-page/lib/invoice.ts:109`, `lib/checkout.ts:40-46` | COD surcharge and shipping treated as outside GST | Probable under-collection of GST (CA to confirm) |
| Low | `nfc-landing-page/lib/invoice.ts:21,74,106` | Fallback invoice number `INV-NFC-<32 hex>` when the store is not tax-ready | Breaks the Rule 46 limit of ≤16 characters in one consecutive series |
| Low | `nfc-landing-page/app/api/webhooks/razorpay/route.ts` | Idempotency is by order state only; no event-id ledger | Replays are mostly harmless today, but there is no audit trail |

### 3.3 Reuse decision

| Component | Decision | Notes |
|---|---|---|
| Landing Razorpay verify + webhook + refund race handling | **Port** (TypeScript, close to drop-in for a Next.js route handler in Coglink) | Replace JSON `updateOrder` with Mongo `findOneAndUpdate` conditional on status |
| Landing `pricing.ts` inclusive GST split, `invoice.ts` FY sequence, `seller.ts` readiness, `order-status.ts` transitions, `order-cancel.ts` | **Port** | Use a Mongo `counters` doc per FY for invoice numbers; add credit notes |
| Landing `settings-crypto.ts` | **Port** | Use for Razorpay and Delhivery secrets in Coglink settings |
| Landing logo upload ticket | **Adapt** | Print assets need SVG/PDF or raster ≥300 dpi (§8) |
| `nfcwebsiteecom-` `delhivery-service.ts`, `delhivery-sync-order.ts`, webhook field extraction, cron worker | **Port** with fixes | Atomic AWB claim (`findOneAndUpdate({_id, awb: null}, {$set:{awbLock}})`); mandatory webhook secret; no auto-create before `packed` |
| `nfcwebsiteecom-` PDFKit GST invoice layout | **Adapt** | Replace HSN default; per-line HSN/SAC; buyer GSTIN |
| `nfcwebsiteecom-` checkout, payment-service, models, auth | **Do not reuse** | See the Critical findings above |
| `nfcwebsiteecom-` admin UI (orders/timeline/refunds) | Reference only | The admin lives in Coglink super-admin |
| Landing storefront UI | Keep as marketing front end; switch its checkout to the new `/api/v1` | Migrate `db.json` orders into Mongo (one-off script) |

---

## 4. NFC tag design (recommendation)

**URL written to the chip:** `https://bizzvot.com/t/{tagCode}`, or a short domain such as
`https://bzv.to/{tagCode}` if one is bought. The URL must be HTTPS, and the same string is also
printed as a QR code on every item.

- `tagCode`: 10 characters of Crockford base32 (about 50 bits), generated by the server,
  unguessable and not sequential. Keep a check digit to catch mistyped manual entries.
- Chip: NTAG213 (144 B) is enough for a URL of about 30 characters. NTAG215/216 are needed only
  for longer payloads. For anti-cloning on premium SKUs, use NTAG 424 DNA with SUN
  (`?e=…&c=…`) verified at `/t`.
- **Lock the chip after writing**: set permanent write-protection at QC. Because the redirect is
  server-side, locking costs nothing and stops anyone with a phone from overwriting a stand's URL
  with a phishing link, which is a real risk for counter-top review stands.
- Record `chipUid` (7-byte UID) at programming. QC re-reads the UID and the URL and taps through
  `/t/{code}?qc=1` to confirm the target resolves.
- `/t/{code}` resolution (public, no auth, rate-limited):
  - `active` + target `card`: **302** to `/card/{currentSlug}` (resolved by `cardId`, so slug
    renames are safe) and log `cardEvents{source:'nfc', tagId}`.
  - `active` + target `google_review`: 302 to the stored, allow-listed Google review URL.
  - `active` + target `review_page`: 302 to the org's Bizzvot review page.
  - `unclaimed` / `shipped`: "Activate this Bizzvot tag" page with an app universal link
    `https://bizzvot.com/t/{code}` (the app handles it via App Links / Universal Links) plus a
    store link.
  - `disabled` (lost) or card lapsed: a neutral "This tag is inactive" page. Never 404, and never
    a stranger's content.
  - Use 302 or 307 with `Cache-Control: no-store`, never 301, so tags remain re-pointable.
- **Claim security:**
  - A tag shipped in an order is pre-bound to the buyer's `organizationId`, so only that org can
    claim it.
  - Retail or unbound tags also need the `claimPin` printed inside the packaging.
  - Allow 5 claim attempts per tag per hour.
- **Google review links:**
  - Store the Place ID and build `https://search.google.com/local/writereview?placeid={id}`.
  - Accept pasted `g.page/r/…/review`, `maps.app.goo.gl`, `search.google.com/local/writereview`
    and `www.google.com/maps/…` links, and normalise them on the server.
  - Allow-list Google hosts only. Today the app accepts any https URL
    (`physical_models.dart:256-262`), which turns Bizzvot-branded tags into open redirects.
- **Google policy guardrails** for the review stand and the `review_card` template:
  - No review gating: do not send only happy (4–5 star) visitors to Google and divert the rest
    to private feedback.
  - No incentives printed on the stand ("review us and get 10% off").
  - Check both during proof approval. Otherwise the customer's Google listing risks review
    removal.

---

## 5. How the products connect to Coglink data

| Concern | Today | Required |
|---|---|---|
| Card a tag opens | `Card.slug` is unique and mutable (`cogcard/lib/models/Card.ts:50`, `app/api/v1/cards/[id]/route.ts:53`) | Tag targets `cardId`; resolve the slug at redirect time; keep `slugHistory` for old QR codes |
| `review_card` template | Not in the backend enum (`Card.ts:67-71` allows only `minimal`, `corporate`, `modern_dark`); the app already has `CardTemplate.reviewCard` (`lib/shared/models/card.dart:9`) | Add `review_card`, `profile_hub`, `cover_card` to the backend (cross-ref audit 01/03) |
| Google review URL | The app reads `card.googleReviewUrl` (`lib/shared/models/card.dart:188,241`); the backend `Card` has no such field | Add `organization.googleReview{placeId, url}` (org-level, shared by stands and cards) + optional per-card override |
| Staff vs staff ID card | Coglink `Staff` = dashboard operator with `assignedCardIds` (`lib/models/Staff.ts:9,25`); plan §6.4 = "one card per staff member" | P3 links a **Card** (the person's card), not a Staff login. Quote must validate `card.ownerId == org` and `status == active`, and must not be `disabledByBilling` |
| Seats / plans | Static `maxCards` on Plan / org override (`lib/plans.ts:29-64`); no expiry, no subscription | `entitlements` (§13.10) with `validUntil`; card-slot counter driven by active entitlements |

---

## 6. P4 bundle: entitlement design

- On verified payment (webhook or verify, whichever lands first), in the same conditional update
  that flips `pending_payment → paid`, enqueue `grantEntitlements(orderId)`.
- That job inserts, for each P4 unit:
  `entitlements{organizationId, type:'card_seat', quantity:1, source:{orderId, orderItemId, unitIndex}, status:'pending_activation', validFrom:null, validUntil:null, termMonths:12}`.
  A unique index on `source.orderId + source.orderItemId + source.unitIndex` makes it idempotent.
- **The clock starts at activation**: when the tag is claimed or the card is activated, or at
  `deliveredAt + 15 days`, whichever comes first. A seat should not burn while the card is still
  being printed. Product decision D4.
- The seat counter becomes the sum of active entitlements plus subscription seats. Activating the
  linked card consumes the P4 seat first.
- **Refund or cancel**: revoke `pending_activation` entitlements. For active ones, refund
  pro-rata, or block the refund once the tag has been activated (policy D5).
- **Expiry**: the card is disabled by billing (`disabledByBilling`) after a grace period. The tag
  keeps resolving, to the "inactive" page.
- **Renewal**: a separate subscription or renewal SKU. This is the digital part, and policy
  applies (§7).
- **Buyer with no org yet** (bought on the website before signing up): attach the entitlement to
  `buyerEmail`/`userId` and bind it to the org at first sign-in.
- **App**: show "Includes 1 year Bizzvot digital card" on the item, and the granted entitlement on
  order detail ("Seat ready: assign to a card"). `Order` and `Subscription` in
  `commerce_models.dart` have no entitlement link yet.

---

## 7. App Store / Google Play payment policy

The policies change often and differ by storefront. Legal or product must confirm the current
text of Apple App Review Guidelines §3.1 and the Google Play Payments policy before release
(plan §12.6, decision D1).

| Item | Apple | Google Play | Recommendation |
|---|---|---|---|
| P1, P2, P3 | 3.1.3(e): physical goods consumed outside the app **must not** use IAP | Physical goods are exempt from Play Billing | Razorpay in-app is fine. Set `paymentPolicy: physical` |
| P4 physical card | same | same | Razorpay |
| P4 included 12-month digital card service | Unlocks a digital service managed in the app. Reviewers may treat it as a digital subscription under 3.1.1 | A digital subscription comes under the Play Billing requirement (India has a user-choice/alternative billing programme; check eligibility) | Option A, lower risk: sell P4 in-app as a physical product whose card hosting is part of what the tag needs to work, with no extra in-app features unlocked, and price it like the physical good. Option B, lowest risk: on iOS, hide P4 or redirect to the web store with no in-app call-to-action (3.1.3(f) companion-app model). Server-driven `purchaseChannel` per platform: `inApp \| webOnly \| hidden` |
| P4 renewals, seat purchases, plan upgrades (`billing/presentation/seat_purchase_screen.dart`) | Digital: IAP required, unless an exemption such as 3.1.3(c) enterprise or 3.1.3(f) companion applies | Play Billing / user-choice billing | **Do not sell through Razorpay in-app on iOS.** Either implement IAP, or treat the app as a companion that manages seats bought on the web, with no purchase CTA |

App-side changes:
- Change `PaymentPolicy.defaultFor(plan)` from `externalDigitalService` to `inAppDigital`, which
  blocks checkout (`catalog_models.dart:68-75`), until D1 is decided.
- Remove the title-substring heuristic that infers NFC personalisation
  (`physical_models.dart:72-84`). Personalisation must come from the server.
- Add `includesDigital: true` and `purchaseChannel` to `CatalogItem` and `QuoteLine`.

---

## 8. Mobile app commerce: gaps for physical products

Snapshot of `lib/features/{catalog,cart_checkout,orders,billing,subscriptions_renewals}`.
What is good:
- The cart holds no prices (`commerce_models.dart:9-12`).
- Idempotency keys exist (`catalog/domain/idempotency.dart`).
- There is a hosted-checkout fallback, and the payment status comes only from the server.
- Per-unit `LinePersonalization` with "assign later" (`physical_models.dart:170-215`).
- Validated Indian address, PIN and GSTIN (`physical_models.dart:222-262`).
- Address and GST are sent to `quote` and `createOrder` (`cart_checkout/data/cart_checkout_repository.dart:20-50`).
- Addresses are stored only in secure storage (`cart_checkout/data/address_store.dart`).
- There is a fulfilment timeline model.

| Sev | Gap | Evidence | Fix |
|---|---|---|---|
| High | Checkout screen not implemented | `cart_checkout/presentation/checkout_screen.dart` is a STUB | Build: address → personalisation review → quote → pay |
| High | No Razorpay native SDK path. `PaymentSession` only reads a hosted `checkoutUrl` (`commerce_models.dart:716-776`) | Razorpay standard checkout needs `key_id + order_id` (SDK), or a Payment Link (`short_url`) | Backend returns both `razorpay{keyId, orderId, amount, prefill}` and `checkoutUrl` (Payment Link). The app prefers the SDK on Android/iOS and falls back to the URL. The app still polls `GET /orders/:id` |
| High | No post-order personalisation: "assign later" is offered in the cart but there is no API or screen to assign after payment | `LinePersonalization.assignLater` (`physical_models.dart:175`); no endpoint in `endpoints.dart` | `GET/PATCH /orders/:id/units/:unitId/personalization`; order-detail CTA "Assign N cards" |
| High | No design-proof approval | `FulfilmentStep.design` is display-only (`physical_models.dart:371`) | Proof viewer (image/PDF) + Approve / Request changes; push notification |
| High | No tag activation, claim or re-pointing; no "My NFC tags" screen; the app does not handle universal links for `/t/{code}` | no NFC code in `lib/` beyond catalogue models | `tags` feature: deep link → claim → choose target; list tags per org; re-point; disable lost tag |
| High | P4 entitlement not modelled | `Order` has no entitlement link; billing screens are stubs | Show granted seats on order detail and billing; refresh after payment (§6) |
| Medium | No cancellation, return or replacement requests | `orders/data/orders_repository.dart` is read-only | `POST /orders/:id/cancel`, `POST /orders/:id/returns` |
| Medium | No PIN serviceability or ETA before checkout | Quote recalculates only after the full address is entered | `GET /shipping/serviceability?pin=` on PIN entry: ETA, COD eligibility |
| Medium | COD not modelled | `PaymentOutcome` has no COD; landing offers COD | `paymentMethod: online \| cod` in `POST /orders` and quote; COD only where `codEligible` |
| Medium | Logo upload goes to `POST /media/upload`, which re-encodes raster images (JPEG/PNG/WebP/GIF ≤5 MB) and counts toward the card media quota (`personalization_repository.dart:96-120`; `cogcard/app/api/v1/media/upload/route.ts:26-56`) | Print needs SVG/PDF or ≥300 dpi PNG, unmodified, and owned by the order | `POST /print-assets` (SVG/PDF/PNG ≤20 MB, virus/structure check, no re-encode) → `printAssetId` |
| Medium | P3 lacks staff-ID fields: photo, employee ID, blood group/emergency contact (optional), front/back template | `UnitPersonalization` has only name, designation, logo (`physical_models.dart:91-160`) | Extend the spec from server `personalization.fields[]` (schema-driven form) |
| Medium | Review target accepts any https URL | `ShippingValidators.reviewUrl` (`physical_models.dart:256`) | Server allow-list; app hint "paste your Google review link"; prefill from `organization.googleReview` |
| Medium | Personalisation for review packs is not per unit | Stop-gap spec sets `perUnit:false` for review items (`physical_models.dart:76-83`) | Server spec `perUnit: optional` for multi-branch packs |
| Low | Address book is device-only | `address_store.dart` notes this | `GET/POST /account/addresses` (server, org-scoped) |
| Low | Tracking: the app shows courier, AWB and URL but no scan events | `Fulfilment` holds no event list | `shipment.events[]` → timeline with location and time; NDR action ("reschedule") |
| Low | Invoice: the model has `buyerGstin` and `placeOfSupply`, but there is no credit-note display | `commerce_models.dart:787-888` | `invoice.type: tax_invoice \| credit_note`; download via short-lived signed URL |

---

## 9. Gap table (platform-wide)

Owners: **BE** backend (Coglink), **APP** Flutter, **OPS** production/fulfilment, **FIN** finance/CA,
**PL** product/legal, **DEVOPS**.

| # | Sev | Area | Gap | Fix | Owner |
|---|---|---|---|---|---|
| G1 | Critical | Platform | No commerce backend in Coglink; plan lists billing routes as "existing" but they do not exist | Commerce module in Coglink (`/api/v1`) per §10; correct plan §11.1 | BE, PL |
| G2 | Critical | Security | `nfcwebsiteecom-` trusts client prices and has unauthenticated arbitrary-amount Razorpay orders | Never deploy that checkout; if it is live, disable or fix now (server repricing, amount check in verify and webhook) | BE |
| G3 | Critical | Privacy | Customer PII CSV exports committed in `nfcwebsiteecom-` | Delete, rewrite history (`git filter-repo`), rotate any credentials, record a DPDP incident if the repo was ever shared | DEVOPS, PL |
| G4 | High | Security | Gateway secrets in plaintext and returned by the admin GET to staff | Encrypt at rest (port `settings-crypto.ts`); write-only secrets in the API; admin-only role | BE |
| G5 | High | Payments | No event-id ledger or replay protection; no amount/currency check in the `nfcwebsiteecom-` webhook | `webhookEvents{provider, eventId unique, receivedAt, processedAt, payloadHash}`; check amount + currency + `notes.orderId` | BE |
| G6 | High | NFC | No tag model, `/t/{code}` redirect, programming log, QC or claim | §4: `tags` collection + redirect + admin batch generator + programming/QC tool | BE, OPS |
| G7 | High | NFC | Slug-based URLs are mutable and can be reused across tenants | Tag targets `cardId`; slug history + reserved-slug cooldown | BE |
| G8 | High | Fulfilment | No proof/production workflow; `nfcwebsiteecom-` auto-creates the AWB on payment | `fulfilmentUnits` state machine; AWB only from `packed` | BE, OPS |
| G9 | High | Entitlement | P4 bundle has no entitlement grant, start date or revocation rules | §6; decisions D4/D5 | BE, PL |
| G10 | High | Policy | P4 digital component and seat purchases may need IAP | §7; server `purchaseChannel`; app default `inAppDigital` for plans | PL, APP |
| G11 | High | Tax | COD and shipping excluded from GST base; no SAC line for the P4 digital service; HSN per product unknown | CA to confirm HSN (cards: 8523.52 "smart cards"; stand: 8523 or 3926), SAC for card hosting, treatment of P4 as mixed vs composite supply; tax all charges | FIN |
| G12 | High | App | Checkout stub; no SDK payment; no post-order assign, proof, activation | §8 | APP |
| G13 | Medium | Data | Landing orders live in `data/db.json` | Migration script into Mongo `orders`; switch the landing checkout to the API | BE |
| G14 | Medium | Shipping | Rates by country/state zones, not PIN; no serviceability pre-check API | Delhivery serviceability + rate in the quote; fallback flat slab (e.g. ₹0 above a threshold, else ₹49–79) | BE |
| G15 | Medium | Shipping | Delhivery webhook secret optional; duplicate-AWB race | Mandatory secret + IP allow-list; atomic AWB lock | BE |
| G16 | Medium | COD | 30% surcharge; personalised items carry RTO scrap risk | COD only for non-personalised packs; flat surcharge with GST; RTO cost tracking | PL, FIN |
| G17 | Medium | Returns | No RMA for dead or misprogrammed tags or misprints | `returns` with reason codes (`nfc_dead`, `misprint`, `damaged`, `wrong_item`), photo upload, replacement unit re-enters printing | BE, OPS, APP |
| G18 | Medium | Invoices | No credit notes; landing fallback numbers >16 characters; `nfcwebsiteecom-` invoice no. = order no. | One series per FY via a Mongo counter (`INV/26-27/00001`); credit-note series `CN/26-27/…` | BE, FIN |
| G19 | Medium | Templates | `review_card` and the Google review URL are missing in the backend | Add to the Card/Organization schema | BE |
| G20 | Medium | Review policy | Risk of review gating or incentive text on stands | Proof checklist; `review_card` template sends everyone to Google | PL, OPS |
| G21 | Medium | Print assets | Media upload re-encodes and shares the card quota | Dedicated print-asset upload | BE, APP |
| G22 | Low | Stock | Blank cards, stands and chips not tracked | `inventory{sku, onHand, reserved}` reserved at order, consumed at printing | BE, OPS |
| G23 | Low | Notifications | No in-app events for proof ready, shipped, delivered, tag inactive | NOT-1 + push later | BE, APP |
| G24 | Low | Reconciliation | No job that compares Razorpay settlements with orders | Nightly `payments.all` / settlements diff → admin alert | BE, FIN |

---

## 10. API proposal (Coglink `/api/v1`)

Conventions follow plan §14: envelope `{success, data, error:{code,message}}`, money in integer
paise plus `currency:"INR"` (COM-2), `Idempotency-Key` on every `POST` that creates something
(COM-1), and org scope taken from the session (never from the body).

### 10.1 Catalogue

| Method & path | Auth | Request | Response `data` |
|---|---|---|---|
| `GET /catalog/products?category=nfc` | anon | — | `items[]: {id, slug, type:'product', title, media[], variants[{id, label, unitCount, price:{amount, currency, taxInclusive:true}, compareAt, sku, inStock}], hsn, gstRate:18, paymentPolicy, purchaseChannel:{ios, android, web}, includesDigital, entitlement?:{type:'card_seat', perUnit:1, termMonths:12}, requiresShipping:true, codEligible, personalization:{nfcTarget:'card'\|'review'\|'none', perUnit:'required'\|'optional'\|'no', fields:[{key, label, type:'text'\|'image'\|'card'\|'review_url', required, maxLength}], proofRequired:true}, leadTimeDays}` |
| `GET /catalog/products/:slug` | anon | — | single item as above + `faqs[]`, `specs[]` |

### 10.2 Quote and serviceability

| Method & path | Auth | Request | Response `data` |
|---|---|---|---|
| `GET /shipping/serviceability?pin=673001` | anon | — | `{pin, serviceable, prepaid, cod, etaDays:{min,max}, city, state}` |
| `POST /cart/quote` | owner | `{lines:[{itemId, variantId, quantity, personalization?}], shippingAddress?, gst?:{gstin, businessName}, paymentMethod?:'online'\|'cod', couponCode?}` | `{quoteId, expiresAt, lines:[{lineKey, itemId, variantId, title, quantity, unitPrice, lineTotal, hsn\|sac, taxableValue, gst:{rate, igst, cgst, sgst}, paymentPolicy, warnings[]}], invalidLines:[{lineKey, code:'CARD_NOT_ACTIVE'\|'OUT_OF_STOCK'\|'SEAT_REQUIRED'\|...}], shipping:{amount, method, etaDays}, codFee?, discounts[], taxTotal, total, placeOfSupply, requiresShipping:true, codAvailable}` |

### 10.3 Orders and personalisation

| Method & path | Auth | Request | Response `data` |
|---|---|---|---|
| `POST /orders` (Idempotency-Key) | owner | `{quoteId, lines[...], shippingAddress, billingAddress?, gst?, paymentMethod, termsAccepted:true}`; the server re-prices, so `quoteId` only detects a stale quote | `{order}` with `status:'pending_payment'`, `paymentDeadline`; 409 `QUOTE_STALE` with fresh totals |
| `GET /orders?status=&page=` | owner | — | `Paged<orderSummary>` |
| `GET /orders/:id` | owner | — | `{id, orderNumber, status, paymentStatus, paymentMethod, totals, taxSnapshot, shippingSnapshot, items:[{id, title, quantity, units:[{id, index, status, personalization, proof?, tag?:{code, status, target}, shipmentId}]}], shipments:[...], entitlements:[...], invoices:[{id, number, type}], timeline:[{step, at, note}], allowedActions:['pay','cancel','assign','approve_proof','return']}` |
| `PATCH /orders/:id/units/:unitId/personalization` | owner | `{target:{type:'card', cardId}\|{type:'google_review', url\|placeId}\|{type:'review_page'}, fields:{printName, printDesignation, photoAssetId, logoAssetId, employeeId}}` | updated unit; 409 `LOCKED_AFTER_PROOF_APPROVAL` |
| `POST /print-assets` (multipart) | owner | `file` (SVG/PDF/PNG/JPEG ≤20 MB), `purpose:'logo'\|'photo'` | `{id, url, width, height, dpiEstimate, warnings[]}` |
| `GET /orders/:id/units/:unitId/proofs` | owner | — | `[{id, version, fileUrl (signed), createdAt, status}]` |
| `POST /orders/:id/units/:unitId/proofs/:proofId/approve` | owner | `{}` | unit `proof_approved` |
| `POST /orders/:id/units/:unitId/proofs/:proofId/request-changes` | owner | `{comment}` (≤3 rounds) | unit `changes_requested` |
| `POST /orders/:id/cancel` (Idempotency-Key) | owner | `{reason}` | `{order, refund?:{id, amount, status}}`; 409 `NOT_CANCELLABLE` |
| `POST /orders/:id/returns` (Idempotency-Key) | owner | `{unitIds[], reason:'nfc_dead'\|'misprint'\|'damaged'\|'wrong_item', comment, photoAssetIds[]}` | `{returnId, status:'requested'}` |
| `GET /returns/:id` | owner | — | `{status, resolution:'replace'\|'refund', reversePickupAwb?}` |

### 10.4 Payments and webhooks

| Method & path | Auth | Request | Response `data` |
|---|---|---|---|
| `POST /orders/:id/payment` (Idempotency-Key) | owner | `{method:'razorpay'}` | `{attemptId, gateway:'razorpay', razorpay:{keyId, orderId:'order_…', amount, currency, name, description, prefill:{name, email, contact}, notes:{orderId}}, checkoutUrl?:'https://rzp.io/…', expiresAt}`. Reuses an open attempt; the amount always equals the server total |
| `POST /payments/razorpay/verify` | owner | `{attemptId, razorpay_order_id, razorpay_payment_id, razorpay_signature}` | `{order}`: advisory, using landing logic (signature + fetch + captured + amount + currency); never grants anything that the webhook would not |
| `POST /webhooks/razorpay` | HMAC `X-Razorpay-Signature` over the raw body | Razorpay events `payment.captured`, `payment.failed`, `order.paid`, `refund.processed`, `refund.failed`, `payment.dispute.*` | `200` fast. Insert `webhookEvents` (unique `x-razorpay-event-id`), process async, conditional state updates |
| `POST /admin/orders/:id/refunds` (Idempotency-Key) | super-admin | `{amount, reason, unitIds?}` | `{refundId, status}` + credit note |
| `POST /admin/orders/:id/cod-collected` | super-admin | `{collectedAt, remittanceRef?}` | `{order}` |

### 10.5 Shipments

| Method & path | Auth | Request | Response `data` |
|---|---|---|---|
| `GET /orders/:id/shipments` | owner | — | `[{id, courier:'Delhivery', awb, status, trackingUrl, eta, events:[{status, location, at, remarks}]}]` |
| `POST /admin/shipments` | super-admin | `{orderId, unitIds[], weightG, dims, pickupLocation}` | `{shipment, awb}`; atomic lock prevents duplicates; units must be `packed` |
| `GET /admin/shipments/:id/label` | super-admin | — | PDF |
| `POST /admin/shipments/:id/pickup`, `/cancel`, `/ndr-action` | super-admin | Delhivery parameters | `{shipment}` |
| `POST /webhooks/delhivery` | mandatory shared-secret header + IP allow-list | Delhivery scan push | `200`; dedupe on `awb + status + statusDateTime` |

### 10.6 Tags

| Method & path | Auth | Request | Response |
|---|---|---|---|
| `GET /t/:code` (web, not under `/api`) | anon, rate-limited | — | 302 to the target, or an activation / inactive page; logs a tap event |
| `POST /tags/claim` | owner | `{code, claimPin?}` | `{tag:{id, code, status:'active'\|'unclaimed', target}}`; 403 `TAG_BOUND_TO_OTHER_ORG`; 429 |
| `GET /organization/tags?status=` | owner | — | `Paged<{id, code, product, unitId, status, target, lastTapAt, taps30d}>` |
| `PATCH /organization/tags/:id` | owner (or staff with `manageLinks`) | `{target}` | updated tag; audit-logged |
| `POST /organization/tags/:id/disable` | owner | `{reason:'lost'\|'stolen'\|'replaced'}` | tag `disabled` |
| `POST /admin/tags/batch` | super-admin | `{count, sku}` | `[{code, claimPin}]` CSV for print and encoding |
| `POST /admin/tags/:code/program` | super-admin / ops device | `{chipUid, unitId, locked:true}` | tag `programmed`, unit `programming` → `qc_passed` after `POST /admin/tags/:code/qc {ok, readUrl}` |

### 10.7 Invoices and entitlements

| Method & path | Auth | Response |
|---|---|---|
| `GET /invoices?orderId=` | owner | `Paged<{id, number, type:'tax_invoice'\|'credit_note', issuedAt, total, placeOfSupply, buyerGstin}>` |
| `GET /invoices/:id` | owner | full invoice incl. per-line HSN/SAC, taxable value, IGST/CGST/SGST, seller GSTIN |
| `GET /invoices/:id/pdf` | owner | 302 to a signed URL valid for 5 minutes |
| `GET /organization/entitlements` | owner | `[{id, type:'card_seat', quantity, status, validFrom, validUntil, source:{orderId}, consumedByCardId?}]` |

### 10.8 Data model additions (to §13)

- `products`: `type`, `slug`, `variants[{id, sku, unitCount, pricePaise, taxInclusive}]`, `hsn`,
  `sac?`, `gstRate`, `paymentPolicy`, `purchaseChannel`, `includesEntitlement`,
  `personalizationSpec`, `codEligible`, `weightG`, `dims`, `leadTimeDays`, `status`.
- `orders`: §13.8 plus `paymentMethod`, `placeOfSupply`, `buyerGstin`, `holds{refundPending}`,
  `allowedActions` (computed), `source:'app'|'web'|'landing_import'`.
- `fulfilmentUnits`: `orderId`, `orderItemId`, `index`, `status`, `personalizationSnapshot`,
  `proofs[]`, `tagId`, `shipmentId`, `history[]`; indexes `(orderId)` and `(status, updatedAt)`
  for the production queue.
- `paymentAttempts`: §13.9 (unique `gatewayOrderId`, unique `idempotencyKey`).
- `webhookEvents`: unique `(provider, eventId)`.
- `shipments`: `orderId`, `unitIds[]`, `awb` (unique), `status`, `events[]`, `codAmount`.
- `tags`: `code` (unique), `claimPinHash`, `chipUid` (unique sparse), `organizationId`, `unitId`,
  `status`, `target{type, cardId?, url?, placeId?}`, `lockedAt`, `taps`.
- `entitlements`: §13.10 plus `source{orderId, orderItemId, unitIndex}` (unique), `status`,
  `consumedByCardId`.
- `invoices`: §13.11 plus `type`, `series`, `fy`, `seq` (unique `(series, fy, seq)`), `lines[]`
  with HSN/SAC.
- `returns`: `orderId`, `unitIds`, `reason`, `photos`, `status`, `resolution`, `reverseAwb`.
- `counters`: `invoice:{fy}`, `creditNote:{fy}`, `order:{yyyymm}`.

---

## 11. Phased implementation plan

| Phase | Duration | Scope | Exit criteria |
|---|---|---|---|
| **0: Stop the bleeding** | 2–3 days | G2: confirm whether `nfcwebsiteecom-` is deployed; if so, disable its checkout or move it to maintenance. G3: purge the PII CSVs from the repo and history. G4: rotate Razorpay/Delhivery secrets that have been stored in that DB. Make the Delhivery webhook secret mandatory on the landing/legacy stores | No client-priced checkout reachable; PII removed |
| **1: Decisions** | 1 week, in parallel with 0 | D1 store policy per item and platform (§7). D2 HSN/SAC, GST on COD and shipping, P4 mixed vs composite supply (CA). D3 COD scope and fee. D4 entitlement term start. D5 cancel/refund cut-offs + RMA policy. D6 short domain for tags. D7 chip type and locking. D8 who programs tags (ops Android app vs USB writer) | Signed-off decision log; plan §12, §13 and Appendix B updated |
| **2: Tag foundation** | 1 week | `tags` collection, `/t/{code}` redirect (302, no-store, tap logging), admin batch generator, inactive and activation pages, universal-link config (AASA + `assetlinks.json`; cross-ref audit 06). Back-fill tags for future landing-page orders | A programmed test tag resolves; re-pointing works without rewriting the chip |
| **3: Checkout core in Coglink** | 2–3 weeks | Products seed (P1–P4 + packs), `POST /cart/quote` with Delhivery serviceability/rate, `POST /orders`, `POST /orders/:id/payment`, verify, webhook with event ledger (port landing logic), invoices and credit notes with an FY counter, email/WhatsApp. Depends on native auth (AUTH-1, audit 02) | Contract tests: tampered client price ignored; amount mismatch auto-refunds; duplicate webhook is a no-op; double-tap "Pay" creates one attempt |
| **4: Production and shipping** | 2 weeks | `fulfilmentUnits` state machine, personalisation PATCH + print-asset upload, proof upload/approve/changes, super-admin production queue, programming + QC endpoints, port Delhivery (atomic AWB, label, pickup, NDR, webhook, cron), shipment timeline API | One P1 and one P3×3 order goes end to end in staging: paid → proof → printed → programmed → AWB → delivered |
| **5: App integration** | 2 weeks (APP), overlapping 3–4 | Checkout screen, Razorpay SDK + hosted fallback, PIN check, COD (if D3), order-detail actions (assign, approve proof, cancel, return), tracking events, "My NFC tags" (claim, re-point, disable) via deep link, entitlement display, invoice PDF | Widget/integration tests per plan §20 Commerce; store reviewer notes prepared for D1 |
| **6: P4 entitlements and seats** | 1 week | Entitlement grant/revoke jobs, seat counter from entitlements, activation-starts-clock, expiry → `disabledByBilling` + inactive tag page, reconciliation job (G24) | Refund of an unactivated P4 revokes the seat; renewal path follows D1 |
| **7: Migration and retirement** | 1 week | Import landing `db.json` orders (`source:'landing_import'`), point the landing checkout at `/api/v1`, archive `nfcwebsiteecom-` (keep as reference only) | One order store; one invoice series |

Critical-path dependencies: native auth (audit 02) gates Phase 3 for the app. Org-level
`googleReview` and the `review_card` template (audits 01 and 03) gate the P1/P2 targets.
Super-admin screens (audit 05) gate Phase 4 operations. Universal links (audit 06) gate tag activation.
