# Bizzvot Customer Mobile App
## Detailed Product Requirements, Technical Architecture & Phased Development Plan

**Platforms:** Android and iOS  
**Mobile framework:** Flutter  
**Backend:** Existing REST API, extended where required  
**Database:** MongoDB, accessed only by the backend  
**API base path:** `/api/v1`  
**Document version:** 1.0  
**Date:** 11 October 2026

---

## 1. Executive summary

Bizzvot needs a customer-facing mobile application for Android and iOS. The app will serve three primary experiences:

1. **Organization owner** — manages the organization, staff, digital cards, reviews, analytics, billing and purchases.
2. **Staff member** — manages only their assigned card, subject to permissions set by the owner.
3. **Public visitor** — opens a shared digital card or scans its QR code without logging in.

The application also needs a **Bizzvot Services & Shop** area where an organization can browse services and products, purchase plans or add-ons, review order history, and renew subscriptions or services.

The proposed app uses one Flutter codebase for Android and iOS. It communicates with the existing `/api/v1` REST API. MongoDB remains on the server and is never accessed directly by the mobile application.

### Core architecture recommendation

- Flutter mobile client for Android and iOS.
- Existing API as the single gateway to business data and permissions.
- MongoDB as the backend data store.
- Secure native authentication agreed with the backend team.
- Server-side payment verification and entitlement updates.
- Role-aware navigation, but authorization enforced on every backend request.
- Additive API/schema changes to avoid breaking existing web clients.

**Important:** This is a product and engineering specification. Existing routes are identified separately from proposed routes. Proposed endpoints and MongoDB collections must be reconciled with the current backend before implementation.

---

## 2. Goals and scope

### 2.1 In scope

- Owner registration, sign-in, password recovery and session management.
- Staff sign-in and permission-based access.
- Organization dashboard and profile editing.
- Staff creation, editing, permissions and removal.
- Digital card creation and editing.
- Card templates, media, section ordering and display settings.
- Organization-wide people-directory public/private setting.
- Per-card public/private override.
- QR code, share link and vCard actions.
- Public digital card experience.
- Review submission, moderation, hiding/unhiding and replies.
- Per-card analytics for views, visitors, ratings and link taps.
- Organization billing, paid seats and trial status.
- Bizzvot services and products catalogue.
- Ecommerce cart, checkout, orders, payment status and invoices.
- Plan purchase, subscription management and renewal flows.
- In-app notifications; optional push notifications as a later enhancement.
- MongoDB schema/index planning, API additions, security, QA and app-store delivery.

### 2.2 Out of scope

- Super-admin dashboard, global organization management, platform-wide plan administration, platform review QR and platform health screens.
- Contact exchange or an exchange inbox. `POST /public/card/:slug/exchange` is retired and returns `410`.
- Direct MongoDB connections from Flutter.
- Client-side decisions about seat limits, paid status or subscription entitlements.
- Treating a payment provider’s client-side success callback as final proof of payment.

---

## 3. User roles and navigation

| Role | Sign-in | Home screen | Access |
|---|---|---|---|
| Organization owner | `POST /auth/login` | Business dashboard | Only their organization’s staff, cards, reviews, analytics and billing |
| Staff | `POST /auth/staff-login` | My card | Only their assigned card and screens permitted by their permissions |
| Public visitor | No login | Public card | Only active, publicly accessible card data and approved reviews |
| Shop customer | Optional, based on product rules | Services & Shop | Own orders and purchases; organization purchases must be associated with the correct organization |

### 3.1 Owner navigation

- Dashboard
- Organization profile
- People and staff
- Cards
- Card editor and preview
- Public/private visibility
- QR and sharing
- Reviews and moderation
- Analytics
- Billing and seats
- Services & Shop
- Cart and checkout
- Orders and invoices
- Subscription and renewals
- Notifications
- Security and change password

### 3.2 Staff navigation

- My card
- Card editor, only if `editCard` is true
- Social/custom links, only if `manageLinks` is true
- Reviews, only if `viewReviews` is true
- Review reply/status, only if `replyReviews` is true
- Analytics for assigned card
- QR and sharing
- Change password

Staff must not create other staff members, access billing, or open another person’s card.

### 3.3 Public visitor navigation

- Public digital card
- Call, WhatsApp, email, website, map and social actions
- Approved reviews and business replies
- Write a review
- Save contact using vCard
- Google review button on the `review_card` template

---

## 4. Authentication and sessions

### 4.1 Existing authentication routes

| Action | Method and path |
|---|---|
| Register organization | `POST /auth/register` |
| Owner login | `POST /auth/login` |
| Staff login | `POST /auth/staff-login` |
| Current user | `GET /auth/me` |
| Refresh session | `POST /auth/refresh` |
| Logout | `POST /auth/logout` |
| Forgot password | `POST /auth/forgot-password` |
| Reset password | `POST /auth/reset-password` |
| Change password | `POST /auth/change-password` |
| Session status | `GET /auth/session-status` |

`POST /auth/login` must reject `super_admin` with `403` and the message “Use the admin sign-in page”. If a staff user attempts owner login, the UI should direct them to staff login without revealing sensitive account details.

### 4.2 Native app authentication gap

The current API sets HTTP-only cookies but does not return access or refresh tokens in JSON. A native Flutter app needs an explicitly supported session mechanism.

The backend team must select and document one of these options:

**Preferred native strategy**
- Login returns a short-lived access token and a rotating refresh credential over TLS.
- Access token is sent as `Authorization: Bearer <accessToken>`.
- Include `x-bizzvot-session: org` where required by the API contract.
- Store credentials using iOS Keychain and Android Keystore-backed secure storage.
- Revoke refresh credentials on logout and rotate them during refresh.

**Alternative**
- Retain cookie-based sessions only if a tested native cookie jar, CSRF strategy, domain/origin policy and refresh/logout behavior are implemented for both platforms.

Do not invent a client-side workaround or embed long-lived secrets in the app.

### 4.3 Session behavior

- Restore a valid session on launch.
- Fetch `GET /auth/me` to establish role and organization context.
- Handle `401` with one coordinated refresh attempt if supported.
- Do not retry indefinitely or create concurrent refresh loops.
- If refresh fails, clear secure storage and return to sign-in.
- Revoke server session on logout.
- Display generic invalid-credential messaging for unknown and locked accounts.
- Do not store tokens in ordinary preferences, logs, analytics events or crash reports.

---

## 5. Organization owner features

### 5.1 Dashboard

**Existing endpoints**
- `GET /organization/dashboard`
- `GET /organization/profile`

Show:
- Organization name and status.
- Trial status and remaining trial details if returned by API.
- Active cards versus paid seats.
- Total cards.
- Total reviews.
- Average rating.
- Cards disabled by billing or quota.
- Quick actions: Add staff, Create/edit card, Share QR, View reviews, Purchase seats, Browse services.

The backend remains authoritative for card activation and seat capacity. Trial seat capacity is unlimited according to the supplied requirements.

### 5.2 Organization profile

**Existing endpoints**
- `GET /organization/profile`
- `PATCH /organization/profile`

Fields should follow the current backend profile schema. Add a Public Presence section for directory visibility; do not add unsupported fields to the API without a backend change.

### 5.3 Staff management

**Existing endpoints**
- `GET /organization/staff`
- `POST /organization/staff`
- `PATCH /organization/staff/:id`
- `DELETE /organization/staff/:id`

Requirements:
- List staff and seat/card status.
- Add staff and create their assigned card.
- Edit staff details, login email and permissions.
- Remove staff with a confirmation step.
- Display whether their card is active, disabled, or disabled by billing.
- Explain when a card cannot be activated because no paid slot is available.

Permissions, all false by default:
- `editCard`
- `viewReviews`
- `replyReviews`
- `manageLinks`

The backend must validate permission changes and organization ownership on every request.

---

## 6. Digital card management

### 6.1 Card fields

**Identity**
- Title
- Designation
- Company
- Pronouns
- Bio

**Images**
- Profile photo
- Cover image
- Logo

**Contact**
- Phone
- Company phone
- WhatsApp
- Email
- Website
- Address
- Map link

**Private details**
- Blood group
- Father’s name
- Mother’s name

Private details must remain hidden by default and must never appear in public API payloads unless a separate, deliberate public-display policy is implemented.

**Other content**
- Social links
- Custom links
- Gallery, up to 5 images
- PDF documents, up to 10
- YouTube videos, up to 5
- Template and brand color
- Section ordering
- Display toggles
- vCard on/off
- Card status: `active` or `disabled`

### 6.2 Templates

- `minimal`
- `corporate`
- `modern_dark`
- `profile_hub`
- `cover_card`
- `review_card`

### 6.3 Card routes

| Action | Method and path |
|---|---|
| List organization cards | `GET /organization/cards` |
| Card detail | `GET /organization/cards/:id` |
| Update card | `PATCH /organization/cards/:id` |
| Delete card | `DELETE /organization/cards/:id` |
| Activate/disable | `PATCH /organization/cards/status` |
| Single QR image | `GET /cards/:id/qrcode` |
| All organization QR images | `GET /organization/cards/qrcodes` |
| vCard file | `GET /cards/:id/vcard` |
| Upload media | `POST /media/upload` and `POST /cards/:id/media` |
| Remove library file | `DELETE /cards/:id/library` |

### 6.4 Seat and activation rules

- One card is associated with each staff member.
- Adding staff has no separate staff-user seat charge according to the supplied requirements.
- Activating a card consumes one paid card slot outside the trial.
- Trial seat capacity is unlimited.
- Billing can disable cards when a trial ends or the organization exceeds quota.
- A card marked `disabledByBilling` must not be reactivated unless the backend confirms a free eligible slot.
- The app should refresh the dashboard, card list and billing data after a successful purchase.

---

## 7. New requirement: public/private people directory

This feature needs a clear distinction between **directory visibility** and **individual card publication**.

### 7.1 Recommended model

Organization setting:

```json
{
  "directoryVisibility": "public"
}
```

Allowed values: `public`, `private`.

Card setting:

```json
{
  "visibility": "inherit"
}
```

Allowed values: `inherit`, `public`, `private`.

### 7.2 Visibility rules

| Organization directory | Card visibility | Expected directory behavior |
|---|---|---|
| Public | Inherit | List if card is active and organization is public-eligible |
| Private | Inherit | Do not list the card in a public people directory |
| Public | Public | List if card and organization meet publication requirements |
| Private | Public | Recommended default: organization-level private directory still hides it; explicit override behavior must be decided |
| Any | Private | Never list the card publicly |

**Recommended precedence:** organization directory privacy wins for the directory itself; a card-level `public` setting should not override an organization-wide private directory unless the product owner explicitly chooses that behavior. The final precedence must be encoded consistently in backend logic and tests.

### 7.3 Separate direct card access

A card hidden from the directory may still be accessible by its direct `/card/{slug}` URL or QR if its publication status is active and the organization is eligible. This allows an owner to hide the staff list while still sharing selected cards directly.

If the business instead requires “private means no one can open the card”, introduce a separate card-publication setting and make direct URL/QR access respect it. Do not assume that hiding a directory automatically means blocking direct card access.

### 7.4 Owner UI

- Organization Profile → Public Presence → `Show people directory` toggle.
- Card Editor → Visibility: `Inherit organization setting`, `Public`, or `Private`.
- Staff/Card list → visibility status.
- Optional bulk actions: Make public / Make private, with confirmation.
- Preview directory and card as a public visitor.

### 7.5 Proposed API additions

These are proposed, not confirmed existing routes:
- Add `directoryVisibility` to the organization profile response/update contract.
- Add `visibility` to card detail and update contract.
- Optional public directory endpoint: `GET /public/organizations/:slug/directory`.

The public directory endpoint must filter data on the server. It must not retrieve all cards and rely on the Flutter app to hide private entries.

---

## 8. Public digital card

### 8.1 Existing endpoints

- `GET /public/card/:slug`
- `GET /public/card/:slug/reviews`
- `POST /public/card/:slug/review`
- `POST /public/track-click`

### 8.2 Display rules

Show the card only when:
- The card is active.
- The organization is allowed to be public (paid or on trial).
- The effective card publication policy allows public access.

If not eligible, show a clear unavailable state based on the API response. Avoid exposing private-resource existence where that creates a security risk.

### 8.3 Visitor actions

- Call
- WhatsApp
- Email
- Website
- Map
- Social and custom links
- Save contact using vCard if `vcardEnabled` is not false
- Read approved reviews and business replies
- Submit one review per staff member
- Open Google review button on `review_card` template

### 8.4 Public review rules

- Rating must be 1–5.
- Comment is optional.
- Do not show pending or hidden reviews.
- Do not show reviewer IP or email publicly.
- A duplicate review returns `409`.
- Rate-limited submission returns `429`.
- Plans with moderation may set new reviews to `pending`; platform auto-approve may make them `approved`.

### 8.5 Share behavior

- Share `https://<app-host>/card/<slug>`.
- Load QR image from `GET /cards/:id/qrcode`.
- Download vCard from `GET /cards/:id/vcard`.
- Use the platform share sheet for vCard so the visitor can save the contact.
- Track taps using `POST /public/track-click` where the API contract defines the event payload.

---

## 9. Reviews and moderation

### 9.1 Owner endpoints

- `GET /organization/reviews`
- `PATCH /organization/reviews/:id/status` with `{ "status": "approved" | "hidden" | "pending" }`
- `POST /organization/reviews/:id/reply` with `{ "text": "..." }`

### 9.2 Staff endpoints

- `GET /staff/reviews`
- `POST /staff/reviews/:id/reply`
- `PATCH /staff/reviews/:id/status`

The backend must restrict staff actions according to `viewReviews` and `replyReviews`. If reply and moderation are meant to be separate permissions, introduce distinct permissions rather than assuming they are interchangeable.

### 9.3 Review screens

- Review list with card, date, rating and status.
- Filter by pending, approved and hidden.
- Approve, hide and unhide.
- Reply composer and reply history if supported.
- Public preview of approved review and business reply.

---

## 10. Analytics

Existing routes:
- `GET /analytics/card/:id/views`
- `GET /analytics/card/:id/reviews`
- `GET /analytics/card/:id/links`

Show:
- Views over time.
- Unique visitors.
- Rating breakdown.
- Review totals and trend.
- Link clicks: WhatsApp, phone, social, custom links, vCard and other supported actions.

Staff analytics must be restricted to their assigned card. Owners may view cards belonging to their organization.

Define a privacy policy for visitor identifiers, retention, analytics aggregation and tracking disclosures. Do not expose raw visitor IP addresses to organization users unless there is an approved and necessary legal basis.

---

## 11. Billing, seats and renewals

### 11.1 Existing organization billing

- `GET /organization/billing`
- `POST /organization/billing`

The current route starts a subscription. The request includes `quantity` of at least 1 and optional `planId`.

### 11.2 Owner billing screens

- Current plan and plan features.
- Trial status and end date.
- Paid seats and active-card count.
- Available plans.
- Additional seat quantity.
- Price, currency, tax and total.
- Checkout/payment status.
- Subscription status and next renewal date.
- Invoices/receipts if available.
- Renewal, upgrade/downgrade and cancellation options if supported.
- Failed-payment and expired-plan states.

### 11.3 Required billing rules

- Fetch all plan pricing and eligibility from the backend.
- Do not hard-code plan prices in Flutter.
- Seat purchases add active-card slots on top of existing seats, according to the supplied product rules.
- Use server-side payment confirmation before adding seats or granting entitlements.
- Refresh billing and dashboard after payment confirmation.
- Define what happens to active cards after trial expiry or failed renewal.
- Define a grace period and a clear warning schedule.
- Keep historical invoices and orders accessible according to retention rules.

### 11.4 Renewal policy decisions

Before implementation, define:
- Manual renewal versus automatic renewal.
- Renewal period and renewal date calculation.
- Grace period length.
- Failed-payment retries and reminders.
- Whether the subscription remains active during grace.
- Whether cards are disabled immediately or after grace.
- Upgrade/downgrade timing and proration.
- Cancellation effective date and refund rules.

---

## 12. Bizzvot services catalogue and ecommerce

This is an additional product area. The supplied API brief does not include ecommerce endpoints, so the following routes and schemas are proposals.

### 12.1 Services catalogue

Each service should support:
- Name and slug.
- Category.
- Description and benefits.
- Images or icon.
- Features/inclusions.
- Price or “contact us” state where applicable.
- Currency and billing period.
- Available plans and add-ons.
- Active/inactive status.
- FAQ and support contact.
- Eligibility and purchase rules.

### 12.2 Product catalogue

For purchasable products:
- Product name, slug and description.
- Images.
- SKU and variants where applicable.
- Price and currency.
- Inventory status if physical stock exists.
- Tax category.
- Shipping/fulfilment requirement if physical.
- Active/inactive status.

### 12.3 Cart and checkout

- Add/remove products and update quantities.
- Select plan, seat quantity or add-ons.
- Validate the cart on the backend.
- Fetch authoritative prices, taxes, discounts and shipping.
- Show an itemized total before payment.
- Create a pending order.
- Start a payment attempt.
- Open the approved payment SDK or hosted checkout.
- Return to an order status screen.
- Fetch final order status from the backend.
- Never mark an order paid only because the app receives a gateway success callback.

### 12.4 Purchase history

Screens:
- Order list.
- Order detail.
- Payment status.
- Invoice/receipt.
- Delivery/fulfilment status where relevant.
- Cancellation/refund status if supported.
- Subscription linked to an order where applicable.

### 12.5 Proposed commerce API

Potential routes for backend design review:

| Purpose | Proposed route |
|---|---|
| Service categories | `GET /catalog/categories` |
| Services | `GET /catalog/services` |
| Products | `GET /catalog/products` |
| Plans | `GET /catalog/plans` |
| Product/service details | `GET /catalog/:type/:id` or dedicated detail routes |
| Quote cart | `POST /cart/quote` |
| Create order | `POST /orders` |
| List own orders | `GET /orders` |
| Order detail | `GET /orders/:id` |
| Start payment | `POST /orders/:id/payment` |
| Subscription list | `GET /subscriptions` |
| Subscription detail | `GET /subscriptions/:id` |
| Renew | `POST /subscriptions/:id/renew` |
| Invoice list/detail | `GET /invoices`, `GET /invoices/:id` |

The backend team must approve route names, request/response shapes, authorization rules and state machines before Flutter integration.

### 12.6 App-store payment policy

Before selecting Razorpay or external checkout for every item, classify each item:
- Physical goods.
- In-person or business service.
- Digital service consumed outside the app.
- Digital feature, content or subscription unlocked inside the app.

Apple App Store and Google Play payment rules may differ by product category, storefront and current policy. Confirm the applicable rules for the exact items sold before implementing checkout. Do not assume one payment method is acceptable for all categories.

---

## 13. Proposed MongoDB data model

MongoDB remains server-side. Collection names below are logical proposals; reuse current collections where possible and avoid duplicate sources of truth.

### 13.1 `organizations`

Illustrative fields:
- `_id`
- `ownerUserId`
- `name`
- `slug`
- `status`
- `trial`
- `directoryVisibility`
- `publicEligible`
- `planId` or subscription summary
- `profile`
- `createdAt`, `updatedAt`

Indexes:
- `ownerUserId`
- Unique slug if public slugs are used.
- Status/visibility index for directory queries where useful.

### 13.2 `users`

Illustrative fields:
- `_id`
- `organizationId`
- `role`: owner, staff or customer
- `email`
- `passwordHash`
- `status`
- `authVersion`
- `createdAt`, `updatedAt`

Indexes:
- Normalized email unique within the chosen account policy.
- Organization and role lookup.

### 13.3 `staffPermissions`

Fields:
- `userId`
- `editCard`
- `viewReviews`
- `replyReviews`
- `manageLinks`
- `updatedAt`

Index:
- Unique `userId`.

Permissions default to false. Validate every permission server-side.

### 13.4 `cards`

Fields:
- `_id`
- `organizationId`
- `staffUserId`
- `slug`
- `status`
- `disabledByBilling`
- `visibility`
- `vcardEnabled`
- `template`
- Identity/contact fields
- Private fields
- Media metadata
- Social/custom links
- Section order and display toggles
- `createdAt`, `updatedAt`

Indexes:
- Unique slug.
- `organizationId + staffUserId`.
- Status/visibility for directory filtering.

### 13.5 `reviews`

Fields:
- `_id`
- `organizationId`
- `cardId`
- `reviewerName`
- `rating`
- `comment`
- `status`
- `reply`
- Privacy-preserving dedupe identifier or keyed hash
- `createdAt`, `updatedAt`

Indexes:
- `cardId + status + createdAt`.
- A suitable duplicate-prevention strategy scoped to one card and one reviewer.

Do not rely only on the client to enforce one review per person. A public app may not have a verified identity, so the backend must define what “same person” means and how to handle shared devices, privacy and abuse.

### 13.6 `cardEvents`

Fields:
- `_id`
- `organizationId`
- `cardId`
- `eventType`
- `visitorKeyHash`
- `destinationType`
- `createdAt`

Indexes:
- `cardId + createdAt`.
- `eventType + createdAt`.

Define retention and aggregation to avoid indefinite collection of unnecessary visitor-level data.

### 13.7 `plans` and `services/products`

Plan fields:
- `_id`
- `name`
- `version`
- `billingPeriod`
- `currency`
- `price`
- `features`
- `limits`
- `active`

Service/product fields:
- `_id`
- `type`
- `slug`
- `title`
- `description`
- `media`
- `variants`
- `priceReference`
- `status`
- `taxCategory`
- `inventory` when needed

Indexes:
- Unique slug.
- Active/category query.
- Unique SKU when applicable.

Existing plan versions should remain stable for historical subscriptions and invoices.

### 13.8 `orders`

Fields:
- `_id`
- `orderNumber`
- `buyerUserId`
- `organizationId` when the purchase belongs to an organization
- `itemsSnapshot`
- `totals`
- `currency`
- `taxSnapshot`
- `shippingSnapshot` if applicable
- `status`
- `paymentStatus`
- `createdAt`, `updatedAt`

Indexes:
- Unique order number.
- Buyer/organization plus creation date.
- Payment status plus creation date.

Save an immutable item/price/tax snapshot so historical orders do not change when catalogue pricing changes.

### 13.9 `paymentAttempts`

Fields:
- `_id`
- `orderId` or `subscriptionId`
- `gateway`
- `gatewayOrderId`
- `amount`
- `currency`
- `status`
- `idempotencyKey`
- `verifiedAt`
- `createdAt`

Indexes:
- Unique gateway transaction/order identifier as appropriate.
- Unique idempotency key.

### 13.10 `subscriptions` and `entitlements`

Subscription fields:
- `_id`
- `organizationId` or `userId`
- `planVersionId`
- `quantity`
- `status`
- `currentPeriodStart`
- `currentPeriodEnd`
- `nextRenewalAt`
- `graceUntil`
- `cancelAtPeriodEnd`

Entitlement fields:
- `_id`
- `organizationId`
- `entitlementType`
- `quantity`
- `validFrom`
- `validUntil`
- `sourceSubscriptionId`

Indexes:
- Organization plus status.
- Next renewal date plus status.
- Organization plus entitlement type and validity.

Entitlements must be updated only after verified payment or another authorized grant. Add reconciliation jobs to detect mismatches between payment records and granted access.

### 13.11 `invoices`

Fields:
- `_id`
- `invoiceNumber`
- `orderId` or `subscriptionId`
- `totals`
- `taxDetails`
- `status`
- `issuedAt`
- `fileUrl`

Index:
- Unique invoice number.
- Order/subscription lookup.

### 13.12 `notifications`

Fields:
- `_id`
- `recipientUserId`
- `organizationId`
- `type`
- `payload`
- `readAt`
- `createdAt`

Index:
- `recipientUserId + readAt + createdAt`.

### 13.13 `auditLogs`

Fields:
- `_id`
- `actorUserId`
- `organizationId`
- `action`
- `resourceType`
- `resourceId`
- Safe metadata only
- `createdAt`

Index:
- `organizationId + createdAt`.

Use audit logs for visibility changes, permission changes, moderation, billing, orders and other consequential actions. Do not write passwords, tokens, reviewer email/IP or private card details into logs.

### 13.14 MongoDB implementation guidelines

- Use consistent ObjectId references and validate incoming IDs.
- Check tenant ownership on every read and write.
- Use schema validation at the application layer and MongoDB validators where appropriate.
- Use transactions for coupled order/payment/entitlement updates when supported by the deployment.
- Use explicit public response DTOs. Do not serialize a private database object and merely remove a few fields afterward.
- Define migration, backup, restore and rollback procedures before schema changes.
- Avoid duplicating subscription or seat counts as independently editable values. Define which record is authoritative and how cached summaries are reconciled.

---

## 14. API contracts and error handling

### 14.1 Standard response format

Success:

```json
{
  "success": true,
  "data": {}
}
```

Error:

```json
{
  "success": false,
  "error": {}
}
```

Use typed response models and a shared API error mapper in Flutter. Prefer stable error codes for UI behavior rather than relying only on free-form text.

### 14.2 HTTP status behavior

| Status | Expected app behavior |
|---|---|
| `401` | Try one supported session refresh; otherwise clear session and sign in again |
| `403` | Show access, plan or publication restriction without leaking private resource details |
| `404` | Show not found or removed content |
| `409` | Show duplicate review, conflicting state or already-processed order; do not blindly retry |
| `410` | Feature retired; do not implement contact exchange |
| `429` | Respect `Retry-After` if supplied; show cooldown and disable repeated submission |

### 14.3 API changes process

For every new endpoint:
- Publish method, path and schema.
- Define authentication requirement.
- Define role and organization authorization.
- Define success/error envelope.
- Define pagination and sorting.
- Define idempotency for order/payment writes.
- Add integration tests and OpenAPI documentation.
- Version breaking changes instead of silently changing existing responses.

---

## 15. Flutter technical architecture

### 15.1 Recommended stack

| Concern | Recommendation |
|---|---|
| UI | Flutter, Material 3, reusable responsive components |
| State management | Riverpod or Bloc; choose one consistently |
| Navigation | `go_router` with deep links and role-aware guards |
| HTTP | Dio or equivalent with interceptors and request cancellation |
| Models | Typed DTOs and generated JSON serialization |
| Secure storage | Keychain/Keystore-backed secure storage |
| Media | Image picker, compression and upload progress |
| QR | Render/display backend-provided QR image |
| Sharing | Native share sheet and platform URL handlers |
| Payments | Approved gateway SDK or hosted checkout based on policy |
| Monitoring | Crash reporting and structured logs with sensitive-data redaction |
| Tests | Unit, widget, integration and API contract tests |

### 15.2 Suggested source tree

```text
lib/
  app/
    bootstrap.dart
    router.dart
    theme.dart
  core/
    api/
    auth/
    errors/
    secure_storage/
    analytics/
    utilities/
  features/
    auth/
    dashboard/
    organization_profile/
    staff/
    cards/
    directory_visibility/
    reviews/
    analytics/
    billing/
    catalog/
    cart_checkout/
    orders/
    subscriptions_renewals/
    notifications/
    public_card/
  shared/
    widgets/
    models/
```

### 15.3 Architecture rules

- UI calls repositories/use cases, not raw HTTP endpoints from every screen.
- API DTOs are separate from UI presentation models where helpful.
- Role and permission state is centralized and refreshed when permissions change.
- Deep links route public card slugs to the public-card experience.
- Public-card pages must work without login.
- Cache only appropriate data; clear private cached content on logout or account switch.
- Do not cache private staff details in shared public caches.
- Network errors, loading states, empty states and retries should be consistent.
- Use separate development, staging and production API configurations.

---

## 16. Security and privacy requirements

### Authentication and authorization
- TLS only.
- Server-side role, tenant and resource checks on every protected endpoint.
- Secure token storage and refresh rotation if using bearer tokens.
- Rate limits for login, password reset, review submission, uploads and checkout.
- Generic login failure responses for unknown and locked accounts.

### Public/private data
- Explicit public DTOs for cards, directories and reviews.
- Private details excluded from public responses by construction.
- No reviewer email or IP in public review lists.
- Hidden and pending reviews excluded from public endpoints.
- Directory privacy enforced on the server.
- Private direct-card behavior explicitly defined and tested.

### Media
- Validate file type, file signature, size and count on the server.
- Respect 5 gallery images, 10 PDFs and 5 YouTube videos.
- Prevent unauthorized media association or removal.
- Use signed uploads if appropriate and ensure upload URLs expire.

### Payments
- Verify gateway webhook signatures.
- Protect against replay and duplicate webhook processing.
- Validate expected amount, currency, order and subscription.
- Use idempotency for order creation and entitlement grants.
- Reconcile gateway transactions with local order/subscription state.
- Never grant paid seats from a client-side callback alone.

### Privacy operations
- Privacy notice and consent where applicable.
- Data retention and deletion policy.
- Analytics tracking disclosure.
- Secure backups and controlled production access.
- Redact tokens and personal data from logs/crash reports.
- Audit consequential changes.

---

## 17. Key end-to-end journeys

### 17.1 Owner onboarding

1. Register or sign in.
2. Establish session and fetch current user.
3. Load organization profile, dashboard, cards, staff, billing and notifications.
4. Add staff member and assigned card.
5. Configure permissions and card content.
6. Configure directory visibility and card visibility.
7. Preview public experience.
8. Activate card if trial/seat rules allow.
9. Share card link and QR.

### 17.2 Staff daily use

1. Sign in using staff login.
2. Fetch only assigned card and current permissions.
3. Display only allowed editor, link, review and reply screens.
4. View analytics for assigned card.
5. Share QR or vCard.
6. Refresh public preview after successful edits.

### 17.3 Public visitor

1. Open `/card/{slug}` from link or QR.
2. Request the public card endpoint.
3. Display only public data when card and organization are eligible.
4. Use call, WhatsApp, email, website, map and social links.
5. Read approved reviews.
6. Submit a review.
7. Handle duplicate `409` and rate-limit `429` states.
8. Save vCard through the platform share sheet if enabled.

### 17.4 Purchase and renewal

1. Browse services/products and current backend prices.
2. Select plan, seat quantity, variant or add-on.
3. Request server-side cart quote.
4. Show line items, taxes, shipping and total.
5. Create pending order/payment attempt.
6. Launch approved checkout.
7. Show processing state after returning from checkout.
8. Fetch order status from backend.
9. Wait for verified payment and entitlement update.
10. Display order receipt/invoice and next renewal date.
11. Send in-app notification; optional push/email reminders can be added later.

---

## 18. Phased development roadmap

The schedule is indicative and assumes a small cross-functional team plus a backend that can be extended. API gaps, store-policy decisions and scope changes may extend it.

### Phase 0 — Discovery and API audit (1 week)

**Tasks**
- Review current endpoints, response payloads and auth behavior.
- Inspect current MongoDB schemas and indexes.
- Confirm role and permission matrix.
- Decide directory privacy semantics.
- Inventory Bizzvot services and products.
- Decide subscription and renewal policy.
- Classify payment items for app-store compliance.
- Write acceptance criteria and API gap list.

**Deliverables**
- Product requirements baseline.
- Screen map and role matrix.
- API gap register.
- Initial data model.
- Risk and decision log.

**Exit criteria**
- Product owner approves MVP scope.
- Backend auth approach and commerce ownership agreed.

### Phase 1 — UX/UI and foundation (1–2 weeks)

**Tasks**
- Wireframe owner, staff, public and ecommerce flows.
- Create design system and reusable components.
- Create Flutter app and environments.
- Configure routing, error handling, networking and state management.
- Set up code quality, CI and build signing approach.

**Deliverables**
- Approved wireframes.
- Flutter project skeleton.
- CI builds for Android and iOS.
- API client and error mapper.

**Exit criteria**
- Owner/staff/public navigation prototype accepted.

### Phase 2 — Authentication and organization core (2 weeks)

**Tasks**
- Implement native session strategy.
- Register, owner login, staff login and password recovery.
- Role-aware routing and session expiry.
- Dashboard and organization profile.
- Staff CRUD and permissions.

**Deliverables**
- Secure auth.
- Owner dashboard.
- Staff list/editor.
- Permission enforcement in UI and backend tests.

**Exit criteria**
- Tenant isolation and role tests pass.

### Phase 3 — Cards, media, visibility and sharing (2–3 weeks)

**Tasks**
- Card list, detail, editor and preview.
- Templates, colors, section ordering and display toggles.
- Photo, cover, logo, gallery, PDF and YouTube fields.
- QR and vCard.
- Organization directory visibility and per-card visibility.
- Public card deep links and private/public tests.

**Deliverables**
- End-to-end card management.
- Public card experience.
- QR/share flows.
- Directory visibility controls.

**Exit criteria**
- Private fields and private directory entries cannot leak through public endpoints.

### Phase 4 — Reviews and analytics (1–2 weeks)

**Tasks**
- Owner review moderation.
- Staff review permissions.
- Public review submission.
- Reply display.
- Views, unique visitors, rating and link-click charts.

**Deliverables**
- Review list and moderation.
- Public review UI.
- Per-card analytics.

**Exit criteria**
- Duplicate review, moderation and rate-limit tests pass.

### Phase 5 — Catalogue, ecommerce, billing and renewals (3–4 weeks)

**Tasks**
- Service/product catalogue and plan detail.
- Cart quote and checkout.
- Gateway integration.
- Order and invoice screens.
- Seat purchase and entitlement update.
- Subscription detail and renewal.
- Failed payment, grace period and expiry behavior.
- In-app order/payment/renewal notifications.

**Deliverables**
- Purchase journey.
- Order history and payment status.
- Billing and renewal experience.
- Server-verified payment flow.

**Exit criteria**
- Duplicate webhooks, delayed payment confirmation, failed payment and entitlement reconciliation tests pass.

### Phase 6 — QA, security and beta (2 weeks)

**Tasks**
- Device and OS matrix testing.
- API contract and integration testing.
- Accessibility and performance checks.
- Security/privacy review.
- Beta distribution and feedback.
- Fix critical and high-priority defects.

**Deliverables**
- Test report.
- Release candidate.
- Known issues list.
- Privacy/security checklist.

**Exit criteria**
- No blocker or critical defects; release approval recorded.

### Phase 7 — Store release and stabilization (1 week)

**Tasks**
- Store listings, screenshots and privacy disclosures.
- Signing and production configuration.
- Staged rollout.
- API/crash/payment monitoring.
- Rollback and support process.

**Deliverables**
- Production Android and iOS releases.
- Release notes.
- Monitoring and support runbook.

**Exit criteria**
- Production smoke tests pass and rollback path is ready.

**Estimated full scope: 12–17 weeks.** A cards/reviews MVP can be released earlier by moving ecommerce and renewals to a subsequent release.

---

## 19. Suggested release plan

| Release | Features |
|---|---|
| MVP 1 | Authentication, owner dashboard/profile, staff, cards, public/private visibility, QR/vCard, public card, reviews and basic analytics |
| Release 1.1 | Services catalogue, product catalogue, plans, seat purchases, billing status, order history and invoices |
| Release 1.2 | Renewals, grace periods, reminders, upgrade/downgrade, failed-payment recovery and richer commerce |
| Future | Localization, multiple currencies, advanced analytics, additional notification channels and optional offline read-only caching |

---

## 20. Testing and acceptance criteria

### Roles and access
- Owner cannot access another organization’s data.
- Staff cannot access another staff member’s card or billing.
- Public visitor cannot access private fields.
- Hidden UI actions are also rejected by the backend when called directly.

### Directory and card visibility
- Organization directory public/private behavior is correct.
- Inherit/public/private card combinations match the agreed precedence.
- Directory endpoints return only eligible cards.
- Direct URLs and QR behavior match the separately defined card publication policy.
- Private cards do not leak through search, caches, sitemap or analytics.

### Seat/billing
- Trial seat behavior follows the supplied rule.
- Paid organization cannot activate more cards than available slots.
- Billing-disabled cards remain disabled until eligible.
- Verified payment adds the correct entitlement quantity.
- Duplicate payment/webhook events do not duplicate entitlements.

### Reviews
- Pending/approved/hidden states work.
- Public list shows only approved reviews.
- Reply appears publicly where allowed.
- Duplicate review returns `409`.
- Rate limiting returns `429`.
- Reviewer email/IP is not exposed.

### Authentication
- Owner and staff login routes are distinct.
- Session refresh and logout are correct.
- Account lockout is handled without account enumeration.
- Tokens are stored securely if the bearer strategy is selected.
- Expired and revoked sessions are handled.

### Commerce
- Prices and totals are calculated server-side.
- Cancelled, delayed and failed payments are handled.
- Wrong amount/currency and invalid gateway signatures are rejected.
- Orders and invoices show correct status.
- Renewal, expiry, grace period and cancellation rules are tested.

### Media and quality
- Gallery/PDF/video limits enforced.
- Invalid file types and oversized uploads rejected.
- Loading, empty, offline and error states are present.
- Accessibility labels, contrast, text scaling and touch targets reviewed.
- Production logs contain no secrets or private card data.

---

## 21. Team and responsibilities

| Role | Responsibility |
|---|---|
| Product owner | Approve feature scope, visibility semantics, service catalogue, renewal rules, tax/currency and refunds |
| Backend engineer | Auth contract, API additions, MongoDB changes, tenant isolation, payments, entitlements and notifications |
| Flutter engineer(s) | Android/iOS app, UI, API integration, session, media, deep links and checkout |
| UI/UX designer | User flows, design system, catalogue, checkout, public card and accessibility |
| QA engineer | Role/visibility tests, device testing, payment lifecycle, regressions and acceptance evidence |
| DevOps/release owner | Environments, secrets, CI/CD, backups, monitoring, signing, rollout and rollback |

---

## 22. Decisions required before development

1. **Directory privacy:** Does private hide only the people list, or also block direct card URLs and QR scans? Recommended: treat directory visibility and card publication separately.
2. **Visibility precedence:** Can a card be individually public when the organization directory is private?
3. **Ecommerce scope:** Which exact Bizzvot services and products are sold in the app? Which are one-time purchases versus subscriptions?
4. **Renewals:** Manual or automatic, grace period, failed-payment retries, cancellation and refund rules.
5. **Payment compliance:** Which items use Razorpay or another gateway, and which items may be subject to Apple/Google in-app purchase rules?
6. **Currency and tax:** INR only at launch or multiple currencies? Tax-inclusive or tax-exclusive pricing? What invoice fields are required?
7. **Native authentication:** Token-based native session or tested cookie-based approach?
8. **Customer accounts:** Guest checkout or account-required checkout? Organization seat purchases should be linked to an authorized organization owner.
9. **Notifications:** In-app only for MVP, or also push/email renewal reminders?
10. **Current backend:** Confirm existing MongoDB collection names, API payloads, indexes and migration ownership.

---

## 23. Definition of done

The project is ready for release when:

- Android and iOS builds pass the agreed device/OS matrix.
- Owner, staff and public experiences use clear role-specific navigation.
- Existing API routes in scope are mapped to typed repositories and tested.
- New API endpoints have approved contracts and integration tests.
- MongoDB changes are reviewed, indexed, migrated and backed up.
- Directory privacy and tenant isolation are proven by automated tests.
- Public APIs do not leak private card fields or reviewer email/IP.
- Payments are server-verified and idempotent.
- Seat allocation, renewals and entitlements are reconcilable.
- App-store policies, privacy disclosures, monitoring, support and rollback are ready.

---

## Appendix A — Screen inventory

| Area | Screens |
|---|---|
| Auth | Welcome, owner sign-in, staff sign-in, register, forgot/reset password, change password, session expired |
| Owner | Dashboard, organization profile, staff list/editor/permissions, cards list/editor/preview, visibility settings, QR/share, reviews/moderation, analytics, billing/plans, seat purchase, notifications |
| Staff | My card, permitted card editor, links editor, QR/share, reviews/reply if allowed, analytics, security |
| Public | Card, reviews, write review, save contact/share sheet, unavailable state |
| Commerce | Services categories, service detail, product list/detail, variants, plans, cart, checkout, payment pending/result, orders, order detail, invoice, subscription, renewal, failed payment |
| System | Loading, empty, offline, error, permission denied, rate limited, maintenance/update notice |

## Appendix B — Proposed state model

### Order states

Illustrative state machine:

- `draft`
- `pending_payment`
- `paid`
- `processing`
- `fulfilled` or `completed`
- `payment_failed`
- `cancelled`
- `refunded`
- `expired`

Exact states depend on whether the order represents physical goods, a digital service, a seat purchase or a subscription.

### Subscription states

Illustrative states:

- `pending`
- `active`
- `past_due`
- `grace_period`
- `cancelled`
- `expired`

The backend must define allowed transitions, effective dates and the impact of each state on cards and entitlements.

### Visibility values

```json
{
  "organization": {
    "directoryVisibility": "public"
  },
  "card": {
    "visibility": "inherit"
  }
}
```

These fields are proposed schema additions and must be approved by the backend team before implementation.
