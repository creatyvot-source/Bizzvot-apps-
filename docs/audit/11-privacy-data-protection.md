# 11 — Privacy & data-protection compliance gap analysis

**Audit agent 11 · read-only · 2026-10-11**
Scope: Coglink/cogcard (web portal + API + MongoDB) `/home/user/cogcard`, ecommerce `/home/user/nfcwebsiteecom-`,
landing + NFC product checkout `/home/user/nfc-landing-page`, Flutter app `/home/user/Bizzvot-apps-`.

> **Not legal advice.** This is an engineering gap analysis against our reading of the India DPDP Act 2023 and
> DPDP Rules 2025, the IT Act SPDI Rules 2011 (which still apply until the DPDP substantive provisions commence),
> GDPR / UK GDPR, UAE PDPL (Federal Decree-Law 45/2021), Qatar PDPPL (Law 13/2016) and CCPA/CPRA. Commencement
> dates, applicability thresholds and the controller/processor characterisation below **must be confirmed by
> qualified counsel in India (and in UAE/Qatar/EU if those markets are actively targeted)** before policies are
> published or store forms are submitted.
>
> No secrets or customer personal data are reproduced in this report. Where committed files contain personal data,
> only column names and counts are given.

---

## 1. Summary

**Overall posture: not ready for public launch from a privacy standpoint.** The engineering base has some good
privacy-by-design work (IP hashing, a 180-day TTL on card views, sanitised public DTOs, secure on-device storage,
in-app deletion UI). The legal and operational layer is mostly missing.

Top findings:

1. **P0 privacy incident: real customer personal data is committed to git.** `nfcwebsiteecom-/orders_export_1.csv`
   is a Shopify order export with 506 rows (432 orders). It contains about 400 distinct buyer names, billing and
   shipping street addresses, phone numbers, 233 distinct emails, payment references and marketing-consent flags.
   `transactions_export_1.csv` (447 rows) holds order↔gateway/payment-method records. The orders are for a
   *different* business (a devotional-products store, "Enkilum Ente Krishna"), not Bizzvot, and the repo is on
   GitHub (`creatyvot-source/nfcwebsiteecom-`). Whether the repo is private or public, this is a breach-assessment
   event. Purge from history, check access logs, and assess notification duties (see §6, P0-1).
2. **There is no privacy policy, terms or grievance contact for any Bizzvot property.** The cogcard web app and the
   landing/checkout site have no privacy page. The ecommerce repo's `/privacy-policy` belongs to the other brand.
   The Flutter app takes its legal links from a *proposed* `GET /app/config` that does not exist in cogcard, so the
   "I agree to the Terms and Privacy Policy" links currently lead to a legal screen with every link disabled. A
   privacy policy is already mandatory today under SPDI Rule 4, and will be under DPDP s.5 / Rule 3 and GDPR Art. 13.
3. **Consent is not captured server-side.** The app's terms checkbox is client-only, and `POST /auth/register` stores
   no consent version or timestamp. The web registration form has no checkbox at all. DPDP s.6(10) puts the burden
   of proving consent on the Data Fiduciary.
4. **No erasure or export path in the backend.** cogcard has no `DELETE /auth/account`, no organisation or
   individual deletion (not even for super-admin), and no data-export endpoint. Uploaded media (photos, logos, PDFs)
   is never deleted. The app's delete-account screen calls a non-existent endpoint (gap ACC-1), so App Store 5.1.1(v)
   and Play's account-deletion requirement would fail review.
5. **The public reviews API leaks reviewer email.** `GET /api/v1/public/card/:slug/reviews` excludes only
   `ipAddress` and `ipHash`. Any `reviewerEmail` a submitter supplied is returned publicly, contrary to PRODUCT_PLAN
   §8.4/§16.
6. **Sensitive staff fields (blood group, father's and mother's names) are collected by the app but silently dropped
   by the backend.** cogcard's `Card` schema and zod `cardWriteSchema` have no such fields. Blood group is
   special-category health data under GDPR Art. 9 and "sensitive personal data" under SPDI Rule 3. Decide whether to
   collect it at all. If yes, design the storage, access control and lawful basis deliberately; today it only
   *appears* to be saved.
7. **Session-replay tracking without consent.** The ecommerce site loads Microsoft Clarity unconditionally on every
   page, checkout included, with no cookie banner, no consent and no disclosure (ePrivacy Art. 5(3), GDPR Art. 6/7,
   DPDP s.5–6).
8. **Retention is undefined almost everywhere.** Exceptions are `CardView` (180-day TTL) and password-reset tokens.
   Reviews, link clicks, "exchange contact" leads (stored as free text in `Notification`), abandoned or failed
   orders, activity logs with IPs, and job applications with CVs are all kept forever.
9. **No sub-processor register, DPAs, breach runbook or DPIA.** There is also no staff-data notice for organisation
   owners, who are the controllers/fiduciaries for their staff's data while Bizzvot is processor.

---

## 2. Data inventory

Lawful-basis column: **DPDP** = consent (s.6) or legitimate use (s.7). **GDPR** basis is in brackets and only
matters if Art. 3(2) targeting of EU/UK users applies. "Owner" means the organisation account owner. Where Bizzvot
acts as **processor** for the owner, the owner's basis applies.

| # | Data item | System / store | Purpose | Lawful basis (proposed) | Retention today | Shared with / visible to |
|---|---|---|---|---|---|---|
| 1 | Account holder name, email, phone, bcrypt password hash, role, lock counters | cogcard `User` (`lib/models/User.ts`), MongoDB | Account, login, support | DPDP consent at sign-up / s.7(a) voluntary provision; [GDPR 6(1)(b) contract] | Forever; no account deletion | Super-admin (all), the user; SMTP provider (reset mail) |
| 2 | Organisation name, logo, industry, address, **GSTIN**, plan | cogcard `Organization` | Tenant profile, invoicing | Contract / legal obligation (GST) [6(1)(b),(c)] | Forever | Super-admin; GSTIN appears on invoices |
| 3 | **Staff** name, email, phone, password, permissions, assigned cards | cogcard `User`+`Staff`; created by owner (`app/api/v1/organization/staff/route.ts`) | Employer issues staff cards and logins | **Owner is fiduciary/controller**; Bizzvot = processor (DPDP s.8(2) contract). Owner relies on s.7(i) employment or consent [GDPR 6(1)(b)/(f)] | Hard-deleted on staff DELETE (good) | Owner, super-admin |
| 4 | Card content: name, designation, company, pronouns, photo, cover, bio, phone, WhatsApp, email, address, map link, socials | cogcard `Card`; media on local disk `public/uploads` or S3 | Public digital business card (purpose: *publication*) | Consent of the card subject (individual: own consent; staff: owner must obtain/notify) | Card hard-deleted with cascade; **media files never deleted** | **Public internet**, vCard downloads, owner, assigned staff, super-admin, S3 provider |
| 5 | **Blood group, father's name, mother's name** ("private details") | App only (`lib/shared/models/card.dart:167-170`, editor `card_editor_screen.dart:761+`); **not persisted** by cogcard | Staff ID card printing (presumed) | If kept: explicit consent; GDPR Art. 9(2)(a) explicit consent for health data | Dropped by backend today | Would be owner + Bizzvot print/fulfilment |
| 6 | Reviewer name, optional email, rating, comment | cogcard `Review` | Public reviews on cards | Consent at submission (needs notice) [6(1)(a)/(f)] | Forever (until card deleted) | Name + comment public; **email leaked publicly** via public API; owner/staff/super-admin |
| 7 | Reviewer IP → salted SHA-256 `ipHash`; legacy plaintext `ipAddress` on old docs | cogcard `Review` | One-review-per-visitor dedupe, abuse prevention | Legitimate interest / s.7 not obviously available → disclose; [6(1)(f)] | Forever; no migration to unset legacy IPs | Internal |
| 8 | Review dedupe cookie `cogcard_rid` (random UUID, 1 year) | Browser cookie, set in `app/api/v1/public/card/[slug]/review/route.ts` | Dedupe | Arguably strictly necessary for the requested service; disclose | 365 days | Internal |
| 9 | Card visitor analytics: ipHash, **full User-Agent**, **Referer**, timestamp | cogcard `CardView` (`lib/models/CardView.ts`) | View counts, unique visitors | Legitimate interest of owner; Bizzvot processor; disclosure required | **180-day TTL** (good) | Aggregates to owner/staff; super-admin |
| 10 | Link-click events: card, link type, URL, ipHash | cogcard `LinkClick` | Link analytics | As above | **Forever**, no TTL | Aggregates to owner/staff |
| 11 | "Exchange contact" leads: visitor name, email, phone, free-text message | cogcard `Notification.message` (free text) via `app/api/v1/public/card/[slug]/exchange/route.ts` | Lead hand-off to card owner | Consent of visitor (notice at form) | **Forever**, unstructured, not erasable by subject | Card owner (org owner or individual) |
| 12 | Rate-limit keys containing raw IPs | Redis or in-memory (`lib/redis.ts`, `lib/api.ts`) | Abuse prevention | Legitimate interest / security | 60 s–30 min TTL (good) | Redis host |
| 13 | Password-reset token hash | cogcard `PasswordResetToken` | Account recovery | Contract | TTL at expiry (good) | SMTP provider (email) |
| 14 | Dev-only email outbox (reset links, recipients) | `.data/emails/outbox.log`, console (`lib/email/sendEmail.ts`) | Local testing | n/a | Unbounded (gitignored) | Developers |
| 15 | NFC product orders: full name, phone, alt phone, email, pincode, home name, street, town, locality, city, state, **GSTIN**, maps URL, logo URL, delivery instructions, payment IDs | Landing `data/db.json` flat file (`lib/db.ts`, `lib/validation.ts`) | Fulfilment, tax invoice | Contract + legal obligation (GST invoice retention) [6(1)(b),(c)] | Forever, including **abandoned/failed** orders | Razorpay, Delhivery (address/phone), Creatyvot WhatsApp API (`api.creatyvot.com`), SMTP, admin |
| 16 | Customer logos uploaded for print | Landing `public/uploads/**` | Print fulfilment | Contract | Forever | Public URL, print vendor |
| 17 | App-local saved delivery addresses | iOS Keychain / Android Keystore (`lib/features/cart_checkout/data/address_store.dart`) | Checkout convenience | Consent (user-initiated) | Until app data cleared; **not cleared on logout/deletion**; iOS Keychain survives uninstall | Device only |
| 18 | Auth tokens | Secure storage (`lib/core/secure_storage/token_store.dart`) | Session | Contract | Until logout | Device |
| 19 | Ecommerce (template repo) users, customers, orders, carts, abandoned carts, stock alerts, returns, loyalty | `nfcwebsiteecom-/src/models/*` (MongoDB) | Shop | Contract / consent (marketing flags exist) | Forever | Razorpay/Stripe/PayPal/Square, Delhivery, Gmail API/SMTP, S3, Clarity |
| 20 | **Job applications:** name, email, phone, LinkedIn, CV text, "analysis" (match %, strengths, weaknesses) | `nfcwebsiteecom-/src/models/JobApplication.ts`; Firestore rules allow public `get,list` (`firestore.rules:128-131`) | Recruitment | Consent / pre-contract; profiling needs Art. 22 review | Forever | Admin; **world-readable if Firestore rules are deployed** |
| 21 | Admin activity log with IP + User-Agent | `nfcwebsiteecom-/src/models/ActivityLog.ts` | Audit/security | Legitimate interest / DPDP Rule 6 log-keeping | Forever (should be ≥1 yr, then purge) | Admin |
| 22 | Session replay, clicks, scroll, device data | Microsoft Clarity (`nfcwebsiteecom-/src/app/layout.tsx:110-113`) | UX analytics | **Consent required** (ePrivacy 5(3), DPDP s.6) | Clarity default (vendor-side) | Microsoft (international transfer) |
| 23 | **Third-party store's customer export** (names, addresses, phones, emails, payment refs, marketing flags) | `nfcwebsiteecom-/orders_export_1.csv`, `transactions_export_1.csv` in git | Apparently import seeding (`scripts/seed-orders-shopify-csv.ts`) | **None for git storage** | Permanent in git history | Anyone with repo access / clones |
| 24 | Payment data | Razorpay hosted checkout (landing, ecommerce); app opens hosted URL | Payment | Contract | Gateway-side; only order/payment IDs stored locally | Razorpay (PCI DSS) |

---

## 3. Gap table

Severity: **Critical** = active incident or blocks launch / store approval. **High** = clear statutory gap with
user-facing exposure. **Medium** = required before scale or before EU/Gulf targeting. **Low** = hygiene.

| ID | Sev | Regulation / provision | Gap | Evidence | Fix | Owner |
|---|---|---|---|---|---|---|
| G-01 | **Critical** | DPDP s.8(5) (reasonable security safeguards), s.8(6) + Rule 7 (breach intimation); SPDI Rule 8; GDPR Art. 5(1)(f), 32–34; CERT-In Directions 2022 (6-hr reporting of certain incidents) | Real third-party customer PII (≈400 people) committed to a GitHub repo, including payment references and marketing-consent flags | `/home/user/nfcwebsiteecom-/orders_export_1.csv`, `/home/user/nfcwebsiteecom-/transactions_export_1.csv`, consumer `/home/user/nfcwebsiteecom-/scripts/seed-orders-shopify-csv.ts` | Treat as incident now: (1) confirm repo visibility and audit GitHub access, clones, forks and Actions logs; (2) remove files and purge history (`git filter-repo --path ... --invert-paths`, force-push, ask GitHub Support to purge cached views and PR refs, invalidate forks); (3) rotate any credentials ever committed alongside them; (4) notify the data's owner (the other store, which is the controller); counsel decides on Board/CERT-In and data-principal notification; (5) add `*.csv`, `*export*`, `db-output.json` to `.gitignore` plus a pre-commit secret/PII scanner (gitleaks/trufflehog with custom regex) | Creatyvot leadership + eng lead + counsel |
| G-02 | **Critical** | SPDI Rule 4 (privacy policy on website, in force now); DPDP s.5 + Rule 3 (itemised notice); GDPR Art. 13; UAE PDPL Art. 13; Qatar PDPPL Art. 6; CCPA §1798.100/130; Apple 5.1.1(i); Play User Data policy | No Bizzvot privacy policy or terms anywhere. Ecommerce policy is another brand's. App legal links depend on a non-existent `/app/config` | `/home/user/cogcard/app` (no privacy route); `/home/user/nfc-landing-page/app` (no privacy/terms route); `/home/user/nfcwebsiteecom-/src/app/privacy-policy/page.tsx` (other brand, other contact email); `/home/user/Bizzvot-apps-/lib/core/config/app_config.dart:66-70`, `docs/API_GAP_REGISTER.md` CFG-1 | Publish one Bizzvot Privacy Policy, Terms, Cookie Notice, Refund/Shipping policy and an Analytics disclosure on a stable URL (e.g. `bizzvot.com/legal/*`); link them from web footer, registration, checkout, public card footer, review and exchange forms; implement `GET /app/config` (CFG-1) **and** hard-code fallback URLs in the app so links never resolve to null | Product + counsel; backend (CFG-1); mobile |
| G-03 | **Critical** | Apple App Store Guideline 5.1.1(v); Google Play account-deletion policy (in-app + **web** URL); DPDP s.12(3), s.8(7); GDPR Art. 17 | No account deletion backend: no `DELETE /auth/account`, no org/individual delete, no super-admin delete. App UI calls a missing endpoint | `/home/user/Bizzvot-apps-/lib/features/account/data/account_repository.dart:13-25`; cogcard DELETE routes limited to cards/staff/domains/plans; `/home/user/cogcard/lib/cardDelete.ts` | Implement ACC-1: re-auth, cancel subscriptions, revoke tokens, cascade-delete org → staff users → cards (reuse `deleteCardAndRelated`) → reviews/views/clicks → notifications → **media objects** → domains; keep invoices/GST records under legal-obligation retention (CGST s.36: about 6 years from the annual-return due date of the relevant year; counsel to confirm), pseudonymised. Add a web deletion-request page for Play. Individual role needs the same path | Backend + mobile |
| G-04 | **High** | DPDP s.6(1), 6(10) (burden of proof of consent), Rule 3; GDPR Art. 7(1) | Consent and notice acknowledgement not recorded. App checkbox is client-only; web registration has no checkbox | `/home/user/Bizzvot-apps-/lib/features/auth/presentation/register_screen.dart:40,200-205,252`; `/home/user/cogcard/app/api/v1/auth/register/route.ts:13-21`; `/home/user/cogcard/app/page.tsx:103` | Add `consents: [{type:'terms'|'privacy', version, acceptedAt, ip/ua(optional), channel}]` on `User`; reject registration without it; add the checkbox to web; re-prompt on material policy-version change | Backend + web + mobile |
| G-05 | **High** | PRODUCT_PLAN §8.4/§16; DPDP s.8(5); GDPR Art. 5(1)(c), 25, 32 | Public reviews endpoint returns `reviewerEmail` | `/home/user/cogcard/app/api/v1/public/card/[slug]/reviews/route.ts:22-31` (`.select("-ipAddress -ipHash")` only); `/home/user/cogcard/lib/api.ts:108-113` | Build an explicit public review DTO (name, rating, comment, createdAt, reply.text/repliedAt). Also strip `reviewerEmail` from the POST response. Add a regression test | Backend |
| G-06 | **High** | GDPR Art. 9 (health = special category); SPDI Rule 3 (physical/physiological/medical info = SPDI) and Rule 5(1) (written consent); DPDP s.4–6 purpose limitation and data minimisation; Qatar PDPPL Art. 16 (personal data of special nature) | Blood group and parents' names are collected in the app with no purpose statement, consent or lawful basis. The backend silently discards them, so users believe they are saved | `/home/user/Bizzvot-apps-/lib/shared/models/card.dart:94-384`; `/home/user/Bizzvot-apps-/lib/features/cards/presentation/card_editor_screen.dart:113-118,623,761-774`; `/home/user/cogcard/lib/models/Card.ts` (no fields); `/home/user/cogcard/lib/validation/card.ts` (strips unknown keys) | Product decision first. Either **remove** these fields (recommended unless the ID-card print product truly needs them), or store them in a separate `CardPrivateDetails` collection, encrypted at field level, never in public DTO or vCard, readable only by owner + subject, with explicit per-field consent from the *staff member* (not the owner), a stated purpose ("printed on your ID card / emergency use"), and deletion when the card is deleted | Product + counsel; backend; mobile |
| G-07 | **High** | ePrivacy Dir. Art. 5(3) / UK PECR reg. 6; GDPR Art. 6, 7, 44–46; DPDP s.5–6 | Microsoft Clarity session replay loaded on all pages, checkout included, with no consent banner or disclosure | `/home/user/nfcwebsiteecom-/src/app/layout.tsx:110-113` | Gate Clarity behind a consent banner (reject as easy as accept); enable Clarity masking of all inputs; exclude checkout/account pages; disclose Microsoft as sub-processor; or remove | Web (ecommerce) |
| G-08 | **High** | DPDP s.8(7) (erase when purpose served), Rule 8; GDPR Art. 5(1)(e) | No retention policy or TTL for Review, LinkClick, Notification (exchange leads), landing abandoned/failed orders, ActivityLog, JobApplication; legacy plaintext review/view IPs never purged | `/home/user/cogcard/lib/models/LinkClick.ts`, `Review.ts:30-33`, `Notification.ts`; `/home/user/nfc-landing-page/lib/db.ts:143-168`; `/home/user/nfcwebsiteecom-/src/models/ActivityLog.ts`, `JobApplication.ts` | Write a retention schedule (§5.6). Add TTLs: LinkClick 180 d; exchange notifications 12–24 mo; failed/abandoned checkouts 30–90 d then delete PII; ActivityLog 1 yr min / 2 yr max; job applications 6–12 mo after closing. One-off migration: `$unset ipAddress` on Review and CardView | Backend + ops |
| G-09 | **High** | DPDP s.11 (access), s.12 (correction/erasure), s.13 (grievance), Rule 14 (publish means; respond ≤90 days); GDPR Art. 15, 16, 17, 20; UAE PDPL Art. 13–17; CCPA right to know/delete | No DSAR mechanism: no export, no visitor/reviewer erasure path, exchange leads stuck in free-text notifications | cogcard API inventory (no export routes); `/home/user/cogcard/app/api/v1/public/card/[slug]/exchange/route.ts:32-40` | Add `GET /auth/account/export` (JSON of user, org, cards, staff list, reviews received, notifications). Add an admin tool to find and erase a reviewer or lead by email. Store exchange leads in a structured `Lead` collection. Publish a privacy request form/email with an SLA | Backend + support |
| G-10 | **High** | DPDP s.8(10), s.10(2)(c) only if SDF; s.13 + Rule 9 (publish DPO/contact who answers questions); SPDI Rule 5(9) (Grievance Officer name + contact, resolve in 1 month); Consumer Protection (E-Commerce) Rules 2020 r.4(4)–(5) (grievance officer, 48-hr ack, 1-month resolution) | No grievance officer or privacy contact published on any property | All four repos (no occurrence) | Appoint a Grievance Officer (name, designation, email, address in India). Publish in the policy, site footer, app Legal screen and checkout | Leadership |
| G-11 | **High** | DPDP s.8(2) (processor only under valid contract), s.8(1) (fiduciary remains responsible); GDPR Art. 28 | Org owners are fiduciaries for staff and visitor data, with Bizzvot as processor, but no DPA/terms define this. No staff-facing notice when an owner creates a staff login and publishes their phone/email | `/home/user/cogcard/app/api/v1/organization/staff/route.ts:60-66`; `/home/user/cogcard/lib/publicCard.ts:26-29` (phone/email always public, no display toggle) | Business Terms with a Data Processing Addendum (instructions, confidentiality, sub-processors, breach notice ≤24–48 h to owner, deletion on termination, assistance with requests). Show a first-login notice to staff explaining what is public. Add display toggles for phone and email | Counsel + product + backend |
| G-12 | **High** | DPDP s.8(6), Rule 7 (intimate Board and affected principals without delay; detailed report within 72 h); CERT-In 6-hr; GDPR Art. 33 (72 h), 34; UAE PDPL Art. 9; Qatar PDPPL Art. 14 | No breach-response runbook, no incident log, no contact tree | No artefact in any repo (`/home/user/Bizzvot-apps-/lib/app/bootstrap.dart:12` references a missing `docs/SECURITY.md`) | Write an incident-response plan (detection → triage → containment → legal assessment → notifications → post-mortem). Keep a breach register. Exercise it on G-01 | Eng lead + counsel |
| G-13 | **Medium** | DPDP s.5–6 notice at collection; GDPR Art. 13, 21 | Public card review and "exchange contact" forms have no notice that data goes to the card owner, how long it is kept, or that a 1-year dedupe cookie is set | `/home/user/cogcard/components/public-card/parts/ReviewSection.tsx`, `/home/user/cogcard/components/public-card/parts/ActionButtons.tsx`; cookie `/home/user/cogcard/lib/middleware/ipHash.ts:4` | Add a short notice under each form ("Your name and comment will be public; your email is shared only with <owner>. Privacy policy"). Make email truly optional. Disclose the cookie | Web |
| G-14 | **Medium** | GDPR Recital 26 / Art. 4(5) (pseudonymised = still personal data); DPDP s.8(5) | IP hash uses a server-wide static salt with a known-weak default fallback; IPv4 hashes can be brute-forced; full UA + referrer are stored per view; "unique visitors" derived from ipHash | `/home/user/cogcard/lib/middleware/ipHash.ts:158-169`; `/home/user/cogcard/lib/models/CardView.ts:6-21`; `/home/user/cogcard/app/api/v1/public/card/[slug]/route.ts:27-32` | Fail startup in production without a strong `IP_HASH_SALT`. Rotate the salt daily for analytics, keeping a separate stable salt only for review dedupe. Truncate UA to browser/OS family and referrer to origin. Describe it in the analytics disclosure | Backend |
| G-15 | **Medium** | DPDP s.8(7); GDPR Art. 17 | Uploaded media (photos/logos/PDFs) never deleted on card/staff/account delete or replace; local-disk uploads are publicly served | `/home/user/cogcard/lib/media/storage.ts` (no delete function); `/home/user/cogcard/lib/cardDelete.ts` | Track media ownership (`Media{key,userId,cardId}`). Delete objects on card delete and replace. Run an orphan sweeper | Backend |
| G-16 | **Medium** | GDPR Art. 28(2),(4), 30; DPDP s.8(2); UAE PDPL Art. 22–23; Qatar PDPPL Art. 15 (cross-border) | No sub-processor list or DPAs; international transfers (S3 region, Microsoft Clarity, SMTP/Gmail, Firebase, Razorpay, Delhivery, Creatyvot WhatsApp API → Meta) undocumented | `.env.example` files; `/home/user/nfc-landing-page/lib/whatsapp.ts:8-35`; `/home/user/nfcwebsiteecom-/package.json` (firebase, googleapis, aws-sdk, razorpay) | Maintain a sub-processor register (§4.3). Sign DPAs (AWS/R2, Microsoft, Google, Razorpay, Delhivery, email provider, Meta WhatsApp). Use SCCs/UK IDTA for EU/UK data. Keep primary data in India (ap-south-1) where feasible | Ops + counsel |
| G-17 | **Medium** | GDPR Art. 35 (DPIA), Art. 22 (automated decisions); DPDP s.10 (only if notified SDF) | No DPIA for visitor analytics, session replay, health-type staff data, or the job-application "match %/strengths/weaknesses" analysis (scoring is currently disabled in code, but the schema and UI remain) | `/home/user/nfcwebsiteecom-/src/models/JobApplication.ts`, `/home/user/nfcwebsiteecom-/src/pages/api/jobs/apply.ts:112-113` | Lightweight DPIA/LIA per processing activity. If CV scoring is re-enabled, add human review, a notice and an objection right | Product + counsel |
| G-18 | **Medium** | DPDP s.8(5); GDPR Art. 32 | Firestore rules allow world `get,list` on `orders` and `job_applications` (latent if the Firebase project is live) | `/home/user/nfcwebsiteecom-/firestore.rules:76-81,123-131` | Deny-all unless used. If used, owner-only reads. Confirm no Firebase project has these rules deployed | Web (ecommerce) |
| G-19 | **Medium** | DPDP s.9 + Rule 10 (verifiable parental consent; no tracking/behavioural monitoring/targeted ads to children); GDPR Art. 8; Apple 1.3/5.1.4 | No age gate or children's-data policy. Staff ID Cards could be ordered by schools for under-18s (students/interns) | Registration routes; product catalogue | State in Terms that accounts and staff are 18+. If schools are a target, design parental consent and disable analytics on minors' cards | Product + counsel |
| G-20 | **Medium** | DPDP s.6(4) withdrawal; GDPR Art. 21(2) marketing objection; TRAI TCCCPR 2018 (commercial WhatsApp/SMS) | WhatsApp order notifications via Creatyvot API with no opt-in record; ecommerce marketing flags exist but landing has none | `/home/user/nfc-landing-page/lib/whatsapp.ts`, `/home/user/nfc-landing-page/lib/notify-order.ts` | Transactional-only by default. Separate opt-in checkbox for marketing; store consent | Landing |
| G-21 | **Medium** | Apple privacy manifest requirement (since 1 May 2024); App Store Connect privacy labels; Play Data safety | No `PrivacyInfo.xcprivacy` in `ios/Runner`; labels/data-safety not yet prepared | `/home/user/Bizzvot-apps-/ios/Runner/` (only `Info.plist`) | Add a privacy manifest declaring required-reason APIs (file timestamp, UserDefaults, disk space, as used by Flutter plugins) and `NSPrivacyTracking=false`. File labels per §5 | Mobile |
| G-22 | **Medium** | DPDP s.8(7); GDPR Art. 17 | App leaves saved delivery addresses in Keychain/Keystore after logout and account deletion (iOS Keychain survives uninstall) | `/home/user/Bizzvot-apps-/lib/features/cart_checkout/data/address_store.dart`; `/home/user/Bizzvot-apps-/lib/core/auth/session_controller.dart:95-99` | Clear the address store (per user key) on account deletion. Offer "clear saved addresses" on logout. Consider a server-side address book with deletion | Mobile |
| G-23 | **Low** | GDPR Art. 5(1)(c); SPDI Rule 8 | Dev email fallback writes reset links and recipients to console and `.data/emails/outbox.log` (disabled in production — good) | `/home/user/cogcard/lib/email/sendEmail.ts:93-115` | Keep it; make sure staging uses SMTP, not console | Backend |
| G-24 | **Low** | GDPR Art. 25 | Web dashboard stores `role` and `userName` in `localStorage` | `/home/user/cogcard/components/DashboardShell.tsx:136-138`, `/home/user/cogcard/app/page.tsx:46-47` | Low risk. Clear on logout; avoid the name | Web |
| G-25 | **Low** | DPDP s.8(3) (accuracy) | Super-admin lists show all user emails and phones with no access logging | `/home/user/cogcard/app/api/v1/admin/individuals/route.ts:10-15` | Audit-log super-admin reads of PII. Restrict production DB access; enforce MFA for admins | Backend + ops |
| G-26 | **Info** | CCPA/CPRA §1798.140(d) thresholds | CCPA likely **not applicable** (under $25M revenue, under 100k CA consumers, no data selling) | — | Revisit if US revenue grows. The Clarity/ads "sharing" definition would trigger opt-out duties if applicable | Counsel |
| G-27 | **Info** | DPDP s.10 | Significant Data Fiduciary status unlikely (volume/sensitivity) unless notified by government | — | Monitor notifications | Counsel |

**Positive controls observed:** salted IP hashing and no new plaintext IP writes (`lib/models/Review.ts`,
`CardView.ts`); `CardView` 180-day TTL; reset-token TTL; staff hard-delete cascade; public card DTO built by
construction (`lib/publicCard.ts`); bot filtering on views; Redis rate-limit TTLs. In the app: tokens and addresses
in secure storage, `allowBackup=false`, `usesCleartextTraffic=false`, debug-only log interceptor with bodies and
headers off, crash handler logging only error types, public review model without email/IP, and an in-app deletion
UI with re-auth.

---

## 4. Roles, sub-processors and jurisdiction notes

### 4.1 Controller / processor map (DPDP: Data Fiduciary / Data Processor)

| Data | Bizzvot (Creatyvot) role | Counter-party role |
|---|---|---|
| Account-holder data (owners, individuals), billing, GST, orders | **Fiduciary / controller** | — |
| Staff data, card content of staff, visitor analytics and reviews on an org's cards, exchange leads | **Processor** for the org owner (also controller for platform security/abuse uses) | Org owner = **fiduciary / controller** |
| Individual's own card and its visitor analytics | Controller (platform) + processor (on behalf of the individual's business use) | Individual |
| Platform-wide aggregate analytics, fraud/dedupe | Controller | — |
| Third-party store export in G-01 | Creatyvot appears to be that store's **processor/agency** | The other store = controller, which must be informed |

### 4.2 Jurisdictional applicability (to confirm)

- **India DPDP Act 2023 + Rules 2025.** Applies (Indian entity, Indian principals). Our understanding is that the
  Rules were notified in Nov 2025 with staged commencement: Board provisions immediately, consent-manager provisions
  about 12 months later, and most fiduciary obligations (notice, security, breach, retention, rights, children)
  about 18 months later, i.e. around **May 2027**. **Until then the IT Act s.43A + SPDI Rules 2011 apply now**:
  privacy policy, written consent for SPDI such as health data, grievance officer.
- **Consumer Protection (E-Commerce) Rules 2020.** Apply to the landing/ecommerce stores: grievance officer,
  seller details, return/refund policy.
- **UAE PDPL / Qatar PDPPL.** Apply when processing data of residents and targeting those markets. They require
  notice, consent or another basis, data-subject rights, breach notification, and controls on cross-border
  transfer. Qatar treats health and children's data as "special nature". Note: the UAE PDPL executive regulations
  status should be checked by counsel. DIFC/ADGM free-zone customers have their own regimes.
- **GDPR / UK GDPR.** Apply only if Bizzvot offers services to people in the EU/UK (Art. 3(2)) or monitors them.
  Clarity on a site that ships internationally, or EU-facing marketing, would trigger it. If triggered, appoint an
  Art. 27 representative.
- **CCPA/CPRA.** Likely not applicable now (G-26).

### 4.3 Sub-processor register (draft, from code)

| Vendor | Used by | Data | Transfer note |
|---|---|---|---|
| MongoDB host (Atlas/self-hosted) | cogcard, ecommerce | All | Confirm region |
| S3-compatible storage (AWS S3 / R2 etc.) | cogcard media, ecommerce | Photos, logos, PDFs | Confirm region; public-read objects |
| Redis provider | cogcard | Rate-limit keys (raw IPs, short TTL), host cache | Confirm region |
| SMTP / Gmail API (Google) | cogcard, landing, ecommerce | Email address, reset links, order emails | US transfer (Google) |
| Razorpay | landing, ecommerce, app (hosted checkout) | Name, phone, email, payment | India; PCI DSS |
| Stripe / PayPal / Square (configured options) | ecommerce template | Payment | Remove if unused |
| Delhivery | landing, ecommerce | Name, phone, shipping address | India |
| Creatyvot WhatsApp API → Meta WhatsApp | landing | Phone, order details | Intra-group + Meta (US/EU) |
| Microsoft Clarity | ecommerce | Session replay, device data | US; consent required |
| Firebase (Google) | ecommerce template | Possibly orders/job applications | Confirm whether used at all |
| Apple / Google (stores) | app | Store-level analytics | Standard |
| NFC card print vendor (if external) | fulfilment | Name, photo, designation, (blood group?) | Needs DPA |

---

## 5. Drafts

### 5.1 Privacy policy contents checklist (Bizzvot, one policy for app + web + store)

- [ ] Identity of the fiduciary/controller: Creatyvot (legal name, CIN/registered address in Kerala), brand Bizzvot; scope (app, `bizzvot.*` sites, public cards, NFC store).
- [ ] **Grievance Officer / privacy contact**: name, designation, email, postal address, response timelines (SPDI: 1 month; DPDP Rule 14: within 90 days; E-Commerce Rules: acknowledge in 48 h, resolve in 1 month).
- [ ] Itemised categories of personal data **per audience**: account holders, staff (data supplied by employer), card visitors, reviewers, exchange-contact senders, shoppers (address, GSTIN), job applicants.
- [ ] Specific purpose for each category (DPDP Rule 3 requires an itemised description, with goods/services enabled by each).
- [ ] Lawful basis / consent vs legitimate use; for GDPR users, Art. 6 basis per purpose and legitimate-interest summaries.
- [ ] What is **public by design**: card fields, reviewer name, rating, comment, business replies; vCard downloads.
- [ ] Analytics disclosure: card views and link taps, salted IP hashing, UA/referrer, 180-day retention, aggregate-only reporting to owners, no sale, no cross-site tracking.
- [ ] Cookies and similar technologies: session cookies, `cogcard_rid` dedupe cookie (1 yr), any analytics (Clarity) **only with consent**; how to withdraw.
- [ ] Sensitive data: whether blood group or parents' names are collected, why, explicit consent, who sees them.
- [ ] Roles: Bizzvot as processor for organisations; organisations responsible for informing their staff; link to the DPA.
- [ ] Recipients and sub-processors (list or link to a live list); no sale of data.
- [ ] International transfers and safeguards (SCCs/IDTA where relevant); storage location.
- [ ] Retention schedule summary (§5.6).
- [ ] Rights: access, correction, completion, update, erasure, nomination (DPDP s.14), grievance redress, withdrawal of consent (as easy as giving it), portability and objection (GDPR), UAE/Qatar rights; how to exercise (in-app delete, export, email/form); identity verification.
- [ ] Right to complain to the Data Protection Board of India (and EU/UK supervisory authority where applicable).
- [ ] Consent Manager: note that principals may use a registered Consent Manager once operational (DPDP s.6(7)–(9)).
- [ ] Children: service not for under-18s; parental-consent process if ever offered.
- [ ] Security measures (high level) and breach notification commitment.
- [ ] Marketing communications and WhatsApp: opt-in/opt-out.
- [ ] Payment: card data processed by Razorpay; Bizzvot does not store card numbers.
- [ ] Account deletion: in-app path + web URL; what is deleted vs retained (invoices) and for how long.
- [ ] Changes to the policy, version and effective date; notice of material changes.
- [ ] Languages: English plus (recommended) Malayalam/Hindi. DPDP s.5(3) lets principals request English or any Eighth Schedule language.

### 5.2 Apple App Store privacy nutrition label (draft)

"Tracking": **No** (no third-party ad/analytics SDKs; confirm before each release that none are added, e.g. crash
reporters). All items below are **Linked to the user**, **Not used for tracking**.

| Apple data type | Collected? | Purposes |
|---|---|---|
| Contact Info → Name | Yes (owner, staff, card subjects, shipping) | App Functionality |
| Contact Info → Email Address | Yes | App Functionality (account, support) |
| Contact Info → Phone Number | Yes | App Functionality |
| Contact Info → Physical Address | Yes (card address, shipping) | App Functionality |
| Contact Info → Other User Contact Info | Yes (WhatsApp, social/website links) | App Functionality |
| Health & Fitness → Health | **Yes only if blood group is kept and sent to server** (G-06). Otherwise remove the field and answer No | App Functionality |
| Financial Info → Other Financial Info | Yes (GSTIN, invoices). Payment info: **No** (Razorpay hosted page; confirm checkout opens in browser/SFSafariVC with no card entry in-app) | App Functionality |
| User Content → Photos or Videos | Yes (profile, cover, logo; YouTube links) | App Functionality |
| User Content → Customer Support | Yes if support emails/tickets are routed through the app | App Functionality |
| User Content → Other User Content | Yes (bio, review replies, PDFs) | App Functionality |
| Identifiers → User ID | Yes (account ID) | App Functionality |
| Identifiers → Device ID | No | — |
| Purchases → Purchase History | Yes (orders, subscriptions) | App Functionality |
| Usage Data → Product Interaction | Yes, when the in-app public card screen sends `track-click` (linked to card, not the viewer's identity → may answer **Not linked**) | Analytics (provided to card owner) |
| Diagnostics → Crash Data | No today. **Yes** once crash reporting is added (bootstrap TODO) | App Functionality |
| Location, Contacts (address book), Browsing/Search History, Sensitive Info, Other Data | No (parents' names: declare under "Other Data Types" if kept) | — |

Also: `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` strings exist. Add `PrivacyInfo.xcprivacy`
(G-21). Privacy Policy URL is mandatory in App Store Connect (G-02).

### 5.3 Google Play Data safety form (draft)

- **Does your app collect or share any required user data types?** Yes.
- **Is all user data encrypted in transit?** Yes (TLS only; `usesCleartextTraffic=false`).
- **Do you provide a way for users to request that their data be deleted?** Yes, in-app (owner) plus a **web
  deletion URL** (must exist, G-03). Staff are directed to their organisation and support email.
- **Data shared with third parties:** No, under Play's definition. Transfers to service providers (Razorpay,
  Delhivery, hosting, email) count as processing on our behalf. Note that card content is **public by user choice**;
  Play treats user-initiated public sharing as not "sharing".

| Play category → type | Collected | Shared | Optional? | Purposes |
|---|---|---|---|---|
| Personal info → Name | Yes | No | Required | App functionality, Account management |
| Personal info → Email address | Yes | No | Required | App functionality, Account management, Developer communications |
| Personal info → Phone number | Yes | No | Optional (card) / required (shipping) | App functionality |
| Personal info → Address | Yes | No | Optional (card) / required (shipping) | App functionality |
| Personal info → User IDs | Yes | No | Required | Account management |
| Personal info → Other info | Yes if parents' names are kept; GSTIN | No | Optional | App functionality |
| Health and fitness → Health info | Only if blood group is kept (G-06) | No | Optional | App functionality |
| Financial info → Purchase history | Yes | No | Required for orders | App functionality |
| Financial info → Payment info | No (hosted Razorpay) | — | — | — |
| Photos and videos → Photos | Yes | No | Optional | App functionality |
| Files and docs | Yes (PDF uploads) | No | Optional | App functionality |
| App activity → App interactions | Yes (public-card link taps sent to server) | No | Required (automatic) | Analytics |
| App info and performance → Crash logs / Diagnostics | No today; Yes once crash reporting ships | No | — | App functionality, Analytics |
| Location, Contacts, Messages, Audio, Calendar, Web browsing, Device IDs | No | — | — | — |

Data is **processed ephemerally**: No (stored server-side).

### 5.4 Staff notice (template text for owners to show staff)

> "<Org> uses Bizzvot to create your digital business card and staff login. The card shows your name, photo,
> designation and the contact details your organisation enters, and it is publicly viewable by anyone with the
> link, QR or NFC tap. Visitors' views and taps are counted for <Org>. <Org> decides what is shown and can remove
> your account. Contact <Org> or privacy@bizzvot… for access or correction."

### 5.5 Consent record schema (proposed, cogcard `User`)

`consents: [{ kind: 'terms'|'privacy'|'marketing'|'whatsapp'|'private_details', version: string, granted: bool,
at: Date, channel: 'app'|'web'|'checkout', withdrawnAt?: Date }]`

### 5.6 Proposed retention schedule (counsel to confirm)

| Record | Retention |
|---|---|
| Active account data | Life of account |
| Deleted account | Purge within 30 days (backups roll off ≤ 35 days), except invoices |
| Invoices / GST / payment records | Per CGST Act s.36 (about 6 years from annual-return due date; counsel to confirm) |
| CardView | 180 days (existing) |
| LinkClick | 180 days |
| Reviews | Life of card; erase on request; reviewer email deleted after 12 months |
| Exchange leads | 24 months or on request |
| Failed/abandoned checkouts | 90 days, then delete PII |
| Security/processing logs | ≥ 1 year (DPDP Rules log-retention), ≤ 2 years |
| Job applications | 12 months after role closed, unless consent to keep |
| Rate-limit keys | ≤ 30 min (existing) |

---

## 6. Prioritised remediation

**P0 — this week (incident and launch blockers)**
1. **G-01**: contain and assess the committed customer export. Purge history, audit access, inform the other
   store's owner, get a counsel decision on notifications, add a PII/secret pre-commit scanner across all 4 repos.
2. **G-05**: remove `reviewerEmail` from public review responses (a one-line projection plus a test).
3. **G-07**: remove or consent-gate Microsoft Clarity on the ecommerce site.
4. **G-02 / G-10**: appoint a Grievance Officer. Publish a Bizzvot Privacy Policy, Terms, Refund/Shipping and
   Analytics disclosure. Link them from web, landing checkout, public cards and the app (hard-coded fallback URLs).
   Replace the other brand's policy in the ecommerce repo, or do not deploy that repo as Bizzvot.

**P1 — before app-store submission / public launch (2–4 weeks)**

5. **G-03**: implement `DELETE /auth/account` with full cascade including media, plus a web deletion-request page,
   for both owners and individuals.
6. **G-04**: server-side consent records; terms checkbox on web registration.
7. **G-06**: product decision on blood group and parents' names. Remove them, or build an encrypted, consented,
   access-controlled store. Stop the "appears saved" behaviour either way.
8. **G-11 / G-13**: Business Terms + DPA for organisations; staff first-login notice; notices on the review and
   exchange forms; phone/email display toggles.
9. **G-21 / §5.2–5.3**: privacy manifest, App Store labels, Play Data safety.
10. **G-12**: incident-response runbook and breach register.

**P2 — within 1–2 quarters (before DPDP substantive commencement, ~May 2027, and before Gulf/EU marketing)**

11. **G-08 / G-15 / G-22**: retention TTLs, legacy-IP `$unset` migration, media deletion, clearing on-device
    addresses.
12. **G-09**: data export endpoint, admin DSAR tooling, structured `Lead` collection.
13. **G-14**: production salt enforcement, salt rotation, UA/referrer minimisation.
14. **G-16 / G-17**: sub-processor register, DPAs/SCCs, DPIAs (analytics, sensitive staff data, recruitment).
15. **G-18 / G-19 / G-20**: lock down Firestore rules, age policy, WhatsApp/marketing opt-in records.
16. **G-23–G-25**: hygiene (admin read audit, MFA, localStorage).

**Owner legend:** Backend = cogcard team; Web = cogcard web / landing / ecommerce front-ends; Mobile = Flutter
team; Counsel = external Indian privacy counsel (plus UAE/Qatar/EU local counsel if those markets are targeted);
Leadership = Creatyvot directors.
