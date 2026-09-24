using PrintAgent;

var builder = Host.CreateApplicationBuilder(args);

// Lets this run either as a normal console app (for testing) or installed
// as a Windows service (`sc create` / New-Service) for unattended operation
// at the restaurant — a no-op when not actually hosted as a service.
builder.Services.AddWindowsService(opt => opt.ServiceName = "Tehzeeb Print Agent");

builder.Services.AddHostedService<Worker>();

var host = builder.Build();
host.Run();
