# 06 — Public web card, NFC/QR links, landing & SEO

Audit agent 06 of 10 · read-only · 2026-10-11

Canonical host (per lead): the live portal is **https://www.bizzvot.com/**. It's the Coglink app (`/home/user/cogcard`) deployed with `NEXT_PUBLIC_APP_URL`/`NEXT_PUBLIC_ROOT_DOMAIN` set to it. Apex `bizzvot.com` is also claimed by the app links. The sandbox blocks that host, so every finding here comes from reading the code; nothing was probed live.

Repos audited:
- Coglink public web + API: `/home/user/cogcard` (Next.js 15 App Router, MongoDB). Single commit `78cc311`.
- Marketing landing: `/home/user/nfc-landing-page`
- Ecommerce storefront: `/home/user/nfcwebsiteecom-`
- Flutter app (deep-link side): `/home/user/Bizzvot-apps-`
- Spec: `docs/PRODUCT_PLAN.md` §7, §8, §16, §20

---

## 1. Summary

The public card web works for a basic demo: three templates, vCard, approved-only reviews, IP-hash dedup and rate limits. It is not ready to back physical NFC products sold under the Bizzvot brand. The main gaps:

1. **No stable redirect layer for NFC chips and QR codes.** QR codes encode `NEXT_PUBLIC_APP_URL/card/{slug}` directly (`app/api/v1/cards/[id]/qrcode/route.ts`). Slugs can be changed with no slug history or 301 (`lib/cardSlug.ts`). Google Review cards sold on the landing page get the raw Google link written to the chip, yet the FAQ promises "contact support to update the destination". Once a tag is written, nobody can re-point it, so a bad link means reprinting the product.
2. **The Google Review flow doesn't exist on the backend.** There is no `review_card` template (the enum is `minimal|corporate|modern_dark`), no `googleReviewUrl`/`placeId` field, and no review-page route. The Flutter app already models all three.
3. **Public eligibility only checks `card.status === "active"`.** Organization or individual `status: suspended` and `planExpiry` are ignored on every public route (card, reviews, review POST, vCard, exchange, resolve-host). Suspending an org does not take its cards offline.
4. **Reviewer email leaks.** `GET /public/card/:slug/reviews` strips only `ipAddress`/`ipHash`, so `reviewerEmail` is returned publicly. This breaks spec §8.4, §16 and §20.
5. **The public page renders only in the browser.** There is no SSR, no `generateMetadata` and no OG tags. Every shared link previews as "Coglink — Digital Card Platform". Missing cards return HTTP 200 instead of 404. A tap goes through about four sequential round-trips before any content shows, which is the slowest possible NFC path.
6. **Deep links can't verify.** No repo serves `/.well-known/apple-app-site-association` or `/.well-known/assetlinks.json`, so Coglink at www.bizzvot.com returns 404 for both. The iOS app has no `Runner.entitlements`. The Android filter now lists `www.bizzvot.com` and `bizzvot.com`, but both still need assetlinks served with HTTP 200 and no redirect.
7. **www vs apex isn't canonicalised (F26).** With `NEXT_PUBLIC_ROOT_DOMAIN=www.bizzvot.com`, the apex `bizzvot.com` is *not* a primary host in `getAppHosts`/`isPrimaryAppHost`. Any account on a custom-domain plan can register `bizzvot.com` as its "custom domain". If the apex reaches the app, the self-answering HTTP verification (F08) passes and the platform's own homepage gets rewritten to the attacker's card. Platform subdomains also become `{label}.www.bizzvot.com`.
8. **Custom-domain and host handling has two security issues.** (a) Middleware builds its internal fetch origin from the request `Host` header and sends `MIDDLEWARE_INTERNAL_SECRET` with it. That is server-side request forgery (SSRF) plus secret exfiltration whenever the proxy forwards arbitrary hosts. (b) HTTP-file domain verification is answered by the platform itself, so any hostname already pointing at the platform can be claimed by anyone (dangling-CNAME takeover).
9. **No public directory exists.** There is no endpoint, page, org slug, `directoryVisibility` or card `visibility`.
10. **Brand is fragmented.** The web card platform is "Coglink", the landing page is "creatyvot", and the "ecommerce storefront" is actually *Enkilum Ente Krishna*, a devotional-goods store with no NFC products. Only the mobile app says "Bizzvot". The landing page sells 2 of the 4 products, has no privacy/terms/refund pages, and hard-codes a 4.9★/86 `AggregateRating` in JSON-LD.
11. **Review abuse controls are brittle in both directions.** The "one review per IP per card, forever" rule blocks the second real customer on shop Wi-Fi or mobile carrier-grade NAT (CGNAT). That is the exact Review Stand scenario. Meanwhile there's no CAPTCHA, honeypot or content filter against IP-rotating spam, and non-moderated plans auto-approve.

---

## 2. Findings

Severity: **C** critical · **H** high · **M** medium · **L** low. Owner: **BE** = Coglink backend/web, **APP** = Flutter, **LP** = landing page, **SF** = storefront, **OPS** = DevOps/DNS/stores, **PO** = product owner.

| # | Sev | Area | Gap | Fix | Owner | Files |
|---|---|---|---|---|---|---|
| F01 | **C** | NFC/QR | No redirect/indirection layer. QR encodes `/card/{slug}`. Slug can change via `applyCardSlug` with no history, so printed QR codes and chips break (404) after a rename. Landing Google Review cards are programmed with the raw Google link, so "update later" (FAQ f4) is impossible without physically rewriting the chip. No `nfcTags` model, no `/t/:id`, no claim/assign flow, although the app supports "assign later" (`LinePersonalization.assignLater`). | Build `/t/{tagId}` resolver + `nfcTags` collection + owner re-point API (see §3). Add `cardSlugHistory` with 301 from old slugs. QR = `/t/{tagId}` for physical products, `/card/{slug}` only for ad-hoc digital shares. | BE, PO | `cogcard/app/api/v1/cards/[id]/qrcode/route.ts`, `cogcard/lib/cardSlug.ts`, `nfc-landing-page/data/products.ts` (faqs f4), `Bizzvot-apps-/lib/features/catalog/domain/physical_models.dart` |
| F02 | **H** | Google Review | Backend has no `review_card` template, `googleReviewUrl`, `placeId`, or `/card/{slug}/review` page. The app reads `googleReviewUrl`/`googleReviewLink` and shows a "Review on Google" button, but those fields can never come back from the API. | Add `theme.templateId: "review_card"`, `googleReviewUrl` (https, validated to `search.google.com/local/writereview`, `g.page/r/*/review`, `maps.app.goo.gl`), optional `placeId`; include in public DTO; SSR review page. Show the Google button to **every** visitor, never gated on rating (Google prohibits review gating). | BE, PO | `cogcard/lib/models/Card.ts` (theme enum), `cogcard/lib/publicCard.ts`, `Bizzvot-apps-/lib/features/public_card/presentation/public_card_screen.dart:142` |
| F03 | **H** | Eligibility | Public card checks only `Card.findOne({slug, status:"active"})`. Org/individual `status` and `planExpiry` are never checked on any public route. Admin org suspension (`admin/organizations/[id]/status`) suspends users/staff but leaves cards live. No `visibility`/publication field. | Add one shared `loadPublicCard(slug)` that joins the owner: owner `status==="active"`, plan active or trial (`planExpiry > now` or trial flag), card active, publication allows. Use it in card, reviews, review POST, vCard, track-click and resolve-host. Return one generic 404 for every "not eligible" case (no existence oracle). | BE | `cogcard/app/api/v1/public/card/[slug]/route.ts`, `.../reviews/route.ts`, `.../review/route.ts`, `cogcard/app/api/v1/cards/[id]/vcard/route.ts`, `cogcard/app/api/v1/public/resolve-host/route.ts`, `cogcard/lib/domains.ts` (`resolveCardSlugForHost`) |
| F04 | **H** | Privacy | `reviewerEmail` is returned by `GET /public/card/:slug/reviews`: `.select("-ipAddress -ipHash")`, and `sanitizeReview` deletes only IP fields. `cardId`/`updatedAt` also leak. | Explicit public review DTO allow-list: `{_id, reviewerName, rating, comment, reply:{text, repliedAt}, createdAt}`. Make `reviewerEmail` `select:false` in schema. Add a test asserting the email is absent. | BE | `cogcard/lib/api.ts:108`, `cogcard/app/api/v1/public/card/[slug]/reviews/route.ts`, `cogcard/lib/models/Review.ts` |
| F05 | **H** | SEO/perf | `app/card/[slug]/page.tsx` renders a `"use client"` shell that fetches `/api/v1/public/card/:slug` after hydration. Consequences: no per-card `<title>`/OG/Twitter/canonical, so WhatsApp/LinkedIn previews show the global "Coglink — Digital Card Platform". Missing cards get HTTP 200 (soft 404). Tap-to-render = HTML, then JS bundle, then API (which **awaits** a `CardView.create` DB write), then render, then a second fetch for reviews. | Server component: fetch the card in the page, `generateMetadata` (title = name · designation · company, OG image = photo/cover, `og:url` canonical on primary host), `notFound()` → 404, embed first page of reviews, defer the view write (`after()` / queue). Add `revalidate`/tag cache invalidated on card edit. Target LCP < 1.5 s on 4G. | BE | `cogcard/app/card/[slug]/page.tsx`, `cogcard/components/public-card/PublicCardShell.tsx`, `cogcard/app/layout.tsx` |
| F06 | **H** | Deep links | No `apple-app-site-association` or `assetlinks.json` in any web repo (cogcard has no `public/`; no `.well-known` route except `coglink-verification.txt`), so www.bizzvot.com returns 404 for both. iOS has no `Runner.entitlements` and no `CODE_SIGN_ENTITLEMENTS`, so Associated Domains are missing. Android `autoVerify` (now `www.bizzvot.com` + `bizzvot.com`) will fail. On Android ≤ 11, one unverified host fails the whole filter. No staging host in the filter. Brand strings: grep finds no `bizzvot` in cogcard, landing or storefront code; the domain exists only as deployment env. | See §4 checklist. Serve both files from Coglink on **both** www and apex with HTTP 200 and no redirect. Add iOS entitlements for both hosts. | OPS, BE, APP | `Bizzvot-apps-/android/app/src/main/AndroidManifest.xml:33-39`, `Bizzvot-apps-/ios/Runner/Info.plist`, `Bizzvot-apps-/ios/Runner.xcodeproj/project.pbxproj`, `cogcard/next.config.ts` |
| F07 | **H** | Host header | `middleware.ts` `resolveHostSlug` and `isSessionCurrent` call `new URL(path, req.nextUrl.origin)`, an origin derived from the incoming `Host`, and attach `x-cogcard-internal-secret`. With a catch-all nginx/PM2 setup, `curl -H 'Host: attacker.tld' https://bizzvot.com/x` makes the server fetch `http://attacker.tld/api/v1/public/resolve-host` **carrying the internal secret**, and the attacker's JSON chooses the rewrite slug. Random Hosts also create a DB lookup + internal fetch each (memo of only 500 entries): an amplification/DoS path. | Use a fixed `INTERNAL_API_ORIGIN` (e.g. `http://127.0.0.1:$PORT`) for middleware fetches. Never derive it from the request. Validate Host against `{app hosts} ∪ active Domain` before any work. Configure the proxy to reject unknown hosts (default server → 421/444) except those provisioned for custom domains. Rotate the secret after the fix. *(Exploitability depends on proxy; verify in staging.)* | BE, OPS | `cogcard/middleware.ts:83-103,141-165`, `cogcard/lib/middleware-internal.ts` |
| F08 | **H** | Custom domains | HTTP verification is self-answering. `checkHttpVerification` GETs `http://{host}/.well-known/coglink-verification.txt`. If the host already CNAMEs to the platform, middleware passes that path and `public/domain-verification` serves **the claimant's own pending token** for that Host. So any hostname still pointing at the platform can be claimed and verified by any paying account: a customer who removed their domain but left DNS, or a wildcard. That's a subdomain takeover, and a phishing card would then be served on a trusted brand domain. | For `type:"custom"` accept **TXT only** (`_coglink.{host}` → token). HTTP proves routing, not ownership. Re-verify active domains periodically (e.g. daily TXT check; deactivate on failure). Bind TLS issuance (on-demand certs) to verified domains only. | BE | `cogcard/lib/domains.ts` (`checkHttpVerification`, `verifyDomainRecord`), `cogcard/app/api/v1/public/domain-verification/route.ts`, `cogcard/middleware.ts:192` |
| F09 | **M** | Custom host scope | On a custom host, every non-`/` path passes through (`NextResponse.next()`). `acme.com/card/<any tenant>` renders other tenants' cards under Acme's domain, and dashboards/login also render on customer domains. Reserved subdomains are only `www/app/api/admin`. | On custom hosts allow only `/`, `/card/{boundSlug}`, `/card/{boundSlug}/review`, `/.well-known/*`, `/_next/*`, assets and `/api/v1/public/*` for the bound card; otherwise 404. Expand the reserved list: `login, auth, account, support, help, mail, smtp, shop, store, pay, billing, status, staging, dev, cdn, static, t, go, directory, bizzvot, coglink, creatyvot, secure, verify`. | BE | `cogcard/middleware.ts:186-207`, `cogcard/lib/domains.ts:64-78` |
| F10 | **M** | Directory | No `GET /public/organizations/:slug/directory`, no `/directory/[orgSlug]` page. `Organization` has no `slug` and no `directoryVisibility`; `Card` has no `visibility`. The app routes `/directory/:orgSlug` (deep-linked in the Android manifest) to an endpoint that 404s. | Add `Organization.slug` (unique), `directoryVisibility`, `Card.visibility` (`inherit/public/private`) per §7. Build a server-filtered directory DTO `{org:{name,logo,slug}, items:[{slug,title,designation,photo}]}` with pagination; SSR page; precedence "org private wins" encoded in one function plus tests (§20). | BE, PO | `cogcard/lib/models/Organization.ts`, `cogcard/lib/models/Card.ts`, `Bizzvot-apps-/lib/core/api/endpoints.dart:64` |
| F11 | **M** | Analytics | `track-click` contract mismatch: the app posts `{slug,type,target}`, the server's `trackClickSchema` requires `{cardId,linkType,linkUrl}`, so every app-originated click is a 400. The server doesn't check that the card is active; an invalid ObjectId gives a 500 (CastError). The web `trackClick` uses plain `fetch` (no `keepalive`/`sendBeacon`), so clicks on `tel:`/`wa.me`/external links are often dropped. `linkType` is free text. | Accept `{slug \| cardId, type ∈ enum[call,whatsapp,email,website,map,social,custom,vcard,google_review,share], target?}`. Validate the ObjectId (400). Use `navigator.sendBeacon`. Respond 202. Record `source` (nfc/qr/link) from `/t/` redirects. | BE, APP | `cogcard/app/api/v1/public/track-click/route.ts`, `cogcard/lib/validation/card.ts:108`, `cogcard/components/public-card/types.ts:44`, `Bizzvot-apps-/lib/features/public_card/data/public_card_repository.dart:85` |
| F12 | **M** | Exchange | Spec §2.2/§14 says `POST /public/card/:slug/exchange` is retired → **410**. The backend still returns 201 and the web UI still shows "Exchange Contact", which collects visitor name/email/phone/message into owner notifications with no privacy notice. | Return `410 {success:false,error:"Feature retired"}`; remove the button from `ActionButtons.tsx`; purge existing `exchange_contact` notifications per retention policy. | BE | `cogcard/app/api/v1/public/card/[slug]/exchange/route.ts`, `cogcard/components/public-card/parts/ActionButtons.tsx:48,120` |
| F13 | **M** | Review abuse | (a) Dedup = unique `{cardId, ipHash}` **forever**, so the 2nd real customer on the same shop Wi-Fi/CGNAT (the Review Stand use case) gets 409. (b) No CAPTCHA, honeypot, min-time or URL/profanity filter; IP rotation bypasses everything; plans without moderation auto-approve, so spam is public instantly. (c) Reviews accepted even when `displayOptions.showReviews=false` and for suspended owners (F03). (d) If `TRUST_PROXY`/hops are misconfigured, all visitors share one `unresolved` bucket of 2 reviews/min **platform-wide**. (e) `REVIEW_COOLDOWN_DAYS` env is documented but unused. (f) Rate limit runs before card lookup but the per-card limit is absent. | Dedup on `{cardId, deviceCookie}` + soft IP window (e.g. ≤3 reviews per IP per card per 24 h) rather than a permanent IP uniqueness index. Add Cloudflare Turnstile/hCaptcha (invisible; enforced after the 1st review per IP/day or when score is low), a honeypot field, min submit time 3 s, max 2 URLs (else force `pending`). Reject when `showReviews=false`. Per-card cap (e.g. 30/h, then auto-`pending`). Start-up health check that fails when in production with hops=0 behind an LB. Keep 409/429 semantics for the app. | BE, OPS | `cogcard/app/api/v1/public/card/[slug]/review/route.ts`, `cogcard/lib/models/Review.ts:47`, `cogcard/lib/middleware/ipHash.ts`, `cogcard/project-docs/DEPLOY.md` |
| F14 | **M** | SEO/privacy | No `robots.txt`, no `sitemap.xml`, no `X-Robots-Tag`/`<meta robots>` anywhere in cogcard. So no sitemap leakage today, but also no way to keep staff/private/directory-hidden cards out of search. `/api/v1/public/card/*` JSON is crawlable. Slugs come from names (`max-mcgonagall`), so "hidden" cards are guessable. | `app/robots.ts`: disallow `/api/`, dashboards. Card page: `robots: {index:false}` unless card `visibility` resolves public **and** owner opts into search; always `noindex` on custom-host duplicates (canonical → primary). Sitemap (if any) built only from the server-filtered public directory query. Add an `X-Robots-Tag: noindex` header on `/api/v1/public/*`. Random suffix for private-card slugs; `/t/{tagId}` is unguessable by design. | BE, PO | `cogcard/app/` (add `robots.ts`, `sitemap.ts`), `cogcard/app/card/[slug]/page.tsx` |
| F15 | **M** | Brand | Four names in play. Web cards: "Coglink" (`app/layout.tsx` metadata, `coglink-verify-*` tokens, `_coglink.` TXT host, `.well-known/coglink-verification.txt`, DNS notes "served by Coglink", seed `@coglink.local`). Landing: "creatyvot" (title, OG siteName, JSON-LD brand, "Powered by creatyvot.com" printed on the product). Storefront: "Enkilum Ente Krishna" devotional store (malas/lockets; no NFC products). App: "Bizzvot". No web property mentions Bizzvot. | Make a brand decision (PO). Then: env-driven `BRAND_NAME`/`BRAND_URL` in cogcard for all visitor- and customer-facing strings (metadata, DNS instructions, footer "Made with Bizzvot", emails). Keep `COGCARD_*` env/cookie names internal. Rebrand landing to Bizzvot (or state "Bizzvot by Creatyvot"). Treat `nfcwebsiteecom-` as unrelated: it should not back Bizzvot commerce or legal links. | PO, BE, LP | `cogcard/app/layout.tsx`, `cogcard/lib/domains.ts:57,140-170`, `nfc-landing-page/app/layout.tsx`, `nfc-landing-page/app/product/[slug]/page.tsx:62`, `nfcwebsiteecom-/src/app/privacy-policy/page.tsx` |
| F16 | **M** | Landing catalogue | One product (`nfc-smart-card` "Google Review NFC Card"): Card ₹350 (strike ₹499) + "With Stand" ₹499 package. **Missing: Staff ID Card ₹350, Business Digital + Physical NFC Card ₹999.** `/` redirects to that one product. No App Store/Play CTAs, no "create your digital card" path into the app/Coglink. | Product pages for all 4 SKUs with exact spec prices. Make Review Stand a separate product (not just a package of the card, so pricing reads ₹499 clearly). Home page with 4 product tiles + "Get the Bizzvot app" badges (URLs from `/app/config.store`). Per-product personalisation fields matching the app's `PersonalizationSpec`. | LP, PO | `nfc-landing-page/data/products.ts`, `nfc-landing-page/app/page.tsx` |
| F17 | **M** | Legal/compliance | No privacy policy, terms, refund/cancellation, shipping or contact pages on the landing page (Razorpay KYC and both app stores require them). The only privacy policy found belongs to Enkilum. `/app/config` doesn't exist on the backend, and the app has **no default** `privacyPolicyUrl`/`termsUrl`, so the register screen's links open nothing. | Publish `bizzvot.com/privacy`, `/terms`, `/refund-policy`, `/shipping-policy`, `/contact` (+ `/delete-account` for Play data-deletion form). Implement `GET /app/config` returning these. Ship compile-time fallbacks in `Env`. | LP, BE, APP | `nfc-landing-page/app/`, `Bizzvot-apps-/lib/core/config/app_config.dart:66`, `Bizzvot-apps-/docs/API_GAP_REGISTER.md` (CFG-1) |
| F18 | **M** | Landing trust | JSON-LD `AggregateRating` 4.9/86 and three testimonials are hard-coded constants (`data/products.ts`). That breaks Google's structured-data review policy (self-serving/unverifiable) and the India CCPA 2022 fake-review guidelines / IS 19000:2022. | Remove `aggregateRating` until backed by real order-linked reviews; label testimonials as such or source from real reviews. | LP | `nfc-landing-page/app/product/[slug]/page.tsx:64`, `nfc-landing-page/data/products.ts` (rating, reviewCount, reviews) |
| F19 | **M** | Google link capture | Landing checkout validates `mapsUrl` as a Google **Maps** link only and rejects the official write-review links (`search.google.com/local/writereview?placeid=…`, `g.page/r/…/review`). A Maps link opens the listing, not the review composer, so conversion is lower. | Accept and prefer write-review URLs. Offer a "find my business" helper (Places API → `placeId`). Store `placeId` and build `https://search.google.com/local/writereview?placeid={id}`. | LP, BE | `nfc-landing-page/lib/validation.ts:72-109` |
| F20 | **M** | QR endpoint | `qrcode` is **POST** (spec §8.5 says GET). It stores a base64 PNG data-URL on the card document (bloats every `Card.findOne`). 512 px PNG only (poor for print); no SVG; encodes the slug URL. | `GET /cards/:id/qrcode?format=svg\|png&size=` generated on the fly (cacheable), not persisted; encodes `/t/{tagId}` when the card has a tag, else the card URL. | BE | `cogcard/app/api/v1/cards/[id]/qrcode/route.ts` |
| F21 | L | App ↔ web | With the app installed, `/card/*` and `/directory/*` open in-app. The app's directory depends on F10, so installed users get an error where web would work. Neither `/t/*` nor `/review` is decided. | Exclude `/t/*` from app links (resolve on web, then the 302 to `/card/*` may open the app). Add "Open in browser" fallback in `PublicCardScreen` on 404/5xx. Hold `/directory/*` out of AASA/intent filter until F10 ships. | APP | `Bizzvot-apps-/lib/app/router.dart:138-141`, `AndroidManifest.xml:38` |
| F22 | L | Accessibility | Low-contrast greys (`#999` on `#fff` ≈ 2.8:1, 8 occurrences in public-card) for section labels and empty states. Star ratings rendered as `"★".repeat(n)` with no accessible label. Loading/error/success messages not in `aria-live`/`role="alert"`. No `<main>` landmark. Template `lang` fixed `en`. | Contrast ≥ 4.5:1 (`#6b6b6b`), `aria-label="4 out of 5 stars"`, live regions, `<main>`, tap targets ≥ 44 px. Run axe in CI. | BE | `cogcard/components/public-card/parts/ReviewSection.tsx`, `.../PublicCardShell.tsx` |
| F23 | L | vCard | `escapeV` doesn't escape `;` or `\r` (field injection by card owner), no 75-octet line folding, no `URL` back to the card, no `PHOTO`. Invalid id → 500. Phone/email have no display toggle (intentional per comment, but confirm with PO). | vCard 3.0/4.0 escaping per RFC 6350, fold lines, add card URL + `X-SOCIALPROFILE`, ObjectId guard → 404. | BE | `cogcard/lib/vcard.ts`, `cogcard/app/api/v1/cards/[id]/vcard/route.ts` |
| F24 | L | Headers | CSP `img-src … http:` allows mixed content; `script-src 'unsafe-eval'` in production. | Drop `http:` in prod; remove `unsafe-eval` in prod builds. | BE | `cogcard/next.config.ts` |
| F26 | **H** | www vs apex | Live config sets `NEXT_PUBLIC_ROOT_DOMAIN`/`APP_URL` to `www.bizzvot.com`. So `getAppHosts()` / `isPrimaryAppHost()` = {`www.bizzvot.com`, `www.www.bizzvot.com`, localhost}, and **apex `bizzvot.com` is not primary**. Consequences: (a) `assertValidCustomHostname("bizzvot.com")` passes, so any plan with `customDomain` can register the apex. If the apex is served by the app rather than 308-redirected at the edge, the HTTP verification is answered by the platform itself (F08), the domain goes `active`, and `bizzvot.com/` rewrites to the attacker's card. That's a platform-brand takeover. Same for other `*.bizzvot.com` hosts that point at the app (`api.`, `shop.`, …), since they fall outside the "root" and are treated as "custom". (b) Platform subdomains are built as `{label}.www.bizzvot.com`. (c) Every apex request costs a middleware `resolve-host` internal fetch. (d) Without an edge redirect, apex and www serve duplicate content with no canonical tag. (e) A blanket apex→www redirect (typical Vercel/nginx setup) would also redirect `/.well-known/*`, which breaks apex universal links (Apple doesn't follow AASA redirects) and Android verification for the apex host. | Set `NEXT_PUBLIC_ROOT_DOMAIN=bizzvot.com` and `NEXT_PUBLIC_APP_HOST=www.bizzvot.com`, `NEXT_PUBLIC_APP_URL=https://www.bizzvot.com`, so both apex and www are primary. Add a hard deny-list in `assertValidCustomHostname` for `bizzvot.com` and `*.bizzvot.com` (plus legacy coglink/creatyvot domains). Audit the existing `Domain` collection for any such hostname now. Edge: `bizzvot.com/*` → **308** → `https://www.bizzvot.com/*`, **except** `/.well-known/apple-app-site-association` and `/.well-known/assetlinks.json` (serve 200 on apex). Emit `<link rel="canonical" href="https://www.bizzvot.com/card/{slug}">`. NFC/QR encode `www.` directly (no redirect hop on tap). Subdomains become `{label}.bizzvot.com`; reserve `www, api, staging, app, admin, shop, store, t, go, …` (F09). | BE, OPS | `cogcard/middleware.ts:24-40`, `cogcard/lib/domains.ts:12-91`, deployment env / proxy config |
| F25 | L | Spec gap | Spec has no section on NFC tags, tag lifecycle, chip locking, or the review-stand flow (no mention of `nfc`, `tag`, `/t/` in `PRODUCT_PLAN.md` or `API_GAP_REGISTER.md`). | Add §8.6 "Physical NFC/QR links" using §3 below; add API gap rows NFC-1…NFC-5. | PO | `Bizzvot-apps-/docs/PRODUCT_PLAN.md`, `docs/API_GAP_REGISTER.md` |

### What is already correct
- Public card DTO is an allow-list (`lib/publicCard.ts`). No `ownerId`, staff IDs, QR blob or tokens. Honours `displayOptions` for bio/whatsapp/address/socials/custom links.
- Public review list filters `status: "approved"`. Pending/hidden reviews are excluded and IPs are stripped (email is not; see F04).
- Duplicate review → 409 (including the E11000 race). Rate limit → 429. Rating validated 1–5 (zod). Plan-based moderation → `pending`.
- Client IP resolution indexes `X-Forwarded-For` from the right with a hop count (no blind `XFF[0]`). Raw IP is not stored on new reviews.
- `resolve-host` hides `cardId` from public callers and is rate-limited. Domain verify pins DNS to a public IP (rebinding-safe) and doesn't follow redirects. Dev-verify is hard-disabled in production. CNAME-only verification is limited to platform subdomains.
- vCard honours `vcardEnabled` and card status.

---

## 3. Recommended NFC / QR URL and redirect design

### 3.1 URL scheme encoded on chips and QR codes

```
NFC NDEF URI record :  https://www.bizzvot.com/t/{tagId}      (URI prefix 0x02 "https://www.")
QR code (same tag)  :  https://www.bizzvot.com/t/{tagId}?s=q
Digital-only share  :  https://www.bizzvot.com/card/{slug}     (app share sheet, not printed)
```

- `tagId`: 10 chars of Crockford base32 from a CSPRNG (about 50 bits), **not** sequential and not derived from the order ID, e.g. `7KQ2M9XA4F`. Print it as the serial on the back of the product.
- Encode the canonical **www** host so a tap never costs an apex→www redirect hop. The apex `bizzvot.com/t/*` must still work via 308 to www, for hand-typed links.
- Payload after the `0x02` prefix: `bizzvot.com/t/7KQ2M9XA4F` is 24 bytes, which fits an NTAG213 (144 B) with room to spare. Use NTAG213/215.
- One brand domain for everything (`www.bizzvot.com`, served by Coglink), so it shows in the iOS NFC banner and the QR preview.
- **Chip hygiene at fulfilment:** write the record, then set the NTAG write-protection password or permanent lock bits. With a redirect layer, locking costs nothing and stops anyone rewriting a counter stand to a phishing URL.

### 3.2 Data model (`nfcTags`)

```jsonc
{
  "_id": ObjectId,
  "tagId": "7KQ2M9XA4F",              // unique index
  "claimCodeHash": "sha256(...)",     // 8-char code inside packaging; required to claim
  "product": "review_stand | review_card | staff_id | business_card",
  "orderId": ObjectId, "orderLineId": "…", "unitIndex": 0,
  "ownerType": "organization | individual | null",
  "ownerId": ObjectId | null,
  "status": "unassigned | active | disabled | lost",
  "target": {
    "type": "card | google_review | review_page | url",
    "cardId": ObjectId,               // card / review_page: resolve slug at tap time
    "googleReviewUrl": "https://search.google.com/local/writereview?placeid=…",
    "placeId": "ChIJ…",
    "url": "https://…"                // admin-only, allow-listed hosts
  },
  "chipUid": "04A2…", "lockedAt": Date,
  "tapCount": 0, "lastTapAt": Date,
  "createdAt": Date, "updatedAt": Date
}
```
Plus `tagEvents` (time-series: `tagId, at, source: nfc|qr, uaFamily, country, ipHash`) and `cardSlugHistory` (`oldSlug → cardId`, unique).

### 3.3 Resolver behaviour — `GET /t/{tagId}`

1. Look up the tag (Redis cache 60 s, invalidated on re-point). Unknown tagId → branded 404.
2. Log the tap **asynchronously** (never block the redirect).
3. Respond **302** (never 301: browsers cache 301 forever and the tag could never be re-pointed) with `Cache-Control: no-store`:

| Tag state / target | Response |
|---|---|
| `unassigned` | 302 → `/activate/{tagId}`: "This Bizzvot tag isn't set up yet". Owner signs in (or opens the app) and enters the claim code. |
| `card` | 302 → `/card/{currentSlug}` (slug looked up from `cardId` at tap time, so renames never break tags) |
| `google_review` (**Google Review Stand / Card default**) | 302 → `googleReviewUrl` directly. Fastest path: one hop, no Bizzvot page render. |
| `review_page` (optional per tag) | 302 → `/card/{slug}/review`: SSR Bizzvot review page with business header, internal star review form, and a **"Review on Google" button always shown to everyone, at the top**. Showing it only after a high rating is review gating, which Google prohibits; it risks the customer's listing. |
| owner suspended / plan lapsed / card disabled | 200 branded "This card is currently unavailable" page (noindex). For `google_review` tags, decide (PO) whether lapsed billing still forwards to Google. Recommend **yes**, since the customer bought hardware and the link costs nothing. |
| `disabled` / `lost` | 410 branded page |

4. Old slugs: `/card/{oldSlug}` → 301 → `/card/{newSlug}`. A 301 is fine here because the content identity is stable.

### 3.4 Owner/API surface (to add to the gap register)

| ID | Endpoint | Notes |
|---|---|---|
| NFC-1 | `GET /nfc-tags` | Owner's tags with product, target, tap stats |
| NFC-2 | `POST /nfc-tags/claim {tagId, claimCode}` | Rate-limited (5/h per user); binds to owner; claim code single-use |
| NFC-3 | `PATCH /nfc-tags/:id {target}` | Re-point; validates card ownership and Google URL hosts; audit-logged |
| NFC-4 | `GET /nfc-tags/:id/analytics` | Taps by day, NFC vs QR |
| NFC-5 | Fulfilment: order line → generate tags, write chips, mark `lockedAt` | Uses the app's `UnitPersonalization` (`cardId`, `reviewUrl`, `useCardReviewPage`) to preset `target`; "assign later" → `unassigned` |

Per product:

| Product | Default target | Notes |
|---|---|---|
| Google Review Stand ₹499 | `google_review` | Option to switch to `review_page` |
| Google Review Card ₹350 | `google_review` | Same |
| Staff ID Card ₹350 | `card` (staff member's card) | Re-pointed when staff leaves; card deactivation → "unavailable" page |
| Business Digital + Physical NFC Card ₹999 | `card` | Includes the digital card subscription/seat (agent 04) |

---

## 4. Deep-link setup checklist

Placeholders: `<TEAM_ID>` (Apple Developer Team ID), `<PLAY_SIGNING_SHA256>` (Play Console → App integrity → App signing key certificate SHA-256), `<UPLOAD_SHA256>` (upload/debug key, optional). Bundle/package: `com.bizzvot.bizzvot` (from `project.pbxproj` / `build.gradle`).

### 4.1 Web (each host the app claims: `www.bizzvot.com` **and** apex `bizzvot.com`; staging separately)

Serve identical files on **both** hosts with HTTP 200. Don't let the apex→www redirect touch `/.well-known/*` (F26).

**`https://www.bizzvot.com/.well-known/apple-app-site-association`** (and the same at `https://bizzvot.com/...`) (no extension, `Content-Type: application/json`, HTTP 200, **no redirects**, < 128 KB):

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["<TEAM_ID>.com.bizzvot.bizzvot"],
        "components": [
          { "/": "/t/*",          "exclude": true, "comment": "NFC/QR redirects resolve on the web first" },
          { "/": "/activate/*",   "exclude": true, "comment": "Tag activation handled on web" },
          { "/": "/card/*/review","exclude": true, "comment": "Review page stays on web (optional)" },
          { "/": "/card/*",       "comment": "Public digital cards" },
          { "/": "/directory/*",  "comment": "Public organization directory (enable when F10 ships)" }
        ]
      }
    ]
  },
  "webcredentials": {
    "apps": ["<TEAM_ID>.com.bizzvot.bizzvot"]
  }
}
```
(Components are evaluated in order, so excludes come first.)

**`https://www.bizzvot.com/.well-known/assetlinks.json`** (and the same at `https://bizzvot.com/...`) (`Content-Type: application/json`, 200, no redirects):

```json
[
  {
    "relation": [
      "delegate_permission/common.handle_all_urls",
      "delegate_permission/common.get_login_creds"
    ],
    "target": {
      "namespace": "android_app",
      "package_name": "com.bizzvot.bizzvot",
      "sha256_cert_fingerprints": [
        "<PLAY_SIGNING_SHA256>",
        "<UPLOAD_SHA256>"
      ]
    }
  }
]
```

Implementation in Coglink: `app/.well-known/apple-app-site-association/route.ts` and `app/.well-known/assetlinks.json/route.ts` returning the JSON with values from env (`IOS_TEAM_ID`, `ANDROID_SHA256_FINGERPRINTS`), `Cache-Control: public, max-age=3600`. Confirm the middleware matcher doesn't rewrite them on primary hosts. Primary hosts aren't rewritten today, but make it explicit. Don't serve them on customer custom domains.

- [ ] Host topology (per lead): Coglink serves `www.bizzvot.com`. Fix env so apex is primary too (`ROOT_DOMAIN=bizzvot.com`, `APP_HOST=www.bizzvot.com`) (F26).
- [ ] Edge rule: `bizzvot.com/*` → 308 `https://www.bizzvot.com/*`, except the two `/.well-known` files (200 on apex).
- [ ] Staging: separate AASA/assetlinks on `staging.bizzvot.com` with staging bundle ID/fingerprint.
- [ ] Verify for **each** of `www.bizzvot.com` and `bizzvot.com`: `curl -sI https://<host>/.well-known/apple-app-site-association` (200, `application/json`, no `Location`); Apple CDN `https://app-site-association.cdn-apple.com/a/v1/<host>`; Google `https://digitalassetlinks.googleapis.com/v1/statements:list?source.web.site=https://<host>&relation=delegate_permission/common.handle_all_urls`.

### 4.2 iOS (Flutter `ios/Runner`)
- [ ] Create `ios/Runner/Runner.entitlements`:
  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0"><dict>
    <key>com.apple.developer.associated-domains</key>
    <array>
      <string>applinks:www.bizzvot.com</string>
      <string>applinks:bizzvot.com</string>
      <string>webcredentials:www.bizzvot.com</string>
    </array>
  </dict></plist>
  ```
- [ ] Set `CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements` for Debug, Release **and** Profile in `project.pbxproj`. Enable the Associated Domains capability on the App ID in the developer portal and regenerate profiles.
- [ ] Optional for staging builds: `applinks:staging.bizzvot.com?mode=developer`.
- [ ] `FlutterDeepLinkingEnabled` is already `true` (Info.plist). Keep go_router handling `/card/:slug`, `/directory/:orgSlug`.
- [ ] Test on a device: Notes app link long-press → "Open in Bizzvot"; NFC tag banner → app.

### 4.3 Android
- [x] Hosts `www.bizzvot.com` + `bizzvot.com` with `autoVerify` (already in the manifest per the lead's update). Target shape:
  ```xml
  <intent-filter android:autoVerify="true">
    <action android:name="android.intent.action.VIEW"/>
    <category android:name="android.intent.category.DEFAULT"/>
    <category android:name="android.intent.category.BROWSABLE"/>
    <data android:scheme="https"/>
    <data android:host="www.bizzvot.com"/>
    <data android:host="bizzvot.com"/>
    <data android:pathPrefix="/card/"/>
    <data android:pathPrefix="/directory/"/>
  </intent-filter>
  ```
  (Don't claim `/t/`.) Note: Android merges all `<data>` in one filter, so `/card/{slug}/review` is also claimed. Handle it in-app or move it to `/r/{slug}`.
- [ ] Staging flavor: manifest placeholder for host `staging.bizzvot.com`.
- [ ] Verify: `adb shell pm verify-app-links --re-verify com.bizzvot.bizzvot` then `adb shell pm get-app-links com.bizzvot.bizzvot` shows `verified`.

### 4.4 Behaviour matrix

| Visitor | Taps tag `/t/{id}` | Opens `/card/{slug}` link |
|---|---|---|
| No app (most NFC visitors) | Web resolver → 302 → Google or SSR card (must be fast: F05) | SSR web card |
| App installed (owner/staff) | Web resolver → 302 `/card/*` → OS hands off to app | App `PublicCardScreen`; needs "Open in browser" fallback (F21) |
| Google Review tag, app installed | Always Google (Google Maps app if installed) | n/a |

---

## 5. Prioritised fixes

**P0 — before selling any NFC product under Bizzvot**
1. F01/F25: `nfcTags` + `/t/{tagId}` 302 resolver + claim codes + slug history. Program and lock chips with `/t/` URLs only.
2. F02: `review_card` template, `googleReviewUrl`/`placeId`, review page with an ungated "Review on Google" button. F19: accept write-review URLs.
3. F04: remove `reviewerEmail` from public reviews (one-line DTO fix plus test).
4. F03: shared public eligibility check (owner status + plan/trial + card + publication) on all public routes.
5. F26: make apex `bizzvot.com` a primary host (`ROOT_DOMAIN=bizzvot.com`, `APP_HOST=www.bizzvot.com`); deny-list `bizzvot.com`/`*.bizzvot.com` as custom domains and audit existing `Domain` rows; apex→www 308 except `/.well-known`.
6. F07/F08: fixed internal origin for middleware fetches and rotate the secret; TXT-only verification for custom domains with periodic re-check.
7. F06: serve AASA + assetlinks on www and apex; add iOS entitlements.

**P1 — launch quality**
8. F05: SSR card page with `generateMetadata`/OG, real 404, embedded reviews, async view logging, caching.
9. F13: review dedup by device + windowed IP limit, invisible CAPTCHA, honeypot, per-card cap, reject when reviews hidden.
10. F12: exchange → 410, remove the UI.
11. F11: align the `track-click` contract with the app; `sendBeacon`; enum types.
12. F17: Bizzvot privacy/terms/refund/shipping/contact/delete-account pages + `GET /app/config` + app fallbacks.
13. F15/F16/F18: brand decision; landing pages for all 4 SKUs at spec prices; app-store CTAs; remove the fake `AggregateRating`.
14. F09: restrict custom-host paths; expand reserved subdomains.

**P2 — follow-ups**
15. F10: org slug + directory visibility + server-filtered directory endpoint/page (with §20 tests), then enable `/directory/*` app links.
16. F14: robots/noindex policy, random slugs for private cards, sitemap only from the public directory.
17. F20: GET QR (SVG/PNG, not persisted, encodes `/t/`).
18. F21–F24: app browser fallback, accessibility pass (contrast, live regions, star labels), vCard RFC escaping, CSP tightening.
