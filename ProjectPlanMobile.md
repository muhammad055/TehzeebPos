# Tehzeeb POS — Phase 2: Flutter Owner/Manager App

Companion to `ProjectPlan.md` (overall SaaS roadmap). This file covers **Phase 2 only**.
Status (2026-09-26): **M0–M3 code complete and now running on a real iPhone 13 (Mac, Xcode 26.6). Redesign, inventory and orders/trend improvements added. M4–M5 not started.** `flutter analyze` is clean and 8 unit tests pass; the backend endpoints the app uses were verified with curl against the local backend.

## Progress log (2026-09-26)

- **Running on a device**: Mac toolchain set up (see `CLAUDE.md` → "Mac dev setup"); app installed on an iPhone 13 via `flutter run --release`. Login, dashboard, orders, expenses and inventory reached on the phone.
- **UI redesign**: full lavender theme from the web tokens (`core/theme.dart`), branded drawer, dashboard hero card + icon tiles + gradient chart, **food-photo login** (mosaic built from `menu-photos-for-delivery`, gold accents from the logo), **app icon from `TL.png`** (source is only 74 px — replace with a high-res logo before release).
- **Orders**: date-range chips (Today / Yesterday / 7 days / This month / Custom), summary card (count, total, average, cash vs card), per-day grouping with daily totals, richer order cards.
- **Dashboard**: expense tiles (today / week / month) open the Expenses list pre-filtered; sales trend has a **custom date range** (backend `GET /api/stats/trend?from=&to=`, up to 366 days).
- **Inventory (off-plan, user request)**: itemised bills, pack sizes, day-end usage, physical stock counts, stock on hand and purchases-vs-usage report — see `CLAUDE.md` → "Inventory & stock tracking". Mobile has On hand / Entry / Report screens and a line-items section in the expense form; **pack sizes are not yet on the mobile bill form** (backend + web only).
- **Still open**: sales-based usage rules for portion dishes (kadahi Q/H/F, tikka = ¼ bird, boti) need the portion recorded on orders + the user's measurements (mutton, veal leg, boneless boti); kitchen big-button/Urdu entry screen; M4 push (needs Firebase + paid Apple account); M5 release; decide purchase/order endpoint restrictions; refresh tokens; per-restaurant usernames.

## Progress snapshot (2026-09-25)

| Milestone | Code | Verified so far | Still to verify (on a device) |
|---|---|---|---|
| M0 Foundations | done | backend: owner role, `AdminOnly`=admin+owner, role validation 400, mobile 30-day token vs 12h web; cashier→403 on order cancel | login on emulator; owner/admin/cashier routing |
| M1 Dashboard | done | analyzer + model unit tests | totals equal web dashboard for the same day |
| M2 Orders/Reports | done | `/api/stats/trend` tested (30 rows, clamp 90); analyzer + tests | list/detail/cancel round-trip vs web; report + Z-Report totals vs web |
| M3 Menu/Expenses | done | full dish + expense API flows via curl (create/update/toggle/photo/attachments/delete), test data removed | screens, camera/gallery, photo cache-busting |
| M4 Push | not started | — | needs your Firebase project |
| M5 Release | not started | — | needs Apple/Google developer accounts |

**Backend changes made in Phase 2 so far:** `Roles` (owner/admin/cashier) + `OwnerOnly` policy; `AdminOnly` now admin+owner; user-create role validation; `client:"mobile"` login → `Jwt:MobileExpiryHours` (default 30 days); `GET /api/stats/trend`; `PATCH /api/orders/{id}/cancel` now `AdminOnly`. Angular: owner treated as admin; "Owner" option in Users.

**Dev environment notes (Windows box):** `flutter.bat` needs PowerShell (blocked by group policy) — `bin/internal/shared.bat` in the SDK was locally patched to skip the engine-version PowerShell check (backup: `shared.bat.orig`); `flutter doctor` still reports missing Android cmdline-tools/licences; the Gradle build failed with "Unable to establish loopback connection" in the assistant's sandbox (retry from your own terminal, or build on the Mac).

**Next steps:** (1) run M0–M3 on an emulator/simulator and fix anything found; (2) create a Firebase project → M4; (3) decide whether to restrict `/api/purchases` writes and `GET /api/orders` to admin/owner (currently any authenticated user); (4) then M5 release prep.

## Goal

The mobile experience the owner described: check the restaurant at 11 PM without sitting in it. **One Flutter app** (Android + iOS) in `mobile/` at the repo root, next to `backend/`, `frontend-ng/`, `print-agent/`, `desktop/`. Role-gated modes (Owner / Manager) inside the same app.

The app **mirrors what already exists on the web** (sales, orders, reports, purchases, menu management). New analytics (profit, food cost, delivery platforms) are Phase 3 — not here. **No functional changes to the web app.**

## Decisions (locked)

- Monorepo: `mobile/` lives in this repo, fully independent build (own `pubspec.yaml`, not referenced by .NET/Angular/Electron builds — same pattern as `print-agent/`).
- One app, role-gated modes (not two apps).
- Flutter native (not PWA). Cloud-only: needs internet, no offline order queue.
- Server policies are the real security; UI gating is convenience only.

## What the backend already provides (backend/Program.cs)

- `POST /api/auth/login` → `{ token, username, role }`; JWT carries role + `restaurant_id`.
- `GET /api/stats` — today/week/month sales, expenses, naive profit, top 5 items, last 7 days (UAE time, UTC+4, computed server-side — the app must not recompute dates).
- `GET /api/reports`, `GET /api/z-report`, `GET /api/orders` (+`/{id}`, `PATCH /{id}/cancel`), `GET/POST/PUT/DELETE /api/purchases` (+attachments), `GET/POST/PUT/DELETE /api/dishes` (+`PATCH /{id}/toggle`, `PATCH /toggle-all`, `POST /{id}/image`).
- Everything is tenant-filtered via the JWT — mobile inherits isolation for free.
- Current gap: only policy is `AdminOnly = RequireRole("admin")`; roles are free strings.

## Backend changes (small, additive)

1. **Roles**: `owner | admin | cashier` as string constants (no DB enum/migration). `AdminOnly` → `RequireRole("admin","owner")` (owner can do everything admin can). Add `OwnerOnly` policy for future owner-only features. Validate `CreateUserDto.Role` against the allowed set. Add "owner" option to the Angular Users screen.
2. **JWT lifetime**: review expiry at token creation; mobile stopgap = ~30-day access token in secure storage. Refresh tokens deferred.
3. **`GET /api/mobile/summary`** (only if `/api/stats` proves too heavy on a phone — it loads all orders in memory): reuse a shared function extracted from `/api/stats` so numbers can never diverge from the web; DB-side aggregation.
4. **Devices + push (M4)**: `DeviceToken` table (`RestaurantId`, `UserId`, `Token`, `Platform`, `CreatedAt`) + `POST/DELETE /api/devices` + EF migration; `IPushSender` over FCM HTTP v1 (service-account JSON via env var `Fcm__ServiceAccountJson`, never committed); daily-summary `BackgroundService` driven by a per-restaurant `SummaryPushTime` setting.

## Flutter app design

- Create: `flutter create --org com.tehzeeb --project-name tehzeeb_mobile mobile`
- Stack: Riverpod (state), go_router (navigation + role guards), dio (HTTP + auth interceptor: attach Bearer, 401 → logout — mirrors `frontend-ng/src/app/auth.interceptor.ts`), flutter_secure_storage (token), fl_chart (trends), intl (AED formatting), firebase_messaging + flutter_local_notifications (M4).
- Config: `--dart-define=API_BASE_URL=...`, flavors `dev` / `prod`. No hardcoded URLs. (Android emulator → local backend at `http://10.0.2.2:5050`.)
- Structure: `lib/core/` (api, auth, theme, config), `lib/features/{auth,dashboard,orders,reports,expenses,menu}/` (data / providers / ui), `lib/shared/widgets/`.
- Theme: derive from `frontend-ng/src/styles.css` tokens (`--bg`, `--surface`, `--accent`, ...); start with `lavender`.
- Urdu: bundle Noto Nastaliq Urdu; display `Name` (Urdu) with a display-only language toggle like `LanguageService`.

### Role gating

| Role | Mobile access |
|---|---|
| **owner** | Dashboard (tiles + 7/30-day trend charts), Orders, Reports, Expenses (read), Menu |
| **admin** (manager) | Dashboard-lite, Orders (incl. cancel with reason), Purchases (add/edit + photos), Reports/Z-report view, **Menu management** (add / edit / delete / enable-disable dishes, toggle-all, photo upload) |
| **cashier** | Blocked with a message — mobile is not a POS |

## Milestones

- [~] **M0 – Foundations** — backend done & verified (owner role, `AdminOnly`=admin+owner, `OwnerOnly`, role validation → 400, mobile login `client:"mobile"` → 30-day token vs 12h web, Angular Users "Owner" option). Flutter code written (dio client + 401 logout, secure storage, login, go_router role guard, owner/manager shell, cashier blocked). Platform folders generated & committed; `flutter analyze` clean and unit tests pass (Flutter 3.47.5 / Dart 3.13, Windows). **Remaining:** run on an emulator/simulator (Gradle build fails on the Windows dev box with 'Unable to establish loopback connection'; try on the Mac). Dart flavors deferred (using `--dart-define=API_BASE_URL`).
- [~] **M1 – Owner dashboard** — code written (not yet compiled/run): `features/dashboard/` (Stats model + unit test, `statsProvider`, tiles for today/week/month, 7-day bar chart via fl_chart, top items, pull-to-refresh, error/retry), drawer shell in `HomeScreen`. **To verify on the Mac:** totals equal the web dashboard for the same day. 30-day trend chart deferred (needs a backend range endpoint; `/api/stats` only returns 7 days).
- [~] **M2 – Orders & Reports** — code written (not yet compiled/run). Backend: new `GET /api/stats/trend?days=N` (AdminOnly, clamped 1–90, zero-filled, UAE days) — tested locally. Flutter: `features/orders/` (day picker, list with cancelled badge, detail, cancel with reason), `features/reports/` (date range + dish filter, summary, daily sales, items sold; read-only Z-Report of the current shift — closing a shift stays a counter/web action), dashboard 7d/30d toggle, `core/format.dart` (UAE-time helpers; timestamps always shown in UTC+4), drawer routes. `/api/mobile/summary` not needed yet. **To verify on the Mac:** order list/detail/cancel round-trip vs web Order History; report totals vs web Reports; Z-Report vs web.
- [~] **M3 – Manager ops** — code written; `flutter analyze` clean, 8 unit tests pass; **API contracts verified end-to-end with curl against the local backend** (dish create/update/toggle/image/delete; expense multipart create/update/attachments/filter/delete; test rows removed afterwards). Not yet run on a device. Flutter: `features/menu/` (search, per-dish enable switch, enable/disable all, add/edit form with Single/Double or Quarter/Half/Full tiers, tax default from `DefaultTaxRate` setting, photo camera/gallery, delete), `features/expenses/` (date-range + category filter, add/edit, receipt photos add/remove, delete), shared `NetworkThumb` + `pickPhoto` (image_picker; iOS camera/photo permission strings added). **Decision:** owner and admin get identical Menu/Expenses screens (server `AdminOnly` already treats them alike) — the earlier 'owner: read-only' idea was dropped. Photos are cache-busted with `?v=` after upload because the server reuses `dish-<id>.jpg`. Note: purchases endpoints still only require *any* authenticated user (web behavior, unchanged).
- [~] **Inventory (added 2026-09-26, off-plan)** — itemised bills, pack sizes, day-end usage, stock counts and a purchases-vs-usage report; backend in `backend/Inventory.cs`, described in `CLAUDE.md` ("Inventory & stock tracking"). Mobile: `features/inventory/` (On hand / Entry / Report tabs) and a line-items section in the expense form (no pack picker yet). Analyzer clean, 6 model unit tests; installed on the iPhone, backend flow verified by a 69-check API script + web UI.
- [ ] **M4 – Push notifications**: Firebase project, `DeviceToken` migration + endpoints, daily-summary push, deep link to dashboard. `google-services.json` / `GoogleService-Info.plist` are gitignored.
- [ ] **M5 – Release prep**: icons/splash (from `TL.png`), Android signed AAB (Play internal testing), iOS TestFlight (needs Mac), HTTPS-only base URL for the VPS, error/empty/no-internet states.

Each milestone gets its own go-ahead before work starts.

## Verification

- **Backend**: log in as owner/admin/cashier via curl — owner+admin 200 on admin endpoints, cashier 403; invalid role on user create → 400; a second tenant still cannot read/write the first's data.
- **App** (per milestone, Android emulator; iOS simulator on the Mac): numbers match Angular Dashboard/Reports for the same day; cancel/edit round-trips show up on web; role gating checked per login.
- Mutation tests on real dishes follow the live-data convention: fetch → minimal temp change → verify → revert → re-fetch.
- **M4**: real push received on a physical device.

## Risks / open items

- No refresh-token flow yet (long-lived token stopgap).
- ~~Server gap found in M2~~ **Fixed**: `PATCH /api/orders/{id}/cancel` is now `AdminOnly` (admin + owner). Cashier token → 403 (verified). `GET /api/orders` still allows any authenticated user.
- Apple Developer account ($99/yr) and Google Play Console ($25 one-time) needed for release; iOS builds require the Mac.
- Cloud-only: phone needs internet; no offline mode.
- Login is still a **global username lookup** (single tenant). Before onboarding a second restaurant it must become unique per `(RestaurantId, Username)` with a restaurant selector — the mobile login UI will need it too.
- Firebase config files: kept out of git; document the setup steps when M4 starts.
