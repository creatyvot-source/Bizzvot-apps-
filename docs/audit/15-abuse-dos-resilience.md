# 15: Abuse, looping-attack and resource-exhaustion resilience

Auditor: agent 15. Mode: read-only, defensive review. No code was changed and no traffic was sent to any live host. Date: 2026-10-11.

Repos and commits read:

| Short name | Path | Commit | Stack |
|---|---|---|---|
| **be** (Coglink, serves `www.bizzvot.com/api/v1`) | `/home/user/cogcard` | `78cc311` | Next.js 15.5 App Router, Mongoose 9, ioredis (optional), bcryptjs, sharp, qrcode |
| **ecom** | `/home/user/nfcwebsiteecom-` | `1ced7ed` | Next.js `pages/api`, Mongoose, NextAuth, Razorpay, Delhivery, PM2 cluster ×2, nginx snippets |
| **app** | `/home/user/Bizzvot-apps-` | `167c9f8` | Flutter, Dio, Riverpod, go_router |

Scope: request floods and brute-force loops, expensive-query loops, token and webhook replay loops, client-side retry and redirect loops, and infrastructure limits. Classic vulnerabilities belong to agent 07, and earlier reports already describe some of the issues here. Those overlaps are listed in §6 and are **not** counted again in the severity summary. Where this report goes further than an earlier finding, the row says "extends 07 M-07" (or similar).

---

## 1. Summary

**Severity counts (new findings in this report):** Critical 0 · **High 5** · **Medium 18** · Low 7 · Info 3. Another 14 overlapping items are cross-referenced in §6.

The main problems:

1. **Every IP rate limit misfires in one of two directions, and nothing between them is correct for the proxies actually in use.**
   - With the shipped defaults (`TRUSTED_PROXY_HOPS=0`), Next 15 exposes no `req.ip`. Every client then shares one `"unresolved"` bucket. A single client sending 21 login attempts a minute blocks **every** login on the platform, and the same goes for register, forgot, reset, review, exchange and track-click (DOS-01).
   - The documented production setting (`TRUSTED_PROXY_HOPS=1`) indexes `X-Forwarded-For` one entry too far left. The nginx snippets in this codebase *append* to XFF (`$proxy_add_x_forwarded_for`), so behind them the value picked is the one the **client** wrote. Any client can then pose as a new IP on every request. That bypasses all IP limits and review de-duplication, and it grows limiter keys without bound (DOS-02).
2. **The defences against unbounded work are thin.**
   - No JSON request body is size-capped before parsing (DOS-03).
   - The Mongo client has no timeouts or queue bound (DOS-05).
   - The analytics `distinct()` call returns every unique visitor hash (DOS-14).
   - Upload decoding has no concurrency control, and the local quota check scans the whole uploads directory on every upload (DOS-17).
3. **The limiter itself can be broken.**
   - Redis `INCR` and `EXPIRE` are separate calls. If `EXPIRE` fails, the key never expires and stays blocked permanently (DOS-06).
   - When Redis is down, limits silently fall back to per-process memory (DOS-07).
   - The memory map evicts *arbitrary* keys, so a client who can mint many keys can wipe other users' login counters (DOS-08).
   - IPv6 is keyed per address rather than per /64 prefix (DOS-09).
   - The account lockout counter is a read-modify-write, so parallel guesses never trip it (DOS-10).
4. **One transient database failure at boot takes an instance down for good.** Both backends cache a *rejected* `mongoose.connect()` promise forever, and neither exposes a health endpoint that would let the orchestrator restart the instance (DOS-04).
5. **Several abuse loops cost an attacker nothing:**
   - analytics inflation (DOS-13)
   - notification flooding through exchange and reviews (DOS-15)
   - free-tier and register spam that squats slugs and storage (DOS-16)
   - random-`Host` amplification through middleware (DOS-19)
   - QR re-generation on every share-screen open (DOS-18)
6. **ecom has no `limit_req`, no timeouts and no body caps in nginx** (DOS-30). It also has:
   - an unbounded raw-body read before the Razorpay signature is checked (DOS-31)
   - Delhivery webhook replays that grow an order document toward the 16 MB limit (DOS-32)
   - races between payment confirmation and fulfilment (DOS-33)
   - unthrottled endpoints that amplify into third-party calls and email (DOS-34)
7. **The Flutter app is mostly well-behaved.**
   - Refresh is single-flight.
   - Every original request is retried at most once.
   - `providerRetry` makes at most 2 retries, and only on network or 5xx errors.
   - Payment polling is bounded (about 2 min, at most 4 consecutive errors, honours `Retry-After`, cancelled per generation).
   - `resolveRedirect` reaches a fixed point, so redirects cannot loop.

   Only small gaps remain: late 401s can each start their own refresh (DOS-40), config is re-fetched on every app resume without a throttle (DOS-41), and backoff has no jitter (DOS-42).

---

## 2. Rate-limit coverage: `be` `app/api/v1/**` (69 route files)

Legend:
- **Store:** `R→M` means Redis `INCR`+`EXPIRE` when `REDIS_URL` is set (`lib/api.ts:90-96`, `lib/redis.ts:71-82`), otherwise a per-process `Map`.
- **Redis down:** `FO-M` means the call silently falls back to the per-process memory bucket. Effectively the limit is multiplied by the replica count, each call gets about 1 reconnect cycle of extra latency, and no alert fires (`lib/redis.ts:33-37,79-81`).
- **IP key:** `getRateLimitIdentity`/`resolveClientIp` (`lib/middleware/ipHash.ts:96-155`). It is the shared `unresolved` value when hops=0 (DOS-01), and spoofable behind an appending proxy with hops≥1 (DOS-02).
- **Retry-After:** not sent by **any** route. 429 bodies are `{success:false,error:"Too many requests"}`.
- "—" means no limiter.

| Route | Method | Auth | Limiter key | Limit / window | Store | Redis down | Retry-After |
|---|---|---|---|---|---|---|---|
| `auth/login` | POST | public | `login:{ip}` | 20 / 60 s | R→M | FO-M | No |
| `auth/staff-login` | POST | public | `staff-login:{ip}` | 20 / 60 s | R→M | FO-M | No |
| `auth/register` | POST | public | `register:{ip}` | 5 / 60 s | R→M | FO-M | No |
| `auth/forgot-password` | POST | public | `forgot:{ip}`; `forgot-email:{sha256(email)}`; `forgot-email-day:{sha256}` | 5 / 60 s; 1 / 15 min; 5 / 24 h | R→M | FO-M | No (email buckets return a generic 200) |
| `auth/reset-password` | POST | public | `reset:{ip}` | 10 / 60 s | R→M | FO-M | No |
| `auth/refresh` | POST | public (refresh JWT) | — | — | — | — | — |
| `auth/refresh-and-return` | GET | refresh cookie | — | — | — | — | — |
| `auth/logout` | POST | optional | — | — | — | — | — |
| `auth/me` | GET | user | — | — | — | — | — |
| `auth/change-password` | POST | user | — (bcrypt compare + hash) | — | — | — | — |
| `auth/session-status` | GET | internal secret + JWT | — | — | — | — | — |
| `public/card/[slug]` | GET | public | `view:{cardId}:{hash(ip)}` gates **only the CardView write**, not the read | 1 write / 30 min | R→M | FO-M | — (read unlimited) |
| `public/card/[slug]/reviews` | GET | public | — | — | — | — | — |
| `public/card/[slug]/review` | POST | public | `review:{ip}` (global across cards) | 5 / 60 s (2 / 60 s when unresolved) | R→M | FO-M | No |
| `public/card/[slug]/exchange` | POST | public | `exchange:{ip}` (global across cards) | 5 / 60 s | R→M | FO-M | No |
| `public/track-click` | POST | public | `click:{ip}` | 30 / 60 s | R→M | FO-M | No |
| `public/resolve-host` | GET | public; internal secret **bypasses** | `resolve-host:{ip}` | 60 / 60 s | R→M | FO-M | No |
| `public/domain-verification` | GET | public (Host-scoped) | — | — | — | — | — |
| `cards/[id]/vcard` | GET | public | — | — | — | — | — |
| `cards/[id]/qrcode` | POST | owner/staff/admin | — (CPU + DB write per call) | — | — | — | — |
| `cards` | POST | org/individual | — (plan slots are atomic) | — | — | — | — |
| `cards/[id]` | GET, PATCH, DELETE | owner/staff/admin | — | — | — | — | — |
| `media/upload` | POST | user | `upload:{userId}` (checked **before** the body is read) | 20 / 60 s | R→M | FO-M | No |
| `domains` | GET, POST | org/individual | — (no cap on domains per owner) | — | — | — | — |
| `domains/[id]` | GET, PATCH, DELETE | org/individual(/admin) | — | — | — | — | — |
| `domains/[id]/verify` | POST | org/individual | `domain-verify:{userId}` | 10 / 60 s | R→M | FO-M | No |
| `individual/card` | GET, POST, PATCH, DELETE | individual | — | — | — | — | — |
| `individual/card/[id]` | GET, PATCH, DELETE | individual | — | — | — | — | — |
| `individual/profile` | GET, PATCH | individual | — | — | — | — | — |
| `individual/reviews` | GET | individual | — (`parsePagination` max 100) | — | — | — | — |
| `individual/reviews/[id]/reply` | POST | individual | — | — | — | — | — |
| `individual/reviews/[id]/status` | PATCH | individual | — | — | — | — | — |
| `organization/cards` | GET, POST | org | — (max 100 per page) | — | — | — | — |
| `organization/cards/[id]` | GET, PATCH, DELETE | org | — | — | — | — | — |
| `organization/dashboard` | GET | org | — (loads every card doc) | — | — | — | — |
| `organization/profile` | GET, PATCH | org | — | — | — | — | — |
| `organization/reviews` | GET | org | — (max 100) | — | — | — | — |
| `organization/reviews/[id]/reply` | POST | org | — (reply text unbounded) | — | — | — | — |
| `organization/reviews/[id]/status` | PATCH | org | — | — | — | — | — |
| `organization/staff` | GET, POST | org | — (bcrypt per create; body unvalidated) | — | — | — | — |
| `organization/staff/[id]` | GET, PATCH, DELETE | org | — | — | — | — | — |
| `staff/cards` | GET | staff | — | — | — | — | — |
| `staff/cards/[id]` | PATCH | staff | — | — | — | — | — |
| `staff/reviews` | GET | staff | — (max 100) | — | — | — | — |
| `staff/reviews/[id]/reply` | POST | staff | — | — | — | — | — |
| `staff/reviews/[id]/status` | PATCH | staff | — | — | — | — | — |
| `analytics/card/[id]/views` | GET | owner/staff/admin | — (`distinct` over all views) | — | — | — | — |
| `analytics/card/[id]/links` | GET | owner/staff/admin | — (aggregate over all-time clicks) | — | — | — | — |
| `analytics/card/[id]/reviews` | GET | owner/staff/admin | — (2 aggregates) | — | — | — | — |
| `notifications` | GET | user | — (limit 50) | — | — | — | — |
| `notifications/[id]/read` | PATCH | user | — | — | — | — | — |
| `admin/dashboard` | GET | super_admin | — (7 `countDocuments`) | — | — | — | — |
| `admin/cards`, `admin/organizations`, `admin/individuals`, `admin/reviews` | GET | super_admin | — (`parsePagination` max 100) | — | — | — | — |
| `admin/cards/[id]`, `admin/organizations/[id]` | GET | super_admin | — | — | — | — | — |
| `admin/cards/[id]/status`, `admin/reviews/[id]/status`, `admin/organizations/[id]/{status,plan,limits}`, `admin/individuals/[id]/{status,plan,limits}` | PATCH | super_admin | — | — | — | — | — |
| `admin/domains` | GET | super_admin | — (limit 200) | — | — | — | — |
| `admin/plans` | GET, POST | super_admin | — | — | — | — | — |
| `admin/plans/[id]` | PATCH, DELETE | super_admin | — | — | — | — | — |

Coverage: **16 limiter calls across 12 route files** out of 69. There is **no default per-user limit** in `withApi` (`lib/withApi.ts:14-31`), so every authenticated route is unlimited. Not one 429 carries `Retry-After` or `RateLimit-*` headers.

**ecom:** `grep -ri ratelimit src` finds nothing. **All 159 `pages/api` handlers are unlimited**, including auth, OTP, webhooks and checkout helpers (see 07 H-04). The nginx snippets have no `limit_req` either (DOS-30).

### 2.1 X-Forwarded-For trust and shared-IP effects

| Deployment | What `resolveClientIp` returns | Effect |
|---|---|---|
| Shipped defaults, `TRUSTED_PROXY_HOPS=0`, Next 15 (no `req.ip`) | `"unresolved"` for **everyone** (`ipHash.ts:122-141`) | All IP limits are global. One client can lock out login, register, reset, review, exchange and click platform-wide (DOS-01). |
| `hops=1` behind nginx `proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for` (the pattern in `ecom/nginx-config-updated.conf:8,33,58` and `nginx-cache-fix.conf:20,42,63`) | XFF arrives as `"<client-written>, <real-ip>"`. `idx = len-1-hops = 0` returns **the value the client wrote** (`ipHash.ts:41-50`). | Per-request IP spoofing. Every IP limit and the `{cardId,ipHash}` review uniqueness are bypassed, and limiter keys can be minted without bound (DOS-02). |
| `hops=1` behind a proxy that **overwrites** XFF with `$remote_addr` | A single entry, so `idx<0` returns `parts[0]`, the real IP | Correct. This is the only correct setup today, and it relies on the proxy's behaviour rather than the hop count. |
| Cloudflare → nginx (overwrite) → app | The Cloudflare edge IP | Thousands of users share each Cloudflare PoP IP, which causes mass false 429s. You must use `CF-Connecting-IP` through `real_ip_header` and the published Cloudflare IP list. |
| Mobile carrier CGNAT (Jio, Airtel, Vi) or venue Wi-Fi | One IP for hundreds of real users | 5 reviews or 5 exchanges per minute per IP is too low at events. This is the Review Stand scenario (06 #11). Real users get 429 while attackers rotate IPs. |
| IPv6 clients | A full /128 address per key | A single host owning a /64 has 2⁶⁴ identities (DOS-09). |

---

## 3. Findings

Paths are relative to each repo root. **be** = `/home/user/cogcard`, **ecom** = `/home/user/nfcwebsiteecom-`, **app** = `/home/user/Bizzvot-apps-`.

### 3.1 Backend (Coglink)

| ID | Sev | Repo | File:line | Abuse or loop scenario | Impact | Fix |
|---|---|---|---|---|---|---|
| DOS-01 | **High** (extends 07 M-07) | be | `lib/middleware/ipHash.ts:122-141`; `.env.example:9,14`; every IP limiter in §2 | With hops=0, every request maps to the stable key `unresolved`. One client at 21 req/min to `auth/login` returns 429 to **all** users. The same applies to register at 6/min, forgot at 6/min, reviews at 3/min, exchange at 6/min and clicks at 31/min. | Platform-wide denial of sign-in, reset and reviews from a single laptop. NFC tap campaigns get mass 429s. | Configure trust correctly (DOS-02 fix). **Fail startup in production** when hops=0 and no peer IP is available. Add per-account and per-email keys so a shared bucket never becomes the only control. Alert when the `unresolved` warning fires. |
| DOS-02 | **High** | be + ecom | `lib/middleware/ipHash.ts:41-50` (`idx = parts.length - 1 - hops`), `:99-110`; `project-docs/DEPLOY.md:42` (recommends hops=1); `ecom/nginx-config-updated.conf:8` (appends XFF) | Behind an *appending* proxy with hops=1, the chosen XFF entry is the one the client wrote. A client sends a new forged IP each time. | Bypasses **all** IP limits (login, register, forgot, reset, review, exchange, click, resolve-host). Unlimited review stuffing, because uniqueness is `{cardId, hash(ip)}`. Unlimited view and click inflation. Redis and memory key explosion (`view:{card}:{ip}` and others). | Use the standard rightmost model: `client = parts[len - hops]` when the trusted proxies **append** (hops = number of trusted proxies). Better still, have the edge set one header the app trusts: nginx `real_ip_header X-Forwarded-For; set_real_ip_from <LB/CF ranges>; real_ip_recursive on;` plus `proxy_set_header X-Real-IP $remote_addr`. The app then trusts only `X-Real-IP` from loopback. Add unit tests for both the "append" and "overwrite" proxy styles. Document a single correct config. |
| DOS-03 | **High** | be | Every handler calling `await req.json()` before validation, e.g. `auth/login/route.ts:23`, `auth/register/route.ts:31`, `auth/forgot-password/route.ts:33`, `auth/refresh/route.ts:14`, `public/card/[slug]/review/route.ts:64`, `exchange/route.ts:31`, `track-click/route.ts:18`, `organization/staff/route.ts:59`; there is no proxy config for be in the repo | App Router route handlers have **no built-in body cap**. The 1 MB `bodyParser` default applies only to `pages/api`, and `serverActions.bodySizeLimit` only to Server Actions. Zod `.max()` runs *after* the whole body is buffered and parsed. A few concurrent multi-hundred-MB JSON bodies, or deeply nested arrays that make `JSON.parse` throw, exhaust heap. (Upload buffering itself is 07 M-06.) | Unauthenticated process out-of-memory or restart loop. Because the IP limiter runs first and is spoofable or shared, it gives no protection. | At the proxy: `client_max_body_size 16k` for `/api/v1/auth/*` and `/api/v1/public/*`, `64k` for other JSON, `6m` only for `/api/v1/media/upload`. In the app: a `readJsonCapped(req, maxBytes)` helper in `withApi` that checks `Content-Length` and stream-reads with an abort at the cap. Return 413. Reject a non-JSON `Content-Type`. |
| DOS-04 | **High** | be + ecom | be `lib/db/connect.ts:20-23`; ecom `src/lib/mongodb.ts:36-41` | `cached.promise = mongoose.connect(...)` is stored even if it rejects. Every later `connectDB()` awaits the same rejected promise. A Mongo blip, DNS hiccup or Atlas failover during the **first** connect (cold start, deploy, autoscale) leaves that instance permanently returning 500. Neither app exposes a readiness probe that would make the orchestrator replace it (14 G21). | Self-inflicted outage that lasts until a manual restart. PM2 `max_restarts: 10` (ecom `ecosystem.config.js`) can also stop restarting after a crash loop. | `cached.promise = mongoose.connect(...).catch(e => { cached.promise = null; throw e; })`, plus bounded retry with jittered backoff. Add `/api/v1/health` (liveness) and `/api/v1/ready` (Mongo `ping` in under 500 ms, Redis `PING`). The LB and orchestrator should use `ready`. |
| DOS-05 | Medium | be + ecom | be `lib/db/connect.ts:21` (only `bufferCommands:false`); ecom `src/lib/mongodb.ts:37-39`; no `maxTimeMS` on any query | Driver defaults: `serverSelectionTimeoutMS` 30 s, no `socketTimeoutMS`, `waitQueueTimeoutMS` 0 (an **unbounded** pool queue), `maxPoolSize` 100. When Mongo slows, requests pile up for 30 s or more and the queue grows without limit. Slow aggregates (DOS-14) keep connections busy. | Mongo connection-pool exhaustion, latency cascade, memory growth. | `{serverSelectionTimeoutMS: 5000, socketTimeoutMS: 20000, waitQueueTimeoutMS: 2000, maxPoolSize: 50, minPoolSize: 5, maxIdleTimeMS: 60000}`. Apply `.maxTimeMS(2000)` to list and analytics queries and `5000` to admin queries. Shed load: return 503 with `Retry-After: 5` on pool timeout. |
| DOS-06 | Medium | be | `lib/redis.ts:71-82` | `INCR` and `EXPIRE` are separate round-trips. If `EXPIRE` throws (timeout, failover) or the process dies between the two, the counter has **no TTL**. Every later `INCR` exceeds the limit forever. | Permanent 429 for that key. Examples: `forgot-email:{hash}` (limit 1) means that user can **never** receive a reset email again. `login:unresolved` means a permanent platform-wide login lock. | Make it atomic with a Lua script (`INCR`; if the result is 1 then `PEXPIRE`), `MULTI` with `INCR` + `PEXPIRE ... NX` (Redis 7), or `SET key 0 PX w NX` followed by `INCR`. Alternat