# Tehzeeb POS

Lightweight Point of Sale for Tehzeeb Restaurant & Kitchen.  
**Stack:** .NET 8 Minimal API · SQLite · Angular 17 Standalone

---

## Prerequisites

```bash
# Check .NET 8 SDK
dotnet --version   # must be 8.x

# Check Node & Angular CLI
node --version     # 18+ recommended
npm i -g @angular/cli@17
ng version
```

---

## 1 — Run the Backend

```bash
cd pos-app/backend

dotnet restore
dotnet run --urls "http://localhost:5050"
```
API Tool 
npm run dev
On first run, `app.db` is created automatically via `EnsureCreated()`.  
The API is live at **http://localhost:5050/api**

---

## 2 — Run the Frontend

```bash
cd pos-app/frontend-ng

npm install
npm start
```

Opens at **http://localhost:4200**

---

## Screens

| Route    | Description                                    |
|----------|------------------------------------------------|
| `/pos`   | Cashier screen — search dishes, build order, print receipt |
| `/admin` | Menu setup — add/edit dishes, set default tax rate |

---

## API Endpoints

| Method | Path                        | Purpose                  |
|--------|-----------------------------|--------------------------|
| GET    | `/api/dishes`               | List all dishes          |
| POST   | `/api/dishes`               | Create dish              |
| PUT    | `/api/dishes/{id}`          | Update dish              |
| DELETE | `/api/dishes/{id}`          | Delete dish              |
| GET    | `/api/settings`             | Get all settings         |
| PUT    | `/api/settings/{key}`       | Upsert a setting         |
| POST   | `/api/orders`               | Save completed order     |
| GET    | `/api/orders`               | Last 50 orders           |
| GET    | `/api/orders/{id}`          | Single order + items     |

---

## Database

SQLite file: `backend/app.db`  
View with: [DB Browser for SQLite](https://sqlitebrowser.org/) (free macOS app)

Tables: `Dishes` · `Orders` · `OrderItems` · `Settings`

---

## Receipt Printing

Click **Print Receipt** after placing an order.  
Uses `@media print` CSS targeting 80mm thermal printers.  
In Chrome: set **Paper size = Custom** · Width = 80mm, disable headers/footers.

---

## Project Structure

```
pos-app/
├── backend/
│   ├── Program.cs          ← All API endpoints + EF Core models
│   └── PosApi.csproj
└── frontend-ng/
    ├── src/
    │   ├── main.ts          ← Bootstrap
    │   ├── styles.css       ← Global styles + print CSS
    │   └── app/
    │       ├── app.component.ts    ← Shell + nav
    │       ├── app.routes.ts       ← Routes
    │       ├── api.service.ts      ← All HTTP calls
    │       ├── admin/              ← Menu management
    │       └── pos/                ← Cashier screen
    ├── angular.json
    ├── package.json
    └── proxy.conf.json
```
