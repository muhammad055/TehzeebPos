using System.Collections.Concurrent;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;

// Tracks which restaurant each connected Local Print Agent belongs to, and
// correlates outstanding print jobs with the agent's eventual result. One
// process-wide singleton — fine for a single backend instance; scaling the
// API out to multiple instances would need a SignalR backplane (e.g. Redis)
// for this tracking to work across instances, which isn't needed yet.
public class PrintAgentRegistry(IHubContext<PrintHub> hub)
{
    public IHubContext<PrintHub> Hub => hub;
    public ConcurrentDictionary<Guid, TaskCompletionSource<PrintJobResult>> PendingJobs { get; } = new();

    private readonly ConcurrentDictionary<int, string> _connectionsByRestaurant = new();
    private readonly ConcurrentDictionary<string, int> _restaurantByConnection = new();

    public void Register(int restaurantId, string connectionId)
    {
        _connectionsByRestaurant[restaurantId] = connectionId;
        _restaurantByConnection[connectionId] = restaurantId;
    }

    public void Unregister(string connectionId)
    {
        if (_restaurantByConnection.TryRemove(connectionId, out var restaurantId))
            _connectionsByRestaurant.TryRemove(new KeyValuePair<int, string>(restaurantId, connectionId));
    }

    public bool TryGetConnection(int restaurantId, out string? connectionId) =>
        _connectionsByRestaurant.TryGetValue(restaurantId, out connectionId);

    public bool IsConnected(int restaurantId) => _connectionsByRestaurant.ContainsKey(restaurantId);
}

// The Local Print Agent (a small Windows service running at the restaurant)
// connects here over a plain WebSocket carrying its restaurant's
// PrintAgentKey as a query string param — deliberately not the user-facing
// JWT scheme, since this is a headless machine credential with its own
// lifecycle (rotated from Admin > Printer Settings), not a logged-in user.
public class PrintHub(AppDbContext db, PrintAgentRegistry registry) : Hub
{
    public override async Task OnConnectedAsync()
    {
        var key = Context.GetHttpContext()?.Request.Query["key"].ToString();
        var restaurant = string.IsNullOrEmpty(key)
            ? null
            : await db.Restaurants.IgnoreQueryFilters().FirstOrDefaultAsync(r => r.PrintAgentKey == key);

        if (restaurant is null)
        {
            Context.Abort();
            return;
        }

        registry.Register(restaurant.Id, Context.ConnectionId);
        await base.OnConnectedAsync();
    }

    public override Task OnDisconnectedAsync(Exception? exception)
    {
        registry.Unregister(Context.ConnectionId);
        return base.OnDisconnectedAsync(exception);
    }

    // Invoked by the agent once it has finished attempting a print job.
    public Task ReportJobResult(Guid jobId, bool success, string? error)
    {
        if (registry.PendingJobs.TryGetValue(jobId, out var tcs))
            tcs.TrySetResult(new PrintJobResult(success, error));
        return Task.CompletedTask;
    }
}
