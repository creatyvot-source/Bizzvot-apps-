# 12 — Store policy, accessibility & mobile-security-standard compliance

**Scope:** Flutter customer app `/home/user/Bizzvot-apps-` (`lib/**`, `android/**`, `ios/**`, `pubspec.yaml`, `docs/PRODUCT_PLAN.md`, `docs/CONVENTIONS.md`, `docs/API_GAP_REGISTER.md`), cross-checked against the Coglink web/API at `/home/user/cogcard`.
**Audit date:** 11 Oct 2026. The audit is read-only. Other agents are still editing feature screens: 52 files were modified in the working tree during the audit. Line numbers are as of audit time.
**Toolchain observed:** Flutter 3.47.7 / Dart 3.13.5. `flutter.targetSdkVersion = 36`, `compileSdk = 36`, `minSdk = 24` (`/opt/flutter-sdk/flutter/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt`). iOS deployment target 15.0, `TARGETED_DEVICE_FAMILY = "1,2"` (iPhone + iPad).
**Products:** Google Review Stand ₹499, Google Review Card ₹350, Staff ID Card ₹350 and Business Digital + Physical NFC Card ₹999 (all physical NFC), plus digital-card **seats / plan subscriptions / renewals**, sold through Razorpay hosted checkout.

Severity: **B** = store blocker (certain rejection or crash), **H** = high (likely rejection or serious compliance or security gap), **M** = medium, **L** = low or hardening. "Verify after build" marks items whose screens are still stubs.

---

## 1. Summary

The app's engineering foundations are better than average for this stage:

- Tokens are in the Keychain/Keystore, with `first_unlock_this_device`, `allowBackup=false` and cleartext disabled in release.
- Logging is debug-only and redacted.
- URL launching uses an allow-list.
- There is no third-party analytics or ads SDK, so ATT is not needed.
- Android uses the system photo picker and declares no `READ_MEDIA_*` permission.
- Owner account deletion is in the app.
- The theme enforces 48 dp targets, and there is good use of `Semantics`, tooltips and reduce-motion.

Store submission is still **blocked**, mainly by policy and backend gaps rather than code quality:

1. **Digital entitlements can be bought in-app through Razorpay.** Seats, plan subscriptions and renewals all use Razorpay. `PaymentPolicy.defaultFor(plan) = externalDigitalService`, which lets plan and seat checkout through. On iOS that breaks Guideline 3.1.1 on every non-US storefront, and on Google Play it breaks the Payments policy. The "Contact us to purchase" button for blocked digital items is also a call to action to buy outside IAP. Physical NFC products via Razorpay are compliant.
2. **The backend is missing the store-mandated features.** Coglink has no `DELETE /auth/account`, no web account-deletion page (Play requirement), no privacy policy or terms pages, and no `GET /app/config`. The app's default privacy, terms and support links are all `null`, so in-app privacy links open nothing (5.1.1(i)).
3. **The iOS share sheet will crash on "Save Image".** The app shares the QR PNG, and `NSPhotoLibraryAddUsageDescription` is missing.
4. **Release signing and build config are not store-ready.** Android release is signed with the **debug key**, and a release build without `--dart-define=BIZZVOT_ENV=production` points at `http://10.0.2.2:5000`.
5. **Required screens are stubs.** Billing, seat purchase and subscriptions are stubs (`SeatPurchaseScreen` renders only its class name), which fails 2.1 completeness unless finished or hidden.
6. **iOS privacy and entitlement files are missing.** There is no app-level `PrivacyInfo.xcprivacy`, no `Runner.entitlements` (Associated Domains), and no `ITSAppUsesNonExemptEncryption` key.
7. **Apple 1.2 and Play UGC rules are not met.** Public reviews have no "Report" or "Block" control.
8. **Accessibility has gaps.** Success and warning status colours fail WCAG 1.4.3 (2.75–3.3:1). The card-preview text colour rule can produce 2.1:1. User brand colours on the public hero are not checked for contrast. Reorder is drag-only (2.5.7).
9. **There is no i18n.** There are no `localizationsDelegates` or `supportedLocales`, about 340+ hard-coded English strings, physical (LTR-only) insets and alignments, and `en_US` number and date formats (no lakh grouping).

**Recommended payment approach** (detail in §2.2):

- **Physical NFC products and human services:** Razorpay in-app (compliant on both stores).
- **Seats, plan subscriptions and renewals in v1:** consumption-only on iOS and Android. Show status only, with no buy buttons and no "buy on web" links outside the US storefront. Sell them on the web.
- **Later (Phase 2):** add StoreKit/Play Billing tiered subscriptions, or Play User Choice Billing in India.
- **₹999 bundle:** sell it as a physical product with an included first-term digital card, disclosed in App Review notes. Renewals of the digital part are never sold in-app outside IAP.

---

## 2. Apple App Store Review Guidelines

### 2.1 Gap table

| Sev | Guideline | Gap | Evidence | Fix |
|---|---|---|---|---|
| **B** | 3.1.1 | Seat purchase and plan subscription start a Razorpay hosted checkout from inside the app. These are digital entitlements (they unlock card activation and slots used in the app and on the web). | `lib/features/billing/data/billing_repository.dart` (`startSubscription` → `POST /organization/billing`, "Returns the hosted checkout"); `lib/features/subscriptions_renewals/presentation/subscriptions_providers.dart` (`checkoutUri`); `lib/features/catalog/presentation/catalog_item_screen.dart` (`isPlan && !blocksCheckout` → "Choose seats") | On iOS, hide every purchase or renew action for seats and plans (consumption-only). Alternatively implement StoreKit IAP. See §2.2. Verify after build (screens are stubs). |
| **B** | 3.1.1 / 3.1.3 | The stop-gap default classes `plan` as `externalDigitalService`, so plans are **not** blocked. The comment admits "confirm classification before store release". | `lib/features/catalog/domain/catalog_models.dart` `PaymentPolicy.defaultFor` | Default `plan`/`unknown` → `inAppDigital` (blocked). Have the server send `paymentPolicy` plus per-platform `channels` (`ios`, `android`, `web`) per item (API gap COM-4). |
| **H** | 3.1.1 (anti-steering, non-US) | Blocked digital items show "Purchase not available in app yet… **Contact us to purchase it**" and a **Contact us** CTA (mail/phone). That is a call to action toward a non-IAP purchase. | `catalog_item_screen.dart` `_statusNotices`, `_bottomBar`, `_contact` | Hide `inAppDigital` items from the iOS and Android catalogue entirely, or show them as information only with no purchase CTA. Keep "Contact us" for physical goods and services. US storefront only: a link-out is allowed (see §2.2.4). |
| **B** | 5.1.1(v) | The owner deletion UI exists, but `DELETE /auth/account` does not exist in Coglink (`app/api/v1/auth/*` has no account route). App Review will test deletion and get an error. | `lib/features/account/data/account_repository.dart`; `cogcard/app/api/v1/auth/` (no `account`); API gap ACC-1; audit 02 G12 | Implement the backend deletion (revoke sessions, cancel renewals, purge data, keep invoices for legal retention) before submission. |
| **H** | 5.1.1(v) | The owner "Delete account" tile is hidden when the remote flag `accountDeletion=false`. A config change could remove a mandatory feature. | `lib/app/shell.dart` (`if (config.isEnabled(Flags.accountDeletion))`) | Never gate deletion behind a remote flag. Remove the flag or ignore it on iOS and Android. |
| **M** | 5.1.1(v) | Staff "Delete account" only explains "ask your owner". The support-email button appears only if `supportEmail` is configured, and it is `null` by default, so the user may see no actionable path. | `lib/features/account/presentation/delete_account_screen.dart` | Add an in-app "Request deletion" call (e.g. `POST /staff/deletion-request`) that notifies the owner and support and completes within a stated SLA. Always show a fallback contact. |
| **H** | 5.1.1(i) | The privacy policy must be reachable in-app. All legal links come from `GET /app/config` (not implemented in Coglink), with **no compile-time fallback**, so the Privacy and Terms tiles are disabled and the register-screen links open nothing. Coglink has no privacy or terms pages. | `lib/core/config/app_config.dart` (`AppConfig.defaults` all null); `lib/features/account/presentation/legal_screen.dart`; `lib/features/auth/presentation/register_screen.dart` (`_openLegal(config.privacyPolicyUrl)`); audit 06 F17 | Publish `https://www.bizzvot.com/privacy`, `/terms` and `/delete-account`. Add `Env` fallbacks for privacy, terms and support. Enter the same URLs in App Store Connect. |
| **B** | 2.1 (crash) / 5.1.1 | The QR PNG is shared through `UIActivityViewController`. Choosing **Save Image** writes to Photos and needs `NSPhotoLibraryAddUsageDescription`; without it iOS terminates the app. | `ios/Runner/Info.plist` (only `NSPhotoLibraryUsageDescription`, `NSCameraUsageDescription`); `lib/features/cards/presentation/card_share_screen.dart` ("Share QR image"); `lib/features/public_card/data/external_actions.dart` `shareFile` | Add `NSPhotoLibraryAddUsageDescription` ("Bizzvot saves your card's QR code to Photos when you choose Save Image."). |
| **B** | 2.1 completeness | `BillingScreen`, `SeatPurchaseScreen`, `SubscriptionsScreen` and `SubscriptionDetailScreen` are stubs showing only their class name. Many routes depend on PROPOSED endpoints (catalogue, cart, orders, notifications, app config) that Coglink doesn't have, so they will show errors in review. | `lib/features/billing/presentation/seat_purchase_screen.dart` ("STUB"); `billing_screen.dart` (10 lines); `subscriptions_screen.dart`; `docs/API_GAP_REGISTER.md` COM-1, NOT-1, CFG-1 | Ship complete or hidden. Gate unfinished modules with **compile-time** flags for the store build, not only remote flags that "default to enabled" (`AppConfig.isEnabled` returns `true` for unknown keys). |
| **H** | 2.1 | A release build defaults to the `development` flavour (`http://10.0.2.2:5000`, blocked by ATS), so a mis-built binary is non-functional. CI only builds debug/staging. | `lib/app/env.dart` (`defaultValue: 'development'`); `.github/workflows/flutter.yml` | In `kReleaseMode`, refuse the `development` flavour (assert or fall back to production). Add a CI job `flutter build ipa/appbundle --release --dart-define=BIZZVOT_ENV=production`. |
| **H** | 2.1 (review access) | App Review needs working **owner and staff demo accounts** with seeded cards, reviews and analytics, plus a way to see a commerce flow without a real charge. | none (process) | Provide demo credentials in App Review notes. Seed a demo org (trial, 2 staff, cards, approved reviews). Give a 100%-off coupon or a ₹1 test SKU for physical checkout, or explain that payment is a real Razorpay charge for physical goods. |
| **M** | 1.2 UGC | Public reviews (user-generated content) are shown in the app with no **Report** action, no way to block an abusive reviewer, and no published contact on the card page. Pre-moderation (approved-only) and owner moderation help but are not sufficient. | `lib/features/public_card/presentation/widgets/public_reviews_section.dart` (no report); `write_review_screen.dart` | Add a "Report review" action (`POST /public/reviews/:id/report`), owner "Hide/block reviewer", and a support contact in the review section. Document the moderation SLA in App Review notes. |
| **M** | Privacy manifest (ITMS-91053/91061) | There is no app-level `ios/Runner/PrivacyInfo.xcprivacy`. Plugins ship their own manifests: file_picker_darwin 2.1.3, flutter_secure_storage_darwin 0.4.3, image_picker_ios 0.8.13+10, package_info_plus 10.2.2, share_plus 13.3.1, url_launcher_ios 6.4.2. `path_provider_foundation` 2.6.0 (FFI) ships none. Collected-data declarations must match App Privacy labels. | `ios/Runner/` listing; `/root/.pub-cache/hosted/pub.dev/*/…/PrivacyInfo.xcprivacy` | Add `Runner/PrivacyInfo.xcprivacy`: `NSPrivacyTracking=false`, no tracking domains. `NSPrivacyCollectedDataTypes`: Name, Email, Phone, Physical Address, Photos, Purchase History, Customer Support, Other UGC (reviews), Product Interaction. Purpose App Functionality, linked to user, not tracking. Re-run Xcode's privacy report on the archive. |
| **L** | 5.1.1(ii)/(iii) data minimisation | `NSCameraUsageDescription` is declared, but the app only uses `ImageSource.gallery` (`media_picker.dart`). `whatsapp` is in `LSApplicationQueriesSchemes`, though the conventions only allow `https://wa.me`. | `ios/Runner/Info.plist`; `lib/features/cards/data/media_picker.dart` | Remove the camera string (or add camera capture deliberately). Drop `whatsapp` from the queries schemes. |
| **M** | 5.1.2 / PRIVACY | Photos for **public** cards may keep GPS EXIF. On Android, `image_picker_android` copies `TAG_GPS_*` when re-encoding (`ExifDataCopier.java:100-109`). `requestFullMetadata:false` helps on iOS only. | `lib/features/cards/data/media_picker.dart`; `/root/.pub-cache/hosted/pub.dev/image_picker_android-0.8.13+25/.../ExifDataCopier.java` | Strip EXIF server-side on `POST /media/upload` (authoritative). Optionally re-encode client-side without metadata. |
| **L** | ATT (5.1.2(i)) | **Not needed.** There is no IDFA, no ad or attribution SDK, and `track-click` is first-party, unlinked analytics. | `pubspec.yaml` (no analytics or ads SDKs) | Keep it this way. If Firebase Analytics, Meta SDK or attribution is added later, re-assess ATT and the labels. |
| **OK** | 4.8 Sign in with Apple | Not required: email/password only, using the company's own account system. | `lib/features/auth/**` (no social login) | If Google or Facebook login is ever added, add Sign in with Apple or an equivalent privacy-preserving login. |
| **OK** | 4.2 minimum functionality | The app is native, not a web wrapper: card editor, QR and vCard generation, share sheet, analytics charts, reviews. | `lib/features/cards/**`, `analytics/**` | — |
| **M** | 2.3 metadata / 2.3.10 | The brand is fragmented: the web and emails say "Coglink"/"creatyvot" while the app says "Bizzvot" (audit 06 F15). The app supports iPad (`TARGETED_DEVICE_FAMILY "1,2"`), so iPad screenshots and iPad QA are mandatory. | `ios/Runner.xcodeproj/project.pbxproj`; `cogcard/app/layout.tsx` | Rebrand customer-facing web strings to Bizzvot before launch. Either QA on iPad and supply 13" screenshots, or set the device family to iPhone-only (`1`) for v1. Screenshots must show real app UI only, with no prices that differ from in-app ones. |
| **M** | Export compliance | `ITSAppUsesNonExemptEncryption` is absent, so every build asks the question in App Store Connect. | `ios/Runner/Info.plist` | Add `<key>ITSAppUsesNonExemptEncryption</key><false/>` (HTTPS/OS crypto only). |
| **H** | Universal links (functional, 4.x quality) | There is no `Runner.entitlements` and no `CODE_SIGN_ENTITLEMENTS`, so `applinks:` is missing. Coglink serves no `/.well-known/apple-app-site-association`. `FlutterDeepLinkingEnabled=true` is set but inert. | `ios/Runner.xcodeproj/project.pbxproj`; audit 06 F06 | Add Associated Domains `applinks:www.bizzvot.com` and `applinks:bizzvot.com`, and serve AASA with 200 and no redirect. Scope the paths to `/card/*` (hold `/directory/*` until the endpoint ships). |
| **M** | 3.1.2 (if IAP adopted) | There is no restore-purchases, subscription terms, or EULA/privacy link at the paywall. | n/a (future) | Required when StoreKit subscriptions are added. |

### 2.2 Purchasable-item analysis and compliant approach

Current guideline structure: **3.1.1** (IAP for digital functionality, content or subscriptions). **3.1.3(a)–(g)** exceptions: (a) reader, (b) multiplatform, (c) enterprise, (d) person-to-person, (e) goods and services outside the app, (f) free stand-alone, (g) ad management. Older guideline numbering called the physical-goods rule **3.1.5(a)**; it is now **3.1.3(e)**, and current 3.1.5 is cryptocurrencies.

| Item | Nature | Apple rule | Google Play rule | Recommended channel |
|---|---|---|---|---|
| Google Review Stand ₹499, Google Review Card ₹350, Staff ID Card ₹350 | Physical goods (NFC chip, printing, shipping) | **3.1.3(e): must not use IAP.** Razorpay or cards are allowed, as is an in-app Razorpay SDK, `SFSafariViewController`, or an external browser. | Exempt from Play Billing (physical goods) | **Razorpay in-app. Compliant.** The current external-browser checkout plus server-side polling is fine (`lib/features/catalog/data/link_launcher.dart`). |
| Business Digital + Physical NFC Card ₹999 | **Mixed bundle**: physical card plus a digital card (seat or term) used in the app | Grey area. Defensible as a physical good when the digital card is the companion to the hardware and is **not** separately renewable in-app. Disclose it in review notes. | "Primarily physical goods" exemption is likely. Document the rationale. | **v1:** sell it as a physical product with "includes 12-month digital card" (fixed term, server-granted after delivery or activation). **Renewal** of the digital part follows the seat rule below (never Razorpay in-app outside the US). If Apple rejects, split it into a physical card via Razorpay plus a seat via IAP or web. |
| Additional seats (active-card slots) | Digital entitlement unlocking app and web functionality | **3.1.1 applies.** (b) multiplatform only lets users *access* seats bought on the web. Buying in-app still needs IAP. (c) enterprise covers only apps sold directly to organisations for their employees, which does not fit open self-service SMB signup. **(f) free stand-alone** applies if there is no in-app purchasing and no CTA. | Play Billing required. In India, **User Choice Billing** (alternative billing shown next to Play Billing) is available through enrolment. Consumption-only with no link-out is allowed. | **v1: consumption-only on both stores.** Show the seat count, trial and status, and "Seats are managed by your organization's account" (neutral, no link or URL) outside the US. Sell on the web. **Phase 2:** StoreKit 2 auto-renewable tiers (e.g. 1/5/10/25 seats; Apple subscriptions have no quantity) mapped server-side using App Store Server Notifications V2. On Play: Play Billing subscriptions, or Razorpay under UCB in India (UCB still requires offering Play Billing). |
| Plan subscription and renewal (`POST /organization/billing`, `POST /subscriptions/:id/renew`) | Digital subscription | 3.1.1 → IAP, or consumption-only | Play Billing, UCB (India), or consumption-only | Same as seats. The "Renew" button must be hidden or IAP-backed on both stores (verify after build: `subscription_detail_screen.dart` is a stub). |
| Services (setup, design, consulting, printing, delivery) | In-person or human business services | 3.1.3(e) "services consumed outside the app": Razorpay is allowed | Physical-services exemption | Razorpay OK. Digital services done by people (e.g. website build, ads management) are usually accepted as services outside the app, but **verify** each SKU. Never sell an in-app feature labelled as a service. |

**Implementation requirements**

1. Server: every catalogue item carries `paymentPolicy` and `channels: {ios, android, web}`. The app decides what to show from `defaultTargetPlatform` plus channels. It must never default a plan to "external" (COM-4).
2. The app hides, rather than disables, purchase CTAs for blocked items, and shows no "cheaper on web" or "buy on our site" copy outside the US storefront.
3. **US storefront only.** Since the *Epic v. Apple* injunction (Guidelines update of 1 May 2025), apps may include buttons, links and CTAs to web purchases for US users. Apple is appealing, so verify the current status at submission. Since the *Epic v. Google* injunction (effective October 2025), Play allows US link-outs and alternative billing under Google's US programme terms. To use this:
   - Detect the storefront with `SKStorefront.countryCode` (needs a small platform channel or approved plugin).
   - Show the web purchase link only for `USA`.
   - India and the GCC (Bizzvot's markets) get **no** steering.
   - EU (DMA) and Japan (MSCA) alternative-payment entitlements exist but are not relevant to the launch markets.
4. Any IAP adoption needs:
   - App Store Server API and Play Developer API receipt verification feeding the **same** server entitlement ledger. Never grant from the client callback (CONVENTIONS rule 8).
   - Restore purchases.
   - Subscription disclosure text.
   - Handling for account deletion while an Apple subscription is active (tell the user to cancel in Settings).

---

## 3. Google Play

| Sev | Policy | Gap | Evidence | Fix |
|---|---|---|---|---|
| **B** | Payments policy | Same as Apple 3.1.1: seats and plans through Razorpay in the app; the `plan` default is "external"; "Contact us to purchase" for digital items. | see §2.1 rows 1–3 | Consumption-only for digital entitlements in v1, Play Billing in Phase 2, or UCB in India (enrol in Play Console; Play Billing must still be offered side by side). Physical goods and services stay on Razorpay. |
| **B** | Release signing | `release { signingConfig = signingConfigs.getByName("debug") }`. Play rejects debug-signed bundles. | `android/app/build.gradle.kts` | Create an upload keystore (kept out of git, injected in CI) and enrol in Play App Signing. Build `appbundle`. |
| **B** | Account deletion (User Data policy) | Play needs **(a)** an in-app path (UI exists, backend missing) and **(b)** a **web URL** where users can request deletion without reinstalling, entered in the Data safety form. Coglink has neither. | `cogcard/app/api/v1/auth/` (no account route); no `/delete-account` page | Implement `DELETE /auth/account` and publish `https://www.bizzvot.com/delete-account` (form plus email verification, covering owners and staff, listing what is deleted and retained, e.g. GST invoices). |
| **H** | Data safety form | There is no inventory of data types yet. | n/a | Declare: Personal info (name, email, phone, address, GSTIN/business name); Financial info → purchase history (card data is handled by Razorpay and not collected by the app); Photos (uploaded); App activity → in-app interactions (`track-click`) and other UGC (reviews); App info → crash logs (once a crash reporter is added). Encrypted in transit: **yes**. Deletion: **yes** + URL. Shared with: Razorpay (payment processing, a service provider). |
| **OK** | Target API level | `targetSdk = flutter.targetSdkVersion` = **36** (Flutter 3.47.7). This meets the 31 Aug 2026 requirement (API 36 for new apps and updates). | `android/app/build.gradle.kts`; `FlutterExtension.kt:34` | Keep it on the Flutter default. Test Android 16 behaviour: edge-to-edge (Flutter handles it; check `SafeArea` on bottom bars), predictive back (`PopScope`), and large-screen resizability. |
| **M** | 16 KB page-size requirement (targetSdk ≥ 35) | Native libraries come from the Flutter engine plus plugin `.so` files (e.g. `jni` 1.1.0 via `path_provider_android`). | `.flutter-plugins-dependencies` | Check the release AAB with APK Analyzer or `zipalign -c -P 16 -v 4` before upload. |
| **OK** | Photo and video permissions | There is no `READ_MEDIA_IMAGES/VIDEO` or `READ_EXTERNAL_STORAGE`. `image_picker_android` uses the system Photo Picker (`photopicker_activity` meta-data) and file_picker uses SAF (`ACTION_OPEN_DOCUMENT`/`GET_CONTENT`). | `android/app/src/main/AndroidManifest.xml`; plugin manifests | Compliant. Do not add media permissions. If camera capture is added, use the `ACTION_IMAGE_CAPTURE` intent (no `CAMERA` permission needed unless declared). |
| **OK** | Exact alarms, foreground services, background location | None declared. | `AndroidManifest.xml` | — |
| **H** | Deep-link verification | `autoVerify` intent filter for `www.bizzvot.com` and `bizzvot.com` on `/card/` and `/directory/`, but Coglink serves no `/.well-known/assetlinks.json`. Verification fails, so Android 12+ opens the browser. | `AndroidManifest.xml:30-41`; audit 06 F06/F26 | Serve `assetlinks.json` (package `com.bizzvot.bizzvot`, **Play App Signing** SHA-256 plus upload key) on both hosts with 200 and no redirect. Check with `adb shell pm get-app-links com.bizzvot.bizzvot`. |
| **M** | UGC policy | Same as Apple 1.2: reviews need in-app reporting and moderation. | §2.1 | Same fix. |
| **M** | App access and target audience | Reviewer credentials are needed. A business app should declare an 18+ target audience so it stays out of Families. | Play Console | Supply owner and staff demo logins in "App access". Set the target age to 18+. |
| **L** | `applicationId` TODO comment | The ID is `com.bizzvot.bizzvot` (it is permanent once published). | `build.gradle.kts` | Confirm the final ID before the first upload. |
| **L** | Backup and transfer | `allowBackup=false` covers cloud backup. With targetSdk ≥ 31, device-to-device transfer still runs unless `dataExtractionRules` exclude it. Restored Keystore-encrypted entries are unreadable, and `SecureTokenStore.read()` already clears them. | `AndroidManifest.xml` | Add `android:dataExtractionRules` excluding the `FlutterSecureStorage` prefs from `device-transfer`. |

---

## 4. NFC scope recommendation

**Current state.** The app has no NFC capability: no `android.permission.NFC`, no `uses-feature android.hardware.nfc`, no Core NFC entitlement and no `NFCReaderUsageDescription`. Checkout only captures **personalisation** (`NfcTarget.card|review`, per-unit name, designation and logo) for factory encoding (`lib/features/catalog/domain/physical_models.dart`). Audit 06 recommends a stable redirect layer `https://www.bizzvot.com/t/{tagId}` with chips **locked at fulfilment**.

**Recommendation for v1: no NFC read or write in the app.**

- Tags are encoded and locked by Bizzvot at fulfilment with `/t/{tagId}`. Every NFC phone opens the URL natively: iPhone XS+ reads NDEF in the background, and Android tag dispatch falls back to `ACTION_VIEW`. Re-pointing (card ↔ Google review link) is done **server-side** from the app ("Assign / re-point product"), so no write is needed.
- **Activation** works without NFC. The owner opens "My products", scans the **QR on the packaging**, or enters the printed code. That calls `POST /nfc-tags/:id/claim`, then the owner assigns the tag to a card or a Google review URL.
- Writing NDEF from customer phones is **not recommended**:
  - unlocked tags could be rewritten by anyone, including phishing on review stands;
  - writing needs a new plugin (e.g. `nfc_manager`, which needs approval under CONVENTIONS);
  - writing adds an iOS entitlement and review surface;
  - iPhone NDEF writing is less reliable for consumers.

**Optional v1.1 "Test my tag" (read-only):**

| Platform | Requirement |
|---|---|
| Android | `<uses-permission android:name="android.permission.NFC"/>` and `<uses-feature android:name="android.hardware.nfc" android:required="false"/>`, so the app still installs on phones without NFC. Use foreground dispatch or reader mode while the screen is open. |
| iOS | `com.apple.developer.nfc.readersession.formats = [NDEF]` in `Runner.entitlements`; the NFC Tag Reading capability on the App ID; `NFCReaderUsageDescription` ("Bizzvot reads your Bizzvot NFC product to confirm it's linked to your card."); iPhone 7+ only, with a QR fallback. |
| Validation | Accept only `https://www.bizzvot.com/t/…` or `/card/…`, and show the resolved destination from the server. Never auto-open other URLs read from a tag (phishing). |
| Excluded | No `NDEF write`/`lock` in customer builds. A separate internal fulfilment tool (or factory encoder) handles writing and permanent locking. |

Add `/t/*` handling to the router and the AASA/assetlinks config only after the web resolver exists. As audit 06 F21 notes, `/t/*` should resolve on the web first.

---

## 5. Accessibility — WCAG 2.2 AA / EN 301 549 (clause 11, software)

Contrast is computed against the theme tokens (`lib/app/theme.dart`), light surface `#F8F9FC` / card `#FFFFFF`, dark surface `#0F1117`.

| Token | on white | on light surface | on dark surface |
|---|---|---|---|
| brand `#4F46E5` | 6.29 ✓ | 5.97 ✓ | 3.00 (dark uses `#A5B4FC` = 9.47 ✓) |
| accent `#FF7A59` (also `tertiary`) | **2.57 ✗** | 2.44 ✗ | 7.35 |
| success `#16A34A` | **3.30 ✗ text** | 3.13 | 5.73 |
| warning `#D97706` | **3.19 ✗ text** | 3.03 | 5.92 |
| star `#F5A623` | **2.03 ✗ non-text** | 1.93 | 9.31 |
| StatusChip success (text on 12% tint) | **2.89 ✗** | 2.76 | 4.98 |
| StatusChip warning (text on 14% tint) | **2.75 ✗** | — | 5.03 |
| White on hero gradient (`#4F46E5`→`#7C3AED`) | 6.29 / 5.70 ✓; subtitle white @85% = 5.00 ✓; `Colors.white70` outline on brand = 3.93 (OK for borders, fails small text) | | |

| Sev | WCAG / EN 301 549 | Gap | Evidence | Fix |
|---|---|---|---|---|
| **H** | 1.4.3 Contrast (min) / 11.1.4.3 | Status chip text (success and warning) is 2.75–2.89:1 in light mode. The same tokens are used for text in payment status and analytics legends. | `lib/shared/widgets/ui_kit.dart` `StatusChip`; `lib/features/catalog/presentation/common/commerce_widgets.dart` `toneColors`; `payment_status_screen.dart:129,148`; `card_analytics_screen.dart:150-167` | Add `successText #166534` (7.1:1 on white, 5.95:1 on the 12% tint) and `warningText #92400E` (7.1:1 / 5.9:1). Lighter `#15803D`/`#B45309` reach 5.0:1 on white but only about 4.27:1 on the tint, so they still fail inside chips. Or use M3 `onTertiaryContainer`-style tonal pairs. Keep the bright tokens for icons only (≥3:1). |
| **H** | 1.4.3 | The card-preview foreground rule `luminance > 0.45 ? black : white` gives a worst case of **2.1:1** (mid-luminance brand colours). | `lib/features/cards/presentation/widgets/card_preview.dart:21` | Choose the foreground by comparing actual contrast ratios: pick black or white, whichever is higher. The crossover is about luminance 0.179. |
| **M** | 1.4.3 / 1.4.11 | The public-card hero gradient uses the **owner's raw brand colour** (`start = seed`) behind white text. Yellow or light brands fail. | `lib/features/public_card/presentation/widgets/card_hero.dart` `heroGradientFor` | Clamp hero lightness so white text is ≥4.5:1 (darken in HSL until the ratio passes), or add a scrim. Warn in the card editor's `BrandColorPicker` when the chosen colour can't reach 4.5:1. |
| **M** | 1.4.11 Non-text contrast | Rating stars `#F5A623` are 2.03:1 on white. The filled/outline difference is carried by colour plus shape, and the semantic label exists. Floating app-bar buttons (white icon on 28% black disc) fall to about 1.9:1 over light cover photos. The accent `#FF7A59` is used as a data colour. | `star_rating.dart`; `public_card_screen.dart:150-153`; `dashboard_screen.dart:292` | Darken the star to about `#B7791F` (3.64:1), or add a 1 px darker outline. Raise the disc to about 55% black, or add an outline. Use accent only with a ≥3:1 neighbour. |
| **M** | 2.5.7 Dragging movements (new in 2.2) | Link and section reordering is **drag-only** (`ReorderableDragStartListener`). Flutter adds screen-reader move actions, but pointer users get no single-tap alternative. | `lib/features/cards/presentation/widgets/editor_widgets.dart:213-235, 578-600` | Add "Move up" and "Move down" items to each row's overflow menu, or arrow buttons. |
| **M** | 1.4.4 Resize text / 1.4.10 Reflow | The conventions require 200% text scale. Risks: `NavigationBar height: 68` with labels; fixed `height: 140` gallery tiles and `height: 36/40/48` boxes containing text; `StatTile` value `maxLines: 1`. | `theme.dart` `navigationBarTheme`; `card_sections.dart:96,344,362`; `editor_widgets.dart:502`; `card_preview.dart:412,471` | Run golden or widget tests at `TextScaler.linear(2.0)` on every main screen (add to the feature test suites). Replace fixed heights around text with `minHeight` constraints. |
| **L** | 1.4.4 | `TextScaler.noScaling` on avatar initials. This is acceptable because they are decorative, inside a fixed circle, and announced by `Semantics(label: 'Photo of …')`. | `public_widgets.dart:112` | No change. Keep the semantic label. |
| **M** | 4.1.2 Name, Role, Value / 1.3.1 | Good coverage: 70 `Semantics` uses, tooltips on all `IconButton`s, `SectionHeader` marks headers, `StatTile` merges its label, star input is adjustable, 18 `semanticLabel`s. Gaps: the "More" screen group headers are plain `Text` (not `header: true`); the `InitialsAvatar` in `ui_kit.dart` exposes raw initials; payment and status changes are not announced. | `lib/app/shell.dart` `header()`; `ui_kit.dart` `InitialsAvatar`; `payment_status_screen.dart` | Wrap the More headers in `Semantics(header: true)`. Give `InitialsAvatar` a `semanticsLabel` of the name, or exclude it when the name is adjacent. Use `SemanticsService.sendAnnouncement`/live regions for payment status transitions and form-error summaries (3.3.1, 4.1.3). |
| **L** | 2.4.11 Focus not obscured (new in 2.2) | Floating snackbars and sticky bottom bars (catalogue and checkout) can cover a focused field when the keyboard or switch access moves focus. | `theme.dart` `snackBarTheme` floating; `catalog_item_screen.dart` `_bottomBar` | Test with a keyboard or switch access. Use `Scrollable.ensureVisible` with padding equal to the bottom-bar height. |
| **L** | 2.3.3 / 2.2.2 Motion | The skeleton pulse continues with reduce-motion on (only the opacity is fixed). The page transitions are the platform defaults. | `ui_kit.dart` `_SkeletonBoxState` | Don't start `repeat()` when `MediaQuery.disableAnimations` is true. |
| **OK** | 2.5.8 Target size (min) / 11.2.5.8 | `minTap = 48`, `MaterialTapTargetSize.padded`, button min height 52, `IconButton` min 48, star buttons 48. | `theme.dart` | Keep these. Watch `StatusChip` if it becomes tappable, and `SegmentedButton` (min 44 high ≥ 24 ✓). |
| **OK** | 3.3.8 Accessible authentication (new in 2.2) | Password fields allow paste and autofill (`autofillHints`); no CAPTCHA or cognitive test. | `lib/features/auth/presentation/widgets/password_field.dart` | Keep these. The "Type DELETE" step is a confirmation, not authentication. |
| **M** | EN 301 549 11.5.2 / 11.7 | System-setting tests are not part of CI: Bold Text, Increase Contrast, Smart Invert, Android colour correction, TalkBack/VoiceOver walkthroughs. | `test/**` | Add an accessibility checklist to the Phase 6 QA plan (`PRODUCT_PLAN.md` §19). Use `meetsGuideline(androidTapTargetGuideline / iOSTapTargetGuideline / textContrastGuideline / labeledTapTargetGuideline)` in widget tests. |

---

## 6. OWASP MASVS v2 mapping

| Control | Status | Evidence | Gap / fix | Sev |
|---|---|---|---|---|
| **MASVS-STORAGE-1** (sensitive data stored securely) | Mostly met | Tokens in `flutter_secure_storage`, `KeychainAccessibility.first_unlock_this_device` (`lib/core/secure_storage/token_store.dart`). Addresses are also kept in secure storage (`lib/features/cart_checkout/data/address_store.dart`). | Writes are not atomic (two keys), see audit 02. | L |
| **MASVS-STORAGE-2** (no leakage) | Partial | `allowBackup=false`; no SharedPreferences; logging is debug-only with bodies and headers off (`buildDio`). | (a) Saved addresses (`bv.addresses.<user>`) **survive logout and account deletion**: neither logout nor deletion wipes them. On deletion call `deleteAll()` for user-scoped keys. (b) vCard and QR temp files from `PlatformExternalActions.shareFile` stay in `getTemporaryDirectory()` (contain PII); `share_service.dart` cleans its own dir, `external_actions.dart` does not. Delete after share. (c) The app-switcher snapshot is not masked; optional `FLAG_SECURE`/blur on billing and checkout screens. (d) Add `dataExtractionRules` (see §3). | M |
| **MASVS-CRYPTO-1/2** | Met (no custom crypto) | OS keystore only; UUID v4 from `Random.secure` for idempotency (`commerce_runtime.dart`). | — | — |
| **MASVS-AUTH-1** (secure auth protocol) | Depends on backend | Bearer plus rotating refresh, single-flight refresh, `noRefresh` flags (`lib/core/api/api_client.dart`). | The backend doesn't return native tokens yet (AUTH-1/2, audit 02). Change-password logs the user out (audit 02 G7). | H (backend) |
| **MASVS-AUTH-2** (local auth) | N/A | No biometric unlock. | Optional: a biometric gate before billing or account deletion. Not required. | L |
| **MASVS-AUTH-3** (step-up for sensitive ops) | Met for deletion | Deletion needs the password plus typing DELETE (`delete_account_screen.dart`). | Consider password re-entry before changing the staff-permissions owner email (backend). | L |
| **MASVS-NETWORK-1** (TLS everywhere) | Met in release | `usesCleartextTraffic=false` (main), `true` only in the debug manifest; iOS ATS default; prod and staging URLs are `https`. | The dev default `http://10.0.2.2` could ship if the flavour isn't set. Add a release-mode guard (§2.1). | H |
| **MASVS-NETWORK-2** (pinning) | Not implemented | No pinning; Android API 24+ ignores user CAs by default. | **Recommendation:** pinning is **not required** for L1 or for this risk profile, because payments are server-verified and the card is hosted by Razorpay. If adopted, pin **SPKI of the intermediate CA(s) plus a backup pin**, add a remote kill switch through `/app/config`, and never pin Razorpay or third-party hosts. Prefer Android `network_security_config` `<pin-set expiration=…>` and iOS `NSPinnedDomains` (Info.plist) over Dart-level pinning, so OS networking (url_launcher, image loads) is also covered. | L |
| **MASVS-PLATFORM-1** (IPC / deep links) | Partial | Deep links are limited to `https` `/card/` and `/directory/` (Android filter). Routes are encoded with `Uri.encodeComponent`; public routes need no session; the router redirect blocks role-mismatched paths. | `MainActivity` is `exported` with `flutter_deeplinking_enabled`, so an **explicit intent** from any app can push *any* URI (e.g. `/o/account/delete`, `/reset-password?token=…`, `/o/checkout`) into go_router. The host is not checked in `resolveRedirect`. Effect is limited (session and password required), but the reset-password screen can be pre-filled with an attacker token (account-confusion). Fix: in `resolveRedirect`, when `uri.hasScheme`, allow only `https` + host ∈ {www.bizzvot.com, bizzvot.com} + path ∈ {`/card/*`, `/directory/*`, `/reset-password`}; map everything else to home. | M |
| **MASVS-PLATFORM-2** (WebViews) | Met | Checkout and documents open in the external browser (`LaunchMode.externalApplication`, https-only `safeHttpsUri`). The app has no WebView (url_launcher's `WebViewActivity` is unused). | If Razorpay switches to an in-app SDK or Custom Tab, keep it out of WebViews that share cookies. | — |
| **MASVS-PLATFORM-3** (UI: sensitive data, overlays) | Partial | Auth fields have `autocorrect:false` and `enableSuggestions:false`; passwords are obscured. | No tapjacking protection on the Android "Delete account" or payment buttons (`filterTouchesWhenObscured`). This is optional hardening. | L |
| **MASVS-CODE-1/2** (up-to-date platform, updates) | Met | targetSdk 36, minSdk 24, iOS 15; force-update gate (`app_gate.dart`). | The store URLs for "Update now" come only from remote config. Add compile-time fallbacks (App Store ID, Play URL). | L |
| **MASVS-CODE-3** (dependencies) | Met / process | `pubspec.lock` committed; no unapproved packages. | Add `flutter pub outdated` plus OSV/Dependabot to CI. | L |
| **MASVS-CODE-4** (input validation) | Met | Defensive JSON helpers, `Validators.isSafeWebUrl`, `ContactLinks.isAllowed` allow-list, `Uri.encodeComponent` in `Endpoints`. | — | — |
| **MASVS-RESILIENCE-1..4** | Not implemented | No root or jailbreak checks, no obfuscation flags in CI, no attestation. | Build releases with `--obfuscate --split-debug-info=build/symbols` (upload symbols to the crash reporter). Consider **Play Integrity + App Attest** on `POST /public/card/:slug/review` and on login to cut review spam and credential stuffing (server-verified tokens). Root detection is not recommended (low value, false positives). | L–M |
| **MASVS-PRIVACY-1** (minimisation) | Partial | The review form collects only name and comment; phone is optional at register; GSTIN optional. | GPS EXIF on public images (§2.1); unused camera purpose string. | M |
| **MASVS-PRIVACY-2** (de-identification) | Partial (backend) | Reviewer IP and email are never shown (CONVENTIONS rule 7). | The server must hash or aggregate visitor identifiers (plan §10). | M (backend) |
| **MASVS-PRIVACY-3** (transparency) | Gap | The analytics-disclosure link exists but is null by default. | Fallback URLs (§2.1). App Privacy and Data safety labels (§2.1, §3). | H |
| **MASVS-PRIVACY-4** (user control) | Partial | Owner deletion UI exists. | Backend deletion, web deletion URL, staff request flow, local wipe on deletion. | H |

Crash reporting is not wired yet (`bootstrap.dart` `TODO(release)`). When it is added (Crashlytics or Sentry), scrub PII and tokens, disable IP collection, declare "Crash logs / Diagnostics" in both labels, and confirm the SDK ships its own privacy manifest. Note that `bootstrap.dart` references `docs/SECURITY.md`, which does not exist.

---

## 7. Localisation and i18n readiness (English, Malayalam, Hindi, Arabic RTL for the Gulf)

| Sev | Area | Gap | Evidence | Fix |
|---|---|---|---|---|
| **H** | Framework | `MaterialApp.router` has no `localizationsDelegates`, `supportedLocales` or `locale`, so Material and Cupertino widgets stay in English, there is no Arabic RTL `Directionality`, and the date picker and text fields are not localised. `flutter_localizations` is not in `pubspec.yaml`. | `lib/app/app.dart`; `pubspec.yaml` | Add `flutter_localizations` (SDK; needs package approval) and `generate: true` with `l10n.yaml` (gen-l10n is SDK tooling, not build_runner). Set `supportedLocales: en, en-IN, ml, hi, ar`. |
| **H** | Strings | About 340+ hard-coded UI literals across `lib/**`, plus manual pluralisation (`'$i ${i == 1 ? 'star' : 'stars'}'`, `star_rating.dart`) and English-only validators (`validators.dart`). | `grep "Text('"` etc. | Extract to ARB with ICU plurals and selects. Validators return keys, not sentences. Server error messages need `error.code` mapped to localised text (AUTH-4). |
| **M** | RTL layout | Physical directions: `EdgeInsets.only(left/right)` (`reviews_screen.dart:79`, `card_editor_screen.dart:566`, `cards_list_screen.dart:213`, `public_card_screen.dart:181`, `star_rating.dart:105`); `Alignment.centerLeft/Right` (`catalog_item_screen.dart:176`, `checkout_screen.dart:383`, `card_editor_screen.dart:871,915,946`, `editor_widgets.dart:263`); `Positioned(right:)` (`card_editor_screen.dart:1079`); hero gradients `topLeft→bottomRight`. | as listed | Use `EdgeInsetsDirectional`, `AlignmentDirectional`, `PositionedDirectional`. Mirror directional icons (`chevron_right`, `open_in_new` are auto-mirrored in Material Icons only for some glyphs; check with `Directionality.rtl` goldens). |
| **M** | Number and currency | `Money.format()` passes `locale: null`, so Intl's default `en_US` gives ₹1,499,999.00 instead of the Indian `₹14,99,999.00`. Gulf currencies are handled (`decimalDigits` from ISO, so KWD/BHD/OMR = 3), but the symbol position and Arabic digits need the `ar` locale. | `lib/features/catalog/domain/money.dart:186-194`; `card_analytics_screen.dart:123` | Set `Intl.defaultLocale` from the app locale (`en_IN` default for India). Pass `Localizations.localeOf(context)` into `Money.format`. Decide per market whether Arabic uses Western or Eastern digits. |
| **M** | Dates and times | `DateFormat.yMMMd()` with no locale gives US order ("Oct 11, 2026"). Times (`add_jm`) are 12h. | `formatting.dart:22-25`, `reviews_screen.dart:332`, `card_detail_screen.dart:362`, `dashboard_screen.dart:106`, `public_reviews_section.dart:182`, `card_analytics_screen.dart:266,333,419` | Use locale-aware formats (`DateFormat.yMMMd(locale)`) and respect `MediaQuery.alwaysUse24HourFormat`. Show renewal dates with the timezone stated (server stores UTC). |
| **M** | Fonts | Inter has no Malayalam, Devanagari or Arabic glyphs, so the system font is used as fallback (mixed metrics; Malayalam conjuncts are tall and need line-height). | `pubspec.yaml` fonts; `theme.dart` `fontFamily: 'Inter'` | Bundle Noto Sans Malayalam, Noto Sans Devanagari and Noto Sans Arabic (OFL) as `fontFamilyFallback`. Set `height` ≥1.4 for `ml`/`hi`. Check text expansion (Malayalam is about 30–40% longer). |
| **L** | Store listings | There are no localised store listings or `CFBundleLocalizations`. | `ios/Runner/Info.plist` | Add `CFBundleLocalizations` (en, ml, hi, ar) and localised permission strings (`InfoPlist.strings`) when the languages ship. |
| **L** | Input | Phone validation is permissive (`^\+?[0-9 ()-]{7,20}$`) and accepts Gulf formats. GSTIN is India-only. | `validators.dart`; `checkout_screen.dart` | Make GST, place of supply and address formats market-aware (UAE/Qatar have no PIN code; VAT TRN instead of GSTIN). |

The plan lists localisation as "Future" (`PRODUCT_PLAN.md` §19). Retrofitting ~340 strings later costs more than doing it now. Adopt ARB extraction before more feature screens land.

---

## 8. Store-submission checklist

### Apple App Store
- [ ] **Payments:** seats, plans and renewals hidden or consumption-only on iOS outside the US. No "contact us to buy" for digital items. `plan` default → `inAppDigital` (§2.2).
- [ ] Physical NFC products and services: Razorpay checkout works end to end in production; server-verified; refunds, shipping and cancellation policies linked.
- [ ] ₹999 bundle wording: "physical NFC card, includes 12-month digital card". The rationale is written into App Review notes.
- [ ] `DELETE /auth/account` live. Deletion tile not behind a remote flag. Staff request path works.
- [ ] Privacy policy, terms and support URLs live and baked into the app as fallbacks. Same URLs in App Store Connect (Privacy Policy URL, Support URL).
- [ ] `Info.plist`: add `NSPhotoLibraryAddUsageDescription` and `ITSAppUsesNonExemptEncryption=false`; remove the unused `NSCameraUsageDescription` and `whatsapp` query scheme.
- [ ] `Runner/PrivacyInfo.xcprivacy` added. Xcode privacy report reviewed. App Privacy "nutrition label" matches (no tracking).
- [ ] `Runner.entitlements` with Associated Domains (`applinks:www.bizzvot.com`, `applinks:bizzvot.com`). AASA served with 200 and no redirect.
- [ ] No stub screens reachable (billing, seats, subscriptions finished or compile-time hidden). All PROPOSED endpoints the build depends on are deployed.
- [ ] Release build uses `BIZZVOT_ENV=production`, with a release-mode guard against `development`.
- [ ] UGC: report review, block reviewer, and a published contact.
- [ ] Demo owner and staff accounts with seeded data in App Review notes. Coupon or test path for physical checkout.
- [ ] iPad: QA plus 13" screenshots, or iPhone-only device family.
- [ ] Brand consistency (Bizzvot) across app, web card, emails and screenshots.
- [ ] Age rating questionnaire (UGC → mention moderation); Export compliance; Content rights for fonts (Inter OFL bundled ✓).

### Google Play
- [ ] Upload keystore plus Play App Signing; `flutter build appbundle --release --obfuscate --split-debug-info`.
- [ ] Payments: digital entitlements consumption-only (or Play Billing, or UCB in India). Physical via Razorpay.
- [ ] Data safety form completed (§3). Account-deletion **web URL** live and entered.
- [ ] `assetlinks.json` (Play signing SHA-256) on both hosts; `pm get-app-links` shows `verified`.
- [ ] targetSdk 36 ✓; Android 16 edge-to-edge and predictive-back QA; 16 KB page-size check on the AAB.
- [ ] No `READ_MEDIA_*`, `CAMERA`, exact-alarm or foreground-service permissions (✓ today). Keep the merged manifest clean (check `build/app/outputs/logs/manifest-merger-release-report.txt`).
- [ ] `dataExtractionRules` added.
- [ ] App access credentials (owner and staff). Target audience 18+. Content rating questionnaire (UGC).
- [ ] UGC reporting in the app.
- [ ] Store listing: privacy policy URL, support email, screenshots (phone plus 7"/10" if tablets are supported).

---

## 9. Prioritised remediation

**P0: store blockers (before any submission)**
1. Reclassify payments. Change `PaymentPolicy.defaultFor(plan|unknown)` to `inAppDigital`. Add a server `channels` field. Hide seat, plan and renew CTAs and the "Contact us to purchase" CTA on iOS and Android. Document the ₹999 bundle (§2.2). *(App + BE + PO/legal)*
2. Backend `DELETE /auth/account`, a web `/delete-account` page, and privacy and terms pages. Add `Env` fallbacks for the legal and support URLs. Remove the remote flag gate on deletion. *(BE, web, App)*
3. Add `NSPhotoLibraryAddUsageDescription` and `ITSAppUsesNonExemptEncryption`. *(App, 5 min)*
4. Android release signing; release-flavour guard; CI release builds for both platforms. *(App/DevOps)*
5. Finish or compile-time hide the stub billing and subscription screens and any module whose endpoints aren't deployed. *(App)*

**P1: high (same release)**

6. App-level `PrivacyInfo.xcprivacy`; App Privacy and Data safety declarations.
7. Associated Domains entitlement plus AASA and `assetlinks.json` on both hosts.
8. UGC report and block on public reviews (backend endpoint plus UI).
9. Fix contrast tokens: success and warning text pairs, the card-preview foreground algorithm, and clamped brand-colour hero.
10. Deep-link host and path allow-list in `resolveRedirect`.
11. Demo accounts and review notes; iPad decision.

**P2: medium (next sprint)**

12. i18n foundation (`flutter_localizations`, ARB extraction, `en_IN` number and date defaults, directional insets, Noto fallbacks) **before** more screens are written.
13. Wipe user-scoped secure-storage keys and temp share files on logout and deletion; add `dataExtractionRules`.
14. Server-side EXIF stripping on media upload.
15. Non-drag reorder alternative; More-screen header semantics; payment-status announcements; 200% text-scale widget tests and `meetsGuideline` checks.
16. Staff in-app deletion request flow.

**P3: low / hardening**

17. Obfuscated release builds with symbol upload; crash reporter with PII scrubbing plus label updates.
18. Optional Play Integrity / App Attest on public review submission and login.
19. Optional SPKI pinning via `network_security_config` / `NSPinnedDomains` with a kill switch.
20. v1.1 NFC "Test my tag" (read-only) with entitlements as in §4. Never ship NDEF write in customer builds.
21. Phase 2 IAP: StoreKit 2 and Play Billing tiered seat subscriptions on the shared server entitlement ledger, or Razorpay under Play UCB in India.

---

### Evidence index
- Platform: `android/app/src/main/AndroidManifest.xml`, `android/app/src/debug/AndroidManifest.xml`, `android/app/build.gradle.kts`, `ios/Runner/Info.plist`, `ios/Runner.xcodeproj/project.pbxproj`, `ios/Runner/` (no entitlements or privacy manifest)
- Core: `lib/core/api/api_client.dart`, `lib/core/secure_storage/token_store.dart`, `lib/core/config/app_config.dart`, `lib/core/utilities/validators.dart`, `lib/app/env.dart`, `lib/app/bootstrap.dart`, `lib/app/app.dart`, `lib/app/router.dart`, `lib/app/routes.dart`, `lib/app/shell.dart`, `lib/app/theme.dart`, `lib/shared/widgets/ui_kit.dart`
- Commerce: `lib/features/catalog/domain/catalog_models.dart`, `lib/features/catalog/presentation/catalog_item_screen.dart`, `lib/features/catalog/data/link_launcher.dart`, `lib/features/billing/**`, `lib/features/subscriptions_renewals/**`, `lib/features/catalog/domain/money.dart`, `lib/features/catalog/domain/physical_models.dart`
- Privacy: `lib/features/account/**`, `lib/features/cards/data/media_picker.dart`, `lib/features/cart_checkout/data/address_store.dart`, `lib/features/public_card/data/external_actions.dart`
- Backend: `/home/user/cogcard/app/api/v1/auth/` (no account deletion), `/home/user/cogcard/next.config.ts`, no `public/.well-known`
- Related audits: `docs/audit/02-auth-sessions.md` (G7, G12), `docs/audit/06-public-web-nfc.md` (F01, F06, F15, F17, F21, F26)
