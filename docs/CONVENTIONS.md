# Bizzvot app — engineering conventions

Source of truth for product scope: `docs/PRODUCT_PLAN.md` (the development plan).

## Stack
Flutter 3.47 / Dart 3.13, Material 3, **Riverpod 3** (`flutter_riverpod`, no codegen),
`go_router` 18, `dio` 5, `flutter_secure_storage`, `url_launcher`, `share_plus`,
`image_picker`, `file_picker`, `fl_chart`, `intl`, `path_provider`. Tests: `flutter_test` + `mocktail`.
Do **not** add packages without approval; no `build_runner`/codegen — models are hand-written.

## Layout
```
lib/app/        bootstrap, router (all routes), shell (tabs, More), theme, env, routes
lib/core/       api client + endpoints, auth/session, errors, secure storage, utilities
lib/shared/     shared models (card, organization, review, paged) and widgets
lib/features/<feature>/
  data/          <feature>_repository.dart  (only place that calls ApiClient)
  domain/        feature-specific models
  presentation/  screens + widgets + providers (<feature>_providers.dart)
test/features/<feature>/  unit + widget tests
```

## Rules
1. **Screens never call HTTP.** UI → providers → repository → `ApiClient`. Use paths from
   `lib/core/api/endpoints.dart` only. Repositories receive `ApiClient` via
   `ref.watch(apiClientProvider)`.
2. **Envelope:** `ApiClient` already unwraps `{success, data}`; `parse:` receives `data`.
   Parse with the defensive helpers in `lib/core/utilities/json.dart` (`asJson`, `str`, `intOr`, `idOf` …).
   Never `as`-cast API data.
3. **Errors:** everything surfaces as `AppException` (`kind`, safe `message`, `retryAfter`).
   Use `AsyncValueView` / `ErrorView` / `EmptyView` / `LoadingView` (`lib/shared/widgets/state_views.dart`)
   and `showError` / `showMessage` / `confirmAction` / `BusyButton` (`lib/shared/widgets/feedback.dart`).
   Handle `409` (conflict/duplicate — don't retry), `429` (cooldown, honor `retryAfter`, disable submit),
   `403` (restriction, no private details), `410` (retired).
4. **Session-scoped caches:** any provider holding private account data must
   `ref.watch(sessionKeyProvider)` so it resets on logout/account switch.
5. **Roles:** current user = `ref.watch(currentUserProvider)` (`AuthUser` with `role`, `cardId`,
   `permissions`). Hide UI the user can't use, but assume the backend enforces it.
   After a change that may alter permissions, call `sessionControllerProvider.notifier.refreshUser()`.
6. **Navigation:** use `context.push/go` with `Routes.*` helpers (`lib/app/routes.dart`).
   Screen class names and constructor signatures in `lib/app/router.dart` are fixed.
7. **Privacy:** private card details (blood group, father/mother name) never on public surfaces.
   Never show reviewer email/IP. Never log tokens, bodies, or personal data (`debugPrint` of models forbidden).
8. **Money & entitlements:** prices, totals, taxes, seat counts and payment status come from the
   server. Never compute a final price client-side or mark something paid from a gateway callback.
9. **URLs:** only open `http(s)`, `tel:`, `mailto:`, `https://wa.me/` links; validate with
   `Validators.isSafeWebUrl` before launching user-supplied URLs.
10. **UI:** modern Material 3 design system in `lib/app/theme.dart` (Inter font, `AppColors`,
    `AppSpacing`, `AppRadius`, `AppMotion`). Use the UI kit in `lib/shared/widgets/ui_kit.dart`:
    `SectionHeader`, `StatTile`, `StatusChip` (+`StatusTone`), `InitialsAvatar`, `HeroHeader`,
    `SkeletonBox`/`SkeletonList` (prefer skeletons over spinners for first loads). Feature flags and
    legal/support links come from `currentConfigProvider` (`lib/core/config/app_config.dart`) — never hard-code them.
    Use `Theme.of(context)`; spacing from `AppSpacing`; wrap page bodies in
    `ContentWidth`; min tap target 48dp; every icon-only button has a `tooltip`;
    support pull-to-refresh on lists; text must survive 200% text scale (no fixed-height text boxes).
11. **Lints:** `flutter analyze` must be clean. Prefer `const`, `final`, small widgets.
12. **Tests:** each feature ships repository parsing tests (fake `ApiClient` via a Dio
    `HttpClientAdapter` stub or mocktail) and at least one widget test of a main screen.
