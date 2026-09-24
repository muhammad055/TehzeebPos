using Microsoft.AspNetCore.SignalR;

// Printing is pluggable so the same backend binary serves both deployment
// modes: desktop (backend and printer on the same machine — print in-process,
// exactly as before Phase 1) and cloud (backend on a VPS, printer at the
// restaurant — dispatch the job to a Local Print Agent over SignalR and wait
// for it to report back). Selected at startup via Printing:Mode config.

public record PrintJobMessage(Guid JobId, string PrinterName, byte[] Data, int Copies);
public record PrintJobResult(bool Success, string? Error);

public interface IPrintDispatcher
{
    Task<PrintJobResult> PrintAsync(int restaurantId, string printerName, byte[] bytes, int copies);
}

// Desktop mode: identical to the pre-Phase-1 behavior — call the Windows
// print spooler directly, in-process, because the backend and the printer
// are the same machine.
public class LocalPrintDispatcher : IPrintDispatcher
{
    public Task<PrintJobResult> PrintAsync(int restaurantId, string printerName, byte[] bytes, int copies)
    {
#pragma warning disable CA1416 // this API runs on Windows only, which is where this backend is deployed
        try
        {
            for (int i = 0; i < copies; i++)
                RawPrinterHelper.SendBytesToPrinter(printerName, bytes);
            return Task.FromResult(new PrintJobResult(true, null));
        }
        catch (Exception ex)
        {
            return Task.FromResult(new PrintJobResult(false, ex.Message));
        }
#pragma warning restore CA1416
    }
}

// Cloud mode: hand the job to whichever Local Print Agent is currently
// connected for this restaurant (see PrintHub) and wait for it to report the
// result back over the same connection, with a timeout in case no agent is
// connected or it hangs.
public class RemotePrintDispatcher(PrintAgentRegistry registry) : IPrintDispatcher
{
    private static readonly TimeSpan Timeout = TimeSpan.FromSeconds(20);

    public async Task<PrintJobResult> PrintAsync(int restaurantId, string printerName, byte[] bytes, int copies)
    {
        if (!registry.TryGetConnection(restaurantId, out var connectionId))
            return new PrintJobResult(false, "No print agent is connected for this restaurant. Make sure the Tehzeeb Print Agent is running at the restaurant.");

        var jobId = Guid.NewGuid();
        var tcs = new TaskCompletionSource<PrintJobResult>(TaskCreationOptions.RunContinuationsAsynchronously);
        registry.PendingJobs[jobId] = tcs;

        try
        {
            await registry.Hub.Clients.Client(connectionId!)
                .SendAsync("ReceivePrintJob", new PrintJobMessage(jobId, printerName, bytes, copies));

            using var cts = new CancellationTokenSource(Timeout);
            await using var reg = cts.Token.Register(() => tcs.TrySetResult(new PrintJobResult(false, "Print agent did not respond in time.")));
            return await tcs.Task;
        }
        finally
        {
            registry.PendingJobs.TryRemove(jobId, out _);
        }
    }
}
