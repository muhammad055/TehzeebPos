using System.Runtime.Versioning;
using Microsoft.AspNetCore.SignalR.Client;

namespace PrintAgent;

// Mirrors backend/PrintDispatch.cs's PrintJobMessage/PrintJobResult shapes —
// duplicated rather than shared for the same reason as RawPrinterHelper.cs.
public record PrintJobMessage(Guid JobId, string PrinterName, byte[] Data, int Copies);

[SupportedOSPlatform("windows")]
public class Worker(ILogger<Worker> logger, IConfiguration config) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var hubUrl = config["HubUrl"]
            ?? throw new InvalidOperationException("HubUrl is not configured (see appsettings.json).");
        var agentKey = config["AgentKey"]
            ?? throw new InvalidOperationException("AgentKey is not configured (see appsettings.json) — get it from Admin > Printer Settings.");

        var connection = new HubConnectionBuilder()
            .WithUrl($"{hubUrl}?key={Uri.EscapeDataString(agentKey)}")
            .WithAutomaticReconnect(new[] { TimeSpan.Zero, TimeSpan.FromSeconds(2), TimeSpan.FromSeconds(5), TimeSpan.FromSeconds(15), TimeSpan.FromSeconds(30) })
            .Build();

        connection.Reconnecting += ex =>
        {
            logger.LogWarning(ex, "Lost connection to {HubUrl}, reconnecting...", hubUrl);
            return Task.CompletedTask;
        };
        connection.Reconnected += _ =>
        {
            logger.LogInformation("Reconnected to {HubUrl}", hubUrl);
            return Task.CompletedTask;
        };
        connection.Closed += ex =>
        {
            logger.LogError(ex, "Connection to {HubUrl} closed permanently", hubUrl);
            return Task.CompletedTask;
        };

        connection.On<PrintJobMessage>("ReceivePrintJob", async job =>
        {
            logger.LogInformation("Print job {JobId}: {Copies}x on \"{PrinterName}\" ({Bytes} bytes)",
                job.JobId, job.Copies, job.PrinterName, job.Data.Length);

            bool success = false;
            string? error = null;
            try
            {
                for (int i = 0; i < job.Copies; i++)
                    RawPrinterHelper.SendBytesToPrinter(job.PrinterName, job.Data);
                success = true;
            }
            catch (Exception ex)
            {
                error = ex.Message;
                logger.LogError(ex, "Print job {JobId} failed", job.JobId);
            }

            try
            {
                await connection.InvokeAsync("ReportJobResult", job.JobId, success, error, stoppingToken);
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Failed to report result for job {JobId} back to server", job.JobId);
            }
        });

        // WithAutomaticReconnect only covers a connection dropping AFTER it
        // succeeds once — retry the very first connect attempt ourselves in
        // case the server (or this machine's network) isn't up yet.
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await connection.StartAsync(stoppingToken);
                logger.LogInformation("Connected to {HubUrl} — ready to print.", hubUrl);
                break;
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Could not connect to {HubUrl}, retrying in 10s...", hubUrl);
                await Task.Delay(TimeSpan.FromSeconds(10), stoppingToken);
            }
        }

        try
        {
            await Task.Delay(Timeout.Infinite, stoppingToken);
        }
        catch (OperationCanceledException)
        {
            // normal shutdown
        }
        finally
        {
            await connection.DisposeAsync();
        }
    }
}
