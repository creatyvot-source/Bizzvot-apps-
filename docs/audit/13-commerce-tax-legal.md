# 13 — Commerce, tax and consumer-law compliance gap analysis

> **Not legal or tax advice.** This is an engineering-led gap analysis written from a read-only review of the code. It cites statutes and rules from general knowledge as of October 2026. Thresholds, rates and rules change: GST rates were restructured on 22 Sep 2025, the DPDP Rules were notified in Nov 2025, and CCPA advisories keep arriving. **A Chartered Accountant (GST) and an Indian consumer/IT-law advocate must review this before anything is relied on.** International points (UAE/GCC/EU) need advice from someone local to each jurisdiction.

**Scope reviewed (read-only).**
- `nfc-landing-page/`: the live NFC store at creatyvot (Google Review card/stand, Razorpay, COD, Delhivery, invoices).
- `nfcwebsiteecom-/`: a general Next.js storefront ("nextn") that is still branded for another merchant.
- `cogcard/`: the Coglink portal/API for digital cards, plans and reviews. It has no payments.
- `Bizzvot-apps-/lib/features/{billing,catalog,cart_checkout,orders,subscriptions_renewals}`, `lib/core/config/app_config.dart`, and `docs/PRODUCT_PLAN.md` §11–13.

No customer personal data is reproduced here.

---

## 1. Summary

**Overall: the store is not yet compliant enough to sell at scale. The Flutter app's commerce layer is the best-prepared part.**

1. **GST registration is effectively mandatory now.** The store ships to other states, and inter-state supply of goods requires compulsory registration under CGST s.24(i) whatever the turnover. The landing store already has a "tax-invoice readiness" switch (`nfc-landing-page/lib/seller.ts`). When GSTIN, address or state is missing it falls back to a "Commercial invoice" numbered `INV-{orderId}` (`lib/invoice.ts:74,192`), and that fallback is not a valid tax invoice.
2. **The taxable value is understated on the landing store.**
   - The 30% COD surcharge is explicitly treated as "outside GST" (`lib/invoice.ts:109`).
   - Shipping collected on COD is also shown as "outside product GST".
   - Under CGST s.15(2)(c) and the composite-supply rules, both form part of the consideration and should bear 18%.
3. **COD invoices are issued too late.** An invoice number is allocated only once an order is *marked paid* (`lib/invoice.ts:66-90`, `app/api/admin/orders/route.ts:71`). For COD that means after cash is collected at the door. CGST s.31(1) requires the tax invoice on or before removal/delivery of goods, so COD goods currently travel with no invoice.
4. **There are no credit notes anywhere.** Grepping all four repos finds no CGST s.34 / Rule 53 document. Cancellations and refunds after an invoice (`lib/order-cancel.ts`; ecom `api/payment/refund.ts`) leave GSTR-1 overstated.
5. **The landing store publishes no consumer-law pages.**
   - Missing: seller legal name and address, grievance officer, terms, returns/refund/cancellation, shipping, and privacy pages. The only public routes are `/product/[slug]`, `/checkout` and `/order-success`, and there is no footer.
   - These are required by Rules 4 and 7 of the Consumer Protection (E-Commerce) Rules 2020. Razorpay also requires these pages for merchant KYC.
6. **Fake-review and misleading-price risk.**
   - Rating 4.9 and "86 reviews" are hard-coded (`data/products.ts:61-62`). They are emitted as schema.org `aggregateRating` (`app/product/[slug]/page.tsx:64`) and shown in `ReviewsSection`, with three anonymous hard-coded testimonials.
   - Strike-through "compare-at" prices are internally inconsistent. A single card is "₹499 → ₹350", yet the 3-pack's compare price is ₹1,050 (₹350 each).
   - This engages CPA 2019 s.2(28)/2(47), the CCPA Misleading Ads Guidelines 2022, and IS 19000:2022.
7. **Drip pricing.**
   - Checkout shows "Delivery: Free". An admin can then add a shipping charge to a COD order after the sale (`app/api/admin/orders/route.ts:76-105`).
   - The 30% COD fee appears only at the payment-method step.
   - The Flutter product screen says "Final price, taxes … confirmed at checkout" (`catalog_item_screen.dart:102`).
   - All three are risks under the Dark Patterns Guidelines 2023 (drip pricing).
8. **The ecommerce repo cannot be deployed as-is.**
   - It still carries another merchant's identity: "Enkilum Ente Krishna", "— Devotional Store —", and that merchant's support email and street address.
   - It defaults to HSN 7113 (jewellery) on GST invoices (`gst-invoice.ts:44,86,192`).
   - It trusts client-sent prices and taxes (`checkout/actions.ts:352-363`).
   - It has **customer order/transaction CSV exports committed to git** (`orders_export_1.csv`, `transactions_export_1.csv`), which is a DPDP Act 2023 / IT Act s.43A exposure.
9. **Payments are in good shape.**
   - Razorpay signatures are verified with an HMAC and `timingSafeEqual` (landing `lib/razorpay.ts:117-169`, `app/api/webhooks/razorpay/route.ts:23-26`; ecom `api/payment/razorpay/verify.ts`, `checkout/actions.ts:759`).
   - Card data is never stored, and hosted checkout keeps the merchant at PCI SAQ A.
   - The Flutter app trusts only the server's state (`checkout_screen.dart` `_SecureNote`).
   - Renewals are manual, so the RBI e-mandate rules do not bite yet.
10. **Coglink reviews (intermediary + IS 19000).**
    - Reviews auto-approve by default (`cogcard/lib/models/Review.ts:37`).
    - The card owner can hide any review, including negative ones, with no reason recorded (`organization/reviews/[id]/status/route.ts`).
    - There is no published moderation policy, no reviewer T&C/genuineness declaration, no public "report" flow, and no grievance officer. Coglink has no public terms or privacy page at all.
11. **The Flutter app is well modelled.** It already has a server-quoted itemised total, `taxLines`, `buyerGstin` and `placeOfSupply` on invoices (`commerce_models.dart:798-832`, `physical_models.dart:349`), an unticked terms checkbox, idempotency keys, and server-only payment truth. Gaps:
    - `/app/config` (`app_config.dart`) has no grievance officer, seller identity, refund/shipping/cancellation policy links, or country of origin.
    - `termsAccepted: true` carries no terms version.
    - The order, invoice and subscription screens are still stubs.
    - There are no cancel, return or refund-request endpoints.
12. **International sales are not ready.** There is no LUT, IEC or export-invoice wording. The ecom tax code sets non-IN destinations to `NO_GST` (`calculate-tax.ts:68`), which is only lawful under an LUT with export documentation. Ecom shows AED prices from hard-coded FX rates. Recommendation: **sell India-only until P2 items are done.** If digital subscriptions are sold to UAE consumers, UAE VAT registration may be triggered.

---

## 2. Requirements matrix

Priority: **P0** fix before/at the next sale, because the exposure exists today. **P1** within about 30 days or before the Flutter shop launches. **P2** before scale or international sales.
Owners: **FIN** (founder + CA), **LEG** (lawyer), **WEB-L** (landing store), **WEB-E** (ecom repo), **API** (Coglink backend / commerce API), **APP** (Flutter), **OPS** (fulfilment/support).

### 2.1 GST (CGST/IGST Acts and CGST Rules 2017)

| # | Law / rule | Requirement | Current state + evidence | Gap | Fix | Owner | P |
|---|---|---|---|---|---|---|---|
| G1 | CGST s.22/24(i) | Register; inter-state taxable supply of goods requires registration from the first sale. Composition scheme not available for inter-state supplies. | Landing has a readiness check (`app/api/admin/needed/route.ts:152-163`, `lib/seller.ts:49-53`). It falls back to `legalName: "creatyvot"` and address `"India"`. | Unknown whether GSTIN is configured in production. No hard block on selling without it. | Confirm GSTIN (single legal entity/PAN behind creatyvot/Cogineo/Bizzvot). Make `taxInvoiceReady` a launch blocker in production. Disable prepaid/COD checkout while it is false. | FIN, WEB-L | P0 |
| G2 | CGST s.31(1), Rule 46/47 | Tax invoice on or before removal/delivery of goods. Invoice for services within 30 days. | Invoice number allocated only when the order is marked paid (`lib/invoice.ts:66-90`). The admin "generate invoice" API refuses unpaid orders (`app/api/admin/orders/route.ts:71`). COD is paid only on delivery. | COD goods move with no invoice. Invoice date is the payment date, not the supply date. | Allocate the invoice when the shipment/AWB is created (prepaid: at capture is fine). Print it into the parcel or attach it to the Delhivery manifest. Show the COD payment status separately on the invoice. | WEB-L, OPS | P0 |
| G3 | CGST s.15(2)(c), s.2(30), s.8 | Taxable value includes incidental charges collected by the supplier (COD fee, delivery). Delivery bundled with goods is a composite supply taxed at the goods' rate. | `orderGstBreakdown()` splits GST only on `onlineTotalPaise` ("COD surcharge is outside GST", `lib/invoice.ts:109`). Invoice text: "Shipping is collected with COD (outside product GST)" (`lib/invoice.ts:380-398`). Ecom invoice adds shipping into "Total excl. GST" without any tax (`gst-invoice.ts:159`). | GST under-reported on COD surcharge and shipping. | Treat the COD fee and buyer-paid shipping as GST-inclusive taxable lines at 18% (or the principal supply's rate). Apply the inclusive split to the grand total. Back-compute past liability with the CA (DRC-03 if needed). | WEB-L, WEB-E, FIN | P0 |
| G4 | Rule 46 | Mandatory invoice fields (full list in §5). | **Landing has:** supplier name/address/GSTIN, FY serial `INV-2526-0001` (≤16 chars, OK), date, buyer name/address, optional buyer GSTIN (`AddressForm.tsx:219`, validated `lib/validation.ts:57-62`), HSN, qty, total taxable value, CGST/SGST or IGST totals. **Landing lacks:** place-of-supply *state name + code* (only a prose note), per-line taxable value/rate/tax, UQC, "reverse charge: No", signature/DSC line, and per-product HSN (one global `seller.hsn` = 8523, `lib/invoice.ts:350`). **Ecom:** wrong merchant name, "Devotional Store" header, HSN default 7113, invoice no. = order no., no place of supply, no buyer GSTIN, "Amount Due" on paid orders (`gst-invoice.ts:44,86,192,323`). | Not a fully compliant tax invoice. Ecom invoice is unusable. | Implement the §5 template. Use per-SKU HSN/SAC and rate from the catalogue. Snapshot both onto the order (PRODUCT_PLAN §13.8 `taxSnapshot`). | WEB-L, WEB-E, API | P1 (ecom: P0 if deployed) |
| G5 | Rule 46(b) | Consecutive serial, unique per FY, single series per GSTIN or declared series. | Landing: `INV-{FY}-{seq}` under a file lock. Fallback `INV-{orderId}` when not tax-ready (`lib/invoice.ts:74,106`). Ecom: order number only. | Two parallel series, the fallback one non-consecutive. The future Coglink/Flutter invoices (`/invoices`) need their own declared series. | One series per GSTIN per document type (INV/CN) and per channel if needed (e.g., `WEB/`, `APP/`), declared in GSTR-1 Table 13. Remove the `INV-{orderId}` fallback for registered persons. | WEB-L, API, FIN | P1 |
| G6 | CGST s.34, Rule 53(1A) | Credit note for cancellations, returns or refunds after invoicing, referencing the original invoice, within the s.34(2) time limit. | None in any repo. Landing cancel refunds via Razorpay (`lib/order-cancel.ts:38-90`). Ecom `RefundForm.tsx`, `api/admin/orders/[id]/refunds.ts`, `ReturnRequest` model. | Output tax stays overstated. No document trail for refunds. | Add a `creditNotes` collection with series `CN-{FY}-{seq}`, created automatically on refund/cancel-after-invoice. Show it on order/invoice screens (Flutter `Invoice` model can carry `type: credit_note`). | API, WEB-L, WEB-E, APP | P1 |
| G7 | IGST s.10(1)(a), s.12(2)/s.13 | Place of supply. Goods: the delivery location, so Kerala→Kerala is CGST+SGST and other states IGST. B2C services: the recipient's address on record. B2B: the registered recipient's location. | Landing compares seller state vs buyer state (`lib/india-states.ts`, `lib/invoice.ts:150-160`). It defaults to CGST+SGST when the seller state is unknown. Ecom does similar logic (`calculate-tax.ts:58-68`) using a **client-supplied** state and prices. Flutter collects `placeOfSupply` (`physical_models.dart:349-372`). | Default-to-intra-state is wrong for out-of-state buyers. Ecom tax is client-trusted. For B2B with a GSTIN, the place of supply should follow the GSTIN's state code (first 2 digits). | Make the server derive POS from the delivery PIN→state (and GSTIN state code for B2B). Reject checkout if unknown. Print "Place of supply: Kerala (32)". | WEB-L, WEB-E, API | P1 |
| G8 | Rule 46 + Notif. 78/2020 | HSN digits: AATO ≤ ₹5 cr → 4-digit mandatory on B2B (B2C optional). > ₹5 cr → 6-digit on all. GSTR-1 Table 12 HSN summary split B2B/B2C. | One global HSN 8523 (landing). Per-product `hsnCode` field exists on ecom (`models/Product.ts:32`), default '' → printed 7113. Flutter `taxCategory` proposed (PRODUCT_PLAN §12.2/13.7). Coglink `Plan` has no SAC/tax fields (`cogcard/lib/models/Plan.ts`). | No per-SKU HSN/SAC. No SAC for the service. | Add `hsnSac`, `gstRate`, `uqc`, `supplyType: goods\|service` to every SKU and plan (see §3). Snapshot onto orders. | API, WEB-L, FIN | P1 |
| G9 | CGST s.2(74)/(90), s.8 | Bundles: decide composite vs mixed supply for the ₹999 "Business Digital + Physical NFC Card". The answer drives HSN/SAC, time of supply and place of supply. | Product not present in any repo's catalogue. Landing sells only review card/stand packs (`data/products.ts`). Coglink has no commerce. | No decision. No invoice treatment. | See §3. Recommended: itemise on the invoice as two separately valued lines (card goods + 12-month service), or record the CA's composite-supply opinion. | FIN, API | P1 |
| G10 | Rule 48(4), Notif. 13/2020 & later | E-invoicing (IRN + QR) required for B2B/export invoices when AATO (PAN-wide, any FY since 2017-18) > ₹5 cr. AATO ≥ ₹10 cr must report to the IRP within 30 days. B2C dynamic QR only if AATO > ₹500 cr. | Not implemented. | Probably not applicable yet. Must be tracked at **PAN level** across all brands. | Add an AATO watch to the finance dashboard (`app/admin/(protected)/reports`). Pick an IRP-integrated invoicing provider before crossing ₹5 cr. | FIN | P2 |
| G11 | Rule 138 | E-way bill for consignments > ₹50,000 (inter-state; intra-state limits vary, confirm Kerala's). Delhivery can generate Part B. | Not handled (Delhivery integration in `lib/delhivery*.ts`, ecom `delhivery-service.ts`). | Bulk B2B orders could cross the threshold (e.g., 150 staff ID cards × ₹350 = ₹52,500). | When the order value incl. GST exceeds the threshold, block auto-manifest until the e-way bill number is entered/generated. Pass it to Delhivery. | OPS, WEB-L | P2 |
| G12 | CGST s.52, s.24(ix) | TCS (0.5% since 10 Jul 2024) collected by marketplaces (Amazon/Flipkart/Meesho), plus compulsory registration. Razorpay, WhatsApp and own-site sales are not ECO sales. | Own site + Razorpay only. | None today. | If marketplaces are added: reconcile GSTR-8 TCS credit, ECO-wise GSTR-1 tables, and income-tax s.194-O. | FIN | P2 |
| G13 | Pricing integrity (s.15 value) | Taxable value must be the actual transaction value. | Ecom `checkout/actions.ts:297-363` accepts `subtotal`, `shipping`, `tax`, `taxType`, `pricesIncludeTax` from the browser and only checks that they add up. No DB re-price. Landing re-prices from the catalogue (`app/api/checkout/route.ts:61`). | Ecom tax records can be tampered with (also a revenue-leak bug). | Ecom must re-price from `Product` server-side (shared with audit 04). Retire ecom if the landing store is the system of record. | WEB-E | P0 if deployed |
| G14 | CGST s.35/36 | Keep accounts and invoices for 72 months from the annual return due date. | Landing stores orders in `data/db.json` (file DB, git-ignored, `lib/db.ts:26`). Admin readiness only *warns* about a durable DB in production (`needed/route.ts:145`). | A single-file store on an app server is a retention and loss risk. | Move orders/invoices/credit notes to durable, backed-up storage (MongoDB per PRODUCT_PLAN §13.11). Store immutable invoice PDFs. | WEB-L, API | P1 |

### 2.2 Consumer Protection Act 2019 and Consumer Protection (E-Commerce) Rules 2020

The seller is an **inventory e-commerce entity** (Rules 4 + 7). Coglink, as a host of third-party cards and reviews, is also an intermediary (§2.4).

| # | Law / rule | Requirement | Current state + evidence | Gap | Fix | Owner | P |
|---|---|---|---|---|---|---|---|
| C1 | E-Com Rule 4(2) | Prominently display legal name, principal geographic address, website, and customer-care contact (email, phone). | Landing: brand "creatyvot" and a link to creatyvot.com in the header (`components/product/AnnouncementBar.tsx`), plus a WhatsApp widget. No address or legal name. Ecom: another merchant's name/email/address (`app/contact/page.tsx:21-29`, `app/about`). Flutter: `supportEmail/supportPhone` only (`app_config.dart:37-38`). | Seller identity missing (landing) or wrong (ecom). | Add a site-wide footer + `/contact` with legal entity name, registered address, GSTIN, CIN/LLPIN if any, email, phone. Add `seller{legalName,address,gstin}` to `/app/config`. | WEB-L, WEB-E, API, APP | P0 |
| C2 | E-Com Rule 4(4)-(5) | Grievance officer: name, designation, contact displayed. Acknowledge within 48 h, resolve within 1 month. Ticket number. | None in any repo (grep "grievance" = 0 hits). | Missing entirely. | Publish the grievance officer. Add `support.grievanceOfficer{name,designation,email,phone}` to `/app/config` and show it in app Settings/Help and on the web footer. Add a ticketing workflow with SLA timers (48 h ack / 30 d resolve) in admin. Mention the National Consumer Helpline (1915) and e-Daakhil. | LEG, OPS, API, APP, WEB-L | P0 |
| C3 | E-Com Rule 7(1)(a) | Accessible info on return, refund, exchange, warranty/guarantee, delivery/shipment, payment modes, and grievance mechanism, **before purchase**. | Landing: none (only a COD FAQ). Ecom: generic template pages with another merchant's name (`returns-refunds`, `shipping-policy`, `terms-of-service`, `privacy-policy`). Flutter: unticked terms checkbox + "Read the terms" link (`checkout_screen.dart:394-425`). | No policies on the live store. No warranty statement for NFC chips. Flutter links only `termsUrl`. | Publish the §4 pages. Link them from product page, checkout and order emails. Add `links.{refund,shipping,cancellation,warranty}` to `/app/config` and show them next to the checkbox. | LEG, WEB-L, API, APP | P0 |
| C4 | E-Com Rule 7(1)(b), Rule 4(9) | Total price as a single figure with a breakup of all compulsory and voluntary charges (delivery, handling, COD, taxes) before purchase. Record explicit, affirmative consent with no pre-ticked boxes. | Landing `OrderSummary.tsx` shows package total, delivery (default "Free"), COD surcharge, and "Total payable incl. GST". Flutter `quote_summary.dart` shows the server-itemised lines, discounts, taxes, shipping and total. Terms checkbox defaults to `false` (`checkout_screen.dart:36`). | Landing admin can add shipping after the order (`admin/orders/route.ts:76-105`), so the paid total is not the displayed total. Flutter posts `termsAccepted: true` with no version or time (`cart_checkout_repository.dart:51`). | Freeze the total at order creation. Any later charge needs fresh customer consent. Send `termsVersion` + `acceptedAt` and store them server-side with the order. | WEB-L, API, APP | P0 (landing), P1 (app) |
| C5 | E-Com Rule 4(10), 7(3) | Refund within a reasonable time once accepted. Cannot refuse to take back or refund defective, deficient, spurious or late goods. | Landing refunds on cancel only (admin). No customer return/refund request. Ecom has `ReturnRequestForm`, 7-day damaged/defective window, "5-7 business days" refund (`returns-refunds/page.tsx`). Flutter: refund status displayed only, no request endpoint. | No customer channel to claim defective/late delivery on landing or app. Ecom excludes "personalized items" while every NFC card is personalised. Lawful for change of mind, but it cannot exclude defects. | Policy: personalised goods are non-returnable for change of mind, but replaced or refunded if defective, mis-printed, chip not working, wrong or late. Add `POST /orders/:id/support-request` (type: defect/not-delivered/cancel) to the commerce API and app. | LEG, API, APP, OPS | P1 |
| C6 | E-Com Rule 4(6) | No cancellation charges unless the seller bears similar charges when it cancels unilaterally. | Landing cancel is admin-only. Ecom: "cancel within 24 hours" (FAQ). | No customer cancellation window for made-to-order goods. | Define "free cancellation until design approval / printing starts". Expose `canCancel` + `cancelDeadline` from the server and add a Flutter cancel action. | LEG, API, APP | P1 |
| C7 | E-Com Rule 7(1)(c)/(e), LM(PC) Rules 2011 r.6(10) | Display mandatory Legal Metrology declarations and **country of origin** on the listing. | No country of origin, manufacturer/packer name and address, net quantity or MRP declaration on any listing (landing `data/products.ts`, ecom `Product`, Flutter catalogue models). | Missing. | Add `countryOfOrigin`, `manufacturer`, `packer`, `netQuantity` ("1 N"), `mrp`, `consumerCare` to the product schema. Render them on the product page and app item screen. If chips/blanks are imported, name the importer. | API, WEB-L, APP | P1 |
| C8 | CPA s.2(28) misleading ad, s.2(47) unfair trade practice; CCPA Misleading Ads & Endorsements Guidelines 2022 | Reference/strike-through prices must be genuine. Endorsements must reflect genuine, verifiable experience. | Landing single-card compare-at ₹499 vs ₹350 each in the 3/5-packs (`data/products.ts:66-90`). The "30% OFF" badge is hard-coded. Testimonials are anonymous, hard-coded copy ("Reviews jumped in a week"). Rating 4.9 / 86 reviews hard-coded and emitted as `aggregateRating` JSON-LD (`app/product/[slug]/page.tsx:64`). | Unverifiable claims and possibly fictitious reference prices. Also violates Google structured-data policy. | Remove `aggregateRating`, rating and testimonials until backed by stored genuine reviews with evidence. Keep reference prices only if they were the real prior selling price for a reasonable period (keep evidence) or are the printed MRP. Label any paid or incentivised endorsement. | WEB-L, LEG | P0 |
| C9 | Guidelines for Prevention & Regulation of Dark Patterns 2023 (Annexure 1) | No drip pricing, false urgency, basket sneaking, subscription trap, forced action, confirm-shaming, SaaS billing, bait-and-switch, disguised ads. | **Drip pricing:** the 30% COD fee appears only at payment selection (`PaymentSelector.tsx:23`, `CODCalculator.tsx`), and post-order shipping can be added on COD (C4). Flutter item screen: "Final price, taxes … confirmed at checkout". **False urgency:** countdown strip disabled (`AnnouncementBar.tsx:1` "offer/countdown strip is hidden"), good. **Basket sneaking:** ecom gift-wrap defaults off (`GiftOptions.tsx:16`), good. **Subscription trap / SaaS billing:** no auto-renew yet, but there is no cancel path in the app either. **Bait-and-switch:** the ₹999 bundle's digital service term is undisclosed. | Several drip-pricing risks. Bundle/renewal disclosure absent. CCPA's 2025 advisory asks platforms to self-audit, and COD fees drew regulatory scrutiny in 2025. | (a) Show "Online ₹X · COD ₹Y" on the product page and justify or reduce the 30% COD fee. (b) Change the app copy to "Inclusive of all taxes. Delivery charges, if any, shown before payment." (c) Disclose the bundle's service period, renewal price and what happens to the physical card on lapse, both on the listing and in the order confirmation. (d) Make cancelling a subscription as easy as buying it. (e) Keep a dated self-audit record. | WEB-L, APP, API, LEG | P0 (a, b), P1 (c-e) |
| C10 | CPA s.2(9) consumer rights; s.84-87 product liability | Information about quality and quantity, and warranty. | No warranty terms (e.g., chip replacement period). | Missing. | Publish a warranty (e.g., X months against chip or print defects) and carry it into the invoice and order emails. | LEG | P1 |
| C11 | E-Com Rule 4(11)-(12) | No manipulated prices or unreasonable profit; no discrimination between consumers. | Ecom `CurrencySelector` shows AED/USD prices from hard-coded FX (`lib/currency-service.ts:37-48`) but charges INR. | Displayed foreign price differs from the charged amount. | Remove the currency selector, or label it "approximate; you will be charged ₹X". | WEB-E | P1 |

### 2.3 Payments (RBI)

| # | Law / rule | Requirement | Current state + evidence | Gap | Fix | Owner | P |
|---|---|---|---|---|---|---|---|
| P1 | RBI e-mandate framework (2019, amended 2021/2023) | Recurring charges: AFA at registration; no AFA for subsequent debits ≤ ₹15,000. Pre-debit notification ≥ 24 h before each debit with an opt-out. Easy mandate withdrawal. | Manual renewals only: `POST /subscriptions/:id/renew` opens hosted checkout each time (`subscriptions_providers.dart:56-90`). `Subscription.autoRenew` is parsed but not used. PRODUCT_PLAN §11.4 leaves auto vs manual open. | None today. A risk if auto-renew is added without a mandate. | Keep manual renewals for v1. If auto-renew ships: use Razorpay Subscriptions / UPI Autopay / card e-mandate. Store the mandate ID. Send pre-debit notices. Add "Cancel auto-renew" in-app. Show "renews on {date} at ₹X incl. GST" before consent. | API, APP | P2 |
| P2 | RBI tokenisation / CoF (Oct 2022), PA guidelines | Merchants must not store card data. Refunds go to the original payment source. | No card storage. Landing refunds via Razorpay to the original payment (`lib/order-cancel.ts:78`). Ecom `PaymentMethodSelector.tsx:340-389` renders raw card number/CVV inputs when the provider is `stripe`/`square`/`mock`, and the default provider is `mock` when `PAYMENT_PROVIDER` is unset (`api/payment/gateway-config.ts:22`). | Ecom could show a fake card form in production, which would put PAN/CVV in the merchant DOM. | Remove the in-page card form and the mock provider from production builds. Fail closed if the provider is unset. | WEB-E | P0 if deployed |
| P3 | PCI-DSS v4.0 (SAQ A) | Hosted or embedded gateway pages only. Integrity of the page that loads checkout (req. 6.4.3 / 11.6.1 for SAQ A). | Razorpay Checkout.js / hosted URL (landing `components/checkout/CheckoutClient.tsx`, Flutter opens an https URL `COM-3`). | Script-integrity monitoring and CSP for checkout pages are not evidenced. | Add a CSP restricted to `checkout.razorpay.com` on checkout pages, a script inventory, and the annual SAQ A attestation Razorpay asks for. | WEB-L | P1 |
| P4 | Gateway best practice | Verify payment and webhook signatures server-side. Make processing idempotent. | Done. Landing `lib/razorpay.ts:117-169` (HMAC SHA-256 + `timingSafeEqual`), `app/api/webhooks/razorpay/route.ts:23-26`. Ecom `checkout/actions.ts:755-765`, `api/payment/razorpay/verify.ts`. Flutter uses idempotency keys (`catalog/domain/idempotency.dart`). | — | Keep. Add webhook replay-window/event-ID dedupe if missing (see audit 04). | — | — |
| P5 | RBI TAT circular (Sep 2019) + E-Com Rule 4(10) | Failed-transaction auto-reversal TATs (T+1 for cards/UPI, ₹100/day compensation, gateway-side). Merchant refunds within a stated time. | Policy text "5-7 business days" (ecom only). | No stated refund TAT on landing or app. | State "refund initiated within 2 business days of approval, credited by your bank in 5-7 business days". Show refund status and UTR/ARN in order detail (Flutter `refundStatus` exists). | LEG, APP, OPS | P1 |
| P6 | RBI Master Direction on Payment Aggregators (2025) | Merchant KYC with PA. Website must show T&C, refund, privacy, contact and shipping policies. | Landing lacks those pages (C1-C3). | Razorpay can suspend settlements if policy URLs are missing. | Same fix as C1-C3. | WEB-L | P0 |
| P7 | Apple/Google store policy (PRODUCT_PLAN §12.6, gap COM-4) | Digital features unlocked in the app may require IAP. Physical goods may use Razorpay. | `paymentPolicy` per item; `inAppDigital` blocked (`API_GAP_REGISTER.md` COM-4). | The ₹999 bundle mixes physical and digital. | Classify the bundle (physical-led, service used outside the app) and keep a written rationale. Seats/subscriptions bought in-app need a policy decision. | LEG, APP | P1 |

### 2.4 IT Act 2000, Intermediary Rules 2021, DPDP Act 2023, and online reviews

| # | Law / rule | Requirement | Current state + evidence | Gap | Fix | Owner | P |
|---|---|---|---|---|---|---|---|
| R1 | IT (Intermediary Guidelines) Rules 2021 r.3(1)(a)-(b) | Publish rules/regulations, privacy policy and user agreement. Inform users about prohibited content. | Coglink has no public terms or privacy pages (`cogcard/app` has only `page.tsx` and `card/[slug]`). Flutter has `links.privacyPolicy/terms` in config (`app_config.dart:66-67`). | Missing on web. Only links (no content) in the app. | Publish a Coglink user agreement + acceptable-use policy + privacy policy. Show them in card-editor sign-up and on every public card footer ("Report this card"). | LEG, API | P1 |
| R2 | Intermediary Rules r.3(1)(d), 3(2) | Takedown within 36 h of a court/government order. Grievance officer: acknowledge in 24 h, resolve in 15 days (72 h for certain content; 24 h for non-consensual intimate imagery). Preserve data 180 days. Disclose the Grievance Appellate Committee route. | None. Reviews can only be hidden by the card owner or super-admin (`api/v1/admin/reviews/[id]/status`). | No public complaint intake. No SLA. No preservation log. | Add a `POST /public/report` endpoint (card/review, reason) and a super-admin queue with SLA timers, an audit log (PRODUCT_PLAN §13.13) and a legal-hold flag. | API, LEG, OPS | P1 |
| R3 | IS 19000:2022 (BIS, voluntary; CCPA promotes it) | Reviewer accepts T&C and declares a genuine experience. Verify the author (email/phone). No suppression of negative reviews. Published moderation criteria, applied consistently. Disclose incentivised reviews. Report-a-review mechanism. Ratings computed from all eligible reviews. | Public review form takes name, optional email, rating and comment (`public/card/[slug]/review/route.ts:22-27`). Dedupe by IP hash/cookie, rate limit. Default status `approved` (`Review.ts:37`), moderation only on some plans. **The owner can set any review to `hidden` with no reason** (`organization/reviews/[id]/status/route.ts:18-22`). | Selective suppression is possible. No T&C/genuineness tick. No author verification. No moderation policy. No reason codes. No public report. | Require a reviewer checkbox ("genuine experience, accepts review terms"). Add optional OTP/email verification and a "verified" badge. Restrict owners to *reply* and *report*; hiding requires a reason code from a published policy (abuse, PII, spam, off-topic) and is logged, with super-admin oversight. Publish the moderation policy. Show counts of moderated reviews. | API, APP, LEG | P1 |
| R4 | CPA s.2(47) + CCPA fake-review focus + Google review policies | NFC "Google Review" cards must not facilitate fake, incentivised or gated reviews. Marketing must not promise 5-star outcomes. | Copy: "Get more 5-star Google reviews", "Ask them to leave a star rating" (`data/products.ts:10,14`). Product name uses the "Google" mark. | Encourages solicitation of positive reviews only. Trademark/affiliation ambiguity. | Reword to "Collect more Google reviews from real customers". Add a buyer guidance note: no incentives, no gating, ask all customers. Add "Google is a trademark of Google LLC; not affiliated" wherever the mark is used. | WEB-L, LEG | P1 |
| R5 | DPDP Act 2023 + DPDP Rules 2025 (phased; most duties expected by ~May 2027); IT Act s.43A / SPDI Rules 2011 | Lawful purpose, notice, security safeguards, breach notification, retention limits. Staff ID cards: the buying business is the data fiduciary and Bizzvot a processor, so a DPA is needed. | Ecom repo commits customer order/transaction exports (`orders_export_1.csv` ~507 rows, `transactions_export_1.csv`; both git-tracked, PII columns present). Coglink stores review emails and IP hashes. | Committed PII in the repo history. No processor terms for staff-ID data. | Remove the CSVs and purge them from git history (rotate any exposed links). Restrict repo access. Publish a privacy notice + a B2B data-processing addendum for staff-ID/directory data. Set retention periods. Covered in depth by audit 07. | WEB-E, LEG | P0 (CSV), P1 (rest) |

### 2.5 Shipping and fulfilment

| # | Law / rule | Requirement | Current state + evidence | Gap | Fix | Owner | P |
|---|---|---|---|---|---|---|---|
| S1 | E-Com Rule 7(1)(a); Dark Patterns (drip pricing) | Disclose delivery timelines and charges before purchase. | Landing: "Free shipping on prepaid" (`data/products.ts:216`). No delivery estimate. Ecom template: "Metro 3-5 / Other 5-7 / Remote 7-10 business days" (another merchant's text). Flutter: fulfilment timeline model (`physical_models.dart:375+`), no estimate in the quote. | No EDD on landing or app. Production (printing) time not stated. | Show "Printed in X working days + delivery Y-Z days to PIN nnnnnn" from Delhivery TAT. Add `estimatedDelivery{from,to}` to `/cart/quote`. | WEB-L, API, APP | P1 |
| S2 | Practical / consumer fairness | Check serviceability (and COD availability) by PIN before taking the order. | Landing PIN lookup uses India Post for address autofill only (`AddressForm.tsx:105`). Delhivery pincode check is admin-only in ecom (`api/admin/shipping/delhivery/check-pincode.ts`). | Orders accepted for non-serviceable or non-COD PINs. | Call the Delhivery serviceability API at checkout. Hide COD where it is not available. | WEB-L, API | P1 |
| S3 | COD rules (gateway/courier T&C; s.31 invoice; C9) | COD fee disclosed upfront and taxed. Invoice travels with goods. Courier remittance reconciled. | 30% COD fee "outside GST". Invoice after collection (G2/G3). | See G2/G3/C9. | See G2/G3/C9. Reconcile Delhivery COD remittances against invoices. | OPS, FIN | P0 |
| S4 | Rule 46/48 + LM labels | Parcel contains the invoice, LM label (MRP, maker, origin, consumer care) and return address. | Not evidenced. Delhivery label endpoint exists (`ecom api/admin/orders/[id]/delhivery-label.ts`). | Unknown. | Add a packing checklist and print a combined invoice + LM label sticker. | OPS | P1 |

### 2.6 International (Gulf, EU)

| # | Law / rule | Requirement | Current state + evidence | Gap | Fix | Owner | P |
|---|---|---|---|---|---|---|---|
| X1 | IGST s.16 (zero-rated), Rule 96A | Export of goods/services without IGST only under an **LUT** (RFD-11, annual) or bond. Otherwise pay IGST and claim a refund. Invoice endorsement "Supply meant for export under LUT without payment of IGST". | Ecom sets `NO_GST` for any non-IN country (`calculate-tax.ts:68`). Landing is India-only (PIN-based address). | No LUT, no export endorsement, no shipping bill / courier export declaration. | Until an LUT is filed: block non-IN shipping (landing already does; ecom must). When enabled: LUT ARN on the invoice, foreign-currency or permitted-INR realisation (Razorpay e-FIRA/e-BRC), courier shipping bill (Courier Exports Regs), IEC from DGFT. | FIN, WEB-E, OPS | P2 |
| X2 | IGST s.2(6), s.13 | Export of *services* (digital card subscription to Gulf businesses) is zero-rated only if all s.2(6) conditions hold, including payment in convertible foreign exchange or INR where RBI permits. | No international billing in Coglink. | — | Capture the customer country and tax ID for subscriptions. Apply export treatment only with FIRA evidence. | FIN, API | P2 |
| X3 | UAE Federal Decree-Law 8/2017 (VAT 5%); KSA 15%, Bahrain 10%, Oman 5%; Qatar/Kuwait no VAT as of writing (verify) | Physical goods: the importer pays import VAT + ~5% GCC customs duty (de minimis rules vary). B2C digital services by a non-resident to UAE consumers: non-resident VAT registration (no threshold). | Not handled. Ecom displays AED prices. | Selling subscriptions to UAE individuals could trigger UAE VAT registration. | Ship goods DAP with a clear "duties and taxes payable by recipient" notice at checkout. Restrict digital subscriptions to B2B (reverse charge) in GCC, or register. Take local advice. | FIN, LEG | P2 |
| X4 | EU Consumer Rights Directive 2011/83 art.9/16; GPSR (EU) 2023/988; EU VAT OSS/IOSS; GDPR | 14-day withdrawal (exempt for personalised goods, art.16(c); digital services need express consent + acknowledgement). An EU-established responsible person for products. VAT via IOSS (≤ €150) / OSS. | Not targeted. | — | **Do not sell to the EU** until a responsible person, IOSS and GDPR basics exist. Geo-block EU addresses at checkout. | LEG, WEB-L | P2 |

### 2.7 Legal Metrology (Packaged Commodities) Rules 2011

| # | Law / rule | Requirement | Current state + evidence | Gap | Fix | Owner | P |
|---|---|---|---|---|---|---|---|
| L1 | LM(PC) r.6 | Package label: manufacturer/packer/importer name and address; common/generic name; net quantity (number, "1 N"); month/year of manufacture; **MRP "₹… (incl. of all taxes)"**; consumer-care contact; country of origin for imports. | No product label spec. Prices are GST-inclusive in UI copy (landing `OrderSummary.tsx:82-86`, `PaymentSelector.tsx:23`), which is good. Never sell above MRP. | Label fields and MRP not defined. Applicability to made-to-order B2B goods is debatable ("institutional consumer" / not pre-packed); comply anyway as a low-cost safe harbour. | Define a label template per SKU. Set MRP ≥ the highest selling price including COD (note the COD price of ₹455 on a ₹350 card). Display MRP on the listing (r.6(10) e-commerce). | OPS, LEG, WEB-L | P1 |

---

## 3. GST treatment table (proposal for CA confirmation)

Prices are **GST-inclusive** (the landing store treats catalogue prices as all-inclusive, `lib/pricing.ts:6-10`). Rates shown are 18%. **Verify each HSN/SAC rate against the rate notifications in force after the 22-Sep-2025 rationalisation.**

| Item | Supply type | Suggested HSN / SAC (CA to confirm) | Rate | Inclusive price → taxable + GST | Place of supply | Notes |
|---|---|---|---|---|---|---|
| Google Review Card (NFC + QR, printed) | Goods | **8523 52** ("smart cards", an NFC chip card). Alternative if no chip: 4911 (printed matter), with a different rate. | 18% | ₹350 → ₹296.61 + ₹53.39 | Delivery state (IGST s.10(1)(a)) | Currently only `SELLER_HSN=8523` globally (`lib/seller.ts:49`). Card packs (3/5) are the same HSN, qty 3/5 NOS. |
| Google Review Stand (stand + NFC card/tag) | Goods. If sold as stand + card for one price, it is a mixed supply (s.8(b)), taxed at the highest rate. | 8523 52 for the NFC card/tag. Stand alone: 3926 (plastic/acrylic) or 4419/4421 (wood); check the material. | 18% (if both lines are 18%) | ₹499 → ₹422.88 + ₹76.12 | Delivery state | Prefer one composite SKU coded 8523 with the stand described as an accessory, or two lines. Record the decision. |
| Staff ID Card (card only) | Goods | 8523 52 (NFC/RFID card). Plain PVC ID card without chip: 3926 90. | 18% | ₹350 → ₹296.61 + ₹53.39 | Delivery state | Bulk B2B orders: capture buyer GSTIN (ITC). E-way bill above ₹50k. Staff personal data needs a DPA (R5). |
| Business Digital + Physical NFC Card ₹999 | **Bundle of goods + service** | Card: 8523 52. Digital card service: **SAC 998315** (hosting/IT infrastructure, SaaS) or **998319** (other IT services). | 18% | ₹999 → ₹846.61 + ₹152.39 | Composite: follows the principal supply. Mixed: follows the highest-rate item. Itemised: goods by delivery state, service by recipient address. | **Decision needed.** (a) The card is useless without the service and the service is the core value, so this is arguably a *composite supply* with the service as principal (SAC on the invoice). (b) Both components are also sold separately, so it is arguably a *mixed supply*. (c) **Recommended for clarity:** itemise as two lines with fair values (e.g., card ₹350 + 12-month service ₹649), which keeps HSN/SAC, time of supply and renewals clean. Tax is the same 18% either way; classification affects GSTR-1 HSN reporting and POS. **Disclose the service term and renewal price** (C9). |
| Digital card subscription / additional seats (Coglink plans) | Service, continuous supply on renewal | SAC 998315 / 998319 | 18% | e.g., ₹X incl. → X/1.18 + GST | B2B: registered recipient's state (GSTIN). B2C: recipient's address on record, else supplier location (IGST s.12(2)). | Time of supply: earlier of invoice or payment (s.13); issue an invoice at each renewal. Prorated upgrades need an invoice; downgrade refunds need a credit note. `Plan` needs `currency`, `billingPeriod`, `sac`, `gstRate`, `priceInclusive` (PRODUCT_PLAN §13.7). |
| Delivery charge collected from buyer | Part of a composite supply with goods | Follows the goods (no separate SAC 9965 when the supplier delivers to the buyer) | 18% | Include in the inclusive split | As goods | Not "outside GST" (G3). Seller-borne freight on prepaid orders should **not** appear as an invoice line at all; remove "Shipping (seller-paid freight)" rows (`lib/invoice.ts:236-246`). |
| COD surcharge | Part of the consideration (s.15(2)(c)) | As goods | 18% | e.g., ₹105 → ₹88.98 + ₹16.02 | As goods | Currently untaxed (`lib/invoice.ts:109`). |
| Export (goods to GCC; services to foreign businesses) | Zero-rated (IGST s.16) | Same HSN/SAC | 0% under LUT | — | Outside India | LUT + export documents required (X1/X2). |

---

## 4. Required policy pages and disclosures

Publish these on the landing store, the Coglink web and any ecom storefront. Link them from the Flutter app via `/app/config` (`links.*`) and show them before the checkout checkbox:

1. **About / Seller information.** Legal entity name, trade names (creatyvot / Bizzvot / Cogineo, with how they relate), registered and principal address, GSTIN, CIN/LLPIN/Udyam if any, email and phone. (E-Com Rule 4(2).)
2. **Contact & Grievance Redressal.** Grievance officer name, designation, email and phone. 48 h acknowledgement / 1-month resolution. Ticket ID. Escalation to the National Consumer Helpline (1915 / consumerhelpline.gov.in) and e-Daakhil. For Coglink UGC, the IT-Rules grievance officer, 24 h / 15-day SLAs and the GAC route. (E-Com Rule 4(4)-(5); IT Rules 3(2).)
3. **Terms of Sale.** Made-to-order nature, design-proof approval, pricing (inclusive of GST), COD fee, the delivery-charge rule, title/risk, governing law and jurisdiction (Kerala), limitation of liability (must not override CPA rights).
4. **Cancellation Policy.** Free until design approval / print start; what happens afterwards; seller-side cancellation (no one-sided charges, Rule 4(6)).
5. **Returns, Replacement & Refund Policy.** Personalised goods are not returnable for change of mind. Defects, mis-prints, non-working chips, wrong items and late delivery are replaced or refunded. Claim window (e.g., 7 days from delivery) with photo/video. Refund TAT and original-source refunds. Credit-note issuance.
6. **Shipping & Delivery Policy.** Production time and courier TAT by zone. Serviceability. Delivery charges (prepaid vs COD). COD availability and fee. Failed-delivery/RTO handling. India-only (until exports are enabled). For international: duties paid by the recipient.
7. **Warranty.** Chip/print warranty period, NFC compatibility disclaimer, QR fallback.
8. **Subscription & Renewal Terms** (digital card / seats / the service in the ₹999 bundle). Term, renewal price, manual vs auto-renew, grace period, what happens to cards and NFC links on lapse, upgrade/downgrade proration, cancellation and refunds. Pre-debit notices if auto-renew is introduced. (PRODUCT_PLAN §11.4 decisions.)
9. **Privacy Policy** (DPDP-aligned). Purposes, data categories (including staff data on ID cards and directories), processors (Razorpay, Delhivery, WhatsApp/SMTP), retention, rights, grievance/DPO contact, cookies.
10. **Coglink User Agreement & Acceptable Use** (intermediary). Prohibited content, takedown and reporting, account termination.
11. **Review Policy** (IS 19000-aligned). Who can review, the genuineness declaration, verification, moderation criteria, the no-suppression rule, how owners can respond, how to report, and incentivised-review disclosure.
12. **Product listing disclosures** (per SKU, not a separate page). Country of origin, manufacturer/packer, net quantity, MRP (incl. all taxes), consumer care, dimensions/material, delivery estimate, return eligibility, and the "Google is a trademark of Google LLC" disclaimer.

**Flutter `/app/config` additions** (extend gap CFG-1 in `docs/API_GAP_REGISTER.md`):
```
seller: { legalName, tradeName, address, gstin, cin? }
support: { email, phone, hours, grievanceOfficer: { name, designation, email, phone } }
links: { privacyPolicy, terms, refund, cancellation, shipping, warranty, subscriptionTerms, reviewPolicy, grievance }
legal: { termsVersion }
```
The app should send `termsVersion` and `acceptedAt` with `POST /orders` (`cart_checkout_repository.dart:51`) and `POST /subscriptions/:id/renew`.

---

## 5. Invoice template (Rule 46 + practical fields)

**Tax invoice (B2C and B2B).**
- **Header.** "TAX INVOICE". Copy marking "ORIGINAL FOR RECIPIENT" / "DUPLICATE FOR TRANSPORTER" / "TRIPLICATE FOR SUPPLIER" for goods (Rule 48).
- **Supplier.** Legal name, trade name, full address, state + state code, GSTIN, and optionally PAN/CIN, email and phone.
- **Invoice serial.** Consecutive, ≤ 16 characters, unique per FY (e.g., `INV/2627/000123`). **Date of issue.**
- **Order reference** (order no., order date) and **payment reference** (Razorpay payment ID / COD).
- **Recipient.** Name, billing address, state + code, and GSTIN if registered. **Delivery address** where it differs. For unregistered recipients with a value ≥ ₹50,000, name, address, delivery address and state name + code are mandatory (give them always).
- **Place of supply.** State name + code (e.g., "Kerala (32)"). For exports: "Outside India — {country}".
- **Per line.**
  - Description (with the bundle components), HSN/SAC, quantity, UQC (NOS).
  - Unit price, gross amount, discount, **taxable value**.
  - **Rate** and **amount** for CGST + SGST *or* IGST (and cess if any).
  - Line total.
- **Other charge lines.** Delivery and COD fee as taxable lines with the same HSN treatment (§3).
- **Totals.** Taxable value, total CGST/SGST/IGST, round-off, invoice total (in figures and words), amount paid / balance (COD).
- **"Whether tax is payable on reverse charge: No."**
- **Signature.** Digital signature or the authorised signatory's name. Electronic invoices may rely on the IT Act proviso; confirm with the CA.
- **For e-invoice** (once AATO > ₹5 cr, B2B/export): IRN, Ack no./date, signed QR.
- **For exports.** "Supply meant for export under LUT without payment of IGST — LUT ARN …", currency and exchange rate, port/courier, buyer country.
- **Footer (consumer law).** "Prices inclusive of GST". Return/refund policy URL. Grievance officer contact. Warranty summary. For bundles/subscriptions: the service period "from … to …" and the renewal terms.

**Credit note (Rule 53(1A)).**
- "CREDIT NOTE"; supplier details; CN serial (separate series, e.g., `CN/2627/000045`) and date.
- Recipient details and GSTIN; **original invoice number and date**.
- Reason (cancellation / return / post-sale discount).
- Per-line taxable value, rate and tax reversed; total; signature.
- Issue by the s.34(2) deadline (30 November after the FY end, or the annual-return date if earlier).

**Data model.** This maps onto PRODUCT_PLAN §13.11 `invoices` with fields `type: invoice|credit_note`, `series`, `seq`, `fy`, `supplierSnapshot`, `recipientSnapshot`, `placeOfSupply{state,code}`, `lines[{desc,hsnSac,qty,uqc,unitPrice,discount,taxable,cgst,sgst,igst,rate}]`, `charges[]`, `totals`, `reverseCharge:false`, `originalInvoiceId?`, `irn?`, `pdfUrl`, `issuedAt`. The Flutter `Invoice` model (`commerce_models.dart:798-832`) already covers most display fields. Add `type`, `originalInvoiceNumber`, `placeOfSupplyCode`, and per-line `hsnSac`/`taxable`/`rate`.

---

## 6. Prioritised remediation

### P0: before or at the next sale (exposure exists today)
1. **FIN/WEB-L.** Confirm GST registration and configure GSTIN, legal name, address and state in landing Admin → Settings. Block checkout in production while `taxInvoiceReady` is false. Remove the `INV-{orderId}` fallback for registered operation.
2. **WEB-L.** Tax the COD fee and buyer-paid shipping (inclusive 18% split on the grand total). Drop "seller freight" rows from customer invoices. With the CA, quantify past under-payment.
3. **WEB-L/OPS.** Allocate COD (and all) invoices at dispatch and pack them with the goods.
4. **WEB-L/LEG.** Publish the policy pages (§4 items 1-7, 9) with a site footer. Name the grievance officer. These also satisfy Razorpay KYC.
5. **WEB-L.** Remove the hard-coded 4.9★/86 rating, the JSON-LD `aggregateRating` and the anonymous testimonials. Fix or justify the strike-through prices.
6. **WEB-L.** Stop post-order shipping changes on COD (or require the customer to re-confirm). Show the COD price on the product page next to the online price.
7. **APP.** Change the catalogue copy at `catalog_item_screen.dart:102` to "Inclusive of all taxes; delivery charges shown before payment".
8. **WEB-E.** Do not deploy the ecom repo as-is: wrong merchant identity, HSN 7113, client-trusted prices/taxes, mock card form. **Purge `orders_export_1.csv` / `transactions_export_1.csv` from git history.**

### P1: within about 30 days or before the Flutter shop goes live
9. **API/WEB-L.** Implement the Rule 46 invoice template (§5): per-SKU HSN/SAC/rate/UQC, POS state + code, reverse-charge line, per-line tax.
10. **API.** Build the credit-note module and series. Refunds and cancellations after invoicing generate CNs automatically.
11. **FIN/API.** Decide the ₹999 bundle treatment (§3) and add the SKU with a disclosed service term and renewal price. Add SAC/rate/period/currency to Coglink `Plan`.
12. **API/APP.** Extend `/app/config` with seller, grievance and policy links. Send `termsVersion` with orders and renewals. Finish the order, invoice and subscription screens to show tax lines, POS and credit notes.
13. **API/APP.** Add cancel and support-request (defect / not delivered) endpoints and app actions with the server-driven `canCancel`. State the refund TAT.
14. **API/APP/LEG.** Bring Coglink reviews to IS 19000: reviewer declaration, optional verification, owner hide-with-reason only, logged moderation, public report endpoint, published review policy. Publish the Coglink user agreement and privacy policy. Set up the intermediary grievance process.
15. **WEB-L/API.** Delhivery serviceability + COD-availability check at checkout, and a delivery estimate in the quote.
16. **OPS/LEG.** Legal Metrology label and listing declarations (country of origin, maker, net qty, MRP incl. taxes, consumer care). Warranty policy. Reword "5-star" marketing and add the Google trademark disclaimer.
17. **WEB-L/API.** Move order and invoice storage off `data/db.json` to durable, backed-up storage with 72-month retention.

### P2: before scale or international sales
18. **FIN.** Track AATO at PAN level and prepare an e-invoicing (IRN) integration before ₹5 cr. Add e-way bill handling for consignments over ₹50k.
19. **API/APP.** If auto-renew is introduced: Razorpay Subscriptions / UPI Autopay e-mandate, pre-debit notices, one-tap cancel, renewal disclosure.
20. **FIN/OPS.** Exports: LUT, IEC, courier shipping bills, e-FIRA/BRC, the export invoice endorsement. Keep non-IN checkout blocked until then (fix ecom `NO_GST`).
21. **LEG/FIN.** GCC: DAP duties notice. Avoid B2C digital subscriptions to UAE consumers unless registered. EU: geo-block until GPSR responsible person / IOSS / GDPR are in place.
22. **FIN.** If marketplaces are added: registration under s.24(ix), TCS reconciliation (GSTR-8), s.194-O.

---

## 7. What is already good (keep)
- Landing re-prices from the server catalogue (`app/api/checkout/route.ts:61`). It verifies Razorpay payment and webhook signatures in constant time, and refunds to the original source.
- Landing shows GST-inclusive pricing with a visible "Includes GST @ 18%" note. It captures and validates buyer GSTIN, and splits CGST+SGST vs IGST by state. Invoice numbering is per FY and sequential under a lock.
- The countdown/false-urgency strip is disabled. Gift-wrap is not pre-selected.
- Flutter: the server is the only source of truth for price, tax and payment (PRODUCT_PLAN §12.3). It shows an itemised quote, uses an unticked terms checkbox and idempotency keys, carries GSTIN and place of supply in the models, and renews manually (no unconsented recurring debits).

*Prepared by audit agent 13 (read-only). Cross-references: audit 04 (commerce/payments), 06 (public web/landing), 07 (security/privacy).*
