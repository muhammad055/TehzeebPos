using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.FileProviders;
using System.Security.Cryptography;
using System.Text;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddDbContext<AppDbContext>(opt =>
    opt.UseSqlite("Data Source=app.db"));

builder.Services.AddCors(opt =>
    opt.AddDefaultPolicy(p =>
        p.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod()));

builder.Services.AddEndpointsApiExplorer();

var app = builder.Build();

// Auto-migrate on startup
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    db.Database.EnsureCreated();

    // Add ImagePath column to Dishes if missing — check first to avoid EF Core error log
    var conn = db.Database.GetDbConnection();
    if (conn.State != System.Data.ConnectionState.Open) conn.Open();
    using (var cmd = conn.CreateCommand())
    {
        cmd.CommandText = "SELECT COUNT(*) FROM pragma_table_info('Dishes') WHERE name='ImagePath'";
        if (Convert.ToInt64(cmd.ExecuteScalar()) == 0)
            db.Database.ExecuteSqlRaw("ALTER TABLE Dishes ADD COLUMN ImagePath TEXT");
    }

    // Add IsActive column to Dishes if missing
    using (var cmdA = conn.CreateCommand())
    {
        cmdA.CommandText = "SELECT COUNT(*) FROM pragma_table_info('Dishes') WHERE name='IsActive'";
        if (Convert.ToInt64(cmdA.ExecuteScalar()) == 0)
            db.Database.ExecuteSqlRaw("ALTER TABLE Dishes ADD COLUMN IsActive INTEGER NOT NULL DEFAULT 1");
    }

    // Add PrintName column to Dishes if missing — lets Name hold a non-Latin
    // script (e.g. Urdu) for on-screen display while receipts/kitchen tickets
    // (ASCII-only ESC/POS output) print this instead, when set.
    using (var cmdP = conn.CreateCommand())
    {
        cmdP.CommandText = "SELECT COUNT(*) FROM pragma_table_info('Dishes') WHERE name='PrintName'";
        if (Convert.ToInt64(cmdP.ExecuteScalar()) == 0)
            db.Database.ExecuteSqlRaw("ALTER TABLE Dishes ADD COLUMN PrintName TEXT");
    }

    // Add DoublePrice column to Dishes if missing — optional 2nd price tier
    // (meaning depends on PricingScheme: "Double" for Single/Double dishes
    // like Biryani, or "Half" for Quarter/Half/Full dishes like Karahi).
    // Null means the dish only has one price (Price).
    using (var cmdDP = conn.CreateCommand())
    {
        cmdDP.CommandText = "SELECT COUNT(*) FROM pragma_table_info('Dishes') WHERE name='DoublePrice'";
        if (Convert.ToInt64(cmdDP.ExecuteScalar()) == 0)
            db.Database.ExecuteSqlRaw("ALTER TABLE Dishes ADD COLUMN DoublePrice REAL");
    }

    // Add ThirdPrice column to Dishes if missing — optional 3rd price tier,
    // only used for Quarter/Half/Full dishes ("Full" price). Null otherwise.
    using (var cmdTP = conn.CreateCommand())
    {
        cmdTP.CommandText = "SELECT COUNT(*) FROM pragma_table_info('Dishes') WHERE name='ThirdPrice'";
        if (Convert.ToInt64(cmdTP.ExecuteScalar()) == 0)
            db.Database.ExecuteSqlRaw("ALTER TABLE Dishes ADD COLUMN ThirdPrice REAL");
    }

    // Add PricingScheme column to Dishes if missing — "SingleDouble" or
    // "QuarterHalfFull", determines the button labels on the Sales screen.
    // Null/missing is treated as "SingleDouble" by convention (so existing
    // dishes with DoublePrice already set keep behaving exactly as before).
    using (var cmdPS = conn.CreateCommand())
    {
        cmdPS.CommandText = "SELECT COUNT(*) FROM pragma_table_info('Dishes') WHERE name='PricingScheme'";
        if (Convert.ToInt64(cmdPS.ExecuteScalar()) == 0)
            db.Database.ExecuteSqlRaw("ALTER TABLE Dishes ADD COLUMN PricingScheme TEXT");
    }

    // Create Users table if it doesn't exist (safe for existing databases)
    db.Database.ExecuteSqlRaw(@"
        CREATE TABLE IF NOT EXISTS Users (
            Id       INTEGER PRIMARY KEY AUTOINCREMENT,
            Username TEXT NOT NULL UNIQUE,
            Password TEXT NOT NULL,
            Role     TEXT NOT NULL
        )
    ");

    // Add TokenNumber column to Orders if missing
    using (var cmd2 = conn.CreateCommand())
    {
        cmd2.CommandText = "SELECT COUNT(*) FROM pragma_table_info('Orders') WHERE name='TokenNumber'";
        if (Convert.ToInt64(cmd2.ExecuteScalar()) == 0)
            db.Database.ExecuteSqlRaw("ALTER TABLE Orders ADD COLUMN TokenNumber INTEGER NOT NULL DEFAULT 0");
    }

    // Add PaymentMethod column to Orders if missing
    using (var cmd3 = conn.CreateCommand())
    {
        cmd3.CommandText = "SELECT COUNT(*) FROM pragma_table_info('Orders') WHERE name='PaymentMethod'";
        if (Convert.ToInt64(cmd3.ExecuteScalar()) == 0)
            db.Database.ExecuteSqlRaw("ALTER TABLE Orders ADD COLUMN PaymentMethod TEXT NOT NULL DEFAULT 'Cash'");
    }

    // Add cancellation columns to Orders if missing — cancelled orders are
    // kept (not deleted) for audit purposes, just excluded from sales totals.
    using (var cmd4 = conn.CreateCommand())
    {
        cmd4.CommandText = "SELECT COUNT(*) FROM pragma_table_info('Orders') WHERE name='IsCancelled'";
        if (Convert.ToInt64(cmd4.ExecuteScalar()) == 0)
            db.Database.ExecuteSqlRaw("ALTER TABLE Orders ADD COLUMN IsCancelled INTEGER NOT NULL DEFAULT 0");
    }
    using (var cmd5 = conn.CreateCommand())
    {
        cmd5.CommandText = "SELECT COUNT(*) FROM pragma_table_info('Orders') WHERE name='CancelledAt'";
        if (Convert.ToInt64(cmd5.ExecuteScalar()) == 0)
            db.Database.ExecuteSqlRaw("ALTER TABLE Orders ADD COLUMN CancelledAt TEXT");
    }
    using (var cmd6 = conn.CreateCommand())
    {
        cmd6.CommandText = "SELECT COUNT(*) FROM pragma_table_info('Orders') WHERE name='CancelReason'";
        if (Convert.ToInt64(cmd6.ExecuteScalar()) == 0)
            db.Database.ExecuteSqlRaw("ALTER TABLE Orders ADD COLUMN CancelReason TEXT");
    }

    // Create Purchases table if it doesn't exist
    db.Database.ExecuteSqlRaw(@"
        CREATE TABLE IF NOT EXISTS Purchases (
            Id          INTEGER PRIMARY KEY AUTOINCREMENT,
            Date        TEXT NOT NULL,
            Supplier    TEXT NOT NULL DEFAULT '',
            Description TEXT NOT NULL DEFAULT '',
            TotalAmount REAL NOT NULL DEFAULT 0,
            ImagePath   TEXT,
            Category    TEXT NOT NULL DEFAULT 'General'
        )
    ");

    // Create PurchaseAttachments table if it doesn't exist, and backfill any
    // existing single-image Purchases.ImagePath into it — a one-time copy
    // that only runs the first time this table is created, so expenses keep
    // their old receipt photo as their first attachment going forward.
    using (var checkCmd = conn.CreateCommand())
    {
        checkCmd.CommandText = "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='PurchaseAttachments'";
        var attachmentsTableExisted = Convert.ToInt64(checkCmd.ExecuteScalar()) > 0;

        db.Database.ExecuteSqlRaw(@"
            CREATE TABLE IF NOT EXISTS PurchaseAttachments (
                Id         INTEGER PRIMARY KEY AUTOINCREMENT,
                PurchaseId INTEGER NOT NULL,
                ImagePath  TEXT NOT NULL,
                UploadedAt TEXT NOT NULL
            )
        ");

        if (!attachmentsTableExisted)
        {
            db.Database.ExecuteSqlRaw(@"
                INSERT INTO PurchaseAttachments (PurchaseId, ImagePath, UploadedAt)
                SELECT Id, ImagePath, Date FROM Purchases
                WHERE ImagePath IS NOT NULL AND ImagePath <> ''
            ");
        }
    }

    if (!db.Settings.Any())
        db.Settings.Add(new Setting { Key = "DefaultTaxRate", Value = "5" });

    if (!db.Users.Any())
    {
        db.Users.Add(new User { Username = "admin",   Password = HashPassword("admin123"),   Role = "admin" });
        db.Users.Add(new User { Username = "cashier", Password = HashPassword("cashier123"), Role = "cashier" });
    }
    else
    {
        var plain = db.Users.Where(u => u.Password.Length != 64).ToList();
        foreach (var u in plain) u.Password = HashPassword(u.Password);
    }

    db.SaveChanges();
}

var wwwRoot = Path.Combine(Directory.GetCurrentDirectory(), "wwwroot");
Directory.CreateDirectory(Path.Combine(wwwRoot, "uploads", "dishes"));
Directory.CreateDirectory(Path.Combine(wwwRoot, "uploads", "purchases"));
var wwwRootProvider = new PhysicalFileProvider(wwwRoot);
app.UseDefaultFiles(new DefaultFilesOptions { FileProvider = wwwRootProvider });
app.UseStaticFiles(new StaticFileOptions
{
    FileProvider = wwwRootProvider,
    RequestPath  = ""
});

app.UseCors();

static string HashPassword(string p) =>
    Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(p))).ToLower();

// ─── AUTH ────────────────────────────────────────────────────────────────────

app.MapPost("/api/auth/login", async (LoginDto dto, AppDbContext db) =>
{
    var hashed = HashPassword(dto.Password);
    var user = await db.Users.FirstOrDefaultAsync(
        u => u.Username == dto.Username && u.Password == hashed);
    if (user is null) return Results.Unauthorized();
    return Results.Ok(new { username = user.Username, role = user.Role });
});

// ─── USERS ──────────────────────────────────────────────────────────────────

app.MapGet("/api/users", async (AppDbContext db) =>
    await db.Users.Select(u => new { u.Id, u.Username, u.Role }).ToListAsync());

app.MapPost("/api/users", async (CreateUserDto dto, AppDbContext db) =>
{
    if (await db.Users.AnyAsync(u => u.Username == dto.Username))
        return Results.Conflict(new { message = "Username already exists." });
    var user = new User { Username = dto.Username, Password = HashPassword(dto.Password), Role = dto.Role };
    db.Users.Add(user);
    await db.SaveChangesAsync();
    return Results.Created($"/api/users/{user.Id}", new { user.Id, user.Username, user.Role });
});

app.MapPut("/api/users/{id:int}/password", async (int id, ChangePasswordDto dto, AppDbContext db) =>
{
    var user = await db.Users.FindAsync(id);
    if (user is null) return Results.NotFound();
    user.Password = HashPassword(dto.Password);
    await db.SaveChangesAsync();
    return Results.NoContent();
});

app.MapDelete("/api/users/{id:int}", async (int id, AppDbContext db) =>
{
    var user = await db.Users.FindAsync(id);
    if (user is null) return Results.NotFound();
    db.Users.Remove(user);
    await db.SaveChangesAsync();
    return Results.NoContent();
});

// ─── DISH IMAGE ────────────────────────────────────────────────────────────

app.MapPost("/api/dishes/{id:int}/image",
    async (int id, HttpRequest request, AppDbContext db, IWebHostEnvironment env) =>
{
    var dish = await db.Dishes.FindAsync(id);
    if (dish is null) return Results.NotFound();
    if (!request.HasFormContentType || request.Form.Files.Count == 0)
        return Results.BadRequest("No file.");
    var file = request.Form.Files[0];
    var webRoot = Path.Combine(Directory.GetCurrentDirectory(), "wwwroot");
    var dir = Path.Combine(webRoot, "uploads", "dishes");
    Directory.CreateDirectory(dir);
    var filename = $"dish-{id}.jpg";
    using (var fs = new FileStream(Path.Combine(dir, filename), FileMode.Create))
        await file.CopyToAsync(fs);
    dish.ImagePath = $"/uploads/dishes/{filename}";
    await db.SaveChangesAsync();
    return Results.Ok(new { imagePath = dish.ImagePath });
});

// ─── SETTINGS ───────────────────────────────────────────────────────────────

app.MapGet("/api/settings", async (AppDbContext db) =>
    await db.Settings.ToListAsync());

app.MapPut("/api/settings/{key}", async (string key, SettingDto dto, AppDbContext db) =>
{
    var setting = await db.Settings.FirstOrDefaultAsync(s => s.Key == key);
    if (setting is null)
    {
        setting = new Setting { Key = key, Value = dto.Value };
        db.Settings.Add(setting);
    }
    else
    {
        setting.Value = dto.Value;
    }
    await db.SaveChangesAsync();
    return Results.Ok(setting);
});

// ─── DISHES ─────────────────────────────────────────────────────────────────

app.MapGet("/api/dishes", async (AppDbContext db) =>
    await db.Dishes.OrderBy(d => d.Name).ToListAsync());

app.MapPost("/api/dishes", async (DishDto dto, AppDbContext db) =>
{
    var dish = new Dish { Name = dto.Name, Price = dto.Price, TaxRate = dto.TaxRate, PrintName = dto.PrintName, DoublePrice = dto.DoublePrice, ThirdPrice = dto.ThirdPrice, PricingScheme = dto.PricingScheme };
    db.Dishes.Add(dish);
    await db.SaveChangesAsync();
    return Results.Created($"/api/dishes/{dish.Id}", dish);
});

app.MapPut("/api/dishes/{id:int}", async (int id, DishDto dto, AppDbContext db) =>
{
    var dish = await db.Dishes.FindAsync(id);
    if (dish is null) return Results.NotFound();
    dish.Name = dto.Name;
    dish.Price = dto.Price;
    dish.TaxRate = dto.TaxRate;
    dish.PrintName = dto.PrintName;
    dish.DoublePrice = dto.DoublePrice;
    dish.ThirdPrice = dto.ThirdPrice;
    dish.PricingScheme = dto.PricingScheme;
    await db.SaveChangesAsync();
    return Results.Ok(dish);
});

app.MapPatch("/api/dishes/{id:int}/toggle", async (int id, AppDbContext db) =>
{
    var dish = await db.Dishes.FindAsync(id);
    if (dish is null) return Results.NotFound();
    dish.IsActive = !dish.IsActive;
    await db.SaveChangesAsync();
    return Results.Ok(dish);
});

app.MapPatch("/api/dishes/toggle-all", async (ToggleAllDto dto, AppDbContext db) =>
{
    await db.Dishes.ExecuteUpdateAsync(s => s.SetProperty(d => d.IsActive, dto.IsActive));
    return Results.Ok(await db.Dishes.ToListAsync());
});

app.MapDelete("/api/dishes/{id:int}", async (int id, AppDbContext db) =>
{
    var dish = await db.Dishes.FindAsync(id);
    if (dish is null) return Results.NotFound();
    db.Dishes.Remove(dish);
    await db.SaveChangesAsync();
    return Results.NoContent();
});

// ─── ORDERS ─────────────────────────────────────────────────────────────────

app.MapGet("/api/orders", async (AppDbContext db, string? date, string? from, string? to) =>
{
    var uaeOffset = TimeSpan.FromHours(4);

    // Date range (from + to)
    if (!string.IsNullOrEmpty(from) && !string.IsNullOrEmpty(to) &&
        DateOnly.TryParse(from, out var fd) && DateOnly.TryParse(to, out var td))
    {
        var utcStart = new DateTime(fd.Year, fd.Month, fd.Day) - uaeOffset;
        var utcEnd   = new DateTime(td.Year, td.Month, td.Day).AddDays(1) - uaeOffset;
        return await db.Orders.Include(o => o.Items)
            .Where(o => o.OrderDate >= utcStart && o.OrderDate < utcEnd)
            .OrderByDescending(o => o.OrderDate)
            .ToListAsync();
    }

    // Single date (backward compat)
    if (!string.IsNullOrEmpty(date) && DateOnly.TryParse(date, out var d))
    {
        var utcStart = new DateTime(d.Year, d.Month, d.Day) - uaeOffset;
        var utcEnd   = utcStart.AddDays(1);
        return await db.Orders.Include(o => o.Items)
            .Where(o => o.OrderDate >= utcStart && o.OrderDate < utcEnd)
            .OrderByDescending(o => o.OrderDate)
            .ToListAsync();
    }

    return await db.Orders.Include(o => o.Items)
        .OrderByDescending(o => o.OrderDate)
        .Take(50)
        .ToListAsync();
});

app.MapGet("/api/stats", async (AppDbContext db) =>
{
    var uaeOffset = TimeSpan.FromHours(4);
    var uaeNow = DateTime.UtcNow + uaeOffset;

    var todayUtcStart = uaeNow.Date - uaeOffset;
    var dow = (int)uaeNow.DayOfWeek;
    var weekUtcStart = uaeNow.Date.AddDays(-dow) - uaeOffset;
    var monthUtcStart = new DateTime(uaeNow.Year, uaeNow.Month, 1) - uaeOffset;

    var orders = await db.Orders.Include(o => o.Items).Where(o => !o.IsCancelled).ToListAsync();

    var todayOrders = orders.Where(o => o.OrderDate >= todayUtcStart).ToList();
    var weekOrders  = orders.Where(o => o.OrderDate >= weekUtcStart).ToList();
    var monthOrders = orders.Where(o => o.OrderDate >= monthUtcStart).ToList();

    // Expense start dates (purchases stored as UTC-midnight of the calendar date)
    var todayPurchStart = new DateTime(uaeNow.Year, uaeNow.Month, uaeNow.Day, 0, 0, 0, DateTimeKind.Utc);
    var weekPurchStart  = new DateTime(uaeNow.Date.AddDays(-dow).Year,
                                       uaeNow.Date.AddDays(-dow).Month,
                                       uaeNow.Date.AddDays(-dow).Day, 0, 0, 0, DateTimeKind.Utc);
    var monthPurchStart = new DateTime(uaeNow.Year, uaeNow.Month, 1, 0, 0, 0, DateTimeKind.Utc);

    var purchases = await db.Purchases.ToListAsync();
    var todayExpenses = purchases.Where(p => p.Date >= todayPurchStart).Sum(p => p.TotalAmount);
    var weekExpenses  = purchases.Where(p => p.Date >= weekPurchStart).Sum(p => p.TotalAmount);
    var monthExpenses = purchases.Where(p => p.Date >= monthPurchStart).Sum(p => p.TotalAmount);

    var topItems = orders
        .SelectMany(o => o.Items)
        .GroupBy(i => i.DishName)
        .Select(g => new {
            name     = g.Key,
            quantity = g.Sum(i => i.Quantity),
            revenue  = g.Sum(i => i.LineTotal)
        })
        .OrderByDescending(x => x.quantity)
        .Take(5)
        .ToList();

    var last7Days = Enumerable.Range(0, 7).Select(i =>
    {
        var localDate = uaeNow.Date.AddDays(-(6 - i));
        var utcStart  = localDate - uaeOffset;
        var utcEnd    = utcStart.AddDays(1);
        return new
        {
            date  = localDate.ToString("MMM dd"),
            total = orders.Where(o => o.OrderDate >= utcStart && o.OrderDate < utcEnd)
                          .Sum(o => o.GrandTotal)
        };
    }).ToList();

    var todaySales  = todayOrders.Sum(o => o.GrandTotal);
    var weekSales   = weekOrders.Sum(o => o.GrandTotal);
    var monthSales  = monthOrders.Sum(o => o.GrandTotal);

    return Results.Ok(new
    {
        todaySales,
        todayOrderCount = todayOrders.Count,
        weekSales,
        monthSales,
        todayExpenses,
        weekExpenses,
        monthExpenses,
        todayProfit  = todaySales  - todayExpenses,
        weekProfit   = weekSales   - weekExpenses,
        monthProfit  = monthSales  - monthExpenses,
        topItems,
        last7Days
    });
});

// ─── REPORTS ────────────────────────────────────────────────────────────────

app.MapGet("/api/reports", async (AppDbContext db, string? from, string? to, int? dishId) =>
{
    var uaeOffset = TimeSpan.FromHours(4);
    var today     = (DateTime.UtcNow + uaeOffset).Date;

    var fromDate = from != null && DateOnly.TryParse(from, out var fd)
        ? fd.ToDateTime(TimeOnly.MinValue) : today;
    var toDate = to != null && DateOnly.TryParse(to, out var td)
        ? td.ToDateTime(TimeOnly.MinValue) : today;

    var fromUtc = fromDate - uaeOffset;
    var toUtc   = toDate.AddDays(1) - uaeOffset;

    var orders = await db.Orders
        .Include(o => o.Items)
        .Where(o => o.OrderDate >= fromUtc && o.OrderDate < toUtc && !o.IsCancelled)
        .ToListAsync();

    var items = orders.SelectMany(o => o.Items).ToList();
    if (dishId.HasValue)
        items = items.Where(i => i.DishId == dishId.Value).ToList();

    var summary = new
    {
        totalOrders    = orders.Count,
        totalRevenue   = Math.Round(orders.Sum(o => o.GrandTotal), 2),
        avgOrderValue  = orders.Count > 0 ? Math.Round(orders.Average(o => o.GrandTotal), 2) : 0m,
        totalItemsSold = items.Sum(i => i.Quantity)
    };

    var itemBreakdown = items
        .GroupBy(i => new { i.DishId, i.DishName })
        .Select(g => new {
            dishId   = g.Key.DishId,
            dishName = g.Key.DishName,
            qtySold  = g.Sum(i => i.Quantity),
            revenue  = Math.Round(g.Sum(i => i.LineTotal), 2)
        })
        .OrderByDescending(x => x.qtySold)
        .ToList();

    var dailySales = orders
        .GroupBy(o => (o.OrderDate + uaeOffset).Date)
        .Select(g => new {
            date    = g.Key.ToString("yyyy-MM-dd"),
            revenue = Math.Round(g.Sum(o => o.GrandTotal), 2),
            orders  = g.Count()
        })
        .OrderBy(x => x.date)
        .ToList();

    return Results.Ok(new { summary, itemBreakdown, dailySales });
});

app.MapGet("/api/orders/{id:int}", async (int id, AppDbContext db) =>
{
    var order = await db.Orders.Include(o => o.Items).FirstOrDefaultAsync(o => o.Id == id);
    return order is null ? Results.NotFound() : Results.Ok(order);
});

app.MapPatch("/api/orders/{id:int}/cancel", async (int id, CancelOrderDto dto, AppDbContext db) =>
{
    var order = await db.Orders.Include(o => o.Items).FirstOrDefaultAsync(o => o.Id == id);
    if (order is null) return Results.NotFound();
    if (order.IsCancelled) return Results.BadRequest(new { message = "Order is already cancelled." });

    order.IsCancelled = true;
    order.CancelledAt = DateTime.UtcNow;
    order.CancelReason = string.IsNullOrWhiteSpace(dto.Reason) ? null : dto.Reason.Trim();
    await db.SaveChangesAsync();
    return Results.Ok(order);
});

app.MapPost("/api/orders", async (CreateOrderDto dto, AppDbContext db) =>
{
    // Daily sequential token number (resets each UAE day, UTC+4)
    var uaeOffset  = TimeSpan.FromHours(4);
    var todayUae   = DateTimeOffset.UtcNow.ToOffset(uaeOffset).Date;
    var dayStartUtc = new DateTime(todayUae.Year, todayUae.Month, todayUae.Day, 0, 0, 0, DateTimeKind.Utc)
                          .AddHours(-4);
    var maxToken = await db.Orders
        .Where(o => o.OrderDate >= dayStartUtc)
        .MaxAsync(o => (int?)o.TokenNumber) ?? 0;

    var order = new Order
    {
        OrderDate     = DateTime.UtcNow,
        TokenNumber   = maxToken + 1,
        PaymentMethod = dto.PaymentMethod,
        SubTotal      = dto.SubTotal,
        Discount    = dto.Discount,
        TaxTotal    = dto.TaxTotal,
        GrandTotal  = dto.GrandTotal,
        Items = dto.Items.Select(i => new OrderItem
        {
            DishId    = i.DishId,
            DishName  = i.DishName,
            Quantity  = i.Quantity,
            UnitPrice = i.UnitPrice,
            LineTotal = i.LineTotal
        }).ToList()
    };
    db.Orders.Add(order);
    await db.SaveChangesAsync();
    return Results.Created($"/api/orders/{order.Id}", order);
});

// ─── Z-REPORT ───────────────────────────────────────────────────────────────

app.MapGet("/api/z-report", async (AppDbContext db) =>
{
    var lastTimeSetting  = await db.Settings.FirstOrDefaultAsync(s => s.Key == "LastZReportTime");
    var reportNumSetting = await db.Settings.FirstOrDefaultAsync(s => s.Key == "ZReportNumber");

    DateTime? shiftStart = null;
    if (lastTimeSetting?.Value is { Length: > 0 } lv)
        shiftStart = DateTime.Parse(lv, null, System.Globalization.DateTimeStyles.RoundtripKind);

    var nextNum = (reportNumSetting?.Value is { Length: > 0 } nv ? int.Parse(nv) : 0) + 1;

    var orders = await db.Orders.Include(o => o.Items)
        .Where(o => (shiftStart == null || o.OrderDate >= shiftStart) && !o.IsCancelled)
        .ToListAsync();

    var topItems = orders.SelectMany(o => o.Items)
        .GroupBy(i => i.DishName)
        .Select(g => new { name = g.Key, qty = g.Sum(i => i.Quantity), revenue = g.Sum(i => i.LineTotal) })
        .OrderByDescending(x => x.qty).Take(10).ToList();

    return Results.Ok(new
    {
        nextReportNumber = nextNum,
        shiftStart       = shiftStart?.ToString("O"),
        totalOrders      = orders.Count,
        grossSales       = orders.Sum(o => o.GrandTotal),
        discounts        = orders.Sum(o => o.Discount),
        taxTotal         = orders.Sum(o => o.TaxTotal),
        netSales         = orders.Sum(o => o.SubTotal),
        topItems
    });
});

app.MapPost("/api/z-report", async (AppDbContext db) =>
{
    var lastTimeSetting  = await db.Settings.FirstOrDefaultAsync(s => s.Key == "LastZReportTime");
    var reportNumSetting = await db.Settings.FirstOrDefaultAsync(s => s.Key == "ZReportNumber");

    DateTime? shiftStart = null;
    if (lastTimeSetting?.Value is { Length: > 0 } lv)
        shiftStart = DateTime.Parse(lv, null, System.Globalization.DateTimeStyles.RoundtripKind);

    var reportNum = (reportNumSetting?.Value is { Length: > 0 } nv ? int.Parse(nv) : 0) + 1;

    var orders = await db.Orders.Include(o => o.Items)
        .Where(o => (shiftStart == null || o.OrderDate >= shiftStart) && !o.IsCancelled)
        .ToListAsync();

    var topItems = orders.SelectMany(o => o.Items)
        .GroupBy(i => i.DishName)
        .Select(g => new { name = g.Key, qty = g.Sum(i => i.Quantity), revenue = g.Sum(i => i.LineTotal) })
        .OrderByDescending(x => x.qty).Take(10).ToList();

    var now        = DateTime.UtcNow;
    var grossSales = orders.Sum(o => o.GrandTotal);
    var discounts  = orders.Sum(o => o.Discount);
    var taxTotal   = orders.Sum(o => o.TaxTotal);
    var netSales   = orders.Sum(o => o.SubTotal);

    // ── Reset shift in Settings ─────────────────────────
    var nowStr = now.ToString("O");
    if (lastTimeSetting  != null) lastTimeSetting.Value  = nowStr;
    else db.Settings.Add(new Setting { Key = "LastZReportTime", Value = nowStr });

    if (reportNumSetting != null) reportNumSetting.Value = reportNum.ToString();
    else db.Settings.Add(new Setting { Key = "ZReportNumber",   Value = reportNum.ToString() });

    await db.SaveChangesAsync();

    // ── Email if configured ─────────────────────────────
    var smtpHost = (await db.Settings.FirstOrDefaultAsync(s => s.Key == "SmtpHost"))?.Value;
    var smtpPort = (await db.Settings.FirstOrDefaultAsync(s => s.Key == "SmtpPort"))?.Value ?? "587";
    var smtpUser = (await db.Settings.FirstOrDefaultAsync(s => s.Key == "SmtpUsername"))?.Value;
    var smtpPass = (await db.Settings.FirstOrDefaultAsync(s => s.Key == "SmtpPassword"))?.Value;
    var toEmail  = (await db.Settings.FirstOrDefaultAsync(s => s.Key == "ReportToEmail"))?.Value;

    bool   emailSent  = false;
    string? emailError = null;

    if (!string.IsNullOrWhiteSpace(smtpHost) && !string.IsNullOrWhiteSpace(toEmail)
        && !string.IsNullOrWhiteSpace(smtpUser) && !string.IsNullOrWhiteSpace(smtpPass))
    {
        try
        {
            var genUae   = now.AddHours(4);
            var startStr = shiftStart.HasValue
                ? shiftStart.Value.AddHours(4).ToString("dd MMM yyyy HH:mm") + " UAE"
                : "Beginning of records";

            var rows = string.Join("", topItems.Select((item, i) =>
                $"<tr style='background:{(i % 2 == 0 ? "#fff" : "#f5f5f5")}'>" +
                $"<td style='padding:6px'>{item.name}</td>" +
                $"<td align='right' style='padding:6px'>{item.qty}</td>" +
                $"<td align='right' style='padding:6px'>AED {item.revenue:F2}</td></tr>"));

            var htmlBody = $@"<!DOCTYPE html><html><body style='font-family:Arial,sans-serif;max-width:620px;margin:auto'>
<h2 style='color:#130330;border-bottom:2px solid #f5c518;padding-bottom:8px'>
  🍽 Tehzeeb POS &mdash; Z-Report #{reportNum}</h2>
<p><b>Generated:</b> {genUae:dd MMM yyyy HH:mm} UAE</p>
<p><b>Shift from:</b> {startStr}</p>
<table width='100%' cellpadding='8' cellspacing='0' style='border-collapse:collapse;margin:16px 0'>
  <tr style='background:#130330;color:#f5c518'>
    <td><b>Total Orders</b></td><td align='right'><b>{orders.Count}</b></td></tr>
  <tr><td>Gross Sales</td><td align='right'>AED {grossSales:F2}</td></tr>
  <tr style='background:#f5f5f5'><td>Discounts</td><td align='right'>&minus; AED {discounts:F2}</td></tr>
  <tr><td>VAT Collected (incl.)</td><td align='right'>AED {taxTotal:F2}</td></tr>
  <tr style='background:#130330;color:#f5c518'>
    <td><b>Net Sales (ex-VAT)</b></td><td align='right'><b>AED {netSales:F2}</b></td></tr>
</table>
<h3 style='color:#130330'>Top Items</h3>
<table width='100%' cellspacing='0' style='border-collapse:collapse'>
  <tr style='background:#130330;color:#f5c518'>
    <th align='left' style='padding:6px'>Item</th>
    <th align='right' style='padding:6px'>Qty</th>
    <th align='right' style='padding:6px'>Revenue</th></tr>
  {rows}
</table>
<p style='color:#aaa;font-size:11px;margin-top:24px'>
  Tehzeeb POS &mdash; Shift closed at {genUae:dd MMM yyyy HH:mm} UAE</p>
</body></html>";

            using var smtp = new System.Net.Mail.SmtpClient(smtpHost, int.Parse(smtpPort))
            {
                EnableSsl   = true,
                Credentials = new System.Net.NetworkCredential(smtpUser, smtpPass)
            };
            using var mail = new System.Net.Mail.MailMessage(
                smtpUser, toEmail,
                $"Z-Report #{reportNum} — {genUae:dd MMM yyyy HH:mm}",
                htmlBody) { IsBodyHtml = true };
            await smtp.SendMailAsync(mail);
            emailSent = true;
        }
        catch (Exception ex) { emailError = ex.Message; }
    }

    return Results.Ok(new
    {
        reportNumber = reportNum,
        generatedAt  = now.ToString("O"),
        shiftStart   = shiftStart?.ToString("O"),
        totalOrders  = orders.Count,
        grossSales,
        discounts,
        taxTotal,
        netSales,
        topItems,
        emailSent,
        emailError
    });
});

// ─── PRINTING ───────────────────────────────────────────────────────────────

app.MapPost("/api/print/receipt", async (PrintReceiptDto dto, AppDbContext db) =>
{
    var printerName = (await db.Settings.FirstOrDefaultAsync(s => s.Key == "PrinterName"))?.Value;
    if (string.IsNullOrWhiteSpace(printerName))
        return Results.BadRequest(new { message = "No printer configured. Set the printer name in Admin > Printer Settings." });

    var copiesSetting = (await db.Settings.FirstOrDefaultAsync(s => s.Key == "PrinterCustomerCopies"))?.Value;
    var copies = int.TryParse(copiesSetting, out var c) ? Math.Max(1, c) : 1;

#pragma warning disable CA1416 // this API runs on Windows only, which is where this backend is deployed
    try
    {
        var bytes = ReceiptPrinter.BuildCustomerReceipt(dto);
        for (int i = 0; i < copies; i++)
            RawPrinterHelper.SendBytesToPrinter(printerName, bytes);
        return Results.Ok(new { printed = true });
    }
    catch (Exception ex)
    {
        return Results.Problem(detail: ex.Message, statusCode: 500, title: "Print failed");
    }
#pragma warning restore CA1416
});

app.MapPost("/api/print/kitchen-token", async (PrintKitchenDto dto, AppDbContext db) =>
{
    var printerName = (await db.Settings.FirstOrDefaultAsync(s => s.Key == "PrinterName"))?.Value;
    if (string.IsNullOrWhiteSpace(printerName))
        return Results.BadRequest(new { message = "No printer configured. Set the printer name in Admin > Printer Settings." });

    var copiesSetting = (await db.Settings.FirstOrDefaultAsync(s => s.Key == "PrinterKitchenCopies"))?.Value;
    var copies = int.TryParse(copiesSetting, out var c) ? Math.Max(1, c) : 1;

#pragma warning disable CA1416 // this API runs on Windows only, which is where this backend is deployed
    try
    {
        var bytes = ReceiptPrinter.BuildKitchenToken(dto);
        for (int i = 0; i < copies; i++)
            RawPrinterHelper.SendBytesToPrinter(printerName, bytes);
        return Results.Ok(new { printed = true });
    }
    catch (Exception ex)
    {
        return Results.Problem(detail: ex.Message, statusCode: 500, title: "Print failed");
    }
#pragma warning restore CA1416
});

// ─── PURCHASES ──────────────────────────────────────────────────────────────

app.MapGet("/api/purchases", async (AppDbContext db, string? from, string? to, string? category) =>
{
    var query = db.Purchases.Include(p => p.Attachments).AsQueryable();

    if (!string.IsNullOrEmpty(from) && DateOnly.TryParse(from, out var fd) &&
        !string.IsNullOrEmpty(to)   && DateOnly.TryParse(to,   out var td))
    {
        var utcStart = new DateTime(fd.Year, fd.Month, fd.Day, 0, 0, 0, DateTimeKind.Utc);
        var utcEnd   = new DateTime(td.Year, td.Month, td.Day, 0, 0, 0, DateTimeKind.Utc).AddDays(1);
        query = query.Where(p => p.Date >= utcStart && p.Date < utcEnd);
    }

    if (!string.IsNullOrEmpty(category))
        query = query.Where(p => p.Category == category);

    return await query.OrderByDescending(p => p.Date).ToListAsync();
});

app.MapGet("/api/purchases/{id:int}", async (int id, AppDbContext db) =>
{
    var p = await db.Purchases.Include(p => p.Attachments).FirstOrDefaultAsync(x => x.Id == id);
    return p is null ? Results.NotFound() : Results.Ok(p);
});

app.MapPost("/api/purchases", async (HttpRequest request, AppDbContext db) =>
{
    if (!request.HasFormContentType) return Results.BadRequest("Expected multipart form.");
    var form = await request.ReadFormAsync();

    if (!decimal.TryParse(form["totalAmount"], System.Globalization.NumberStyles.Any,
            System.Globalization.CultureInfo.InvariantCulture, out var total))
        return Results.BadRequest("Invalid totalAmount.");

    var date = DateOnly.TryParse(form["date"].ToString(), out var parsedDate)
        ? new DateTime(parsedDate.Year, parsedDate.Month, parsedDate.Day, 0, 0, 0, DateTimeKind.Utc)
        : DateTime.UtcNow.Date;

    var purchase = new Purchase
    {
        Date        = date,
        Supplier    = form["supplier"].ToString(),
        Description = form["description"].ToString(),
        TotalAmount = total,
        Category    = form["category"].ToString() is { Length: > 0 } cat ? cat : "General"
    };

    db.Purchases.Add(purchase);
    await db.SaveChangesAsync();
    return Results.Created($"/api/purchases/{purchase.Id}", purchase);
});

app.MapPut("/api/purchases/{id:int}", async (int id, HttpRequest request, AppDbContext db) =>
{
    var purchase = await db.Purchases.FindAsync(id);
    if (purchase is null) return Results.NotFound();

    if (!request.HasFormContentType) return Results.BadRequest("Expected multipart form.");
    var form = await request.ReadFormAsync();

    if (decimal.TryParse(form["totalAmount"], System.Globalization.NumberStyles.Any,
            System.Globalization.CultureInfo.InvariantCulture, out var total))
        purchase.TotalAmount = total;

    if (DateOnly.TryParse(form["date"].ToString(), out var parsedDate))
        purchase.Date = new DateTime(parsedDate.Year, parsedDate.Month, parsedDate.Day, 0, 0, 0, DateTimeKind.Utc);

    if (form["supplier"].ToString() is { Length: > 0 } s) purchase.Supplier = s;
    purchase.Description = form["description"].ToString();
    if (form["category"].ToString() is { Length: > 0 } cat2) purchase.Category = cat2;

    await db.SaveChangesAsync();
    return Results.Ok(purchase);
});

app.MapPost("/api/purchases/{id:int}/attachments", async (int id, HttpRequest request, AppDbContext db) =>
{
    var purchase = await db.Purchases.FindAsync(id);
    if (purchase is null) return Results.NotFound();

    if (!request.HasFormContentType) return Results.BadRequest("Expected multipart form.");
    var form = await request.ReadFormAsync();
    if (form.Files.Count == 0) return Results.BadRequest("No files.");

    var year    = purchase.Date.Year.ToString();
    var month   = purchase.Date.ToString("MMMM");
    var uploads = Path.Combine(Directory.GetCurrentDirectory(), "wwwroot", "uploads", "purchases", year, month);
    Directory.CreateDirectory(uploads);

    var added = new List<PurchaseAttachment>();
    foreach (var file in form.Files)
    {
        var filename = $"purchase-{id}-{Guid.NewGuid():N}.jpg";
        using (var fs = new FileStream(Path.Combine(uploads, filename), FileMode.Create))
            await file.CopyToAsync(fs);

        var attachment = new PurchaseAttachment
        {
            PurchaseId = id,
            ImagePath  = $"/uploads/purchases/{year}/{month}/{filename}",
            UploadedAt = DateTime.UtcNow
        };
        db.PurchaseAttachments.Add(attachment);
        added.Add(attachment);
    }

    await db.SaveChangesAsync();
    return Results.Ok(added);
});

app.MapDelete("/api/purchases/{id:int}/attachments/{attachmentId:int}", async (int id, int attachmentId, AppDbContext db) =>
{
    var attachment = await db.PurchaseAttachments.FirstOrDefaultAsync(a => a.Id == attachmentId && a.PurchaseId == id);
    if (attachment is null) return Results.NotFound();

    var filePath = Path.Combine(Directory.GetCurrentDirectory(), "wwwroot", attachment.ImagePath.TrimStart('/'));
    try { if (File.Exists(filePath)) File.Delete(filePath); } catch { /* best effort — DB record is still removed */ }

    db.PurchaseAttachments.Remove(attachment);
    await db.SaveChangesAsync();
    return Results.NoContent();
});

app.MapDelete("/api/purchases/{id:int}", async (int id, AppDbContext db) =>
{
    var purchase = await db.Purchases.Include(p => p.Attachments).FirstOrDefaultAsync(x => x.Id == id);
    if (purchase is null) return Results.NotFound();

    foreach (var attachment in purchase.Attachments)
    {
        var filePath = Path.Combine(Directory.GetCurrentDirectory(), "wwwroot", attachment.ImagePath.TrimStart('/'));
        try { if (File.Exists(filePath)) File.Delete(filePath); } catch { /* best effort */ }
    }

    db.Purchases.Remove(purchase);
    await db.SaveChangesAsync();
    return Results.NoContent();
});

// ─── SPA FALLBACK ───────────────────────────────────────────────────────────
// Serves the built Angular app (copied into wwwroot at package time) for any
// unmatched GET request, so client-side routes like /pos or /admin work on a
// direct load/refresh. Only applies when no API endpoint above matched.
app.MapFallbackToFile("index.html");

app.Run();

// ─── DB CONTEXT ─────────────────────────────────────────────────────────────

public class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    public DbSet<Dish> Dishes => Set<Dish>();
    public DbSet<Order> Orders => Set<Order>();
    public DbSet<OrderItem> OrderItems => Set<OrderItem>();
    public DbSet<Setting> Settings => Set<Setting>();
    public DbSet<User> Users => Set<User>();
    public DbSet<Purchase> Purchases => Set<Purchase>();
    public DbSet<PurchaseAttachment> PurchaseAttachments => Set<PurchaseAttachment>();
}

// ─── MODELS ─────────────────────────────────────────────────────────────────

public class Dish
{
    public int Id { get; set; }
    public string Name { get; set; } = "";
    public decimal Price { get; set; }
    public decimal TaxRate { get; set; }
    public string? ImagePath { get; set; }
    public bool IsActive { get; set; } = true;
    // Optional ASCII/English name used on receipts and kitchen tickets when
    // Name holds a non-Latin script (e.g. Urdu) that ESC/POS printing can't
    // render. Falls back to Name when not set.
    public string? PrintName { get; set; }
    // Optional 2nd/3rd price tiers for dishes with a portion-size option —
    // either Single/Double (e.g. Biryani) or Quarter/Half/Full (e.g. Karahi),
    // per PricingScheme. Price is always the 1st tier (Single or Quarter).
    // Null DoublePrice means the dish only has one price.
    public decimal? DoublePrice { get; set; }
    public decimal? ThirdPrice { get; set; }
    // "SingleDouble" or "QuarterHalfFull". Null is treated as "SingleDouble".
    public string? PricingScheme { get; set; }
}

public class Order
{
    public int Id { get; set; }
    public DateTime OrderDate { get; set; }
    public int TokenNumber { get; set; }
    public string PaymentMethod { get; set; } = "Cash";
    public decimal SubTotal { get; set; }
    public decimal Discount { get; set; }
    public decimal TaxTotal { get; set; }
    public decimal GrandTotal { get; set; }
    public List<OrderItem> Items { get; set; } = [];
    public bool IsCancelled { get; set; }
    public DateTime? CancelledAt { get; set; }
    public string? CancelReason { get; set; }
}

public class OrderItem
{
    public int Id { get; set; }
    public int OrderId { get; set; }
    public int DishId { get; set; }
    public string DishName { get; set; } = "";
    public int Quantity { get; set; }
    public decimal UnitPrice { get; set; }
    public decimal LineTotal { get; set; }
}

public class Setting
{
    public int Id { get; set; }
    public string Key { get; set; } = "";
    public string Value { get; set; } = "";
}

public class User
{
    public int Id { get; set; }
    public string Username { get; set; } = "";
    public string Password { get; set; } = "";
    public string Role { get; set; } = "";
}

public class Purchase
{
    public int Id { get; set; }
    public DateTime Date { get; set; }
    public string Supplier { get; set; } = "";
    public string Description { get; set; } = "";
    public decimal TotalAmount { get; set; }
    // Legacy single-image field, kept for backward compat with old rows —
    // no longer written to; see Attachments for the current (multi-image) model.
    public string? ImagePath { get; set; }
    public string Category { get; set; } = "General";
    public List<PurchaseAttachment> Attachments { get; set; } = [];
}

public class PurchaseAttachment
{
    public int Id { get; set; }
    public int PurchaseId { get; set; }
    public string ImagePath { get; set; } = "";
    public DateTime UploadedAt { get; set; }
}

// ─── DTOs ───────────────────────────────────────────────────────────────────

public record DishDto(string Name, decimal Price, decimal TaxRate, string? PrintName = null, decimal? DoublePrice = null, decimal? ThirdPrice = null, string? PricingScheme = null);
public record ToggleAllDto(bool IsActive);
public record SettingDto(string Value);
public record LoginDto(string Username, string Password);
public record CreateUserDto(string Username, string Password, string Role);
public record ChangePasswordDto(string Password);
public record CreateOrderItemDto(int DishId, string DishName, int Quantity, decimal UnitPrice, decimal LineTotal);
public record CreateOrderDto(decimal SubTotal, decimal Discount, decimal TaxTotal, decimal GrandTotal, string PaymentMethod, List<CreateOrderItemDto> Items);
public record CancelOrderDto(string? Reason);

public record PrintItemDto(string DishName, int Quantity, decimal UnitPrice, decimal LineTotal);
public record PrintReceiptDto(
    int OrderId, int TokenNumber, string OrderDate, List<PrintItemDto> Items,
    decimal SubTotal, decimal Discount, decimal DiscountPercent, decimal Tax, decimal TaxRate, bool ApplyTax,
    decimal GrandTotal, string PaymentMethod, decimal CashReceived, decimal Change);

public record PrintKitchenItemDto(string DishName, int Quantity);
public record PrintKitchenDto(int TokenNumber, string OrderDate, List<PrintKitchenItemDto> Items);
