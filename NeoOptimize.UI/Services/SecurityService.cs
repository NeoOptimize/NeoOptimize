using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

namespace NeoOptimize.UI.Services
{
    public class SecurityProgressEventArgs : EventArgs
    {
        public string Json { get; }
        public SecurityProgressEventArgs(string json) => Json = json;
    }

    public class SecurityService : IDisposable
    {
        private bool _disposed;

        public event EventHandler<SecurityProgressEventArgs>? Progress;

        public SecurityService()
        {
            EngineInterop.ProgressReceived += OnEngineProgress;
        }

        private void OnEngineProgress(string json)
        {
            Progress?.Invoke(this, new SecurityProgressEventArgs(json));
        }

        public Task StartOperationsAsync(IEnumerable<string> operations, CancellationToken cancellationToken = default)
        {
            if (cancellationToken.CanBeCanceled)
            {
                cancellationToken.Register(() => {
                    try { Stop(); } catch { }
                });
            }
            return EngineInterop.StartSecurityOperationsAsync(operations);
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

