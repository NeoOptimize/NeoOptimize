using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

namespace NeoOptimize.UI.Services
{
    public class OptimizerProgressEventArgs : EventArgs
    {
        public string Json { get; }
        public OptimizerProgressEventArgs(string json) => Json = json;
    }

    public class OptimizerService : IDisposable
    {
        private bool _disposed;

        public event EventHandler<OptimizerProgressEventArgs>? Progress;

        public OptimizerService()
        {
            EngineInterop.ProgressReceived += OnEngineProgress;
        }

        private void OnEngineProgress(string json)
        {
            Progress?.Invoke(this, new OptimizerProgressEventArgs(json));
        }

        public Task StartAsync(string optionsJson = "{}", CancellationToken cancellationToken = default)
        {
            if (cancellationToken.CanBeCanceled)
            {
                cancellationToken.Register(() => {
                    try { Stop(); } catch { }
                });
            }
            return EngineInterop.StartOptimizerAsync(optionsJson);
        }

        public Task StartOperationsAsync(IEnumerable<string> operations, CancellationToken cancellationToken = default)
        {
            if (cancellationToken.CanBeCanceled)
            {
                cancellationToken.Register(() => {
                    try { Stop(); } catch { }
                });
            }
            return EngineInterop.StartOptimizerOperationsAsync(operations);
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
