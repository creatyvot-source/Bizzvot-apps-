# Bizzvot Security & Privacy Controls

**Scope:** Customer mobile application (`creatyvot-source/Bizzvot-apps-`), Backend API (`/api/v1`), and Hardware NFC integrations.  
**Standards:** OWASP MASVS-L1, OWASP API Security Top 10, DPDP Act 2023, GDPR.

---

## 1. Authentication & Native Sessions

1. **Bearer Token Authentication:**
   - Native mobile clients send `x-bizzvot-client: mobile` header.
   - Access tokens are short-lived JWTs (1 hour) carrying tenant (`organizationId`) and role claims.
   - Refresh tokens are cryptographically random 256-bit strings stored hashed at rest (SHA-256).
   - Refresh token rotation is strictly enforced: every `/auth/refresh` issues a new token pair and revokes the predecessor.
   - Automatic family revocation occurs if an already-used refresh token is presented (reuse detection).

2. **Mobile Secure Storage:**
   - Tokens stored strictly via `FlutterSecureStorage`:
     - iOS: Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
     - Android: Android Keystore-backed encrypted preferences (`EncryptedSharedPreferences`).
   - Cleartext storage, logging, analytics events, and bug reporting of tokens or passwords are completely prohibited.

3. **Session Revocation:**
   - Per-device revocation: Logging out on mobile revokes only the device's refresh token record, preserving web sessions unless user explicitly selects "Sign out everywhere".
   - `DELETE /auth/account` terminates all active sessions across all devices immediately.

---

## 2. API Authorization & Tenant Isolation

1. **Server-Authoritative Enforcement:**
   - Every protected route (`/organization/*`, `/staff/*`) inspects the authenticated caller's `organizationId` from the verified session token.
   - Resource access checks (`Card.ownerId === session.organizationId`) are enforced directly on MongoDB queries.
   - Role-based access control (RBAC):
     - `super_admin`: Forbidden from customer `/auth/login`.
     - `organization` (Owner): Scoped strictly to their own tenant records.
     - `staff`: Scoped strictly to assigned cards and granted permissions (`editCard`, `viewReviews`, `replyReviews`, `manageLinks`).

2. **Card Status Integrity:**
   - Card `status` (`active` | `disabled`) cannot be overridden by tenant PATCH requests.
   - Separate boolean flags maintain distinct lifecycle states: `adminDisabled`, `disabledByBilling`, `userDisabled`.
   - Cards disabled by billing quota cannot be reactivated until verified payment grants a free seat slot.

---

## 3. Privacy & Data Protection (DPDP Act 2023 & GDPR)

1. **Strict Public Response DTOs (Deny-by-Default):**
   - Public card (`/public/card/:slug`) and review (`/public/card/:slug/reviews`) endpoints use strict allow-lists.
   - `reviewerEmail`, `ipAddress`, `ipHash`, and internal DB `_id` references (such as `reply.repliedBy`) are never included in public JSON payloads.
   - Private card fields (`bloodGroup`, `fatherName`, `motherName`) are restricted to owner/staff internal screens and never serialized to public clients.

2. **Account Erasure & Right to Forget:**
   - `DELETE /auth/account` permits organization owners to permanently delete their account and organization data.
   - Public reviews authored by deleted accounts are anonymized.
   - Uploaded media in S3/Cloudflare R2 is purged.

3. **Log Sanitization & PII Scrubbing:**
   - Sentry crash reports and client console logs sanitize Authorization headers, email addresses, phone numbers, and vCard contents.
   - Production logger filters out all authorization tokens and sensitive request bodies.

---

## 4. Hardware NFC & Dynamic Redirect Security

1. **Dynamic URL Indirection:**
   - Physical NFC chips (Stands, PVC Cards, ID Badges) are programmed with immutable redirect links (`https://www.bizzvot.com/t/:tagUid`).
   - Static URLs are forbidden to prevent hardware bricking.
   - Redirect handler performs high-speed edge verification of tag status before 302 redirection.

2. **Abuse & Flood Resilience:**
   - Rate limiting on `/public/card/:slug/review`: Max 2 submissions per 10-minute window per IP subnet.
   - Invisible honeypot field catches automated submission scripts without requiring intrusive CAPTCHAs on customer review stands.
   - Submissions with profanity or spam patterns are routed to `pending` moderation queue.
