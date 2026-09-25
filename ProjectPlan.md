# Tehzeeb POS → SaaS Platform: Roadmap

## Context

Tehzeeb POS today is a single-restaurant, single-tenant Windows desktop app: Angular frontend + ASP.NET Core backend bundled into one Electron installer, talking to a local SQLite file, with zero server-side authentication. The owner wants to turn this into a multi-restaurant SaaS product with a mobile "Owner/Manager" app that surfaces **actual profit** (not just gross sales) by pulling in expenses, food cost, delivery-platform commissions, staff/rent/utilities/wastage — plus an AI assistant that can answer questions like "why did profit drop this week?"

Three foundational decisions were made before this plan (asked directly, since they reshape the entire roadmap):

1. **Deployment**: Convert the desktop POS into a **web app hosted on a Windows VPS**, rather than keeping it local-first with a sync layer. This means cashier terminals become browsers hitting a hosted backend instead of running their own local backend+DB.
2. **Multi-tenancy**: **One shared database**, every tenant-owned table gets a `RestaurantId` column, enforced at the data-access layer (not just at the API surface) — reject any cross-tenant access even if a valid ID is guessed.
3. **Mobile app**: **Flutter** (native Android + iOS), not a PWA.

**Consequence the owner specifically asked about — printer integration**: `RawPrinterHelper.cs` opens a Windows printer by name via `winspool.drv` P/Invoke, which only works for a printer visible to the machine *executing that code*. Once the backend runs on a remote VPS, it can no longer see a USB printer sitting in the restaurant. The fix is a **Local Print Agent** (Phase 1d below) — a small Windows service that stays at the restaurant and does the actual printing, receiving jobs from the cloud backend. The good news: `EscPosBuilder.cs`, `ReceiptPrinter.cs`, `LogoImage.cs`, and `RawPrinterHelper.cs` themselves barely change — they just move into a new small executable instead of running inside the API process. This is the same pattern real cloud POS products (Toast, Square, Lightspeed) use for exactly this reason.

**Consequence not directly asked but worth flagging now**: going fully cloud-hosted (vs. the local+sync option) means **order-taking requires internet at the restaurant**. If the VPS or the restaurant's connection goes down, cashiers can't ring in orders or print until it's back, unless an offline queue is added later (not in this plan — flag as a future hardening item, not a blocker to starting).

**Decided**: migrate off SQLite to **PostgreSQL** as part of the hosting move (confirmed 2026-09-24). Reasoning: SQLite is a single-writer file, poorly suited to a hosted web app serving concurrent cashier terminals + reporting queries + (eventually) many restaurants at once; Postgres is the standard, VPS-friendly choice for a multi-tenant EF Core app and plays well with EF Core global query filters for tenant isolation (Phase 1b). This is a bigger lift than the raw `ALTER TABLE` pattern currently in `Program.cs` — Phase 1 will need a real EF Core migrations setup (`dotnet ef migrations`) replacing the current pragma-check-and-ALTER startup pattern.

## Reuse map (what NOT to rebuild)

- `EscPosBuilder.cs`, `ReceiptPrinter.cs`, `LogoImage.cs`, `RawPrinterHelper.cs` — reused almost unchanged, relocated into the new Print Agent.
- `Purchase` + `PurchaseAttachment` (`backend/Program.cs:992-1012`, endpoints `765-903`) — reused as the backbone for the expense-category feature (Phase 3); `Category` is already a free-text column, just needs constraining + a manager-facing UI.
- `Order.PaymentMethod`, `Order.Discount` (`Program.cs:950-964`) — reused for cash/card and discount reporting; just need to actually be aggregated in `/api/stats`/`/api/reports`.
- `ApiService` (`frontend-ng/src/app/api.service.ts:184-266`) — the existing flat DTO/HTTP wrapper pattern is fine to extend, no need for a new abstraction.
- `LanguageService`'s signal-based pattern and the CSS-variable theme in `styles.css:8-19` — reuse as the visual base for both the web app and as a reference palette for the Flutter app.
- Dashboard/Reports hand-rolled bar charts (`dashboard.component.ts`, `reports.component.ts`) — fine to extend with new bars/cards for Phase 3; no need to adopt a charting library yet unless the new profit/food-cost visuals get complex.

## Phase order (owner's explicit sequencing, 2026-09-24)

The owner wants execution in this order, overriding a "ship value fastest" ordering: **Phase 1 (cloud migration) → Phase 2 (mobile apps) → then the rest** (analytics, AI, deeper ops, SaaS productization, in whatever order makes sense once the platform is cloud-hosted and mobile-accessible). The sections below are numbered to match this.

## Phase 1 progress (as of 2026-09-24)

Done, tested locally against Postgres in Docker: multi-tenant schema (`Restaurant` + `RestaurantId` on every tenant table), EF Core Migrations replacing the old raw-ALTER pattern, EF Core global query filters + explicit tenant-scoped mutation lookups (verified a second tenant can't see or PUT-hijack another tenant's row even with a guessed ID), JWT auth with an `AdminOnly` policy on admin-only endpoints, frontend token storage + `HttpInterceptorFn` attaching `Authorization: Bearer` + 401 auto-logout, `environment.ts`/`environment.prod.ts` replacing the hardcoded API URL. Full regression pass through the browser (login, POS sale end-to-end, Menu Setup, Order History, Reports/Z-Report, Users, Expenses) showed no functional changes.

Also done (2026-09-24): real menu data migrated from `app.db` into Postgres — 73 dishes (Urdu names + English print names + prices + pricing schemes, exact IDs preserved so existing dish photos still resolve), the real (non-default) user password hashes, and the actual printer/report Settings. Orders/Purchases were empty in the source DB (owner confirmed transactions are dummy/test data, not real), so nothing there to migrate. Verified visually in the POS screen — full real menu renders correctly.

Also done (2026-09-24): the Local Print Agent. Printing now goes through a pluggable `IPrintDispatcher` — `Printing:Mode=RemoteAgent` dispatches jobs over SignalR to a small new `print-agent/` Worker Service project running at the restaurant (authenticated via a per-restaurant `PrintAgentKey`, viewable/regenerable from Admin → Printer Settings), while the desktop build keeps printing in-process unchanged (default mode). Verified end-to-end: connect/status, successful print, error propagation (nonexistent printer), and "no agent connected" all work correctly through the full chain.

This surfaced a real blocker for keeping the desktop build working: the backend is now Postgres-only, but the desktop installer was designed to be a lightweight zero-external-dependency install. Decided: bundle a portable local PostgreSQL with the desktop installer (Electron manages it alongside the backend exe) rather than re-adding SQLite — one DB engine and one migrations set everywhere.

**Also done (2026-09-24): desktop Postgres bundling.** `desktop/main.js` now manages a bundled local PostgreSQL (via the `embedded-postgres` npm package) alongside the backend exe — init/start before the backend spawns, clean stop on quit, data persisted per-install, a per-install JWT secret generated once and persisted. Along the way, fixed a real bug: `dotnet publish` was including `appsettings.Development.json` (dev-only weak secret + dev DB credentials) in every publish output, including this installer — excluded via csproj now. Verified with a full real `npm run dist` build (145MB installer) run standalone: Postgres starts, backend connects/migrates/seeds fresh, login works, the SPA serves correctly, and a write persists.

Phase 1 is now functionally complete except for the actual VPS provisioning/deployment, which the user is doing manually.

## Phase 1 — Platform Foundation (blocks everything else)

**Goal**: move from desktop to a cloud-hosted, multi-tenant, internet-facing platform — **with no functional/feature changes**. Every screen, workflow, and behavior in the current app (POS sales flow, Menu Setup, Order History, Purchases/Expenses, Reports, Z-Report, printing) stays exactly as-is; only *where* and *how* it runs changes (hosting, auth, tenancy, printing plumbing). Analytics/profit features (old Phase 2) are explicitly deferred until after the mobile app.

1. **Schema**: add a `Restaurants` table (`Id`, `Name`, plan tier, created date) and a `RestaurantId` FK column to every tenant-owned table: `Dishes`, `Orders`, `OrderItems` (via parent Order), `Purchases`, `PurchaseAttachments` (via parent Purchase), `Users`, `Settings`. Existing Tehzeeb data gets backfilled with a single seeded `RestaurantId`.
2. **Tenant isolation, enforced twice (defense in depth)**:
   - EF Core global query filter on every tenant-scoped `DbSet` keyed off the current request's `RestaurantId` claim (`AppDbContext`, currently `Program.cs:915-924`), so a missed `.Where()` can't leak data.
   - Every write path explicitly validates the target row's `RestaurantId` matches the caller's before mutating (covers the "Restaurant A requests Restaurant B's order 123" case the owner called out).
3. **Real authentication**: replace the current no-op auth (`POST /api/auth/login` at `Program.cs:207-214`, which just checks a password hash and returns `{username, role}` with nothing enforced server-side) with JWT bearer auth — `AddAuthentication`/`AddAuthorization` + `[Authorize]` on every endpoint, token carries `RestaurantId` + `Role` claims. Frontend `AuthService` (`auth.service.ts:11-42`) stores the token instead of a trusted-by-nobody JSON blob; add an `HttpInterceptor` (none exist today) to attach `Authorization: Bearer` to every `ApiService` call.
4. **Web hosting**: point `ApiService`/`AuthService`'s hardcoded `http://localhost:5050/api` (`api.service.ts:186`, `auth.service.ts:14`) at an environment-based config (`environment.ts`, doesn't exist yet); deploy Angular build + backend to the VPS, served over HTTPS, same `UseDefaultFiles`/`MapFallbackToFile` single-origin pattern already in place — this part barely changes.
5. **Local Print Agent** (new small project, e.g. `print-agent/`): a lightweight Windows background service, one per restaurant terminal, that:
   - Connects to the cloud backend (SignalR is the natural fit given ASP.NET Core is already the backend framework) authenticated as that restaurant.
   - Receives the same `PrintReceiptDto`/`PrintKitchenDto` payloads currently built client-side and posted to `/api/print/receipt`/`/api/print/kitchen-token` (`Program.cs:717-763`).
   - Calls the relocated `RawPrinterHelper`/`ReceiptPrinter`/`EscPosBuilder` locally, exactly as today, including the `KickDrawer()` cash-drawer logic.
   - Printer name still configured in Admin → Printer Settings, just now stored per-restaurant and read by the agent instead of the API process.

## Phase 2 — Owner/Manager App (Flutter)

**Goal**: the mobile experience the owner described — check the restaurant at 11 PM without sitting in it. Built directly on top of Phase 1 (cloud-hosted, multi-tenant, JWT-authenticated API) with **no functional changes to the web app** yet — the mobile app mirrors what already exists (sales, orders, reports) rather than waiting for the profit/food-cost analytics in Phase 3.

1. New Flutter project, hitting the Phase 1 API (JWT auth, tenant-scoped) — no backend duplication. Add a couple of lightweight `/api/mobile/summary`-style endpoints tuned for home-screen tiles if the general-purpose `/api/stats` response ends up too heavy for a phone.
2. Two modes, gated by the existing `User.Role` (`Program.cs:990`, currently just `"admin"`/`"cashier"` strings — formalize into an enum with an `owner` role too): **Owner** (today's sales/orders/avg order tiles + 7/30-day trend charts, using whatever `/api/stats` already returns at this point) and **Admin/Manager** (orders, refunds, discounts, purchases, reports — the operational screens already built for web, exposed mobile-first).
3. Push notifications (Firebase Cloud Messaging) — initially basic (e.g. daily summary), with richer threshold alerts ("food cost 4.2% over target") added once Phase 3's analytics exist.
4. Manager should be able to manage dishes, update, add, delete, enable/disbale dishes

## Phase 3 — Profit/Expense/Food-Cost Analytics

**Goal**: ship the "actual profit instead of gross sales" feature on top of the now-multi-tenant, mobile-accessible platform, in both the existing Angular admin/reports screens and the Flutter app from Phase 2.

1. **Expense categories**: constrain `Purchase.Category` (`Program.cs:1002`) to a known set — Food, Staff Costs, Rent, Utilities, Wastage, Discounts/Promotions, Other — via a dropdown in `purchases.component.ts`; add optional `IsRecurring`/`Frequency` fields for rent/utilities/payroll-style entries.
2. **Delivery-platform tracking**: add `OrderSource` (InHouse/Talabat/Keeta/Noon) and `CommissionAmount` to `Order`; surface at checkout in `pos.component.ts` cart flow. New report card: Sales / Commission / Discounts / VAT / Net Contribution per platform, matching the owner's spec almost verbatim.
3. **Cash/card breakdown**: aggregate `Order.PaymentMethod` in `/api/stats` (`Program.cs:378-450`) and `/api/reports` (`454-506`) — the field already exists, it's just never been grouped.
4. **Food cost (MVP)**: add `CostPrice` to `Dish` (`Program.cs:928-948`), manually entered per dish in Admin → Menu Setup, exposing `FoodCostPercent = CostPrice / Price`. This replaces the "no cost data exists at all" gap; true per-ingredient recipe costing is deferred to Phase 5.
5. **Real P&L**: rework `/api/stats`'s naive `profit = sales - purchases` (`Program.cs:444-446`) into `Sales − Food Cost − Staff − Rent − Utilities − Wastage − Discounts − Commissions = Actual Profit`, using the categorized `Purchase` data from step 1 and the per-dish cost from step 4.
6. Feed these new numbers into the Phase 2 Flutter dashboard tiles and add the richer threshold push notifications deferred from Phase 2.

## Phase 4 — AI Assistant

**Goal**: "How was the restaurant yesterday?" answered from real data, not a bolted-on chatbot.

1. Claude API integration via a constrained set of backend "tools" (pre-built, parameterized report queries — not raw SQL execution) so every answer stays tenant-scoped and grounded, reusing the Phase 3 reporting endpoints as the tools' implementation.
2. `POST /api/ai/ask` endpoint, used by the Flutter app first, web chat widget later.
3. Proactive insights: scheduled job flags anomalies (cost spikes, sales dips vs. same weekday last week) and pushes them through the Phase 2 notification pipeline.

## Phase 5 — Deeper Operational Features

Inventory, true per-ingredient recipe costing (replacing the Phase 3 manual `CostPrice` estimate), supplier management, structured waste tracking (vs. the Phase 3 "Wastage" purchase category), employee attendance, branch comparison (trivial once `RestaurantId` exists — add a "chain" grouping for owners with multiple locations), menu engineering (margin × popularity matrix).

## Phase 6 — SaaS Productization

Tiered plans per the owner's own sketch (Owner App / Restaurant Management / Full Platform), self-serve restaurant onboarding (creates a `Restaurant` row + first admin user), Stripe billing, usage metering, an internal ops dashboard across all tenants.

## Verification approach (per phase, not all at once)

- **Phase 1**: log in as two different seeded restaurants locally, confirm restaurant A's JWT cannot read/write restaurant B's orders/dishes/purchases via direct API calls (curl/Postman), even when guessing valid IDs. Print a real receipt via the relocated Print Agent against the actual Q838L printer to confirm ESC/POS output, cut, and cash-drawer kick all still work byte-for-byte like today.
- **Phase 2**: Flutter app against the hosted staging backend, confirm Owner vs Admin role gating and that dashboard numbers match the web Reports page for the same day.
- **Phase 3**: cross-check the new `/api/stats` profit figure by hand against a day's real (or temporarily test) Purchases + Orders data, following the existing live-data testing convention (fetch → minimal temp change → verify → revert immediately); confirm the same figures now show correctly in the Phase 2 Flutter dashboard.
- **Phase 4**: ask the AI assistant a handful of real questions ("why did profit decrease this week?") and confirm its answer traces back to actual query results, not hallucinated numbers.
