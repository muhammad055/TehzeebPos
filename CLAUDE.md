# Tehzeeb POS — Project Context

Restaurant POS for Tehzeeb Restaurant & Kitchen (Ajman, UAE). This file is auto-loaded at the start of every Claude Code session in this repo — keep it updated as the source of truth for context handoff between sessions.

## Stack & Structure

```
backend/       ASP.NET Core 8 Minimal API — everything lives in Program.cs (single file).
               PostgreSQL via Npgsql + real EF Core Migrations (Migrations/ folder) —
               replaced the old raw ALTER TABLE/pragma_table_info SQLite pattern as
               part of the SaaS Phase 1 cloud migration (see "Multi-tenancy & auth"
               below). Local dev Postgres: `docker compose up -d` in backend/.
frontend-ng/   Angular 17 standalone app (esbuild-based "application" builder).
desktop/       Electron wrapper that packages backend+frontend into a Windows
               desktop installer. See "Desktop packaging" below — NOTE: not yet
               updated for the Postgres/JWT switch (see SaaS Phase 1 status).
```

Default login: `admin`/`admin123` (admin role), `cashier`/`cashier123` (cashier role) — unchanged.

Dev workflow: `docker compose up -d` (backend/docker-compose.yml, first time only) →
`dotnet run --urls "http://localhost:5050"` in `backend/` (applies pending migrations
+ seeds the Tehzeeb restaurant/users automatically on startup) → `npm start` in
`frontend-ng/` (serves on :4200, proxies /api to :5050).

## Multi-tenancy & auth (SaaS Phase 1, in progress)

Added as the first step of the SaaS transformation (see the "SaaS transformation
roadmap" plan/memory) — desktop → cloud migration, deliberately with **no feature
changes**, just real server-side security:

- **Every tenant-owned table** (Dish, Order, OrderItem, Purchase, PurchaseAttachment,
  User, Setting) now has a `RestaurantId` FK to a new `Restaurant` table. `AppDbContext`
  applies an EF Core global query filter on all of them keyed off the caller's JWT
  `restaurant_id` claim (`ICurrentTenant`/`HttpCurrentTenant` in Program.cs) — a
  missed `.Where()` in an endpoint can't leak another restaurant's rows. Every
  mutation endpoint also does an explicit tenant-scoped lookup (`FirstOrDefaultAsync`
  against the filtered `DbSet`, not raw `FindAsync`) before updating/deleting, so a
  guessed valid ID for another tenant's row 404s instead of succeeding.
- **Real JWT auth**: `POST /api/auth/login` now returns `{ token, username, role }`;
  every endpoint requires `[Authorize]` (via `.RequireAuthorization()`), with an
  `"AdminOnly"` policy on the endpoints backing admin-only screens (Menu Setup writes,
  Users, Reports, Z-Report). This closes what was previously a **zero server-side
  authorization** gap — role checks used to be enforced only client-side. Frontend:
  `AuthService` stores the token, `auth.interceptor.ts` (functional `HttpInterceptorFn`,
  registered in `main.ts`) attaches `Authorization: Bearer` to every request and
  force-logs-out on a 401.
- **Login is still a global (unscoped) username lookup** (`IgnoreQueryFilters()`) since
  there's one tenant today — before onboarding a second restaurant this needs to become
  unique per-`(RestaurantId, Username)` with a tenant-selection step. Flagged, not yet
  built.
- Jwt secret/connection string come from `appsettings.Development.json` (dev-only,
  committed) locally; production (the eventual VPS) must set `ConnectionStrings__Default`
  and `Jwt__Secret` as environment variables — the app throws at startup if they're
  missing, deliberately (no silent insecure default in prod).
- **Real menu data migrated** (2026-09-24): all 73 real dishes (Urdu names, English
  print names, prices, pricing schemes, original IDs preserved so dish photos still
  resolve), the real non-default password hashes (the `cashier` account's password
  had actually been changed from the default — preserved, not reset), and the real
  printer/report Settings were copied from `app.db` into Postgres. Orders/Purchases
  were empty in the source DB (confirmed dummy/test only, not real transactions), so
  nothing to migrate there.
- **Still pending for Phase 1**: the actual VPS provisioning/deployment, and updating
  `desktop/` packaging for the new Postgres/JWT requirements (see "Desktop + cloud
  coexistence" below — the printing side of that is done, the database side isn't).

**Gotcha**: `dotnet build`/`dotnet run` fails with a file-lock error if a previous backend instance is still running. Find and kill it first: `tasklist | grep -i posapi` then `taskkill //PID <pid> //F`. If that returns "Access is denied" (seen on this machine — likely an EDR/group-policy process-protection rule blocking scripted termination), build with `-c Release` instead — it writes to `bin/Release/...`, a different path than the locked `bin/Debug/...` exe, so it's unaffected — and ask the human to close the stuck process themselves (Task Manager / Ctrl+C in its terminal).

## Local Print Agent (`print-agent/`) — desktop + cloud coexistence

Printing goes through `IPrintDispatcher` (`backend/PrintDispatch.cs`) rather than calling `RawPrinterHelper` directly, so **one backend binary** serves both deployment modes, switched by `Printing:Mode` config:

- **`Printing:Mode` unset/anything else (desktop default)** → `LocalPrintDispatcher`: prints in-process exactly as before Phase 1 — backend and printer are the same machine. No changes needed for desktop builds.
- **`Printing:Mode=RemoteAgent` (cloud)** → `RemotePrintDispatcher`: the backend (on a VPS) can't see a printer sitting at the restaurant, so it dispatches the job over SignalR (`backend/PrintHub.cs`, hub at `/hubs/print`) to whichever Local Print Agent is currently connected for that restaurant, and awaits the result (20s timeout) so the HTTP response still reflects real success/failure — same error messages as desktop (e.g. "Could not open printer ... Win32 error 1801").
- **`print-agent/`** is a small separate .NET 8 Worker Service project (own `.csproj`, not referenced by `backend/`) meant to run at the restaurant, one per printer/terminal. It holds an outbound SignalR connection to the cloud hub (agents can't accept inbound connections — no public IP at a restaurant), authenticated by a per-restaurant `PrintAgentKey` (`Restaurant.PrintAgentKey`, viewable/regenerable from Admin → Printer Settings, `GET/POST /api/printer-agent/key`, `/regenerate-key`) — **not** the user JWT scheme, since it's a headless machine credential with its own lifecycle. `print-agent/RawPrinterHelper.cs` is a deliberate duplicate of `backend/RawPrinterHelper.cs` (small, stable, ~80 lines) rather than a shared project reference, keeping the agent dependency-free from the API project. Configure via `print-agent/appsettings.json` (`HubUrl`, `AgentKey`), can run as a normal console app or install as a Windows service (`AddWindowsService`, name "Tehzeeb Print Agent") for unattended operation. `GET /api/printer-agent/status` (AdminOnly) reports whether an agent is currently connected — shown as a green/gray dot in Admin → Printer Settings.
- Connection tracking (`PrintAgentRegistry`) is an in-memory singleton — fine for a single backend instance; scaling the API out to multiple VPS instances later would need a SignalR backplane (e.g. Redis) for this to keep working, not needed yet.
- Verified end-to-end (2026-09-24) against a real local Postgres + a locally-run agent: connect/status, a real print job succeeding, a nonexistent-printer error propagating byte-for-byte back through the chain, and the "no agent connected" case — all behave correctly.
- **Desktop database (built 2026-09-24)**: `desktop/main.js` now bundles and manages a portable local PostgreSQL via the `embedded-postgres` npm package (real Postgres binaries, `@embedded-postgres/windows-x64`, no separate install/admin rights needed) instead of resurrecting SQLite — one DB engine and one migrations set everywhere. Runs on port `55432` (deliberately non-default, can't collide with a real Postgres install), data persisted at `%APPDATA%\tehzeeb-pos-desktop\pgdata\`. On first run: `pg.initialise()` + `pg.createDatabase('tehzeeb_pos')`; every run: `pg.start()` before the backend spawns, `pg.stop()` on `before-quit` (quit is deferred with `e.preventDefault()` until both the backend and Postgres have shut down cleanly). The backend is spawned with `ConnectionStrings__Default` pointing at this local instance and a `Jwt__Secret` generated once and persisted to `%APPDATA%\tehzeeb-pos-desktop\secrets.json` (stable across restarts, otherwise every relaunch would invalidate all sessions). `Printing:Mode` is left unset (desktop always prints in-process).
  - `embedded-postgres` is ESM-only; `main.js` stays CommonJS and loads it via dynamic `import()` rather than converting the whole file.
  - `desktop/package.json`: `embedded-postgres` is a real `dependency` (not dev), and `build.files`/`asar: false` were needed — Postgres's actual binaries can't be executed from inside an asar archive, so asar packaging is disabled for this app entirely rather than fiddling with `asarUnpack` globs. electron-builder's own dependency-walking still correctly excludes devDependencies (electron, sharp, etc.) from the shipped `node_modules` despite the broad `node_modules/**/*` files glob — verified by inspecting `release/win-unpacked/resources/app/node_modules` after a real build.
  - **`backend/PosApi.csproj`**: had to add `<Content Update="appsettings.Development.json"><CopyToPublishDirectory>Never</CopyToPublishDirectory></Content>` — discovered that `dotnet publish` was including the dev-only file (weak hardcoded JWT secret, dev Postgres credentials) in every publish output, including this desktop installer. Applies to cloud VPS publishes too, not just desktop.
  - Verified end-to-end with a real `npm run dist` build (145MB installer) run standalone with a fresh `--user-data-dir`: Postgres initializes and starts, backend connects/migrates/seeds a fresh restaurant, login issues a correct JWT, the Angular SPA and its static assets serve correctly, and a dish write persists. `desktop/scripts/build.js` needed no changes — it already just publishes the backend and copies the Angular build; the new logic all lives in `main.js`/`package.json`.

## Mobile app (`mobile/`, SaaS Phase 2 — in progress)

One Flutter app (Android + iOS), role-gated Owner/Manager modes. Full plan + milestone checklist: `ProjectPlanMobile.md` (overall roadmap: `ProjectPlan.md`). Setup/run: `mobile/README.md`.
- **Roles** are now `owner | admin | cashier` (`Roles` class in `backend/Program.cs`). `AdminOnly` policy = admin **or** owner; `OwnerOnly` exists for future use. `POST /api/users` rejects other role values (400). Angular `isAdmin()` treats owner as admin.
- `POST /api/auth/login` accepts optional `"client":"mobile"` → token lifetime `Jwt:MobileExpiryHours` (default 30 days) instead of `Jwt:ExpiryHours` (12h). No refresh-token flow yet.
- M0 Flutter code was written on a Windows box without Flutter — **not yet compiled**; run `flutter create .` inside `mobile/` first (see its README).

## Backend architecture highlights

- **SPA serving**: `app.UseDefaultFiles()` + `app.MapFallbackToFile("index.html")` — the backend serves the built Angular app directly from its own `wwwroot`, so the packaged desktop app runs from a single origin (`http://localhost:5050`), no separate frontend server needed in production.
- **Receipt/kitchen printing**: raw ESC/POS byte commands sent straight to the Windows print spooler, bypassing whatever driver is bound to the printer queue entirely.
  - `RawPrinterHelper.cs` — P/Invoke `winspool.drv`, opens the printer and writes bytes with `RAW` datatype (classic `OpenPrinter`/`StartDocPrinter`/`WritePrinter` pattern). Windows-only (`[SupportedOSPlatform("windows")]`).
  - `EscPosBuilder.cs` — fluent byte-buffer builder (Init, Align, Bold, DoubleSize, Feed, Cut, KickDrawer, Text, TwoCol/FourCol table helpers, ASCII sanitizer for the Urdu/Arabic characters ESC/POS can't render).
  - `ReceiptPrinter.cs` — builds the actual customer-receipt and kitchen-token byte streams using the builder above.
  - `LogoImage.cs` — rasterizes `backend/wwwroot/logo-receipt.jpg` into an ESC/POS bitmap (`GS v 0`) for the receipt header, cached after first use. (This is a *different, higher-detail* file from the website logo `frontend-ng/src/TL.png` — the original logo was only 74×67px and its wordmark was unreadable once rasterized; `logo-receipt.jpg` was supplied specifically for print.)
  - `EscPosBuilder.CutFeedLines = 8` — paper fed before the cut command, to clear the print-head-to-cutter gap. If paper gets trapped inside the printer instead of ejecting, increase this.
  - Cash drawer: `KickDrawer()` fires only on **Cash** payments (not Card), pin 2 by default (`ESC p 0 25 250`). If the drawer doesn't open, try pin 1 (RJ11 pin 5 wiring) — see `ReceiptPrinter.cs`.
  - **Printer must be configured** in Admin → Printer Settings → "Printer Name", which must exactly match the printer's registered name in Windows (Settings → Printers & scanners) — this is what `RawPrinterHelper` opens by name.
- **Printer hardware**: generic ESC/POS clone (label: Q838L, 80mm, USB, has a cash-drawer port). Originally used Windows' "Generic / Text Only" driver which garbled everything (stripped layout, mangled Unicode) — fixed by bypassing the driver entirely via RAW spooler mode above. No further driver hunting needed.

## Data model highlights

- **Dish**: `Name` (display name — can be Urdu), `PrintName` (English fallback used on receipts, since ESC/POS output is ASCII-only and silently drops non-ASCII chars), `Price` (tier 1), `DoublePrice` (tier 2, nullable), `ThirdPrice` (tier 3, nullable, only meaningful for `QuarterHalfFull` scheme), `PricingScheme` (`"SingleDouble"` | `"QuarterHalfFull"` | null≈`SingleDouble`). Sales-screen cart buttons are S/D or Q/H/F depending on scheme, shown only when `DoublePrice` is set.
- **Order**: `IsCancelled`/`CancelledAt`/`CancelReason` — soft-cancel (never hard-deleted), excluded from `/api/stats`, `/api/reports`, and both Z-Report endpoints, but still visible in Order History for audit. Cancel via `PATCH /api/orders/{id}/cancel`, admin-only screen.
- **Purchase (Expenses)**: supports multiple photo attachments via `PurchaseAttachment` (one-to-many, `POST/DELETE /api/purchases/{id}/attachments[/{attachmentId}]`). Legacy single `Purchase.ImagePath` kept for backward compat (auto-backfilled into `PurchaseAttachment` on first migration run) but the attachments list is the current source of truth.

## Frontend highlights

- `LanguageService` (`frontend-ng/src/app/language.service.ts`) — global Urdu/English **display** toggle in the nav bar (اردو/EN buttons), signal-based, persisted to `localStorage`. Only changes what's shown on Menu Setup + Sales screens (reuses `Dish.Name`/`PrintName` — no separate translation data). Does **not** affect what's stored on orders or printed on receipts, which have their own independent English-fallback logic.
- `.i18n-dish-name` CSS class = Noto Nastaliq Urdu font + sizing (17px), applied to every element that shows a dish name. Watch for **CSS specificity fights** — several base rules (`input[type="text"]`, `.dish-table td:nth-child(2)`, `.dish-card-name`, `.cart-item-name`) are equally or more specific than a bare `.i18n-dish-name` class and will silently win; the working rule lives near the end of `styles.css` using compound selectors (e.g. `input.i18n-dish-name`) specifically to beat them.
- POS cart portion buttons live in the cart item's top row (next to the dish thumbnail, before the name), 36×36px.
- **`ThemeService`** (`frontend-ng/src/app/theme.service.ts`) — configurable color theme, same signal + localStorage pattern as `LanguageService`. A `data-theme` attribute on `<html>` selects between theme blocks in `styles.css`'s `:root` section — **11 themes**: `midnight` (the original dark purple/gold, kept for anyone who prefers it), `lavender` (new default — light, professional, added because the dark theme "didn't look professional"), `slate` (light neutral gray/blue), `emerald` (light green accent), plus 7 user-supplied palettes — `sapphire`/`rose`/`teal`/`amber`/`cobalt`/`terracotta`/`sky` (labelled "Slate & Sky" — id different from `slate` to avoid collision, since the user's naming overlapped). Picker is the `<select class="theme-select">` in the nav bar (`app.component.ts`) — deliberately uses `[ngModel]`/`(ngModelChange)` rather than plain `[value]`/`(change)`, since a plain property-bound `<select>` with `*ngFor`-generated `<option>`s doesn't reliably reflect the bound value on first render in Angular (a known gotcha — confirmed by testing: `data-theme` was correctly set but the dropdown itself showed the wrong option selected until switched to `ngModel`).
  - Every color in `styles.css` is one of ~12 tokens (`--bg`, `--surface`, `--surface2`, `--border`, `--text`, `--text-muted`, `--accent`, `--accent-dim`, `--accent-contrast`, `--danger`, `--success`, `--warning`) or built from one via `color-mix()`/gradients — adding a theme means adding one more `[data-theme="..."]` block with these same tokens, nothing else needs touching. `--accent-contrast` (text color placed on a solid-accent background, e.g. buttons) is intentionally separate from `--text`, since whether it needs to be light or dark depends on how bright that theme's `--accent` is, not on the theme's overall light/dark-ness. `--warning` was added alongside the 7 user-supplied palettes (they specified explicit warning colors) and retrofitted onto the original 4 themes too, replacing 2 previously-hardcoded orange spots (`.zr-message--warn`, `.zr-load-error`).
  - User-supplied palette source columns map onto these tokens as: Primary→`--accent`, Primary Dark→`--accent-dim`, Background→`--bg`, Surface→`--surface`, Sidebar→`--surface2`, Main Text→`--text`, Secondary Text→`--text-muted`, Border→`--border`, Success/Warning/Error→`--success`/`--warning`/`--danger`. "Secondary" (a second accent color some palettes specified) has no home in the current token system and was dropped — not used anywhere in the CSS.
  - Printed output (`@media print`, and the print template in `orders.component.ts`) is correctly untouched by any of this — always fixed black-on-white for paper, regardless of on-screen theme.

## Desktop packaging (`desktop/`)

- `npm run dist` in `desktop/` = full pipeline: `ng build` → `dotnet publish` (self-contained `win-x64`) → merge Angular build into published `wwwroot` → generate `build/icon.ico` from `backend/wwwroot/TL.png` → `electron-builder` NSIS installer.
- Output: `desktop/release/Tehzeeb POS Setup 1.0.0.exe` (per-user install, no admin/UAC prompt; unsigned, so Windows SmartScreen warns on first run — "More info → Run anyway").
- **App data lives outside the install directory**: `%APPDATA%\tehzeeb-pos-desktop\backend-data\` (SQLite DB + uploaded images), because Program Files is read-only to standard user processes. `desktop/main.js` spawns the backend exe with this as its working directory.
- First launch auto-migrates from `D:\TehzeebPOS\backend\app.db` if that exact path exists (hardcoded — only true on this dev machine; installs on other PCs start blank unless you manually copy `app.db` + `wwwroot/uploads` into the AppData folder above).
- **Gotcha**: `electron-builder`'s `win.signAndEditExecutable: false` disables icon embedding into the exe, not just code signing — that's why the app briefly shipped with Electron's default icon despite a valid `icon.ico`. Fix in place: use `cross-env CSC_IDENTITY_AUTO_DISCOVERY=false` before `electron-builder` instead (see the `dist` script in `desktop/package.json`), which dodges the `winCodeSign` download/symlink-permission crash without touching icon embedding.
- As of the last session, **no installer had yet been built with dual/triple pricing or the Urdu toggle** — run `npm run dist` again before deploying if those matter.
- Windows 8 (32 or 64-bit) cannot run this app — .NET 8 and modern Electron/Chromium both require Windows 10+, independent of bitness. Windows 10 32-bit *would* work if ever needed (unlike Windows 8), by rebuilding with `win-x86`/Electron `ia32` — not currently built.

## Working conventions established this session

- **Testing against live production data**: this `app.db` holds the restaurant's real menu/orders, not test data. When verifying a change requires touching real rows (e.g. temporarily setting a price/flag to test UI behavior), always: fetch current state first, make the minimal temp change, verify, revert immediately, then re-fetch to confirm the revert. Never leave test data in place.
- **Non-ASCII text (Urdu/Arabic) via shell tools**: `curl -d` through Git Bash corrupts UTF-8 (shell re-encodes to the console codepage) — use Python `urllib.request` with explicit `.encode('utf-8')` and a `charset=utf-8` content-type header instead. Likewise, printing Urdu/Arabic strings to the Windows console crashes with a `cp1252` `UnicodeEncodeError` — write to a file and read it back instead of printing directly.
- User prefers direct execution over up-front clarification once a pattern is established, but wants a heads-up (not silent assumptions) on decisions with real business-logic consequences (e.g. was asked before generalizing Single/Double vs Quarter/Half/Full into one vs. two schemes).
