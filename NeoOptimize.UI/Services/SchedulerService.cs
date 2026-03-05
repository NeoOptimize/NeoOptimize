using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

namespace NeoOptimize.UI.Services
{
    public class SchedulerProgressEventArgs : EventArgs
    {
        public string Json { get; }
        public SchedulerProgressEventArgs(string json) => Json = json;
    }

    public class SchedulerService : IDisposable
    {
        private bool _disposed;

        public event EventHandler<SchedulerProgressEventArgs>? Progress;

        public SchedulerService()
        {
            EngineInterop.ProgressReceived += OnEngineProgress;
        }

        private void OnEngineProgress(string json)
        {
            Progress?.Invoke(this, new SchedulerProgressEventArgs(json));
        }

        public Task StartOperationsAsync(IEnumerable<string> operations, CancellationToken cancellationToken = default)
        {
            if (cancellationToken.CanBeCanceled)
            {
                cancellationToken.Register(() => {
                    try { Stop(); } catch { }
                });
            }
            return EngineInterop.StartSchedulerOperationsAsync(operations);
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

