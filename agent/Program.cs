using Microsoft.Extensions.DependencyInjection;
using System.Net.Http;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Configuration;
using Serilog;
using System.Reflection;
using NeoOptimize.Agent.Services;
using NeoOptimize.Agent.Security;
using NeoOptimize.Agent.Commands;
using NeoOptimize.Agent.Safety;

namespace NeoOptimize.Agent;

public class Program
{
    public static void Main(string[] args)
    {
        // 1. Setup Serilog Manually to avoid Single-File Reflection bugs
        Log.Logger = new LoggerConfiguration()
            .MinimumLevel.Information()
            .Enrich.FromLogContext()
            .WriteTo.Console()
            .CreateLogger();

        try
        {
            if (TamperProtectionRequested(args))
            {
                var shield = new AntiTamperShield();
                shield.LockdownServiceAndRegistry();
            }

            CreateHostBuilder(args).Build().Run();
        }
        catch (Exception ex)
        {
            Log.Fatal(ex, "Agent crashed unrecoverably");
        }
        finally
        {
            Log.CloseAndFlush();
        }
    }

    public static IHostBuilder CreateHostBuilder(string[] args) =>
        Host.CreateDefaultBuilder(args)
            .UseWindowsService(options =>
            {
                options.ServiceName = "NeoOptimize RMM Agent";
            })
            .UseSerilog()
            .ConfigureServices((hostContext, services) =>
            {
                // Register local services
                services.AddSingleton<ISystemCollector, SystemCollector>();
                services.AddSingleton<AgentSecureStore>();
                services.AddSingleton<RegistrySnapshotManager>();
                services.AddSingleton<WindowsRestorePointManager>();
                services.AddSingleton<SystemHealthProbe>();
                services.AddSingleton<CommandSafetyRuntime>();
                services.AddSingleton<CommandDispatcher>();

                services.AddHttpClient<ApiClient>().ConfigurePrimaryHttpMessageHandler(() =>
                {
                    var handler = new HttpClientHandler();
                    if (ReadBool(hostContext.Configuration, "AllowInsecureTls", false))
                    {
                        handler.ServerCertificateCustomValidationCallback = (message, cert, chain, errors) => true;
                    }
                    return handler;
                });

                // Setup RSA verifier from deployment config or the public key copied next to the EXE.
                string pubKey = ResolvePublicKey(hostContext.Configuration);
                if (string.IsNullOrWhiteSpace(pubKey))
                    throw new InvalidOperationException("Missing signing public key. Copy signing.pub.pem next to the agent or set PublicKeyPem.");

                services.AddSingleton(new RsaVerifier(pubKey));

                // Start the Worker
                services.AddHostedService<AgentWorker>();
            });

    private static bool TamperProtectionRequested(string[] args)
    {
        return args.Any(arg => string.Equals(arg, "--enable-tamper-protection", StringComparison.OrdinalIgnoreCase)) ||
               IsTruthy(Environment.GetEnvironmentVariable("NEO_AGENT_TAMPER_PROTECTION"));
    }

    private static bool IsTruthy(string? value)
    {
        return value is not null &&
               (value.Equals("1", StringComparison.OrdinalIgnoreCase) ||
                value.Equals("true", StringComparison.OrdinalIgnoreCase) ||
                value.Equals("yes", StringComparison.OrdinalIgnoreCase));
    }

    private static string ResolvePublicKey(IConfiguration configuration)
    {
        var configured = configuration["PublicKeyPem"] ?? configuration["Agent:PublicKeyPem"] ?? "";
        if (LooksLikePublicKey(configured)) return configured;

        var exePath = System.Diagnostics.Process.GetCurrentProcess().MainModule?.FileName;
        var exeDir = Path.GetDirectoryName(exePath) ?? AppDomain.CurrentDomain.BaseDirectory;
        foreach (var path in new[]
        {
            Path.Combine(exeDir, "signing.pub.pem"),
            Path.Combine(exeDir, "keys", "signing.pub.pem"),
            Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "signing.pub.pem"),
            Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "keys", "signing.pub.pem")
        })
        {
            if (File.Exists(path))
            {
                var pem = File.ReadAllText(path);
                if (LooksLikePublicKey(pem)) return pem;
            }
        }

        return ReadEmbeddedResource("NeoOptimize.Agent.keys.signing.pub.pem");
    }

    private static bool ReadBool(IConfiguration configuration, string key, bool defaultValue)
    {
        var value = configuration[key] ?? configuration[$"Agent:{key}"];
        return bool.TryParse(value, out var parsed) ? parsed : defaultValue;
    }

    private static bool LooksLikePublicKey(string value)
    {
        return !string.IsNullOrWhiteSpace(value) && value.Contains("BEGIN PUBLIC KEY");
    }

    private static string ReadEmbeddedResource(string resourceName)
    {
        try
        {
            var assembly = Assembly.GetExecutingAssembly();
            using var stream = assembly.GetManifestResourceStream(resourceName);
            if (stream == null) return "";
            using var reader = new StreamReader(stream);
            return reader.ReadToEnd();
        }
        catch
        {
            return "";
        }
    }
}
