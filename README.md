# Bizzvot — customer mobile app

Flutter app (Android + iOS) for Bizzvot organization owners, staff members and public
card visitors, plus the Bizzvot Services & Shop. Talks only to the Bizzvot REST API
(`/api/v1`); MongoDB stays server-side.

- Product spec: [`docs/PRODUCT_PLAN.md`](docs/PRODUCT_PLAN.md)
- Engineering rules: [`docs/CONVENTIONS.md`](docs/CONVENTIONS.md)
- Backend items still to agree: [`docs/API_GAP_REGISTER.md`](docs/API_GAP_REGISTER.md)
- Security & privacy controls: [`docs/SECURITY.md`](docs/SECURITY.md)

## Experiences

| Role | Sign-in | Home |
|---|---|---|
| Organization owner | `POST /auth/login` | Dashboard, cards, people, reviews, billing, shop |
| Staff | `POST /auth/staff-login` | My card (+ editor / links / reviews per permission) |
| Public visitor | none | `/card/{slug}` deep link or QR |

## Run

```bash
flutter pub get
flutter run --dart-define=BIZZVOT_ENV=development            # http://10.0.2.2:3000/api/v1 (local Coglink portal, Android emulator)
flutter run --dart-define=BIZZVOT_ENV=staging
flutter run --dart-define=BIZZVOT_ENV=production   # https://www.bizzvot.com/api/v1 (Bizzvot web portal)
flutter run --dart-define=BIZZVOT_API_BASE=https://my-api/api/v1 --dart-define=BIZZVOT_WEB_HOST=my-web
```

## Quality gates

```bash
flutter analyze
flutter test
```

CI (`.github/workflows/flutter.yml`) runs analyze + tests and debug Android/iOS builds.

## Structure

```
lib/app/       router (role-aware guards), shell, theme, env
lib/core/      API client (envelope, errors, single-flight refresh), auth/session, secure storage
lib/shared/    shared models and widgets
lib/features/  auth, dashboard, organization_profile, staff, cards, directory_visibility,
               public_card, reviews, analytics, billing, catalog, cart_checkout, orders,
               subscriptions_renewals, notifications
```

## Release checklist (not yet done)
- Backend sign-off on every item in the API gap register (notably native auth tokens, AUTH-1).
- Production signing (Android keystore, iOS team/provisioning) and app icons.
- iOS Associated Domains entitlement (`applinks:www.bizzvot.com`, `applinks:bizzvot.com`) and the web host's
  `apple-app-site-association` / `assetlinks.json` for `/card/*` deep links.
- App Store / Play payment-policy classification for every purchasable item (plan §12.6).
- Crash reporting with PII scrubbing; store privacy disclosures.
