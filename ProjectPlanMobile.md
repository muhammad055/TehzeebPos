# Tehzeeb POS — Phase 2: Flutter Owner/Manager App

Companion to `ProjectPlan.md` (overall SaaS roadmap). This file covers **Phase 2 only**.
Status: **M0 code written** (backend roles verified locally; Flutter scaffold written on a machine without Flutter — not yet compiled, see `mobile/README.md` first-time setup). Phase 1 cloud migration is functionally complete; VPS deploy is manual.

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

- [~] **M0 – Foundations** — backend done & verified (owner role, `AdminOnly`=admin+owner, `OwnerOnly`, role validation → 400, mobile login `client:"mobile"` → 30-day token vs 12h web, Angular Users "Owner" option). Flutter code written (dio client + 401 logout, secure storage, login, go_router role guard, owner/manager shell, cashier blocked). **Remaining on the Mac:** `flutter create .` to generate `android/`/`ios/`, `flutter pub get && flutter analyze`, run on a simulator, commit platform folders. Dart flavors deferred (using `--dart-define=API_BASE_URL`).
- [ ] **M1 – Owner dashboard**: tiles + 7-day chart from `/api/stats`, pull-to-refresh. Totals must equal the web dashboard for the same day.
- [ ] **M2 – Orders & Reports**: order list by date, detail, cancel (admin); reports with date range + dish filter; Z-report view; `/api/mobile/summary` if needed.
- [ ] **M3 – Manager ops**: menu management (CRUD, toggle, toggle-all, photo upload); expenses list/add/edit with camera attachments.
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
- Apple Developer account ($99/yr) and Google Play Console ($25 one-time) needed for release; iOS builds require the Mac.
- Cloud-only: phone needs internet; no offline mode.
- Login is still a **global username lookup** (single tenant). Before onboarding a second restaurant it must become unique per `(RestaurantId, Username)` with a restaurant selector — the mobile login UI will need it too.
- Firebase config files: kept out of git; document the setup steps when M4 starts.
