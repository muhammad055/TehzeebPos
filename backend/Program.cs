using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.FileProviders;
using Microsoft.IdentityModel.Tokens;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;

// Npgsql maps DateTime to "timestamp without time zone" regardless of Kind by
// default as of Npgsql 6+, EXCEPT it throws when a Utc-Kind DateTime (e.g.
// DateTime.UtcNow, used throughout this file's UAE-offset date math) is
// written to that column type. The app's existing date arithmetic mixes
// Utc/Unspecified Kind DateTimes freely and correctness doesn't depend on
// Kind (everything is manual UTC+4 offset math against naive values), so we
// opt back into the lenient legacy behavior rather than rewrite every
// DateTime construction across the file.
AppContext.SetSwitch("Npgsql.EnableLegacyTimestampBehavior", true);

var builder = WebApplication.CreateBuilder(args);

var jwtSecret   = builder.Configuration["Jwt:Secret"]
    ?? throw new InvalidOperationException("Jwt:Secret is not configured (see appsettings.json / Jwt__Secret env var).");
var jwtIssuer   = builder.Configuration["Jwt:Issuer"] ?? "TehzeebPos";
var jwtAudience = builder.Configuration["Jwt:Audience"] ?? "TehzeebPosClients";
var jwtExpiryHours = double.TryParse(builder.Configuration["Jwt:ExpiryHours"], out var eh) ? eh : 12;
// Phones stay signed in far longer than a cashier terminal; no refresh-token flow yet.
var jwtMobileExpiryHours = double.TryParse(builder.Configuration["Jwt:MobileExpiryHours"], out var meh) ? meh : 24 * 30;

builder.Services.AddDbContext<AppDbContext>(opt =>
    opt.UseNpgsql(builder.Configuration.GetConnectionString("Default")
        ?? throw new InvalidOperationException("ConnectionStrings:Default is not configured.")));

builder.Services.AddHttpContextAccessor();
builder.Services.AddScoped<ICurrentTenant, HttpCurrentTenant>();

builder.Services.AddCors(opt =>
    opt.AddDefaultPolicy(p =>
        p.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod()));

builder.Services.AddEndpointsApiExplorer();

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(opt =>
    {
        opt.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = jwtIssuer,
            ValidateAudience = true,
            ValidAudience = jwtAudience,
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtSecret)),
            ValidateLifetime = true,
            ClockSkew = TimeSpan.FromMinutes(1)
        };
    });

builder.Services.AddAuthorizationBuilder()
    .AddPolicy("AdminOnly", p => p.RequireRole(Roles.Admin, Roles.Owner))
    .AddPolicy("OwnerOnly", p => p.RequireRole(Roles.Owner));

builder.Services.AddSignalR();
builder.Services.AddSingleton<PrintAgentRegistry>();

// Printing:Mode = "RemoteAgent" for the cloud build (backend on a VPS, prints
// via a Local Print Agent over SignalR); anything else (including unset, the
// desktop build's default) prints in-process, exactly as before Phase 1.
var printingMode = builder.Configuration["Printing:Mode"];
if (printingMode == "RemoteAgent")
    builder.Services.AddSingleton<IPrintDispatcher, RemotePrintDispatcher>();
else
    builder.Services.AddSingleton<IPrintDispatcher, LocalPrintDispatcher>();

var app = builder.Build();

// Apply pending EF Core migrations on startup (replaces the old
// pragma_table_info-and-ALTER pattern now that we're on Postgres).
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    db.Database.Migrate();

    // Seed the single Tehzeeb restaurant + default users on first run.
    // Multi-restaurant onboarding (Phase 6) will replace this with a real
    // signup flow; for now there's exactly one tenant.
    var restaurant = db.Restaurants.IgnoreQueryFilters().FirstOrDefault();
    if (restaurant is null)
    {
        restaurant = new Restaurant { Name = "Tehzeeb Restaurant & Kitchen" };
        db.Restaurants.Add(restaurant);
        db.SaveChanges();
    }

    if (!db.Settings.IgnoreQueryFilters().Any(s => s.RestaurantId == restaurant.Id))
        db.Settings.Add(new Setting { RestaurantId = restaurant.Id, Key = "DefaultTaxRate", Value = "5" });

    if (!db.Users.IgnoreQueryFilters().Any(u => u.RestaurantId == restaurant.Id))
    {
        db.Users.Add(new User { RestaurantId = restaurant.Id, Username = "admin",   Password = HashPassword("admin123"),   Role = "admin" });
        db.Users.Add(new User { RestaurantId = restaurant.Id, Username = "cashier", Password = HashPassword("cashier123"), Role = "cashier" });
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
app.UseAuthentication();
app.UseAuthorization();

app.MapHub<PrintHub>("/hubs/print");

static string HashPassword(string p) =>
    Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(p))).ToLower();

static string IssueToken(User user, string jwtSecret, string jwtIssuer, string jwtAudience, double expiryHours)
{
    var claims = new[]
    {
        new Claim(JwtRegisteredClaimNames.Sub, user.Id.ToString()),
        new Claim(ClaimTypes.Name, user.Username),
        new Claim(ClaimTypes.Role, user.Role),
        new Claim("restaurant_id", user.RestaurantId.ToString())
    };
    var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtSecret));
    var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);
    var token = new JwtSecurityToken(
        issuer: jwtIssuer,
        audience: jwtAudience,
        claims: claims,
        expires: DateTime.UtcNow.AddHours(expiryHours),
        signingCredentials: creds);
    return new JwtSecurityTokenHandler().WriteToken(token);
}

// ─── AUTH ────────────────────────────────────────────────────────────────────
// Login is intentionally the one endpoint that looks a user up without a
// restaurant already established (there's no token yet to carry one) — it
// queries Users unscoped (IgnoreQueryFilters) by username. Username is
// globally unique today because there's a single tenant; before onboarding a
// second restaurant this needs to become unique per-(RestaurantId, Username)
// with a tenant-selection step in the login flow (Phase 6 concern, not this
// phase — flagged here so it isn't forgotten).

app.MapPost("/api/auth/login", async (LoginDto dto, AppDbContext db) =>
{
    var hashed = HashPassword(dto.Password);
    var user = await db.Users.IgnoreQueryFilters().FirstOrDefaultAsync(
        u => u.Username == dto.Username && u.Password == hashed);
    if (user is null) return Results.Unauthorized();
    var hours = dto.Client == "mobile" ? jwtMobileExpiryHours : jwtExpiryHours;
    var token = IssueToken(user, jwtSecret, jwtIssuer, jwtAudience, hours);
    return Results.Ok(new { token, username = user.Username, role = user.Role });
});

// ─── USERS ──────────────────────────────────────────────────────────────────

app.MapGet("/api/users", async (AppDbContext db) =>
    await db.Users.Select(u => new { u.Id, u.Username, u.Role }).ToListAsync())
    .RequireAuthorization("AdminOnly");

app.MapPost("/api/users", async (CreateUserDto dto, AppDbContext db, ICurrentTenant tenant) =>
{
    if (!Roles.IsValid(dto.Role))
        return Results.BadRequest(new { message = $"Role must be one of: {string.Join(", ", Roles.All)}." });
    if (await db.Users.AnyAsync(u => u.Username == dto.Username))
        return Results.Conflict(new { message = "Username already exists." });
    var user = new User { RestaurantId = tenant.RestaurantId!.Value, Username = dto.Username, Password = HashPassword(dto.Password), Role = dto.Role };
    db.Users.Add(user);
    await db.SaveChangesAsync();
    return Results.Created($"/api/users/{user.Id}", new { user.Id, user.Username, user.Role });
}).RequireAuthorization("AdminOnly");

app.MapPut("/api/users/{id:int}/password", async (int id, ChangePasswordDto dto, AppDbContext db) =>
{
    var user = await db.Users.FirstOrDefaultAsync(u => u.Id == id);
    if (user is null) return Results.NotFound();
    user.Password = HashPassword(dto.Password);
    await db.SaveChangesAsync();
    return Results.NoContent();
}).RequireAuthorization("AdminOnly");

app.MapDelete("/api/users/{id:int}", async (int id, AppDbContext db) =>
{
    var user = await db.Users.FirstOrDefaultAsync(u => u.Id == id);
    if (user is null) return Results.NotFound();
    db.Users.Remove(user);
    await db.SaveChangesAsync();
    return Results.NoContent();
}).RequireAuthorization("AdminOnly");

// ─── DISH IMAGE ────────────────────────────────────────────────────────────

app.MapPost("/api/dishes/{id:int}/image",
    async (int id, HttpRequest request, AppDbContext db, IWebHostEnvironment env) =>
{
    var dish = await db.Dishes.FirstOrDefaultAsync(d => d.Id == id);
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
}).RequireAuthorization("AdminOnly");

// ─── SETTINGS ───────────────────────────────────────────────────────────────

app.MapGet("/api/settings", async (AppDbContext db) =>
    await db.Settings.ToListAsync())
    .RequireAuthorization();

app.MapPut("/api/settings/{key}", async (string key, SettingDto dto, AppDbContext db, ICurrentTenant tenant) =>
{
    var setting = await db.Settings.FirstOrDefaultAsync(s => s.Key == key);
    if (setting is null)
    {
        setting = new Setting { RestaurantId = tenant.RestaurantId!.Value, Key = key, Value = dto.Value };
        db.Settings.Add(setting);
    }
    else
    {
        setting.Value = dto.Value;
    }
    await db.SaveChangesAsync();
    return Results.Ok(setting);
}).RequireAuthorization("AdminOnly");

// ─── DISHES ─────────────────────────────────────────────────────────────────

app.MapGet("/api/dishes", async (AppDbContext db) =>
    await db.Dishes.OrderBy(d => d.Name).ToListAsync())
    .RequireAuthorization();

app.MapPost("/api/dishes", async (DishDto dto, AppDbContext db, ICurrentTenant tenant) =>
{
    var dish = new Dish { RestaurantId = tenant.RestaurantId!.Value, Name = dto.Name, Price = dto.Price, TaxRate = dto.TaxRate, PrintName = dto.PrintName, DoublePrice = dto.DoublePrice, ThirdPrice = dto.ThirdPrice, PricingScheme = dto.PricingScheme };
    db.Dishes.Add(dish);
    await db.SaveChangesAsync();
    return Results.Created($"/api/dishes/{dish.Id}", dish);
}).RequireAuthorization("AdminOnly");

app.MapPut("/api/dishes/{id:int}", async (int id, DishDto dto, AppDbContext db) =>
{
    var dish = await db.Dishes.FirstOrDefaultAsync(d => d.Id == id);
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
}).RequireAuthorization("AdminOnly");

app.MapPatch("/api/dishes/{id:int}/toggle", async (int id, AppDbContext db) =>
{
    var dish = await db.Dishes.FirstOrDefaultAsync(d => d.Id == id);
    if (dish is null) return Results.NotFound();
    dish.IsActive = !dish.IsActive;
    await db.SaveChangesAsync();
    return Results.Ok(dish);
}).RequireAuthorization("AdminOnly");

app.MapPatch("/api/dishes/toggle-all", async (ToggleAllDto dto, AppDbContext db) =>
{
    await db.Dishes.ExecuteUpdateAsync(s => s.SetProperty(d => d.IsActive, dto.IsActive));
    return Results.Ok(await db.Dishes.ToListAsync());
}).RequireAuthorization("AdminOnly");

app.MapDelete("/api/dishes/{id:int}", async (int id, AppDbContext db) =>
{
    var dish = await db.Dishes.FirstOrDefaultAsync(d => d.Id == id);
    if (dish is null) return Results.NotFound();
    db.Dishes.Remove(dish);
    await db.SaveChangesAsync();
    return Results.NoContent();
}).RequireAuthorization("AdminOnly");

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
}).RequireAuthorization();

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
}).RequireAuthorization();

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
}).RequireAuthorization("AdminOnly");

app.MapGet("/api/orders/{id:int}", async (int id, AppDbContext db) =>
{
    var order = await db.Orders.Include(o => o.Items).FirstOrDefaultAsync(o => o.Id == id);
    return order is null ? Results.NotFound() : Results.Ok(order);
}).RequireAuthorization();

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
}).RequireAuthorization();

app.MapPost("/api/orders", async (CreateOrderDto dto, AppDbContext db, ICurrentTenant tenant) =>
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
        RestaurantId  = tenant.RestaurantId!.Value,
        OrderDate     = DateTime.UtcNow,
        TokenNumber   = maxToken + 1,
        PaymentMethod = dto.PaymentMethod,
        SubTotal      = dto.SubTotal,
        Discount    = dto.Discount,
        TaxTotal    = dto.TaxTotal,
        GrandTotal  = dto.GrandTotal,
        Items = dto.Items.Select(i => new OrderItem
        {
            RestaurantId = tenant.RestaurantId!.Value,
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
}).RequireAuthorization();

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
}).RequireAuthorization("AdminOnly");

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
}).RequireAuthorization("AdminOnly");

// ─── PRINTING ───────────────────────────────────────────────────────────────
// Goes through IPrintDispatcher rather than RawPrinterHelper directly, so the
// same backend works both as the desktop build (prints in-process — printer
// is on this machine) and the cloud build (dispatches to a Local Print Agent
// over SignalR — printer is at the restaurant, not on the VPS). See
// PrintDispatch.cs for the two implementations and Printing:Mode config.

app.MapPost("/api/print/receipt", async (PrintReceiptDto dto, AppDbContext db, IPrintDispatcher dispatcher, ICurrentTenant tenant) =>
{
    var printerName = (await db.Settings.FirstOrDefaultAsync(s => s.Key == "PrinterName"))?.Value;
    if (string.IsNullOrWhiteSpace(printerName))
        return Results.BadRequest(new { message = "No printer configured. Set the printer name in Admin > Printer Settings." });

    var copiesSetting = (await db.Settings.FirstOrDefaultAsync(s => s.Key == "PrinterCustomerCopies"))?.Value;
    var copies = int.TryParse(copiesSetting, out var c) ? Math.Max(1, c) : 1;

#pragma warning disable CA1416 // ReceiptPrinter/LogoImage use System.Drawing (Windows-only) — fine, both desktop and the planned cloud VPS are Windows
    var bytes = ReceiptPrinter.BuildCustomerReceipt(dto);
#pragma warning restore CA1416
    var result = await dispatcher.PrintAsync(tenant.RestaurantId!.Value, printerName, bytes, copies);
    return result.Success
        ? Results.Ok(new { printed = true })
        : Results.Problem(detail: result.Error, statusCode: 500, title: "Print failed");
}).RequireAuthorization();

app.MapPost("/api/print/kitchen-token", async (PrintKitchenDto dto, AppDbContext db, IPrintDispatcher dispatcher, ICurrentTenant tenant) =>
{
    var printerName = (await db.Settings.FirstOrDefaultAsync(s => s.Key == "PrinterName"))?.Value;
    if (string.IsNullOrWhiteSpace(printerName))
        return Results.BadRequest(new { message = "No printer configured. Set the printer name in Admin > Printer Settings." });

    var copiesSetting = (await db.Settings.FirstOrDefaultAsync(s => s.Key == "PrinterKitchenCopies"))?.Value;
    var copies = int.TryParse(copiesSetting, out var c) ? Math.Max(1, c) : 1;

#pragma warning disable CA1416 // ReceiptPrinter/LogoImage use System.Drawing (Windows-only) — fine, both desktop and the planned cloud VPS are Windows
    var bytes = ReceiptPrinter.BuildKitchenToken(dto);
#pragma warning restore CA1416
    var result = await dispatcher.PrintAsync(tenant.RestaurantId!.Value, printerName, bytes, copies);
    return result.Success
        ? Results.Ok(new { printed = true })
        : Results.Problem(detail: result.Error, statusCode: 500, title: "Print failed");
}).RequireAuthorization();

// ─── PRINT AGENT ────────────────────────────────────────────────────────────

app.MapGet("/api/printer-agent/key", async (AppDbContext db, ICurrentTenant tenant) =>
{
    var restaurant = await db.Restaurants.FirstAsync(r => r.Id == tenant.RestaurantId!.Value);
    return Results.Ok(new { key = restaurant.PrintAgentKey });
}).RequireAuthorization("AdminOnly");

app.MapPost("/api/printer-agent/regenerate-key", async (AppDbContext db, ICurrentTenant tenant) =>
{
    var restaurant = await db.Restaurants.FirstAsync(r => r.Id == tenant.RestaurantId!.Value);
    restaurant.PrintAgentKey = Guid.NewGuid().ToString("N");
    await db.SaveChangesAsync();
    return Results.Ok(new { key = restaurant.PrintAgentKey });
}).RequireAuthorization("AdminOnly");

app.MapGet("/api/printer-agent/status", (PrintAgentRegistry registry, ICurrentTenant tenant) =>
    Results.Ok(new { connected = registry.IsConnected(tenant.RestaurantId!.Value) }))
    .RequireAuthorization("AdminOnly");

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
}).RequireAuthorization();

app.MapGet("/api/purchases/{id:int}", async (int id, AppDbContext db) =>
{
    var p = await db.Purchases.Include(p => p.Attachments).FirstOrDefaultAsync(x => x.Id == id);
    return p is null ? Results.NotFound() : Results.Ok(p);
}).RequireAuthorization();

app.MapPost("/api/purchases", async (HttpRequest request, AppDbContext db, ICurrentTenant tenant) =>
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
        RestaurantId = tenant.RestaurantId!.Value,
        Date        = date,
        Supplier    = form["supplier"].ToString(),
        Description = form["description"].ToString(),
        TotalAmount = total,
        Category    = form["category"].ToString() is { Length: > 0 } cat ? cat : "General"
    };

    db.Purchases.Add(purchase);
    await db.SaveChangesAsync();
    return Results.Created($"/api/purchases/{purchase.Id}", purchase);
}).RequireAuthorization();

app.MapPut("/api/purchases/{id:int}", async (int id, HttpRequest request, AppDbContext db) =>
{
    var purchase = await db.Purchases.FirstOrDefaultAsync(p => p.Id == id);
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
}).RequireAuthorization();

app.MapPost("/api/purchases/{id:int}/attachments", async (int id, HttpRequest request, AppDbContext db, ICurrentTenant tenant) =>
{
    var purchase = await db.Purchases.FirstOrDefaultAsync(p => p.Id == id);
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
            RestaurantId = tenant.RestaurantId!.Value,
            PurchaseId = id,
            ImagePath  = $"/uploads/purchases/{year}/{month}/{filename}",
            UploadedAt = DateTime.UtcNow
        };
        db.PurchaseAttachments.Add(attachment);
        added.Add(attachment);
    }

    await db.SaveChangesAsync();
    return Results.Ok(added);
}).RequireAuthorization();

app.MapDelete("/api/purchases/{id:int}/attachments/{attachmentId:int}", async (int id, int attachmentId, AppDbContext db) =>
{
    var attachment = await db.PurchaseAttachments.FirstOrDefaultAsync(a => a.Id == attachmentId && a.PurchaseId == id);
    if (attachment is null) return Results.NotFound();

    var filePath = Path.Combine(Directory.GetCurrentDirectory(), "wwwroot", attachment.ImagePath.TrimStart('/'));
    try { if (File.Exists(filePath)) File.Delete(filePath); } catch { /* best effort — DB record is still removed */ }

    db.PurchaseAttachments.Remove(attachment);
    await db.SaveChangesAsync();
    return Results.NoContent();
}).RequireAuthorization();

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
}).RequireAuthorization();

// ─── SPA FALLBACK ───────────────────────────────────────────────────────────
// Serves the built Angular app (copied into wwwroot at package time) for any
// unmatched GET request, so client-side routes like /pos or /admin work on a
// direct load/refresh. Only applies when no API endpoint above matched.
app.MapFallbackToFile("index.html");

app.Run();

// ─── TENANT CONTEXT ─────────────────────────────────────────────────────────

public interface ICurrentTenant
{
    int? RestaurantId { get; }
}

public class HttpCurrentTenant(IHttpContextAccessor accessor) : ICurrentTenant
{
    public int? RestaurantId
    {
        get
        {
            var claim = accessor.HttpContext?.User.FindFirst("restaurant_id")?.Value;
            return int.TryParse(claim, out var id) ? id : null;
        }
    }
}

// ─── DB CONTEXT ─────────────────────────────────────────────────────────────

public class AppDbContext(DbContextOptions<AppDbContext> options, ICurrentTenant tenant) : DbContext(options)
{
    public DbSet<Restaurant> Restaurants => Set<Restaurant>();
    public DbSet<Dish> Dishes => Set<Dish>();
    public DbSet<Order> Orders => Set<Order>();
    public DbSet<OrderItem> OrderItems => Set<OrderItem>();
    public DbSet<Setting> Settings => Set<Setting>();
    public DbSet<User> Users => Set<User>();
    public DbSet<Purchase> Purchases => Set<Purchase>();
    public DbSet<PurchaseAttachment> PurchaseAttachments => Set<PurchaseAttachment>();

    // Every tenant-owned table is filtered to the caller's RestaurantId (from
    // the JWT) at the query level — a missed .Where() elsewhere in an
    // endpoint can't leak another restaurant's rows. tenant.RestaurantId is
    // only ever null pre-authentication (the login endpoint explicitly opts
    // out via IgnoreQueryFilters), so this bypass isn't reachable from any
    // [Authorize]-protected endpoint.
    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Dish>().HasQueryFilter(x => tenant.RestaurantId == null || x.RestaurantId == tenant.RestaurantId);
        modelBuilder.Entity<Order>().HasQueryFilter(x => tenant.RestaurantId == null || x.RestaurantId == tenant.RestaurantId);
        modelBuilder.Entity<OrderItem>().HasQueryFilter(x => tenant.RestaurantId == null || x.RestaurantId == tenant.RestaurantId);
        modelBuilder.Entity<Setting>().HasQueryFilter(x => tenant.RestaurantId == null || x.RestaurantId == tenant.RestaurantId);
        modelBuilder.Entity<User>().HasQueryFilter(x => tenant.RestaurantId == null || x.RestaurantId == tenant.RestaurantId);
        modelBuilder.Entity<Purchase>().HasQueryFilter(x => tenant.RestaurantId == null || x.RestaurantId == tenant.RestaurantId);
        modelBuilder.Entity<PurchaseAttachment>().HasQueryFilter(x => tenant.RestaurantId == null || x.RestaurantId == tenant.RestaurantId);
    }
}

// ─── MODELS ─────────────────────────────────────────────────────────────────

public class Restaurant
{
    public int Id { get; set; }
    public string Name { get; set; } = "";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    // Machine credential the Local Print Agent presents when it connects to
    // /hubs/print — deliberately separate from user JWTs (see PrintHub.cs).
    public string PrintAgentKey { get; set; } = Guid.NewGuid().ToString("N");
}

public class Dish
{
    public int Id { get; set; }
    public int RestaurantId { get; set; }
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
    public int RestaurantId { get; set; }
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
    public int RestaurantId { get; set; }
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
    public int RestaurantId { get; set; }
    public string Key { get; set; } = "";
    public string Value { get; set; } = "";
}

public class User
{
    public int Id { get; set; }
    public int RestaurantId { get; set; }
    public string Username { get; set; } = "";
    public string Password { get; set; } = "";
    public string Role { get; set; } = "";
}

public class Purchase
{
    public int Id { get; set; }
    public int RestaurantId { get; set; }
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
    public int RestaurantId { get; set; }
    public int PurchaseId { get; set; }
    public string ImagePath { get; set; } = "";
    public DateTime UploadedAt { get; set; }
}

// ─── DTOs ───────────────────────────────────────────────────────────────────

public record DishDto(string Name, decimal Price, decimal TaxRate, string? PrintName = null, decimal? DoublePrice = null, decimal? ThirdPrice = null, string? PricingScheme = null);
public record ToggleAllDto(bool IsActive);
public record SettingDto(string Value);
public record LoginDto(string Username, string Password, string? Client = null);

public static class Roles
{
    public const string Owner   = "owner";
    public const string Admin   = "admin";
    public const string Cashier = "cashier";
    public static readonly string[] All = { Owner, Admin, Cashier };
    public static bool IsValid(string? role) => role is not null && All.Contains(role);
}
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
