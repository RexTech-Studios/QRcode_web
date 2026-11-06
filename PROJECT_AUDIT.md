# PROJECT_AUDIT — ReviewQR / FullStar QR

Read-only audit. Date: 2026-11-05. Repo: `main` @ `b368dd3` plus uncommitted edits (`generate_qr_screen.dart`, `my_qr_codes_screen.dart`, `pubspec.yaml`, `pubspec.lock`, `.firebase/hosting.*.cache`, untracked `test/qr_export_resolution_test.dart`).

**Method and limits.** Everything below comes from reading source, config and `git`. Nothing was built, run, deployed or queried against live Firebase, so anything about runtime behaviour or console settings is marked *unverified*. **No secret values are reproduced.** Secrets are cited by file:line and type only.

---

## A. Summary

ReviewQR is a single Flutter **web** app (Provider state, Hive local cache, Firestore cloud store) hosted on Firebase Hosting at `qrcode-16b68.web.app`. One bundle contains **both** the public customer page and the admin dashboard.

**Customer flow.** A shop owner prints a QR code that encodes `https://qrcode-16b68.web.app/#/review/<shopId>` (`qr_service.dart:19,23`). Scanning it loads the Flutter app, `main()` initialises Hive and Firebase, and `onGenerateInitialRoutes` (`main.dart:84-92`) matches `/review/<id>` and shows `ReviewScreen`. The page loads the shop from the Hive cache or Firestore `shops/{id}`, shows a 1-5 star form, and on submit:

1. Writes a `feedback` doc to Firestore (`firebase_service.dart:138-144`).
2. For 4-5 stars, opens the shop's Google review URL (`review_screen.dart:154-159`).
3. For 1-3 stars, POSTs the rating and comment to a Google Apps Script endpoint, which appends a row to the shop's own Google Sheet (`review_screen.dart:189-197`).

**Admin flow.** Any other URL, including `/`, shows a Splash then `DashboardScreen` (`main.dart:87-91`). There is **no authentication of any kind**. The dashboard has five tabs held in an `IndexedStack`:

| Tab | State |
|---|---|
| Generate QR | Real |
| My QR Codes | Real |
| Shops | "Coming soon" placeholder |
| Analytics | "Coming soon" placeholder |
| Settings | Counts and JSON/PDF export |

Generate QR creates the shop (which also asks Apps Script to create a Google Sheet), writes `shops/{id}` and `qr_codes/{id}`, and offers a PNG download. Firestore is the source of truth and Hive mirrors it.

**Bottom line for the planned `/app/` + admin-login move:** today the Firestore rules are `allow read, write: if true` for `shops` and `qr_codes`, and `allow read: if true` for `feedback`. The login screen would only hide UI. The rules are the real boundary, and they currently are not one.

---

## B. File-by-file responsibility table

Status: **active** = reachable from the running app, **dead** = no callers found by grep, **unclear** = needs a decision.

### `lib/`

| Path | Purpose | Depends on | Status |
|---|---|---|---|
| `main.dart` | Init Hive + Firebase, `MultiProvider`, `MaterialApp`, route table | all providers, `ReviewScreen`, `DashboardScreen`, `SplashScreen`, `ViewportCompensator` | active |
| `firebase_options.dart` | FlutterFire config for web/android/ios (project `qrcode-16b68`) | `firebase_core` | active |
| `models/shop_model.dart` (+`.g.dart`) | Hive type 0; `toMap`/`fromMap` for Firestore | `hive` | active |
| `models/qr_code_model.dart` (+`.g.dart`) | Hive types 1 (enum `QRStyle`) and 2 (`QRCodeModel`) | `hive` | active |
| `models/settings_model.dart` (+`.g.dart`) | Hive type 3: `businessName`, `selectedTheme`, `cloudSyncEnabled`, `defaultQrStyleName` | `hive` | **dead** (loaded, never read; see G) |
| `providers/navigation_provider.dart` | Enum `DashboardTab` + current tab | — | active |
| `providers/shop_provider.dart` | Shop CRUD, Sheet create/rename/heal, Hive+Firestore write | `ShopModel`, `GoogleSheetsService`, `FirebaseService`, `HiveService`, `QrService` | active |
| `providers/qr_provider.dart` | QR CRUD, short-code (`QR1`..) generation, selected style | `QRCodeModel`, services | active |
| `providers/settings_provider.dart` | Loads/updates `SettingsModel` | `HiveService` | **dead** (nothing reads `.settings`) |
| `screens/splash/splash_screen.dart` | 2.8s animated splash, then `pushReplacement` to `next` | `assets/images/splashscreenicon.png` | active |
| `screens/dashboard/dashboard_screen.dart` | Admin shell: sidebar/drawer + top bar + `IndexedStack` of 5 tabs | all tab screens, `Sidebar`, `TopBar` | active |
| `screens/generate_qr/generate_qr_screen.dart` | Create shop + QR, style picker, PNG export | `ShopProvider`, `QrProvider`, `QrService`, `download_helper` | active |
| `screens/my_qr_codes/my_qr_codes_screen.dart` | QR cards: edit modal, copy link, download PNG, delete, "View/Generate Google Sheet" | providers, `download_helper`, `url_launcher` | active |
| `screens/shops/shops_screen.dart` | "Coming soon" placeholder | `ComingSoonPlaceholder` | active (stub) |
| `screens/analytics/analytics_screen.dart` | "Coming soon" placeholder | `ComingSoonPlaceholder` | active (stub) |
| `screens/settings/settings_screen.dart` | Shop/QR counts + JSON/PDF export | `ExportService`, providers | active |
| `screens/customer/review_screen.dart` | **Public** review page | `FirebaseService`, `GoogleSheetsService`, `HiveService`, `browser_nav_service`, `url_launcher` | active |
| `services/firebase_service.dart` | All Firestore reads/writes (`shops`, `qr_codes`, `feedback`) | `cloud_firestore`, `firebase_options` | active |
| `services/hive_service.dart` | Hive boxes `shops_box`, `qr_codes_box`, `settings_box`, `meta_box`; in-memory "review submitted" set | `hive_flutter` | active (some members dead) |
| `services/google_sheets_service.dart` | HTTP POST to Apps Script: `create_sheet`, `rename_sheet`, `submit_feedback` | `http` | active |
| `services/qr_service.dart` | UUIDs + builds the QR URL | `uuid` | active |
| `services/export_service.dart` | JSON (blob download) and PDF (`Printing.sharePdf`) of shops + QR codes | `pdf`, `printing`, `package:web`, `dart:js_interop` | active (web-only, no conditional import) |
| `services/emailjs_service.dart` | POST to EmailJS REST API (placeholder creds `YOUR_*`) | `http` | **dead** (zero callers) |
| `services/browser_nav_service.dart` / `_web.dart` / `_stub.dart` | History-guard + visibility hooks for the review page | `dart:html` (web variant) | active |
| `services/viewport_info_service.dart` / `_web.dart` / `_stub.dart` | `physicalScreenWidth()` via `window.screen.width` | `dart:html` (web variant) | active |
| `services/download_helper.dart` / `_web.dart` / `_stub.dart` | `downloadBytes()` PNG download | `dart:html` (web variant) | active |
| `utils/app_colors.dart`, `utils/app_theme.dart` | Admin palette / theme (`GoogleFonts.inter`) | `google_fonts` | active |
| `utils/validators.dart` | Google Maps URL check (used); email / WhatsApp / `digitsOnly` helpers | — | partly dead (see G) |
| `widgets/sidebar.dart`, `top_bar.dart` | Admin navigation and Export menu | `NavigationProvider`, `ExportService` | active |
| `widgets/section_card.dart`, `coming_soon_placeholder.dart`, `qr_style_selector.dart` | Shared admin UI | `qr_flutter` | active |
| `widgets/viewport_compensator.dart` | Re-scales the review page when a phone uses "Request Desktop Site" | `viewport_info_service` | active |

### Other directories

| Path | Purpose | Status |
|---|---|---|
| `web/index.html` | Host page: `<base href="$FLUTTER_BASE_HREF">`, conditional manifest link (hidden on review pages) | active |
| `web/manifest.json` | PWA manifest; still boilerplate (`"description": "A new Flutter project."`, theme `#0175C2`) | active, unbranded |
| `functions/` (`index.js`, `package.json`, `.env.example`) | Cloud Function: `feedback` onCreate -> nodemailer email to shop owner | unclear (see G, J) |
| `firestore.rules`, `firestore.indexes.json`, `firebase.json`, `.firebaserc` | Firebase config | active |
| `assets/images/` | `splashscreenicon.png` used; `app_icon.png`, `splashscreeniconn.png` unreferenced in `lib/` or `web/` | partly dead |
| `test/widget_test.dart` | One `Validators` test | active |
| `test/qr_export_resolution_test.dart` | Untracked; checks QR PNG export resolution (needs `image` dev dep) | new, uncommitted |
| `android/`, `ios/` | Flutter scaffolds (bundle id `com.rextech.reviewqr_admin`) | unclear: almost certainly do not compile, see I.12 |
| `.firebase/hosting.*.cache` | Firebase CLI deploy cache | should be untracked (see G) |

### State management

`provider` ^6.1.2. `main.dart:53-69` builds a `MultiProvider` with four `ChangeNotifierProvider`s: `NavigationProvider`, `ShopProvider..loadShops()`, `QrProvider..loadQrCodes()` and `SettingsProvider..loadSettings()`. The `..load*()` cascades are skipped when `isReviewRoute` is true. `lazy` is left at its default (true), so a provider is only constructed when something first reads it.

---

## C. Route table

Routing is manual: `MaterialApp(onGenerateRoute: _generateRoute, onGenerateInitialRoutes: ...)` (`main.dart:77-92`). There is no `go_router` and no named-route table.

| Route (as seen by Flutter) | Screen | Public / admin | Notes |
|---|---|---|---|
| `/review/<shopId>` (exactly 2 segments, first = `review`) | `ReviewScreen` in `ViewportCompensator` | **Public** | `main.dart:38-49`. Real-world URL is `https://qrcode-16b68.web.app/#/review/<shopId>` (hash strategy). Query string is parsed away and ignored. |
| `/` and every other name, including `/review`, `/review/a/b`, typos | `SplashScreen` -> `DashboardScreen` | **Admin, unauthenticated** | `main.dart:87-91`. A mistyped review link lands on the full admin dashboard. |
| Dashboard tabs (Generate QR, My QR Codes, Shops, Analytics, Settings) | Selected via `NavigationProvider`, not the URL | Admin | `dashboard_screen.dart:21-30`. All five screens are built at once by `IndexedStack`. |
| Edit/Delete dialogs | `showDialog` | Admin | `my_qr_codes_screen.dart` |

- **Query params:** none are read anywhere. There is no `?shop=` support. Grep for `queryParameters` / `shop=` in `lib/` returned nothing.
- **URL strategy:** default **hash**. No `setUrlStrategy` / `usePathUrlStrategy` call exists in `lib/`. `build/web/index.html` has `<base href="/">`.
- **`isReviewRoute` (`main.dart:25-28`)** reads `Uri.base.pathSegments.first == 'review'`. With hash URLs the path is `/`, so this is always `false` on a real QR scan. It is harmless today because `ReviewScreen` reads no provider and providers are lazy, so the "fetch all" syncs never fire on a customer scan (checked: no `Provider`/`context.read` in `review_screen.dart`, no `lazy:` anywhere). It will start misbehaving under `/app/` (see I.6).
- **Auth today:** none. `firebase_auth` is in `pubspec.yaml:47` but never imported in `lib/` (grep for `FirebaseAuth|signIn|login|password|PIN|currentUser` found nothing). The dashboard is protected only by nobody knowing the URL, which is the same URL as the customer page.

---

## D. QR URL format and every hardcoded domain

**Format** (`qr_service.dart:17-20`): `'$origin/#/review/$shopId'`, where `shopId` is a UUIDv4 (`qr_service.dart:11`).

**Origin source** (`qr_service.dart:22-24`): `_currentOrigin()` returns the **hardcoded** string `https://qrcode-16b68.web.app`. Despite the doc comment ("based on the app's own current origin"), it does not read `window.location` and does not use `viewport_info_service`. `baseOrigin` can be passed in, but no caller does.

**Where the URL is consumed**

- `qr_provider.dart:62` stores it in `qr_codes/{id}.qrContent` (a permanent copy per QR).
- `generate_qr_screen.dart:80,262` use it for the live preview and copy-link.
- `my_qr_codes_screen.dart` copies the stored `qr.qrContent`, not a rebuilt value.
- Printed or downloaded PNG stickers embed it permanently.

**Every hardcoded domain**

| Domain | Location | Role |
|---|---|---|
| `qrcode-16b68.web.app` | `lib/services/qr_service.dart:23` | **Live QR origin** |
| `qrcode-16b68` (project id) | `.firebaserc:3`, `lib/firebase_options.dart:35,45,52`, `android/app/google-services.json:4` | Firebase project |
| `qrcode-16b68.firebaseapp.com` | `lib/firebase_options.dart:36` | `authDomain` (web) |
| `qrcode-16b68.firebasestorage.app` | `lib/firebase_options.dart:37,46,53` | Storage bucket (Storage is unused) |
| `reviewqr.web.app` | `functions/index.js:153` | Email "View Dashboard" link. **Different site from the live one.** |
| `reviewqr.app` | `lib/widgets/qr_style_selector.dart:81` (preview QR), `test/qr_export_resolution_test.dart:30` | Placeholder/preview strings, unrelated to the live origin |
| `script.google.com/macros/s/...` | `lib/services/google_sheets_service.dart:89` | Apps Script endpoint (id not reproduced) |
| `api.emailjs.com` | `lib/services/emailjs_service.dart:32` | Dead service |

`firebaseapp.com` appears only as the auth domain. `reviewqr.web.app` and `reviewqr.app` look like abandoned or aspirational domains. **None of them is the real one except `qrcode-16b68.web.app`.**

---

## E. Firestore data model and what current rules allow anonymously

No subcollections. Three top-level collections. All fields below come from `toMap()` and `firebase_service.dart`.

### `shops/{shopId}`
Written by the dashboard with a full-document `set()` (no merge), `firebase_service.dart:45`. Read by the dashboard (`fetchAllShops`, line 79), by the **customer page** (`fetchShop`, line 120) and by the Cloud Function (admin SDK).

| Field | Type | Notes |
|---|---|---|
| `shopId` | string | UUIDv4 |
| `shopName` | string | |
| `shopLogo` | string? | Never set by any UI (only pass-through in `shop_provider.dart`) |
| `googleReviewUrl` | string | Customers are redirected to this URL (`review_screen.dart:155`) |
| `createdAt` | **string** (ISO-8601, client clock) | Not a Firestore Timestamp |
| `whatsappNumber` | string? | **PII** (`shop_model.dart:53`) |
| `notificationEmail` | string? | **PII** (`shop_model.dart:54`) |
| `emailNotificationsEnabled` | bool | |
| `googleSheetsUrl` | string? | Customer client reads this and uses the spreadsheet id to call Apps Script |

### `qr_codes/{qrId}`
Written by the dashboard (`firebase_service.dart:56,67`). Read by the dashboard (all) and by the customer page via `where('shopId' == x).limit(1)` (`firebase_service.dart:105-108`, used for the sheet row label).

| Field | Type |
|---|---|
| `qrId`, `shopId`, `qrContent` (full URL), `qrLabel`, `qrCode` (short `QR1`..) | string |
| `qrStyle` | string (enum name) |
| `createdAt`, `updatedAt?` | ISO-8601 **strings** |

### `feedback/{autoId}`
**Written by anonymous customers.** Exact keys sent (`firebase_service.dart:138-144`):

| Key | Type | Source |
|---|---|---|
| `shopId` | string | route param |
| `rating` | int | 1-5 |
| `comment` | string or null | free text, max 250 per the form and rules (**may contain PII**) |
| `createdAt` | Firestore Timestamp | `FieldValue.serverTimestamp()`, **not** a client DateTime |
| `emailNotificationStatus` | string | always `'pending'` |

The Cloud Function later adds `emailSentAt` and rewrites `emailNotificationStatus` (`functions/index.js:139,145,170-171,176`). **No Dart code ever reads `feedback`**: `firebase_service.dart` only has `.add()`. The Analytics tab is a placeholder.

### What the current rules allow an anonymous (not signed-in) user

`firestore.rules`, in plain English:

- **`shops`** (lines 16-18): anyone on the internet can read, **list**, create, overwrite and delete any shop. That includes every owner's email and WhatsApp number, and the ability to change any shop's `googleReviewUrl` or `googleSheetsUrl`.
- **`qr_codes`** (lines 20-22): the same. Anyone can list, edit or delete any QR record.
- **`feedback`** (lines 24-28): anyone can **read and list all feedback**, including every customer comment. Anyone can **create** a feedback doc if it has the keys `shopId`, `rating`, `createdAt`, `emailNotificationStatus`, `rating` is an int 1-5, and `comment` is null or at most 250 chars (lines 31-38). Nobody can update or delete from a client.
- **Gaps in the feedback create rule:**
  - It uses `hasAll`, not `hasOnly`, so extra arbitrary fields are accepted.
  - `createdAt` is not checked against `request.time`.
  - `shopId` is not checked to exist.
  - There is no rate limiting or App Check.
  - The rule hard-requires `emailNotificationStatus`, so the email feature is baked into the security rule.
- `firestore.indexes.json` is empty (`indexes: []`). That is fine today because only single-field equality queries exist.

---

## F. External services and how each authenticates

| Service | File | Auth | Secrets in the web bundle? |
|---|---|---|---|
| **Firestore** | `firebase_service.dart`, `firebase_options.dart` | **None.** Public Firebase client API keys and open rules; `firebase_auth` unused | Firebase **client** keys at `firebase_options.dart:32,42,49` and `google-services.json:18`. These are identifiers, not secrets, but only safe if rules + key restrictions are right (neither is today). |
| **Google Sheets** | `google_sheets_service.dart` | **Google Apps Script web app**, "Execute as: me, Who has access: **Anyone**" (documented in the file's header comment, lines 17-19). No OAuth, no service account, no API key, no shared secret. | The **script URL** (line 89) is the only "credential", and it ships in `main.dart.js`. Anyone who has it can call the script. |
| **EmailJS** | `emailjs_service.dart` | Placeholder `YOUR_*` values (lines 10-12) | None, and it is never called. |
| **Cloud Function (email)** | `functions/index.js` | SMTP user/pass via Firebase **secrets** `EMAIL_USER`, `EMAIL_PASS` (`defineSecret`, lines 9-10); Gmail SMTP | Not in the bundle. `functions/.env.example` is placeholders only. |
| **Google Fonts** | `app_theme.dart:17-18` | none | Runtime fetch of Inter from Google's CDN on every first load, including the customer page. |
| **Google Maps / g.page** | `url_launcher` | none | Outbound link only. |

### Service by service

- **`firebase_service.dart`**: all Firestore I/O. It fails soft: `isAvailable=false` turns everything into no-ops. Callers: providers and `ReviewScreen`.
- **`hive_service.dart`**: caches shops, QR codes and settings in the browser (IndexedDB). It stores the **full shop docs including `notificationEmail` and `whatsappNumber`** in whatever browser opened the page. On a customer device that is the single shop they scanned. Dead members: `isUploaded`, `markUploaded`, `deleteShop`, and the `meta_box` "uploaded" flags (legacy pre-cloud-sync). "Review submitted" is intentionally in-memory only (lines 90-100), so a refresh re-shows the form and the same person can submit repeatedly.
- **`export_service.dart`**: builds JSON and PDF of **all shops including WhatsApp and email** (lines 90-97) and **all QR codes**. Callers: `TopBar`, `SettingsScreen`.
- **`download_helper*`, `browser_nav*`, `viewport_info*`**: conditional-import trios. **The stub/web pattern is wired correctly.** Each barrel is `export 'x_stub.dart' if (dart.library.html) 'x_web.dart';`, and the stub and web files expose identical signatures. Caveat: `dart.library.html` is false under dart2wasm, so a future WASM build would silently pick the stubs and disable the back-guard and downloads.
- **`qr_service.dart`**: see D.
- **`emailjs_service.dart`**: see G.

---

## G. Dead code / cleanup list, ranked by safety to remove (report only)

### Safe
| Item | Evidence |
|---|---|
| `lib/services/emailjs_service.dart` | Zero references; placeholder credentials |
| `.firebase/hosting.YnVpbGRcd2Vi.cache` (tracked + modified) | CLI deploy cache; add `.firebase/` to `.gitignore` and `git rm --cached` |
| `cupertino_icons` (`pubspec.yaml:36`) | No `Cupertino*` usage in `lib/` |
| `assets/images/app_icon.png`, `splashscreeniconn.png` | Unreferenced in `lib/` and `web/` (but `assets/images/` is bundled wholesale via `pubspec.yaml:90`, so they ship) |
| `Validators.isValidEmail`, `isValidWhatsappNumber`, `digitsOnly` (`validators.dart:41-57`) | Only definitions; the inputs they served are gone from the UI |
| `ShopProvider.syncFromCloud`, `QrProvider.syncFromCloud`, `ShopProvider.selectShop` | No callers |
| `README.md`, `web/manifest.json` | Boilerplate text ("A new Flutter project.") |

### Check first
| Item | Why check |
|---|---|
| `SettingsModel`, `SettingsProvider`, `settings_box`, Hive adapter id 3 | Nothing reads `settings`; all four fields are write-only. Removing the adapter while a browser still holds a `settings_box` could break `Hive.openBox` there, so remove the box and adapter together and test on a browser with old data. |
| `HiveService.isUploaded/markUploaded/deleteShop`, `meta_box` | Legacy flags; probably dead but part of the cache format. |
| Email-notification surface: `ShopModel.notificationEmail`, `emailNotificationsEnabled`, `whatsappNumber` (and their Hive field ids 5, 6, 7), `shop_provider.dart:56-58,74-76,84-86`, `export_service.dart:90,96-97`, `emailNotificationStatus` in `firebase_service.dart:143` and `firestore.rules:31,38` | **No screen reads or writes these any more** (no UI references in `lib/screens`), yet they are still stored, exported and required by the rule. Older shop docs may still hold real emails. Remove the rule and client together, loosening the rule first. |
| `functions/` + `firebase.json:31-42` | See below. |
| `image` dev dependency (`pubspec.yaml:76`) | Used only by the new untracked test. |
| `firebase_auth` (`pubspec.yaml:47`) | **Unused today but needed for the admin-login plan.** Keep. |
| `shopLogo` field | Never set by any UI. |
| `GoogleSheetsService` Apps Script header comment (lines 9-86) | It documents the code to paste; the deployed script may differ (see J). |

### Risky
| Item | Why |
|---|---|
| `qr_service.dart:23` hardcoded origin and `qr_codes.qrContent` stored URLs | Printed stickers depend on this exact URL form; do not change without a permanent redirect. |
| Hash-based review URL format | Same reason. |
| `android/` and `ios/` | Probably do not compile (see I.12), but they hold bundle ids and `google-services.json`. |

### `functions/` confirmation
It **is** the email-notification Cloud Function: `exports.sendFeedbackEmailNotification = onDocumentCreated("feedback/{feedbackId}")` (`index.js:126-127`). It reads `shops/{shopId}` (line 137), checks `emailNotificationsEnabled` and `notificationEmail` (line 144), sends via Gmail SMTP with nodemailer (lines 19-27, 156-158), then writes `emailNotificationStatus` and `emailSentAt`.

Everything that references it:
- `firebase.json:31-42` (`functions` block, codebase `default`)
- `functions/package.json` (scripts `serve`, `deploy`, `logs`; node 20)
- `firestore.rules:31,38` (`emailNotificationStatus` required)
- `firebase_service.dart:129,143` (writes `'pending'`)
- model/provider/export fields listed above

It is **not** referenced in `.firebaserc`, in any other script, or in docs. Dart has no `cloud_functions` dependency and never calls it directly.

Inconsistencies:
- **Spark plan:** Cloud Functions require Blaze, so the function cannot be deployed on Spark. `firebase.json` still declares it, so a plain `firebase deploy` may fail or prompt for an upgrade; use `--only hosting,firestore:rules`.
- The email's dashboard link points at `reviewqr.web.app` (`index.js:153`), a different site than the live one.
- There is no `package-lock.json` and no `.env` ignore rule.

Other findings: no `TODO`, `FIXME` or `HACK` comments found in `lib/`. No commented-out code blocks of note.

### Tracked-in-git check
- `build/`, `.dart_tool/`, `.idea/` and `.widget_preview/` are properly **ignored and not tracked**.
- `.firebase/hosting.*.cache` **is tracked** (and shows as modified).
- `android/app/google-services.json` is tracked (normal for Firebase client config, but see H.5).
- `pubspec.lock` is tracked (fine for an app).

---

## H. Security findings, ranked by severity (no secret values)

**1. CRITICAL: anyone can rewrite every shop and QR record.** `firestore.rules:16-22` is `read, write: if true`. With only the public project id (visible in `main.dart.js`), an attacker can change a shop's `googleReviewUrl` so a customer who scans a genuine sticker is sent to a phishing site after a 4-5 star rating (`review_screen.dart:155` launches the stored URL with no validation). They can also delete all shops and QR docs, or change `googleSheetsUrl`. Fix: auth-gate writes in the rules (see I).

**2. HIGH: owner PII is world-readable.** `shops` docs hold `notificationEmail` and `whatsappNumber` (`shop_model.dart:53-54`). `allow read` covers list as well as get, so one unauthenticated query returns every owner's contact details. The customer page needs only `shopName`, `googleReviewUrl` and `googleSheetsUrl`. The same fields are also written into any browser that opens a shop's review page (Hive).

**3. HIGH: all customer feedback is publicly readable.** `firestore.rules:25` `allow read: if true`. Comments are free text and may contain names or phone numbers. Nothing in the app reads `feedback`, so this can be locked to admin with no functional loss today.

**4. HIGH: unauthenticated Apps Script endpoint.** Per the header comment (`google_sheets_service.dart:17-19`) it is deployed as "Anyone". The URL is in the public bundle (line 89). Per the documented script logic (unverified against the deployed one): anyone can create unlimited spreadsheets in the owner's Drive (the `create_sheet` action), and `rename_sheet` / `submit_feedback` take a caller-supplied `spreadsheetId` and `openById` it. That reaches **any spreadsheet the script's account can open**, not only the shops' sheets. Fix idea: have the script accept only IDs it created (store them in Script Properties) and, ideally, verify a token.

**5. MEDIUM: Firebase client API keys + open rules.** Keys at `firebase_options.dart:32,42,49` and `google-services.json:18` (web, android, ios). They are not secrets by design, but with rules open they are effectively full DB credentials. It is *unverified* whether they have HTTP-referrer / app restrictions in Google Cloud Console. The keys are also in git history (commit `b368dd3`).

**6. MEDIUM: unauthenticated admin dashboard.** The root URL is the full admin UI: create, edit, delete, and export all shops with email/WhatsApp (`export_service.dart:96-97`).

**7. MEDIUM: feedback create rule is spam-friendly** (details in E): `hasAll` not `hasOnly`, unchecked `createdAt` / `shopId`, no rate limit or App Check. A script can fill the database or the Firestore free quota.

**8. MEDIUM/LOW: spreadsheet formula injection.** Per the documented script, `data.comment` goes into `appendRow` unescaped (comment block line 67). A comment starting with `=` is interpreted as a formula in the owner's sheet. Depends on the deployed script (unverified).

**9. LOW: personal Gmail address committed** in `google_sheets_service.dart:7,10,17,106` (comments and docs). Shows who owns the Drive account.

**10. LOW: no repeat-submission guard.** "Review submitted" is session-memory only (`hive_service.dart:93-100`), so reload gives a fresh form. Also `debugPrint` logs the Apps Script response body (`google_sheets_service.dart:122`), which still prints in release builds on web.

**11. LOW: hosting config has no security headers** (no CSP or `X-Frame-Options`, `firebase.json:15-25` sets only `Cache-Control`). The admin UI could be framed (clickjacking). Firebase Hosting default headers were not verified.

**Secret scan (current tree and all git history, 2 commits):**
- **No** service-account JSON, private key, `.env`, GitHub token, AWS key or Slack token found.
- Key-like patterns match only: `firebase_options.dart:32,42,49`, `android/app/google-services.json:18`, `google_sheets_service.dart:89`. History contains the same three files at `b368dd3`, and **no deleted credential files**.
- `.gitignore` does **not** cover `.env`, `functions/.env*`, `serviceAccountKey*.json`, `*.pem`, `functions/node_modules/` or `.firebase/` (confirmed with `git check-ignore`). Only `.dart_tool/`, `/build/`, `.idea/`, `*.log`, etc. are ignored.
- The email function reads SMTP credentials from Firebase secrets, not from files, which is good.

**Admin capability exposed to an anonymous visitor:** the **entire** admin app ships in the same `main.dart.js` that customers download, and `/` serves it. Any login added later is UI-only; the rules remain the boundary.

---

## I. What will break moving the app to `/app/` and adding admin-only auth

1. **Every printed sticker.** QR codes point to `https://qrcode-16b68.web.app/#/review/<id>` (D). The fragment is never sent to the server, so a new static landing page at `/` will simply load and ignore it. The landing page needs a small script: if `location.hash` starts with `#/review/`, redirect to `/app/#/review/<id>`. That shim must stay as long as old stickers exist. `qr_codes.qrContent` in Firestore keeps the old URL, and `qr_service.dart:23` needs updating for new QR codes.
2. **Old service workers.** `flutter_bootstrap.js` registers `flutter_service_worker.js` at scope `/` (`build/web`). Returning visitors' browsers hold the old Flutter app in that SW cache and may keep serving it at `/` instead of the new landing page. If `/flutter_service_worker.js` disappears, the current catch-all rewrite (`firebase.json:9-13`) returns `index.html` for it, which is not a valid SW script, so the old SW is never replaced. Plan a root `flutter_service_worker.js` kill-switch that unregisters itself and clears caches, kept for a while. The new app's SW lives at `/app/` with scope `/app/`.
3. **`firebase.json` hosting.** `"public": "build/web"` is a single directory and the rewrite is `** -> /index.html`. You need a combined public dir (landing at root, Flutter build under `app/`) and rewrites scoped to `/app/**` -> `/app/index.html`; otherwise unknown paths on the landing site render the Flutter app. The blanket `Cache-Control: no-cache` header (`firebase.json:15-25`) also applies to the landing page and all assets.
4. **Build flags.** Flutter must be built with `--base-href /app/`. `web/index.html:4` already uses `$FLUTTER_BASE_HREF`, so no template change is needed.
5. **`web/index.html:39-41` `isReviewPage()`** tests `^\/review` against `location.pathname`. Under `/app/` the pathname starts with `/app/`, so only the `#/review` branch matches. That works as long as the hash strategy is kept; it would break with path URLs.
6. **`main.dart:25-28` `isReviewRoute`** reads `Uri.base.pathSegments.first`. Under `/app/` that is `'app'`, never `'review'`, so the flag is always false (it already is today with hash URLs; see C). It is harmless only because providers are lazy and `ReviewScreen` reads none. Adding any provider read to the review page (for example an auth provider) would trigger `loadShops()` and `loadQrCodes()` for customers.
7. **Auth gate placement.** Today the fallback route is `Splash -> Dashboard` for **any** unknown path (`main.dart:84-92`) and `ShopProvider` / `QrProvider` load at startup (`main.dart:60-68`). A login screen has to sit between the route fallback and `DashboardScreen`, and the provider loads must move behind it. After the rules are locked down, startup reads from an anonymous session would fail silently (`FirebaseService` returns `null` and falls back to Hive), and writes would show "cloud sync failed" errors.
8. **Rules rewrite.** Customers need exactly three things: **get** one shop, a **qr_codes query** `where shopId == x` (`firebase_service.dart:105`, only used to label sheet rows), and **create** on `feedback`. Everything else becomes admin-only. Because the shop doc mixes public fields (`shopName`, `googleReviewUrl`, `googleSheetsUrl`) with private ones (`notificationEmail`, `whatsappNumber`), either split the private fields into a separate doc or drop them. Otherwise the customer's single-doc `get` still returns the PII. Consider a public `shops_public/{id}` doc or storing `qrCode` on the shop to avoid the customer-side `qr_codes` query.
9. **Rollout order matters.** `firestore.rules:31,38` require `emailNotificationStatus`, and old cached clients will keep sending it. Loosen first, deploy the client, then tighten. Browsers still running an old cached build (point 2) may keep writing with the old shape for a while.
10. **Apps Script (H.4)** is a separate hole. An admin login does not secure it, because the call is made from the **customer's** browser with a spreadsheet id read from the shop doc. It needs an allow-list of sheet ids, or a proxy (a Cloud Function needs Blaze).
11. **Manifest.** `start_url: "."` and the relative icon paths resolve against `/app/manifest.json`, so they work, but the name, description and theme colour are still boilerplate. The manifest is already deliberately not attached on review pages (`index.html:44-49`).
12. **Non-web builds.** `export_service.dart` imports `package:web` and `dart:js_interop` unconditionally (lines 2-5) and is used by `TopBar` / `SettingsScreen`, so an Android or iOS build almost certainly fails to compile even though stubs exist for the other three web services. Not a blocker for `/app/`, but the `android/` and `ios/` folders are effectively unused.
13. **`dart:html`** (`browser_nav_web.dart:2`, `viewport_info_web.dart:2`, `download_helper_web.dart:3`) is deprecated, and a WASM build would select the stubs (F). Not a blocker.
14. **Email function link** (`functions/index.js:153`) points at the wrong site and would also need `/app/`, if the function is kept.

---

## J. Open questions I could not answer from the code

1. Is the GitHub remote `RexTech-Studios/QRcode_web` public? If so, the Apps Script URL and Firebase keys are public, and so is history from `b368dd3`.
2. Is the Cloud Function actually deployed? It needs Blaze but you said Spark. If it was ever deployed, are there shop docs that still have `emailNotificationsEnabled: true` and a real `notificationEmail`? The UI to set them is gone.
3. Does the **deployed** Apps Script match the code in the `google_sheets_service.dart` header comment (`rename_sheet`, the `qrCode` column)? The Dart comment at lines 162-163 says "an older script answers unknown actions with success".
4. Which domain is the real long-term one? `qrcode-16b68.web.app` is live. `reviewqr.web.app` (function) and `reviewqr.app` (UI preview, test) suggest other candidates. This decides what goes into new QR codes.
5. How many stickers are already printed with the old `#/review/` URL, and are any irreplaceable? That sets how long the redirect shim and SW kill-switch must live.
6. Who is the single admin (Google account or email + password) and is Firebase Authentication enabled in the console? `firebase_auth` is in `pubspec.yaml` but unused.
7. Are the Firebase API keys restricted (HTTP referrers) in Google Cloud Console? Not visible from code.
8. Does anything outside this repo read `feedback` (a sheet, a script, a BI tool)? The app does not, which is why locking it is probably free.
9. Is mobile (`android/`, `ios/`) a real target? `export_service.dart` suggests not.
10. Runtime behaviour in section C and H.8 was derived by reading code only. Worth confirming with a quick manual test.
