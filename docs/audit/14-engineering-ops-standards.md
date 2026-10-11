# 14: Engineering, architecture and operations standards gap analysis

Audit agent 14 · read-only · 2026-10-11

**Repos and commits**
- **be**: `/home/user/cogcard` (Coglink web portal + `/api/v1`). This is the live portal at **https://www.bizzvot.com**. Single commit `78cc311`.
- **ecom**: `/home/user/nfcwebsiteecom-`. Single commit `1ced7ed`.
- **land**: `/home/user/nfc-landing-page`. Single commit.
- **app**: `/home/user/Bizzvot-apps-` (Flutter). Commit `0d1b6f5`.

**Standards used**
- OWASP ASVS 4.0.3 L2, architecture chapters only (V1, V7, V14). The vulnerabilities themselves are in 07 and 10.
- ISO/IEC 27001:2022 Annex A operational controls.
- SOC 2 Common Criteria (CC6 to CC9).
- The Twelve-Factor App.
- OpenAPI 3.1, RFC 9457 (Problem Details), IETF RateLimit headers, the IETF Idempotency-Key draft.
- Google SRE and Core Web Vitals budgets.

**What this report does not repeat.** API contract details (01), auth flaws (02), data model and tenancy queries (03), commerce logic (04) and vulnerabilities (07, 10) are covered in those reports. Here they appear only at architecture or process level.

No secret values were read into this report. Where an env file or config held credentials, only variable names were inspected.

---

## 1. Summary

1. **Three separate commerce stacks exist. None of them is the one Bizzvot should run.**
   - **ecom** is a white-labelled store for another business: "Enkilum Entekrishna" / "PlyMart" devotional jewellery. Its package name is `nextn` and its README is a "Firebase Studio" starter. It contains **0** references to Bizzvot or NFC.
   - **land** is the actual NFC storefront (₹350 card, ₹499 stand). It uses Razorpay with a signed webhook, Delhivery and GST invoices, but it stores orders in a JSON file (`data/db.json`).
   - **be** (Coglink) has no commerce at all, but it is the only system the mobile app talks to.
   - **Recommendation:** rebuild commerce as a module inside Coglink `/api/v1`. Port the domain logic from **land**, not **ecom**. Retire both as order stores.
2. **Customer PII is committed to git in ecom.** `orders_export_1.csv` has 508 rows of names, emails, phones and billing/shipping addresses. `transactions_export_1.csv` has 448 rows. `db-output.json` and the `enkilum-entekrishna.*.json` exports are also tracked. This is the single most urgent operational finding (ISO A.5.34, A.8.12; India DPDP Act 2023).
3. **There is no CI/CD on any web repo.** be, ecom and land have no `.github/` folder, and each has a single squashed commit. That means no tests, lint, type-check, dependency scan, secret scan or SAST gate before code reaches www.bizzvot.com. The mobile repo does have CI, but it builds debug APKs only, and format drift is a warning rather than a failure.
4. **An OpenAPI spec exists, but it is not a contract.**
   - `be/project-docs/05-API/openapi.yaml` is OpenAPI **3.0.3**, not 3.1.
   - It is missing 6 of the 69 implemented routes.
   - It has no request or response component schemas and no error schema.
   - Its only server is `http://localhost:3000`.
   - It says register/login return tokens in the body, but `jsonOkWithAuth` deliberately strips them.
   - There is no versioning or deprecation policy.
5. **There are two error envelopes.**
   - be returns `{success:false, error:"<string>"}` with no machine code (`be/lib/api.ts:35`).
   - ecom has the better `{error:{message, code}, meta:{requestId}}` shape (`ecom/src/lib/api-response.ts`).
   - The mobile app already parses `error.code` (`app/lib/core/api/api_client.dart:183-188`), but it always gets `null` from be.
6. **Observability is close to zero.**
   - be logs with bare `console.error(err)` (`be/lib/api.ts:47`): no request ID, no structured logs, no metrics, no tracing.
   - There is no `/healthz` endpoint and no documented uptime or alerting.
   - The mobile app has an empty `lib/core/analytics/` and no crash reporting.
7. **There is no documented backup, restore, RPO/RTO, migration framework or staging environment.**
   - `docker-compose.yml` runs a standalone mongod, so transactions are not available. Commerce will need a replica set.
   - The app's staging host `staging.bizzvot.com` is "not confirmed" (`app/lib/app/env.dart`).
8. **The public card hurts NFC tap latency.**
   - `/card/[slug]` is a client component that fetches its own data after hydration: HTML, then JS, then API, then render (`be/components/public-card/PublicCardShell.tsx:1,16`).
   - The API does a synchronous `CardView.create` on the hot path, with no `Cache-Control` (`be/app/api/v1/public/card/[slug]/route.ts:16-33`).
9. **Branding is inconsistent across wire identifiers.**
   - Coglink, COGCard and Creatyvot appear in be (`cogcard_*` cookies, `x-cogcard-internal-secret`, `/.well-known/coglink-verification.txt`, default DB `cogcard`, package `coglink`).
   - Enkilum/PlyMart appear in ecom, Creatyvot in land, and Bizzvot in app (`com.bizzvot.bizzvot`, `x-bizzvot-*`).
10. **Dependency licences are compliant.**
    - Almost everything is MIT, Apache or ISC.
    - LGPL-3.0 libvips comes in through `sharp`'s dynamically loaded prebuilt binaries, which is acceptable with attribution.
    - MPL-2.0 is dev-only.
    - Housekeeping gaps: be's `package.json` says `"license": "ISC"` for a proprietary private app; there is no THIRD-PARTY-NOTICES file; ecom pins `next-auth: "latest"`; `png-js` has no declared licence.

**Strengths worth keeping**
- Config comes from env and secrets fail closed in production (`be/lib/jwt-secret.ts`, `be/lib/middleware-internal.ts`).
- Rate limiting is Redis-backed (`be/lib/api.ts:90`).
- Pagination is consistent (`be/lib/pagination.ts`).
- There is a `withApi` wrapper and Zod validation.
- Session revocation uses `tokenVersion`.
- The CardView TTL index is in place.
- Project documentation is thorough (PDD/PRD/SRS/architecture/DB/API/audits).
- The mobile layering conventions, idempotency keys, env flavours and CI are good.
- `showLicensePage` is wired in the app.

---

## 2. Standards gap table

Severity: **Critical** = fix before handling more customer data or money. **High** = before mobile GA. **Medium** = within the first quarter after GA. **Low** = hygiene.

Owners: **BE** = Coglink backend · **MOB** = Flutter · **OPS** = DevOps/platform · **PO** = founder/product owner · **SEC** = security lead.

### 2.1 Data protection, secrets, supplier and change management (ISO 27001 / SOC 2)

| # | Sev | Standard / control | Gap | Evidence | Fix | Owner |
|---|---|---|---|---|---|---|
| G1 | Critical | ISO A.5.34 privacy/PII; A.8.12 data-leakage prevention; SOC 2 CC6.1; DPDP Act 2023 | Real customer order and transaction exports (names, emails, phones, addresses, payment metadata) are tracked in git | `ecom/orders_export_1.csv` (508 rows), `ecom/transactions_export_1.csv` (448), `ecom/db-output.json`, `ecom/enkilum-entekrishna.*.json` | Remove the files. Purge history (`git filter-repo`) and force-push. Rotate anything the exports reveal. Check who cloned the repo. Add `*.csv`, `*export*` and `db-output.json` to `.gitignore`. Add a gitleaks/trufflehog pre-commit hook and CI step. Record the incident in an incident log (see G8). | SEC + PO |
| G2 | Critical | ISO A.5.19–5.22 supplier security; A.5.9 asset inventory | The ecom repo belongs to a different business. Its admin, customers and orders are not Bizzvot's, yet it is listed as Bizzvot's ecommerce. Ownership of data and code is unclear. | `ecom/package.json` name `nextn`; `ecom/ecosystem.config.js:4` `enkilum-entekrishna`; `ecom/firestore.rules:2` "PlyMart"; `ecom/README.md` "Firebase Studio" | PO decides: (a) archive ecom as out of scope for Bizzvot, or (b) fork only reusable libraries (Delhivery service, logger, `api-response.ts`) into Coglink under clear licence/ownership. Keep a written asset register: repos, domains, DBs, third-party accounts. | PO |
| G3 | High | ISO A.8.24 use of cryptography; A.5.17 authentication information | Payment-gateway secrets (Razorpay key secret and webhook secret, Stripe, PayPal client secret) are stored as plain Mongoose string fields in a settings collection | `ecom/src/models/PaymentGatewaySettings.ts:9-26,59-65` | Do not port this design. Keep gateway secrets in the platform secret manager/env only. If admin-editable secrets are ever needed, use envelope encryption with a KMS key (land already has `lib/settings-crypto.ts`). | BE |
| G4 | High | ISO A.8.32 change management; SOC 2 CC8.1 | Each web repo has a single squashed commit. There is no PR review trail, no branch protection, no release tags, no changelog. Changes reach production with no recorded approval. | `git log` = 1 commit in be/ecom/land | Turn on branch protection for `main`: PR required, 1 reviewer, status checks. Use conventional commits. Tag releases (`v1.x.y`) and use GitHub Releases as the change record. Write a deploy-approval rule for prod. | OPS |
| G5 | High | ISO A.8.25 secure development lifecycle; A.8.29 security testing; ASVS V1.1, V14.2 | No CI on be/ecom/land, so none of lint, `tsc --noEmit`, unit tests, build, `npm audit`, secret scan or SAST runs anywhere. Dependencies use caret ranges and `latest`. | No `.github/` in be/ecom/land; `ecom/package.json:67` `"next-auth": "latest"` | Add the GitHub Actions pipeline in §5 (lint, type-check, vitest, build, `npm audit --omit=dev --audit-level=high`, gitleaks, CodeQL or Semgrep). Add Dependabot for npm, pub and GitHub Actions. Pin `latest`. | OPS |
| G6 | High | ISO A.8.31 separation of dev/test/prod; 12-factor X (dev/prod parity) | No staging environment is documented for be. The app's staging host is unconfirmed. ecom has four conflicting deploy targets: PM2 on `:9255` while nginx proxies `:3005`, Firebase App Hosting `maxInstances:1`, Vercel, and Firestore rules. Local Mongo is standalone while production is presumably Atlas. | `app/lib/app/env.dart` ("Staging host is not confirmed"); `ecom/ecosystem.config.js:6` vs `ecom/nginx-config-updated.conf:5`; `ecom/apphosting.yaml`, `vercel.json` | Define three environments: `dev` (local compose, Mongo **replica set**), `staging.bizzvot.com` (separate Atlas project, Razorpay **test** keys, separate S3 bucket, Delhivery staging) and `www.bizzvot.com` (prod). Choose one hosting target and delete the other deploy configs. | OPS |
| G7 | High | ISO A.8.13 information backup; SOC 2 A1.2/A1.3 | No backup policy, no restore runbook, no RPO/RTO, no drills. Uploads default to local disk (`public/uploads`). | `be/project-docs/DEPLOY.md` (no backup section); no `mongodump` or backup scripts in any repo | Use Atlas continuous cloud backup with point-in-time restore. **Target RPO ≤ 15 min, RTO ≤ 4 h.** Take a weekly encrypted `mongodump` to a separate cloud account for supplier independence. Turn on S3 versioning, a 30-day lifecycle and cross-region replication for media and invoices. Run a quarterly restore drill into staging and record the timings. | OPS |
| G8 | High | ISO A.5.24–5.28 incident management; SOC 2 CC7.3–7.5 | No incident-response plan, severity scale, on-call, status page or breach-notification procedure. DPDP and CERT-In require incident reporting within 6 h. | none in any repo | Write `RUNBOOK.md` and `INCIDENT.md`: severity levels, contact tree, CERT-In 6-hour reporting, DPDP Board notice, customer comms template, post-mortem template. Add a status page (e.g. UptimeRobot or Better Stack). | PO + SEC |
| G9 | Medium | ISO A.5.15/5.18 access rights; A.8.2 privileged access; ASVS V1.4 | The super-admin is created from env seed credentials. There is no admin audit trail in be (no AuditLog model), so plan, suspend and limit changes leave no record. ecom has an `ActivityLog` model; be does not. | `be/project-docs/DEPLOY.md` (`SUPER_ADMIN_*` seed); `be/lib/models/` (no audit model) | Add an append-only `auditEvents` collection (actor, action, target, before/after hash, IP hash, requestId) that every `/admin/*` and owner write route records to. Require MFA for super-admin. Review admin accounts quarterly. | BE |
| G10 | Medium | ISO A.5.17 secret lifecycle; ASVS V1.6, V6.4 | No secret-rotation procedure. JWTs are signed with one symmetric key and no `kid`, so rotation logs out every user at once. | `be/lib/auth.ts:30-44` | Add `kid` and a key ring (current + previous), and rotate every 90 days. Write a rotation runbook for JWT, `IP_HASH_SALT` (note: rotating it breaks review dedupe), SMTP, S3, Razorpay and Delhivery. Store secrets in the host's secret manager. | BE + OPS |
| G11 | Medium | ISO A.5.23 cloud services; A.5.20 supplier agreements | No register of processors: Atlas, AWS S3, SMTP provider, Razorpay, Delhivery, the Creatyvot WhatsApp API (`land` `CREATYVOT_API_*`), hosting, and the future push/crash vendor. Without one there are no DPAs and no data-residency record. | env var names in `be/.env.example`, `land/.env.example` | Keep a supplier register (purpose, data shared, region, DPA link, owner, exit plan). Mirror it in the privacy policy. | PO |

### 2.2 API standards (OpenAPI, errors, pagination, idempotency, rate limiting, contract tests)

| # | Sev | Standard / control | Gap | Evidence | Fix | Owner |
|---|---|---|---|---|---|---|
| G12 | High | OpenAPI 3.1; ASVS V1.5/V13.1 | The spec is 3.0.3. It has no response or request component schemas, no error schema and only a localhost server. Six routes are missing: `/auth/change-password`, `/auth/refresh-and-return`, `/auth/session-status`, and `/{individual,organization,staff}/reviews/{id}/status`. Line 41 says register returns tokens, which is false. | `be/project-docs/05-API/openapi.yaml:1,8,41`; components at end of file contain only `bearerAuth`, `Id`, `Slug` | Upgrade to 3.1. Add `components.schemas` for every DTO (Card, PublicCard, Org, Staff, Review, Paged<T>, Problem). Add `cookieAuth` alongside `bearerAuth`. Set servers to prod `https://www.bizzvot.com/api/v1` and staging. Add the 6 missing routes plus every PROPOSED route from `app/docs/API_GAP_REGISTER.md`, marked `x-status: proposed`. Lint the spec in CI with Spectral/Redocly. Publish Redoc at `/api/docs` (staging only). | BE |
| G13 | High | API versioning and deprecation (RFC 8594 `Sunset`, RFC 9745 `Deprecation`) | There is a `/v1` prefix but no written policy. A mobile build stays in the field for 12 months or more. | none | Write `API_VERSIONING.md` with these rules. Additive changes only within v1. Breaking changes need `/v2` or a negotiated field. Deprecations send `Deprecation` and `Sunset` headers for at least 6 months. Use `GET /app/config` `version.min` to force upgrades. Send `x-bizzvot-app-version` in every app request and log it. | BE + MOB |
| G14 | High | Consistent error envelope (RFC 9457 semantics); ASVS V7.4 | be errors are free-text strings with no stable codes. The mobile app falls back to HTTP status. Zod errors return only the first issue. 429 responses have no `Retry-After`. | `be/lib/api.ts:35-55`; `app/lib/core/api/api_client.dart:183-188`; no `Retry-After` in be | Change to `{success:false, error:{code, message, details?, fields?}, meta:{requestId}}`. Add a code registry (`AUTH_INVALID_CREDENTIALS`, `ACCOUNT_IS_STAFF`, `PLAN_LIMIT_REACHED`, `RATE_LIMITED`, `VALIDATION_FAILED`, `NOT_FOUND`, `CONFLICT`, `IDEMPOTENCY_REPLAY`, …) published in the spec. Update `be/lib/client-api.ts` in the same PR. The app already accepts the object form. Return `Retry-After` and `RateLimit-*` headers with every 429. | BE |
| G15 | Medium | Pagination conventions | Offset pagination (`page`, `limit`, max 100, `{items,page,limit,total,totalPages,hasMore}`) is consistent, which is good. However, only 8 routes use `paginatedResult`, the shape is not in the spec, and offset paging with `countDocuments` degrades on large event collections. | `be/lib/pagination.ts`; 8 routes use `paginatedResult` | Document `Paged<T>` in the spec and audit every list route for it. For append-only feeds (notifications, views, clicks, orders) add cursor pagination (`?cursor=<opaque>&limit=`, returns `nextCursor`). | BE |
| G16 | High | Idempotency (IETF `Idempotency-Key` draft); SOC 2 PI1 | The app sends `Idempotency-Key` on order, payment and renew writes, but be has no idempotency store. land relies on Razorpay order IDs. ecom's "idempotency check" fails open (`checkout/actions.ts:857-858`). | `app/lib/features/catalog/domain/idempotency.dart:4`; no match for "idempot" in be | Add an `idempotencyKeys` collection with a unique index on {userId, key, route}, a request hash, a stored response, and a 24 h TTL. Replay the stored response for the same hash. Return `409 IDEMPOTENCY_KEY_REUSED` for a different hash. Required on every `POST /orders`, `/payments`, `/subscriptions/*/renew` and refund. Webhooks dedupe on the provider event ID (see §3.5). | BE |
| G17 | Medium | Rate limiting (ASVS V11.1.4; IETF RateLimit headers) | Redis-backed limits exist on 16 routes. If Redis is configured but unreachable, limits silently fall back to per-process memory, so each replica gets its own limit. There is no global or per-token limit on authenticated routes and no response headers. | `be/lib/api.ts:57-96`, `be/lib/redis.ts:73-82` | Make Redis required in production; fail closed on auth routes when it is down and alert. Add a default per-user limit in `withApi` (e.g. 120/min) and per-IP limits on `/public/*`. Emit `RateLimit-Limit/Remaining/Reset`. At the edge, add a WAF/bot rule for `/public/card/*/review`. | BE + OPS |
| G18 | High | Contract tests between app and API | No consumer-driven contract tests. Report 01 found shape mismatches that a contract test would catch: register without `role`, reset sending `password` instead of `newPassword`, and the role enum. | `be/tests/*` (7 unit files, 45 cases, no route tests); `app/test/helpers/fake_api.dart` hand-written fakes | (1) be: vitest route tests on `mongodb-memory-server` (replica-set mode) that validate every response against the OpenAPI schema with ajv. (2) app: JSON fixtures generated from spec `examples` and loaded by repository tests, so a spec change breaks the app's tests. (3) Optional: Pact. Both CIs fail on drift. | BE + MOB |
| G19 | Medium | 12-factor III/IV; ASVS V14.1 | `MONGODB_URI` silently defaults to `mongodb://127.0.0.1:27017/cogcard`, so a production deploy missing the var tries localhost instead of failing at boot. There is no env schema validation at startup. | `be/lib/db/connect.ts:3` | Add a Zod `env.ts` parsed at boot that fails fast in production for every required var in the DEPLOY.md table. | BE |

### 2.3 Observability and operations

| # | Sev | Standard / control | Gap | Evidence | Fix | Owner |
|---|---|---|---|---|---|---|
| G20 | High | ISO A.8.15 logging; A.8.16 monitoring; ASVS V7.1–7.3; SOC 2 CC7.2 | Unstructured `console.*`. No request or correlation ID. No security-event log (login failures, lockouts, token revocation, admin actions). The API has no metrics, tracing or alerting. | `be/lib/api.ts:47`; `be/lib/email/sendEmail.ts:87`; ecom has a structured logger (`ecom/src/lib/logger.ts`) but be does not | Use pino with JSON to stdout and redaction (tokens, password, email, phone, IP). Generate `x-request-id` in middleware, echo it in responses and the error envelope, and have the app log it with crashes. Name security events (`auth.login.failed`, `auth.lockout`, `session.revoked`, `admin.plan.changed`). Ship logs to a sink with 90-day retention. Add OpenTelemetry later. | BE + OPS |
| G21 | High | Uptime and alerting (SRE golden signals) | No `/api/health` (liveness) or `/api/ready` (Mongo, Redis, S3 reachable). No external uptime checks. The super-admin "Health" page shows moderation signals, not system health. | `be/app/(dashboard)/super-admin/health/page.tsx`; no health route | Add `GET /api/v1/health` (always 200, includes build SHA) and `/api/v1/ready`. Run external probes every 1 min on `/`, `/card/<canary>`, `/api/v1/health` and `/api/v1/app/config`. Alert on 5xx > 1 %, p95 > 800 ms, Razorpay webhook failures, and Delhivery sync backlog. | OPS |
| G22 | High | Mobile crash reporting (ISO A.8.16; Play/App Store vitals) | No crash or ANR reporting and no performance tracing. `lib/core/analytics/` is empty. | `app/lib/core/analytics/` (empty); `app/pubspec.yaml` | Add Sentry for Flutter (also usable on the Next.js side, so one vendor), or Firebase Crashlytics. Set `beforeSend` to scrub tokens, PII and URLs with query strings. Tag the release with the build SHA, upload obfuscation/dSYM symbols in CI, and attach the API `requestId` to breadcrumbs. Track cold-start time. | MOB |
| G23 | Medium | Migrations strategy | No migration framework or `migrations` collection. Indexes are created by Mongoose `autoIndex` at runtime (unsafe on large collections). Schema changes such as visibility fields and commerce collections will need backfills. | `be/lib/models/*` (`.index()` only); `be/scripts/seed.ts` only | Use `migrate-mongo` (or a small `scripts/migrations/NNN-*.ts` runner) that records runs in a `migrations` collection and runs as a pre-deploy step in CI. Set `autoIndex:false` in prod and run `syncIndexes()` from the migration step. Write migrations to be re-runnable and expand/contract-safe. | BE |

### 2.4 Performance and scalability

| # | Sev | Standard / control | Gap | Evidence | Fix | Owner |
|---|---|---|---|---|---|---|
| G24 | High | Performance budget: public card TTFB/LCP for NFC taps (Core Web Vitals) | The public card is client-rendered: an HTML shell, then the JS bundle, then `fetch /api/v1/public/card/:slug`, then render. The page has no metadata or OG tags. The API writes `CardView` synchronously before responding and sends no cache headers. | `be/components/public-card/PublicCardShell.tsx:1,15-23`; `be/app/card/[slug]/page.tsx`; `be/app/api/v1/public/card/[slug]/route.ts:26-33` | Make it a server component that renders the public DTO directly from Mongo (no self-HTTP), with `generateMetadata`. Cache with `revalidate` 60 s plus a tag invalidated on card update (`revalidateTag('card:'+slug)`). Move view tracking to a fire-and-forget beacon (`navigator.sendBeacon` to `/public/track-view`) or an async queue. **Budget:** TTFB p75 ≤ 200 ms cached / ≤ 600 ms uncached on Indian 4G; LCP p75 ≤ 2.0 s on a mid-range Android; JS ≤ 90 KB gzip for `/card/*`. | BE |
| G25 | Medium | App performance budget | No budget or measurement for cold start, frame times or APK size. | `app/.github/workflows/flutter.yml` (debug builds only) | Budget: cold start to first frame p50 ≤ 1.5 s / p90 ≤ 3 s on a mid-range Android (e.g. Snapdragon 6-series), release APK/AAB download ≤ 25 MB, jank ≤ 1 %. Measure with an `integration_test` + `flutter drive --profile` job, and with Sentry/Crashlytics performance in production. | MOB |
| G26 | Medium | Scalability: stateless processes (12-factor VI) | The default media store is local disk. Rate limits and caches fall back to process memory. land's order DB is a JSON file with a lockfile ("prefer a single Node process"). ecom runs PM2 cluster ×2 with 2 GB per instance. | `be/project-docs/DEPLOY.md` (media, Redis); `land/README.md`, `land/lib/db.ts:26-31`; `ecom/ecosystem.config.js:8-11` | Production must use S3 for media (with a CDN in front) and Redis (managed, with TLS). No file-backed state. All commerce state goes in Mongo. | OPS + BE |
| G27 | Medium | Data store design: indexes, retention, transactions | `LinkClick` has no TTL and no compound `{cardId, clickedAt}` index. `Card` has `ownerId` only; list queries filter by owner + status. Analytics aggregate raw events on every read. Local Mongo is standalone, so there are no multi-document transactions, and commerce needs them (order + payment + entitlement). | `be/lib/models/LinkClick.ts:12-20`; `be/lib/models/Card.ts:48`; `be/docker-compose.yml` | Add `{cardId:1, clickedAt:-1}` and a 180-day TTL to match CardView. Add `{ownerType, ownerId, status}` on cards. Roll analytics up nightly into `cardStatsDaily`. Run a replica set everywhere (`--replSet rs0` in compose; Atlas already is one) and use `session.withTransaction` for commerce. See report 03 for tenant indexes. | BE |
| G28 | Medium | Multi-tenancy architecture (ASVS V1.4.x, V4.1.x) | Shared database. Tenant scoping uses an `ownerType`/`ownerId` discriminator (plus `organizationId` on staff and users) enforced per route by hand, with no central tenant guard. A single missed filter leaks data across tenants. | `be/lib/models/Card.ts:46-48`; per-route queries in `be/app/api/v1/**` (detail in report 03) | Add a tenant context to `withApi` (`ctx.tenant = {type, id}`) and tenant-scoped repository helpers (`cardsFor(ctx)`), or a Mongoose plugin that rejects tenant-collection queries without a tenant filter. Add a test per role that fuzzes cross-tenant IDs. | BE |

### 2.5 CI/CD, testing, documentation, naming, licences

| # | Sev | Standard / control | Gap | Evidence | Fix | Owner |
|---|---|---|---|---|---|---|
| G29 | Medium | Mobile CI/CD gates | Format drift only warns. No coverage threshold. Only debug builds. No release signing, no store upload, no secret or dependency scan, no `flutter pub outdated` / OSV check. CI runs on `claude/**` pushes, which is fine. | `app/.github/workflows/flutter.yml` (`|| echo "::warning::format drift"`) | Make format blocking. Add a coverage gate (start at 60 % of lines in `lib/core` and `lib/features/*/data`). Add a release workflow: AAB + IPA, signing secrets from GitHub Environments with required reviewers, fastlane upload to the internal track or TestFlight, symbol upload. Add `osv-scanner` on `pubspec.lock` and gitleaks. | MOB + OPS |
| G30 | Medium | Test coverage | be has 45 unit cases and no route/integration tests. ecom and land have **0** tests. land's `deploy.sh`-style `npm test --if-present` passes vacuously in ecom. | `be/tests/*.test.ts`; `ecom/deploy.sh:27` | be: route tests per role for auth, cards, reviews and plan limits, then commerce. Target ≥ 70 % on `lib/` and 100 % of money paths. Smoke `scripts/smoke-qa.sh` against staging after each deploy. | BE |
| G31 | Low | Documentation quality | be docs are strong, but there are no ADRs, no runbook, no data-classification document, and no architecture view beyond the single-app mermaid chart. ecom has ~20 overlapping status `.md` files (FINAL-STATUS, FINAL_DEEP_SCAN_REPORT, START-HERE…) and a stub README. | `be/project-docs/03-Architecture/high-level-architecture.md`; `ecom/*.md` | Add `docs/adr/` (first ADRs: single API gateway; commerce inside Coglink; bearer + cookie dual auth; API/web split criteria). Add RUNBOOK.md, a data map (collection → PII class → retention), and the §3 diagram. Archive the ecom status files. | BE + PO |
| G32 | Medium | Brand and naming consistency | Product is "Bizzvot", codebase "Coglink", identifiers "cogcard"/"COGCard", legal and seller "Creatyvot", ecom "Enkilum Entekrishna"/"PlyMart". Cookie and header names, the verification-file path and the DB name are part of the wire contract. | `be/package.json` `coglink`; `be/lib/session-cookies.ts`; `be/project-docs/DEPLOY.md` (`x-cogcard-internal-secret`, `/.well-known/coglink-verification.txt`, `COGCARD_COOKIE_SECURE`); `be/lib/db/connect.ts:3`; app `com.bizzvot.bizzvot`, `x-bizzvot-*` | Naming ADR: **Bizzvot** for all user-facing text, domains, app IDs and new headers (`x-bizzvot-*`). **Creatyvot** only as the legal seller entity on invoices and the company footer. **Coglink** may stay as the internal repo name. Rename wire identifiers with dual-accept periods: read both the old and new cookie names for one refresh-token lifetime; serve both `.well-known` paths, because verified customer domains depend on the old one. Keep the DB name as is (renaming has no value). | PO + BE |
| G33 | Low | Licence compliance | Dependencies are permissive. LGPL-3.0 libvips in `@img/sharp-*` (dynamic prebuilt, so no copyleft obligation on our code) still needs attribution. MPL-2.0 packages are dev-only (lightningcss, axe-core). `png-js` (ecom, via pdfkit) declares no licence. be declares `ISC` for a private proprietary package. There is no THIRD-PARTY-NOTICES and no licence scan in CI. Flutter shows `showLicensePage`. | lockfile scan of `be/ecom/land/package-lock.json`; `be/package.json:16`; `app/lib/features/account/presentation/legal_screen.dart:66` | Set `"license": "UNLICENSED"`. Generate NOTICES with `license-checker --production` / `npx @cyclonedx/cyclonedx-npm` (an SBOM also serves ISO A.8.8). Fail CI on GPL/AGPL/SSPL in production dependencies. Check font licences (Inter is OFL; ship its licence in `LicenseRegistry`). | OPS |
| G34 | Medium | ASVS V1.1.2 threat modelling; ISO A.8.27 secure architecture | No threat model for new trust boundaries: the mobile bearer channel, customer custom domains served by the same app, payment webhooks, NFC URL permanence. | none | Run a one-page STRIDE per boundary in §3 and keep it in `docs/adr/`. Revisit whenever a boundary changes. | SEC |
| G35 | Medium | Code duplication between stacks | Three implementations each of auth (Coglink JWT, ecom NextAuth credentials, land admin password session), Razorpay, Delhivery, email/SMTP, WhatsApp, S3/R2 media and invoices. Each uses a different Mongoose major (be 9 vs ecom 8) and Next major (15 vs 16), so models cannot be shared directly. | `be/package.json`; `ecom/package.json`; `land/lib/{razorpay,delhivery,invoice,whatsapp}.ts`; `ecom/src/lib/{payment-service,delhivery-service,email-service}.ts` | Consolidate into one platform. Phase 1: Coglink `lib/commerce/*` ports **land**'s pricing, GST invoice, Razorpay order + webhook and Delhivery modules (smallest, NFC-specific, already signature-verified). Take ecom's `api-response.ts` and `logger.ts` patterns. Phase 2: land becomes marketing-only and checks out through Coglink. Phase 3: archive ecom for Bizzvot. | BE + PO |

---

## 3. Integration model (recommended target)

### 3.1 Principles

1. **One gateway, one database owner.** `https://www.bizzvot.com/api/v1`, the Coglink Next.js deployment, is the **only** process that reads or writes the Bizzvot MongoDB. The Flutter app, the web dashboards, the landing page, admin, workers and third-party webhooks all go through it or through workers that share its codebase. Nothing else holds a `MONGODB_URI`, so land and ecom lose DB access to Bizzvot data.
2. **One identity, two session transports.** `users` is the only identity store, and `requireAuth` (`be/lib/auth.ts:149`, which uses `getAccessTokenFromRequest` at `:61`: Bearer first, then the cookie) is the only verifier.
   - **Web:** httpOnly `Secure` `SameSite=Lax` host-only cookies (current behaviour). Add an `Origin`/`Sec-Fetch-Site` check on all unsafe methods as CSRF defence.
   - **Mobile:** `x-bizzvot-client: mobile` on login, register or refresh returns `{accessToken (15 min JWT), refreshToken (opaque, rotating)}` in the body and no cookies. Refresh tokens are stored **hashed** in a `sessions` collection (family ID, device ID, platform, app version, lastUsedAt) with reuse detection, which revokes the whole family. `POST /auth/logout {refreshToken}` revokes one session. `tokenVersion` stays as "log out everywhere". This closes AUTH-1/AUTH-2 (details in report 02).
   - **Webhooks:** each provider has its own HMAC secret, never a user session.
3. **The contract is the OpenAPI 3.1 spec in the be repo.** The web client uses `openapi-typescript` types. The app keeps hand-written models (per `CONVENTIONS.md`, no codegen), and spec-derived JSON fixtures keep them honest (G18).
4. **Money and fulfilment are server-authoritative and event-driven.** The client never marks anything paid. Only a verified Razorpay webhook (or a server-side `payments.fetch`) moves an order to `paid`. Side effects run from a transactional outbox, not inline in the request.
5. **NFC URLs are permanent.** A chip is written once and lives for years. Encode `https://www.bizzvot.com/t/{tagCode}`, a short opaque code, rather than `/card/{slug}`. Coglink maps tag to card in an `nfcTags` collection (reassignable, deactivatable, analytics source `nfc`). The `/t/` path must never break, whatever happens to slugs, brands or an API/web split.

### 3.2 Architecture diagram

```
                         Customer devices / visitors
   ┌──────────────────┐  ┌───────────────────┐  ┌──────────────┐  ┌───────────────────┐
   │ Flutter app      │  │ Browser: portal   │  │ NFC tap / QR │  │ Landing (static)  │
   │ (owner, staff)   │  │ dashboards, admin │  │ any phone    │  │ marketing only    │
   │ Bearer + refresh │  │ httpOnly cookies  │  │ no auth      │  │ links → /shop     │
   └────────┬─────────┘  └─────────┬─────────┘  └──────┬───────┘  └─────────┬─────────┘
            │ HTTPS                │ same-origin       │ /t/{tag} → 302     │
            ▼                      ▼                   ▼  /card/{slug}      ▼
   ┌───────────────────────────────────────────────────────────────────────────────┐
   │  CDN / WAF (TLS, bot rules, cache /card/* 60s + tag purge, /_next/static)     │
   └───────────────────────────────────────┬───────────────────────────────────────┘
                                           ▼
   ┌───────────────────────────────────────────────────────────────────────────────┐
   │  Coglink Next.js — www.bizzvot.com  (+ customer custom domains → /card only)  │
   │  ┌──────────────┐  ┌───────────────────────────────────────────────────────┐  │
   │  │ Web UI (RSC) │  │ /api/v1  (ONLY DB accessor)                           │  │
   │  │ /card SSR    │  │ withApi: requestId · auth(cookie|bearer) · tenant ctx │  │
   │  │ dashboards   │  │ rate limit · Zod · error envelope · idempotency       │  │
   │  └──────┬───────┘  │ modules: auth · orgs · staff · cards · reviews ·      │  │
   │         │ direct   │ analytics · domains · notifications · media ·         │  │
   │         │ lib call │ commerce(catalog, cart, orders, payments, shipments,  │  │
   │         └─────────►│ invoices, subscriptions, entitlements) · app/config   │  │
   │                    │ /webhooks/razorpay · /webhooks/delhivery (HMAC)       │  │
   │                    └───────────┬──────────────────────────┬────────────────┘  │
   └────────────────────────────────┼──────────────────────────┼───────────────────┘
                writes + outbox     │                          │ cache / limits / locks
                (same transaction)  ▼                          ▼
   ┌────────────────────────────────────────────┐   ┌──────────────────────────┐
   │ MongoDB Atlas (replica set, PITR backup)   │   │ Redis (managed, TLS)     │
   │ dbs per env: dev / staging / prod          │   │ rate limits, tv cache,   │
   │ outbox ◄── change stream / poll ──┐        │   │ host cache, job locks    │
   └───────────────────────────────────┼────────┘   └──────────────────────────┘
                                       ▼
   ┌───────────────────────────────────────────────────────────────────────────────┐
   │  Coglink worker (same repo, separate process: `node dist/worker.js`)          │
   │  order.paid → create Delhivery shipment · issue GST invoice PDF → S3          │
   │             → provision entitlements (seats/cards/NFC tags) → notify          │
   │  shipment.updated → order status → notify  ·  subscription.expiring → notify  │
   │  nightly: analytics rollups, retention purge, Delhivery reconciliation        │
   └──────┬────────────┬──────────────┬──────────────┬───────────────┬─────────────┘
          ▼            ▼              ▼              ▼               ▼
     Razorpay API  Delhivery API   AWS S3 (+CDN)  SMTP/SES       FCM (Android+iOS via APNs)
     (orders,      (create, track, media, invoices transactional  push to `devices` tokens
      refunds)      label, NDR)    versioned       email          WhatsApp (Creatyvot API)
          │            │
          └─ webhooks ─┴──► /api/v1/webhooks/*  (verify HMAC → webhookEvents unique(eventId) → outbox)
```

### 3.3 One deployment or split `api.bizzvot.com`?

**Recommendation: keep one deployment (www.bizzvot.com serving web and `/api/v1`) through mobile GA and the commerce launch. Design for a later split now.**

Why stay together now:
- **Cookies and CSRF stay simple.** Browser calls are same-origin, cookies are host-only, and there is no CORS surface. Splitting would force either `Domain=.bizzvot.com` cookies (wider blast radius: every subdomain, including any future marketing or customer-facing host, would receive the session) or a CORS + credentialed-fetch setup.
- **Native apps do not use CORS.** Mobile gains nothing from a split.
- **Server components can call `lib/*` directly.** They need no HTTP hop, which is what fixes the public card latency (G24).
- **The team and traffic are small.** One deploy, one set of secrets and one dashboard is safer (ISO A.8.9).

Do these now, so a split later costs nothing:
- Keep all API logic in `lib/` modules, not in route files, so it can be mounted elsewhere.
- Base URLs come only from env: the app's `BIZZVOT_API_BASE` already does this. Add `API_BASE_URL` for the web.
- Never set a cookie `Domain`.
- Mobile reads `GET /app/config` and could follow an `apiBase` field there.
- Restrict customer custom domains to `/card/*` and `/api/v1/public/*`. Make middleware reject `/api/v1/auth/*` and dashboard paths on any non-primary host, so tenant domains can never receive or set session cookies.

Split to `api.bizzvot.com` when any of these become true:
- API traffic (mobile + webhooks) needs a different scaling profile or WAF policy than SSR.
- Public card SSR needs edge or regional deployment and the API does not.
- You need separate blast radius or deploy cadence (e.g. a payments hotfix without redeploying the web).
- A third party needs the API.

When you split:
- Web keeps cookie auth, with Next rewrites proxying `/api/v1/*` to `api.bizzvot.com`, so the browser stays same-origin and cookies stay host-only on www.
- Mobile goes direct with bearer.
- `api.bizzvot.com` sends **no** `Access-Control-Allow-Credentials` and only allowlists the origins it needs.
- Keep `www.bizzvot.com/api/v1` as a permanent proxy for at least the 12-month app support window, because shipped app builds have it baked in.

### 3.4 Collection ownership (all in the Coglink DB; Coglink repo owns every schema)

| Domain module (`be/lib/<module>`) | Collections | Writers | Notes |
|---|---|---|---|
| identity | `users`, `sessions` (new), `passwordResetTokens`, `devices` (new: push tokens, platform, appVersion) | auth routes | `sessions` replaces stateless refresh JWTs for mobile |
| tenancy | `organizations`, `individuals`, `staff`, `plans`, `domains` | owner/admin routes | tenant guard (G28) |
| cards | `cards`, `nfcTags` (new) | owner/staff routes, worker (provisioning) | `nfcTags` = tag code → card, status, batch, orderItemId |
| engagement | `reviews`, `cardViews`, `linkClicks`, `cardStatsDaily` (new), `exchanges` | public routes, worker (rollups) | TTL on raw events |
| commerce (new) | `products`/`catalogItems`, `carts`, `orders`, `payments`, `shipments`, `invoices`, `subscriptions`, `entitlements`, `coupons`, `counters` | commerce routes, webhooks, worker | ported from **land**; money in integer paise + ISO currency (COM-2) |
| platform | `notifications`, `outbox` (new), `webhookEvents` (new, unique provider event ID), `idempotencyKeys` (new, TTL), `auditEvents` (new), `migrations` (new), `appConfig` (new) | all modules, worker | outbox written in the same transaction as the state change |

Repo roles after consolidation:
- **cogcard (Coglink):** owns every collection, the API, web, admin and worker.
- **Bizzvot-apps-:** an API consumer only.
- **nfc-landing-page:** a static marketing site with no DB and no Razorpay secret. It links to `www.bizzvot.com/shop` or calls the public catalogue API.
- **nfcwebsiteecom-:** no access to Bizzvot data. Archive it, or keep it as a separate client project with its own infrastructure.

### 3.5 Key event flows

1. **Purchase (app or web)**
   - The client calls `POST /orders` with an `Idempotency-Key`.
   - The server re-prices from the catalogue and creates a Razorpay order, then returns `{orderId, checkout:{url|razorpayOrderId, keyId}}`.
   - The client pays through the hosted page or SDK. When it returns, the client polls `GET /orders/:id`; it never trusts the callback (COM-3).
   - Razorpay POSTs `payment.captured` to `/api/v1/webhooks/razorpay`. The server verifies the HMAC on the raw body, inserts into `webhookEvents` (a duplicate means return 200 and stop), then in one transaction sets the order to `paid`, inserts a `payments` row and writes an `order.paid` outbox event.
   - The worker creates the Delhivery shipment, stores the AWB, generates the GST invoice PDF to S3, provisions entitlements and NFC tags, and sends email and push.
   - A reconciliation job compares Razorpay settlements with orders every night.
2. **Shipping:** the Delhivery webhook carries a shared secret, **made mandatory** (ecom treats it as optional, `ecom/src/pages/api/webhooks/delhivery.ts:106-112`). It updates `shipments`, writes the outbox event, and triggers push "Out for delivery" and "Delivered". A worker poll every 2 h covers missed webhooks (pattern from `ecom` `cron-delhivery-sync`).
3. **NFC tap:** `GET /t/{tag}` does a lookup through a Redis cache, returns 302 to `/card/{slug}` (or to a custom domain), and queues the view event asynchronously. `/card/{slug}` is SSR from cache. Target total ≤ 1 s to content on 4G.
4. **Push:**
   - The app registers `POST /devices {fcmToken, platform, appVersion}` after login and deletes it on logout.
   - The worker sends through FCM HTTP v1, using APNs via FCM for iOS.
   - Every push is also stored in `notifications`, so the in-app list (NOT-1) is the source of truth. Push is only a hint.
   - Payloads carry IDs only, no PII.
5. **Media:** `POST /media/upload` goes through the server (magic bytes, re-encode, quota) to S3. Later, move to presigned PUT to S3 followed by `POST /media/confirm`, which the server validates and re-encodes. Public objects are served through the CDN; invoices live in a private bucket behind short-lived presigned GET.
6. **Email:** SES/SMTP from the worker only, never inline except for password reset. Send with SPF/DKIM/DMARC on `bizzvot.com`, from the brand name "Bizzvot", with Creatyvot as legal sender in the footer.

---

## 4. Prioritized roadmap

### P0: this week (stop-the-bleed)
1. **G1:** Purge the PII CSV/JSON exports from ecom, including history. Rotate exposed credentials. Log it as an incident.
2. **G2, G35:** PO decision, recorded as an ADR: commerce goes inside Coglink, porting from land; ecom is out of scope for Bizzvot data.
3. **G4, G5:** Branch protection on all four repos. Minimal be CI: `npm ci`, lint, `tsc --noEmit`, vitest, build, gitleaks, `npm audit`. Turn on Dependabot.
4. **G7:** Confirm Atlas backups and PITR are on for the www.bizzvot.com database. Write down RPO 15 min / RTO 4 h. Do one restore test into a scratch cluster.
5. **G21:** `/api/v1/health` plus external uptime probes on `/`, a canary `/card/*` and `/api/v1/health`.

### P1: before mobile GA (2–4 weeks)
6. **G14, G20:** Error envelope with codes and `requestId`. pino structured logs with redaction. Security-event logging.
7. **G12, G13, G18:** OpenAPI 3.1 with full schemas and the missing routes. Versioning and deprecation policy. Spec lint in CI. Contract fixtures in both repos.
8. **Native auth (report 02, §3.1):** token-in-body for `x-bizzvot-client: mobile`, a `sessions` collection, rotation with reuse detection.
9. **G6:** Stand up `staging.bizzvot.com` with its own Atlas project, Razorpay test keys and S3 bucket. The mobile staging flavour points at it.
10. **G22, G29:** Sentry/Crashlytics in the app. Release workflow with signing, symbols and blocking format.
11. **G24:** SSR public card, cache, async view beacon, `/t/{tag}` NFC redirect plus the `nfcTags` collection. Do this **before** printing the next chip batch.
12. **G19, G17:** Boot-time env validation. Redis required in production, `Retry-After` and RateLimit headers.
13. **§3.3:** Restrict custom domains to `/card` and `/api/v1/public`.

### P2: commerce launch (4–8 weeks)
14. **G16, G27, G23:** Replica set everywhere. Migration runner. Idempotency store. Outbox and worker process. `webhookEvents` dedupe.
15. **G35:** Port land's pricing, GST invoice, Razorpay and Delhivery into `be/lib/commerce`. Mandatory webhook secrets. Nightly reconciliation. Land becomes marketing-only.
16. **G9:** `auditEvents` on admin and owner writes. MFA for super-admin.
17. **G30:** Route and integration tests for commerce money paths, with 100 % branch coverage there.
18. **Push:** `devices` collection, FCM, notification fan-out from the worker.

### P3: hardening and readiness for SOC 2 / ISO 27001 (quarter 2)
19. **G8, G11, G10:** Incident plan (CERT-In 6 h, DPDP). Supplier register with DPAs. Secret-rotation runbook and JWT `kid` key ring.
20. **G28, G34:** Central tenant guard and cross-tenant fuzz tests. STRIDE threat models stored as ADRs.
21. **G25, G26:** App performance budgets measured in CI. CDN for media. Analytics rollups.
22. **G32, G33, G31:** Naming ADR and dual-accept renames. Set `UNLICENSED`, add NOTICES and SBOM. Runbook, data map, ADR index. Archive ecom status docs.
23. **Quarterly:** Restore drill. Access review. Dependency review. Policy review. This produces the evidence a SOC 2 Type I audit will ask for.
