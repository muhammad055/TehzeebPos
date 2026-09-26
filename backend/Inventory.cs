using Microsoft.EntityFrameworkCore;
using System.Security.Claims;

// ─── INVENTORY ──────────────────────────────────────────────────────────────
//
// Stock ledger per item:
//   expected stock = last physical count + bought since - used since
// A physical count that disagrees with the expected figure is stored as a
// variance (negative = shortage), which is how over-use / waste shows up.
//
// Bought  = PurchaseItem lines on itemised bills (Purchase.Date).
// Used    = StockUsage, entered by kitchen staff at day end (one row per day+item).
// Counted = StockCount, a periodic physical count (one row per day+item).
//
// Dates are calendar dates stored as UTC midnight, the same convention as Purchase.Date.

public class Item
{
    public int Id { get; set; }
    public int RestaurantId { get; set; }
    public string Name { get; set; } = "";
    public string Unit { get; set; } = "kg";
    public bool IsActive { get; set; } = true;
    public List<ItemPack> Packs { get; set; } = [];
}

/// <summary>
/// A named way an item is bought, converting to the item's base unit
/// (e.g. chicken, unit pcs: "Packet - 10 pcs" = 10). Stock is always kept in the base unit.
/// </summary>
public class ItemPack
{
    public int Id { get; set; }
    public int RestaurantId { get; set; }
    public int ItemId { get; set; }
    public string Name { get; set; } = "";
    public decimal Quantity { get; set; }   // base units per pack
    public bool IsActive { get; set; } = true;
}

public class PurchaseItem
{
    public int Id { get; set; }
    public int RestaurantId { get; set; }
    public int PurchaseId { get; set; }
    public int ItemId { get; set; }
    // Snapshots, so bills keep reading correctly if an item is renamed later.
    public string ItemName { get; set; } = "";
    public string Unit { get; set; } = "";
    public decimal Quantity { get; set; }    // always in the item's base unit
    public decimal UnitPrice { get; set; }   // per base unit
    public decimal LineTotal { get; set; }
    // Set when the line was entered as packs: snapshots of what was typed.
    public int? PackId { get; set; }
    public string PackName { get; set; } = "";
    public decimal? Packs { get; set; }
    public decimal? PackPrice { get; set; }
}

public class StockUsage
{
    public int Id { get; set; }
    public int RestaurantId { get; set; }
    public DateTime Date { get; set; }
    public int ItemId { get; set; }
    public decimal Quantity { get; set; }
    public string Note { get; set; } = "";
    public string EnteredBy { get; set; } = "";
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
}

public class StockCount
{
    public int Id { get; set; }
    public int RestaurantId { get; set; }
    public DateTime Date { get; set; }
    public int ItemId { get; set; }
    public decimal CountedQty { get; set; }
    public decimal ExpectedQty { get; set; }
    public decimal Variance { get; set; }   // CountedQty - ExpectedQty
    public string Note { get; set; } = "";
    public string CountedBy { get; set; } = "";
    public DateTime CreatedAt { get; set; }
}

public record PackDto(string Name, decimal Quantity, bool? IsActive = null);
public record ItemDto(string Name, string Unit, bool? IsActive = null, List<PackDto>? Packs = null);
// Either loose (Quantity + UnitPrice in the base unit) or by pack (PackId + Packs + PackPrice).
public record PurchaseLineDto(int ItemId, decimal Quantity = 0, decimal UnitPrice = 0,
    int? PackId = null, decimal? Packs = null, decimal? PackPrice = null);
public record UsageEntryDto(int ItemId, decimal Quantity, string? Note = null);
public record UsageBatchDto(string Date, List<UsageEntryDto> Entries);
public record CountEntryDto(int ItemId, decimal CountedQty, string? Note = null);
public record CountBatchDto(string Date, List<CountEntryDto> Entries);

public static class Inventory
{
    public static readonly string[] Units = ["kg", "g", "L", "ml", "pcs", "dozen", "pack"];

    public static DateTime UaeToday() => (DateTime.UtcNow + TimeSpan.FromHours(4)).Date;

    public static bool TryDate(string? s, out DateTime date)
    {
        if (DateOnly.TryParse(s, out var d))
        {
            date = new DateTime(d.Year, d.Month, d.Day, 0, 0, 0, DateTimeKind.Utc);
            return true;
        }
        date = default;
        return false;
    }

    static decimal R2(decimal v) => Math.Round(v, 2, MidpointRounding.AwayFromZero);
    static decimal R3(decimal v) => Math.Round(v, 3, MidpointRounding.AwayFromZero);

    public record Position(int ItemId, DateTime? BaseDate, decimal BaseQty, decimal Bought, decimal Used, decimal Expected);

    /// <summary>
    /// Expected stock per item as of a date. The baseline is the latest physical count before
    /// (or, when <paramref name="includeCountOnDate"/>, on) that date; everything after the
    /// baseline date up to and including the date is applied. No count = baseline 0 from the start.
    /// </summary>
    public static async Task<Dictionary<int, Position>> ComputePositions(AppDbContext db, DateTime asOf, bool includeCountOnDate)
    {
        var items = await db.Items.Select(i => i.Id).ToListAsync();

        var counts = await db.StockCounts
            .Where(c => includeCountOnDate ? c.Date <= asOf : c.Date < asOf)
            .ToListAsync();
        var latest = counts.GroupBy(c => c.ItemId)
            .ToDictionary(g => g.Key, g => g.OrderByDescending(c => c.Date).First());

        var lines = await (from pi in db.PurchaseItems
                           join p in db.Purchases on pi.PurchaseId equals p.Id
                           where p.Date <= asOf
                           select new { pi.ItemId, p.Date, pi.Quantity }).ToListAsync();
        var usage = await db.StockUsages.Where(u => u.Date <= asOf)
            .Select(u => new { u.ItemId, u.Date, u.Quantity }).ToListAsync();

        var result = new Dictionary<int, Position>();
        foreach (var id in items)
        {
            latest.TryGetValue(id, out var baseCount);
            var baseDate = baseCount?.Date;
            var baseQty = baseCount?.CountedQty ?? 0m;
            bool After(DateTime d) => baseDate is null || d > baseDate.Value;

            var bought = lines.Where(l => l.ItemId == id && After(l.Date)).Sum(l => l.Quantity);
            var used = usage.Where(u => u.ItemId == id && After(u.Date)).Sum(u => u.Quantity);
            result[id] = new Position(id, baseDate, baseQty, bought, used, R3(baseQty + bought - used));
        }
        return result;
    }

    static string Who(ClaimsPrincipal user) => user.Identity?.Name ?? "";

    public static void MapInventoryEndpoints(this WebApplication app)
    {
        // ── Items ──────────────────────────────────────────────────────────
        // Readable by every signed-in role (the kitchen usage screen needs the list);
        // writes are admin/owner only.

        app.MapGet("/api/items", async (AppDbContext db, bool? includeInactive) =>
        {
            var q = includeInactive == true
                ? db.Items.Include(i => i.Packs)
                : db.Items.Include(i => i.Packs.Where(p => p.IsActive)).Where(i => i.IsActive);
            return await q.OrderBy(i => i.Name).ToListAsync();
        }).RequireAuthorization();

        app.MapPost("/api/items", async (ItemDto dto, AppDbContext db, ICurrentTenant tenant) =>
        {
            var name = dto.Name?.Trim() ?? "";
            if (name.Length == 0) return Results.BadRequest("Item name is required.");
            if (!Units.Contains(dto.Unit)) return Results.BadRequest($"Unit must be one of: {string.Join(", ", Units)}.");
            if (await db.Items.AnyAsync(i => i.Name.ToLower() == name.ToLower()))
                return Results.Conflict($"An item named \"{name}\" already exists.");

            var item = new Item { RestaurantId = tenant.RestaurantId!.Value, Name = name, Unit = dto.Unit };
            foreach (var pk in dto.Packs ?? [])
            {
                var perr = ValidatePack(pk, item.Packs);
                if (perr is not null) return Results.BadRequest(perr);
                item.Packs.Add(new ItemPack { RestaurantId = tenant.RestaurantId!.Value, Name = pk.Name.Trim(), Quantity = R3(pk.Quantity) });
            }
            db.Items.Add(item);
            await db.SaveChangesAsync();
            return Results.Created($"/api/items/{item.Id}", item);
        }).RequireAuthorization("AdminOnly");

        app.MapPut("/api/items/{id:int}", async (int id, ItemDto dto, AppDbContext db) =>
        {
            var item = await db.Items.Include(i => i.Packs).FirstOrDefaultAsync(i => i.Id == id);
            if (item is null) return Results.NotFound();

            var name = dto.Name?.Trim() ?? "";
            if (name.Length == 0) return Results.BadRequest("Item name is required.");
            if (!Units.Contains(dto.Unit)) return Results.BadRequest($"Unit must be one of: {string.Join(", ", Units)}.");
            if (await db.Items.AnyAsync(i => i.Id != id && i.Name.ToLower() == name.ToLower()))
                return Results.Conflict($"An item named \"{name}\" already exists.");

            if (dto.Unit != item.Unit && await IsReferenced(db, id))
                return Results.BadRequest("This item already has purchases, usage or counts, so its unit can't change. Create a new item instead.");

            item.Name = name;
            item.Unit = dto.Unit;
            if (dto.IsActive is bool active) item.IsActive = active;
            await db.SaveChangesAsync();
            return Results.Ok(item);
        }).RequireAuthorization("AdminOnly");

        // An item with any history is deactivated (hidden from pickers) rather than deleted,
        // so past bills, usage and counts keep making sense.
        app.MapDelete("/api/items/{id:int}", async (int id, AppDbContext db) =>
        {
            var item = await db.Items.FirstOrDefaultAsync(i => i.Id == id);
            if (item is null) return Results.NotFound();

            if (await IsReferenced(db, id))
            {
                item.IsActive = false;
                await db.SaveChangesAsync();
                return Results.Ok(new { deactivated = true });
            }
            db.Items.Remove(item);
            await db.SaveChangesAsync();
            return Results.Ok(new { deactivated = false });
        }).RequireAuthorization("AdminOnly");

        // ── Pack sizes ────────────────────────────────────────────────────

        app.MapPost("/api/items/{id:int}/packs", async (int id, PackDto dto, AppDbContext db, ICurrentTenant tenant) =>
        {
            var item = await db.Items.Include(i => i.Packs).FirstOrDefaultAsync(i => i.Id == id);
            if (item is null) return Results.NotFound();
            var err = ValidatePack(dto, item.Packs);
            if (err is not null) return err.StartsWith("A pack") ? Results.Conflict(err) : Results.BadRequest(err);

            var pack = new ItemPack { RestaurantId = tenant.RestaurantId!.Value, ItemId = id, Name = dto.Name.Trim(), Quantity = R3(dto.Quantity) };
            db.ItemPacks.Add(pack);
            await db.SaveChangesAsync();
            return Results.Created($"/api/items/{id}/packs/{pack.Id}", pack);
        }).RequireAuthorization("AdminOnly");

        app.MapPut("/api/items/{id:int}/packs/{packId:int}", async (int id, int packId, PackDto dto, AppDbContext db) =>
        {
            var item = await db.Items.Include(i => i.Packs).FirstOrDefaultAsync(i => i.Id == id);
            var pack = item?.Packs.FirstOrDefault(p => p.Id == packId);
            if (item is null || pack is null) return Results.NotFound();
            var err = ValidatePack(dto, item.Packs, ignoreId: packId);
            if (err is not null) return err.StartsWith("A pack") ? Results.Conflict(err) : Results.BadRequest(err);

            // Past bills keep their own snapshot of the pack, so editing its size is safe.
            pack.Name = dto.Name.Trim();
            pack.Quantity = R3(dto.Quantity);
            if (dto.IsActive is bool active) pack.IsActive = active;
            await db.SaveChangesAsync();
            return Results.Ok(pack);
        }).RequireAuthorization("AdminOnly");

        app.MapDelete("/api/items/{id:int}/packs/{packId:int}", async (int id, int packId, AppDbContext db) =>
        {
            var pack = await db.ItemPacks.FirstOrDefaultAsync(p => p.Id == packId && p.ItemId == id);
            if (pack is null) return Results.NotFound();
            if (await db.PurchaseItems.AnyAsync(x => x.PackId == packId))
            {
                pack.IsActive = false;
                await db.SaveChangesAsync();
                return Results.Ok(new { deactivated = true });
            }
            db.ItemPacks.Remove(pack);
            await db.SaveChangesAsync();
            return Results.Ok(new { deactivated = false });
        }).RequireAuthorization("AdminOnly");

        // ── Daily usage (kitchen, day end) ────────────────────────────────

        app.MapGet("/api/stock/usage", async (string? date, AppDbContext db) =>
        {
            var d = TryDate(date, out var parsed) ? parsed : UaeToday();
            var rows = await db.StockUsages.Where(u => u.Date == d).ToListAsync();
            return Results.Ok(new
            {
                date = d.ToString("yyyy-MM-dd"),
                entries = rows.Select(u => new { u.ItemId, u.Quantity, u.Note, u.EnteredBy })
            });
        }).RequireAuthorization();

        // Batch upsert: one row per (date, item). A quantity of 0 clears that item's row.
        app.MapPut("/api/stock/usage", async (UsageBatchDto dto, AppDbContext db, ICurrentTenant tenant, ClaimsPrincipal user) =>
        {
            if (!TryDate(dto.Date, out var d)) return Results.BadRequest("Invalid date.");
            if (dto.Entries is null) return Results.BadRequest("No entries.");
            if (dto.Entries.Any(e => e.Quantity < 0)) return Results.BadRequest("Quantities can't be negative.");
            if (dto.Entries.GroupBy(e => e.ItemId).Any(g => g.Count() > 1))
                return Results.BadRequest("Each item can appear only once per day.");

            var ids = dto.Entries.Select(e => e.ItemId).ToList();
            var known = await db.Items.Where(i => ids.Contains(i.Id)).Select(i => i.Id).ToListAsync();
            if (known.Count != ids.Count) return Results.BadRequest("Unknown item in entries.");

            var existing = await db.StockUsages.Where(u => u.Date == d && ids.Contains(u.ItemId))
                .ToDictionaryAsync(u => u.ItemId);
            var now = DateTime.UtcNow;

            foreach (var e in dto.Entries)
            {
                existing.TryGetValue(e.ItemId, out var row);
                if (e.Quantity == 0)
                {
                    if (row is not null) db.StockUsages.Remove(row);
                    continue;
                }
                if (row is null)
                {
                    db.StockUsages.Add(new StockUsage
                    {
                        RestaurantId = tenant.RestaurantId!.Value, Date = d, ItemId = e.ItemId,
                        Quantity = R3(e.Quantity), Note = e.Note?.Trim() ?? "",
                        EnteredBy = Who(user), CreatedAt = now, UpdatedAt = now
                    });
                }
                else
                {
                    row.Quantity = R3(e.Quantity);
                    row.Note = e.Note?.Trim() ?? "";
                    row.EnteredBy = Who(user);
                    row.UpdatedAt = now;
                }
            }
            await db.SaveChangesAsync();
            return Results.Ok(new { saved = dto.Entries.Count });
        }).RequireAuthorization();

        // ── Physical counts ───────────────────────────────────────────────

        app.MapGet("/api/stock/counts", async (string? date, AppDbContext db) =>
        {
            var d = TryDate(date, out var parsed) ? parsed : UaeToday();
            var rows = await db.StockCounts.Where(c => c.Date == d).ToListAsync();
            return Results.Ok(new { date = d.ToString("yyyy-MM-dd"), entries = rows });
        }).RequireAuthorization();

        // The response includes expected and variance, so the caller learns straight away
        // when a count doesn't match. Re-saving a date replaces that date's count for the item.
        app.MapPost("/api/stock/counts", async (CountBatchDto dto, AppDbContext db, ICurrentTenant tenant, ClaimsPrincipal user) =>
        {
            if (!TryDate(dto.Date, out var d)) return Results.BadRequest("Invalid date.");
            if (dto.Entries is null || dto.Entries.Count == 0) return Results.BadRequest("No entries.");
            if (dto.Entries.Any(e => e.CountedQty < 0)) return Results.BadRequest("Counts can't be negative.");
            if (dto.Entries.GroupBy(e => e.ItemId).Any(g => g.Count() > 1))
                return Results.BadRequest("Each item can appear only once per count.");

            var ids = dto.Entries.Select(e => e.ItemId).ToList();
            var items = await db.Items.Where(i => ids.Contains(i.Id)).ToDictionaryAsync(i => i.Id);
            if (items.Count != ids.Count) return Results.BadRequest("Unknown item in entries.");

            var positions = await ComputePositions(db, d, includeCountOnDate: false);
            var existing = await db.StockCounts.Where(c => c.Date == d && ids.Contains(c.ItemId))
                .ToDictionaryAsync(c => c.ItemId);
            var now = DateTime.UtcNow;
            var results = new List<object>();

            foreach (var e in dto.Entries)
            {
                var expected = positions.TryGetValue(e.ItemId, out var pos) ? pos.Expected : 0m;
                var counted = R3(e.CountedQty);
                var variance = R3(counted - expected);

                existing.TryGetValue(e.ItemId, out var row);
                if (row is null)
                {
                    row = new StockCount { RestaurantId = tenant.RestaurantId!.Value, Date = d, ItemId = e.ItemId, CreatedAt = now };
                    db.StockCounts.Add(row);
                }
                row.CountedQty = counted;
                row.ExpectedQty = expected;
                row.Variance = variance;
                row.Note = e.Note?.Trim() ?? "";
                row.CountedBy = Who(user);

                results.Add(new
                {
                    itemId = e.ItemId, name = items[e.ItemId].Name, unit = items[e.ItemId].Unit,
                    counted, expected, variance
                });
            }
            await db.SaveChangesAsync();
            return Results.Ok(new { date = d.ToString("yyyy-MM-dd"), results });
        }).RequireAuthorization();

        // ── Stock views (admin/owner only) ────────────────────────────────
        // Deliberately not readable by kitchen staff: someone entering a count shouldn't
        // be able to see what the system expects them to find.

        app.MapGet("/api/stock/on-hand", async (string? asOf, AppDbContext db) =>
        {
            var d = TryDate(asOf, out var parsed) ? parsed : UaeToday();
            var items = await db.Items.OrderBy(i => i.Name).ToListAsync();
            var positions = await ComputePositions(db, d, includeCountOnDate: true);

            // Average purchase price per unit across all itemised bills up to the date.
            var prices = await (from pi in db.PurchaseItems
                                join p in db.Purchases on pi.PurchaseId equals p.Id
                                where p.Date <= d
                                select new { pi.ItemId, pi.Quantity, pi.LineTotal }).ToListAsync();

            var rows = items
                .Select(i =>
                {
                    var pos = positions[i.Id];
                    var pl = prices.Where(p => p.ItemId == i.Id).ToList();
                    var qty = pl.Sum(p => p.Quantity);
                    var avg = qty > 0 ? R2(pl.Sum(p => p.LineTotal) / qty) : 0m;
                    return new
                    {
                        itemId = i.Id, name = i.Name, unit = i.Unit, isActive = i.IsActive,
                        lastCountDate = pos.BaseDate?.ToString("yyyy-MM-dd"),
                        lastCountQty = pos.BaseDate is null ? (decimal?)null : pos.BaseQty,
                        bought = pos.Bought, used = pos.Used, expected = pos.Expected,
                        avgUnitCost = avg, value = R2(Math.Max(pos.Expected, 0) * avg)
                    };
                })
                // Hide deactivated items that hold no stock.
                .Where(r => r.isActive || r.expected != 0)
                .ToList();

            return Results.Ok(new { asOf = d.ToString("yyyy-MM-dd"), items = rows });
        }).RequireAuthorization("AdminOnly");

        app.MapGet("/api/stock/report", async (string? from, string? to, AppDbContext db) =>
        {
            var today = UaeToday();
            var fd = TryDate(from, out var f) ? f : new DateTime(today.Year, today.Month, 1, 0, 0, 0, DateTimeKind.Utc);
            var td = TryDate(to, out var t) ? t : today;
            if (td < fd) return Results.BadRequest("'to' is before 'from'.");

            var items = await db.Items.OrderBy(i => i.Name).ToListAsync();
            var lines = await (from pi in db.PurchaseItems
                               join p in db.Purchases on pi.PurchaseId equals p.Id
                               where p.Date >= fd && p.Date <= td
                               select new { pi.ItemId, pi.Quantity, pi.LineTotal }).ToListAsync();
            var usage = await db.StockUsages.Where(u => u.Date >= fd && u.Date <= td)
                .Select(u => new { u.ItemId, u.Quantity }).ToListAsync();
            var counts = await db.StockCounts.Where(c => c.Date >= fd && c.Date <= td).ToListAsync();

            var rows = items.Select(i =>
            {
                var pl = lines.Where(l => l.ItemId == i.Id).ToList();
                var boughtQty = pl.Sum(l => l.Quantity);
                var spend = R2(pl.Sum(l => l.LineTotal));
                var avg = boughtQty > 0 ? R2(spend / boughtQty) : 0m;
                var usedQty = usage.Where(u => u.ItemId == i.Id).Sum(u => u.Quantity);
                var cs = counts.Where(c => c.ItemId == i.Id).ToList();
                var shortage = cs.Where(c => c.Variance < 0).Sum(c => c.Variance);   // negative
                return new
                {
                    itemId = i.Id, name = i.Name, unit = i.Unit,
                    boughtQty, spend, avgUnitCost = avg,
                    usedQty, usedValue = R2(usedQty * avg),
                    counts = cs.Count,
                    netVariance = R3(cs.Sum(c => c.Variance)),
                    shortageQty = R3(shortage),
                    shortageValue = R2(shortage * avg)   // negative = money lost
                };
            })
            .Where(r => r.boughtQty != 0 || r.usedQty != 0 || r.counts != 0)
            .ToList();

            return Results.Ok(new
            {
                from = fd.ToString("yyyy-MM-dd"), to = td.ToString("yyyy-MM-dd"),
                totalSpend = R2(rows.Sum(r => r.spend)),
                totalShortageValue = R2(rows.Sum(r => r.shortageValue)),
                items = rows
            });
        }).RequireAuthorization("AdminOnly");

        app.MapGet("/api/stock/units", () => Results.Ok(Units)).RequireAuthorization();
    }

    /// <summary>Returns an error message, or null when the pack is valid for the item.</summary>
    static string? ValidatePack(PackDto pk, IEnumerable<ItemPack> existing, int? ignoreId = null)
    {
        var name = pk.Name?.Trim() ?? "";
        if (name.Length == 0) return "Pack name is required.";
        if (pk.Quantity <= 0) return "Pack size must be above zero.";
        if (existing.Any(p => p.Id != ignoreId && string.Equals(p.Name, name, StringComparison.OrdinalIgnoreCase)))
            return $"A pack named \"{name}\" already exists for this item.";
        return null;
    }

    static async Task<bool> IsReferenced(AppDbContext db, int itemId) =>
        await db.PurchaseItems.AnyAsync(x => x.ItemId == itemId)
        || await db.StockUsages.AnyAsync(x => x.ItemId == itemId)
        || await db.StockCounts.AnyAsync(x => x.ItemId == itemId);

    /// <summary>
    /// Parses the optional "items" JSON field on the multipart purchase form and rewrites the
    /// purchase's lines. Returns an error message, or null on success. When lines are present the
    /// purchase total becomes their sum. A line is either loose (quantity + price per base unit)
    /// or by pack (packId + packs + price per pack); pack lines are converted to base units here,
    /// so the client never does that arithmetic.
    /// </summary>
    public static async Task<string?> ApplyPurchaseLines(
        AppDbContext db, ICurrentTenant tenant, Purchase purchase, string itemsJson)
    {
        List<PurchaseLineDto>? lines;
        try
        {
            lines = System.Text.Json.JsonSerializer.Deserialize<List<PurchaseLineDto>>(itemsJson,
                new System.Text.Json.JsonSerializerOptions { PropertyNameCaseInsensitive = true });
        }
        catch (System.Text.Json.JsonException) { return "Invalid items."; }
        if (lines is null) return "Invalid items.";

        foreach (var l in lines)
        {
            if (l.PackId is not null)
            {
                if (l.Packs is null || l.Packs <= 0) return "Every item needs a number of packets above zero.";
                if (l.PackPrice is null || l.PackPrice < 0) return "Every packet needs a price.";
            }
            else
            {
                if (l.Quantity <= 0) return "Every item needs a quantity above zero.";
                if (l.UnitPrice < 0) return "Prices can't be negative.";
            }
        }

        var ids = lines.Select(l => l.ItemId).Distinct().ToList();
        var items = await db.Items.Include(i => i.Packs).Where(i => ids.Contains(i.Id)).ToDictionaryAsync(i => i.Id);
        if (items.Count != ids.Count) return "Unknown item in bill.";

        // Replace the existing lines wholesale.
        var old = await db.PurchaseItems.Where(x => x.PurchaseId == purchase.Id).ToListAsync();
        db.PurchaseItems.RemoveRange(old);
        purchase.Items.Clear();

        foreach (var l in lines)
        {
            var it = items[l.ItemId];
            var line = new PurchaseItem
            {
                RestaurantId = tenant.RestaurantId!.Value,
                ItemId = it.Id, ItemName = it.Name, Unit = it.Unit
            };

            if (l.PackId is int packId)
            {
                var pack = it.Packs.FirstOrDefault(p => p.Id == packId);
                if (pack is null) return $"That pack does not belong to {it.Name}.";
                if (!pack.IsActive) return $"The pack \"{pack.Name}\" is no longer in use.";

                line.PackId = pack.Id;
                line.PackName = pack.Name;
                line.Packs = R3(l.Packs!.Value);
                line.PackPrice = R2(l.PackPrice!.Value);
                line.Quantity = R3(line.Packs.Value * pack.Quantity);
                line.LineTotal = R2(line.Packs.Value * line.PackPrice.Value);     // exact money
                line.UnitPrice = line.Quantity > 0 ? R2(line.LineTotal / line.Quantity) : 0;
            }
            else
            {
                line.Quantity = R3(l.Quantity);
                line.UnitPrice = R2(l.UnitPrice);
                line.LineTotal = R2(l.Quantity * l.UnitPrice);
            }
            purchase.Items.Add(line);
        }
        if (purchase.Items.Count > 0)
            purchase.TotalAmount = R2(purchase.Items.Sum(x => x.LineTotal));
        return null;
    }
}
