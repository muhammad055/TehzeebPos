# Tehzeeb POS — Project Context

Restaurant POS for Tehzeeb Restaurant & Kitchen (Ajman, UAE). This file is auto-loaded at the start of every Claude Code session in this repo — keep it updated as the source of truth for context handoff between sessions.

## Stack & Structure

```
backend/       ASP.NET Core 8 Minimal API — everything lives in Program.cs (single file).
               SQLite (app.db), EF Core. No migrations — schema changes are raw
               ALTER TABLE/CREATE TABLE IF NOT EXISTS checks in the startup block
               (pattern: check pragma_table_info('X') before ALTER, every time).
frontend-ng/   Angular 17 standalone app (esbuild-based "application" builder).
desktop/       Electron wrapper that packages backend+frontend into a Windows
               desktop installer. See "Desktop packaging" below.
```

Default login: `admin`/`admin123` (admin role), `cashier`/`cashier123` (cashier role).

Dev workflow (unchanged by desktop packaging): `dotnet run --urls "http://localhost:5050"` in `backend/`, `npm start` in `frontend-ng/` (serves on :4200, proxies /api to :5050).

**Gotcha**: `dotnet build`/`dotnet run` fails with a file-lock error if a previous backend instance is still running. Find and kill it first: `tasklist | grep -i posapi` then `taskkill //PID <pid> //F`.

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
