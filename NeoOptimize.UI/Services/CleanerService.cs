using System;
using System.Threading;
using System.Threading.Tasks;

namespace NeoOptimize.UI.Services
{
    public class CleanerProgressEventArgs : EventArgs
    {
        public string Json { get; }
        public CleanerProgressEventArgs(string json) => Json = json;
    }

    public class CleanerService : IDisposable
    {
        private bool _disposed;

        public event EventHandler<CleanerProgressEventArgs>? Progress;

        public CleanerService()
        {
            EngineInterop.ProgressReceived += OnEngineProgress;
        }

        private void OnEngineProgress(string json)
        {
            Progress?.Invoke(this, new CleanerProgressEventArgs(json));
        }

        public Task StartAsync(string categoriesJson = "{}", CancellationToken cancellationToken = default)
        {
            if (cancellationToken.CanBeCanceled)
            {
                cancellationToken.Register(() => {
                    try { Stop(); } catch { }
                });
            }
            return EngineInterop.StartCleanerAsync(categoriesJson);
        }

        public Task ExecuteAsync(string requestJson = "{}")
        {
            return EngineInterop.ExecuteCleanerAsync(requestJson);
        }

        public void Stop()
        {
            EngineInterop.Stop();
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            EngineInterop.ProgressReceived -= OnEngineProgress;
            EngineInterop.UnregisterCallback();
        }
    }
}
