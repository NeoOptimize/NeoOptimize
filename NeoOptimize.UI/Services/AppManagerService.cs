using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Threading.Tasks;

namespace NeoOptimize.UI.Services
{
    public record AppInfo(
        string Id,
        string Name,
        string Scope,
        string Publisher,
        string Uninstall,
        string QuietUninstall);

    public class AppManagerService : IDisposable
    {
        private bool _disposed;
        public event Action<string>? Progress;

        public AppManagerService()
        {
            EngineInterop.ProgressReceived += OnEngineProgress;
        }

        private void OnEngineProgress(string json)
        {
            Progress?.Invoke(json);
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            EngineInterop.ProgressReceived -= OnEngineProgress;
            EngineInterop.UnregisterCallback();
        }

        public async Task<List<AppInfo>> ListInstalledAppsAsync()
        {
            string json = await EngineInterop.ListInstalledAppsAsync();
            var list = new List<AppInfo>();
            try
            {
                using var doc = JsonDocument.Parse(json);
                if (doc.RootElement.ValueKind == JsonValueKind.Array)
                {
                    foreach (var el in doc.RootElement.EnumerateArray())
                    {
                        string id = el.GetProperty("id").GetString() ?? string.Empty;
                        string name = el.GetProperty("name").GetString() ?? string.Empty;
                        string scope = el.TryGetProperty("scope", out var scopeEl) ? (scopeEl.GetString() ?? string.Empty) : string.Empty;
                        string publisher = el.TryGetProperty("publisher", out var publisherEl) ? (publisherEl.GetString() ?? string.Empty) : string.Empty;
                        string uninstall = el.TryGetProperty("uninstall", out var uninstallEl) ? (uninstallEl.GetString() ?? string.Empty) : string.Empty;
                        string quietUninstall = el.TryGetProperty("quietUninstall", out var quietUninstallEl) ? (quietUninstallEl.GetString() ?? string.Empty) : string.Empty;
                        list.Add(new AppInfo(id, name, scope, publisher, uninstall, quietUninstall));
                    }
                }
            }
            catch
            {
                // malformed JSON -> return empty list
            }
            return list;
        }

        public Task UninstallAppAsync(string id)
        {
            return EngineInterop.UninstallAppAsync(id);
        }

        public Task RunOperationsAsync(IEnumerable<string> operations)
        {
            return EngineInterop.StartAppManagerOperationsAsync(operations);
        }
    }
}
