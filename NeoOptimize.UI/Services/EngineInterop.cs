using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading.Tasks;

namespace NeoOptimize.UI.Services
{
    internal static class EngineInterop
    {
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate void NativeProgressCallback(IntPtr utf8JsonPtr);

        private static NativeProgressCallback? s_nativeCb;
        private static readonly object s_lock = new object();

        public static event Action<string>? ProgressReceived;

        [DllImport("NeoOptimize.Engine.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int NO_RegisterProgressCallback(IntPtr cb);

        [DllImport("NeoOptimize.Engine.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern void NO_UnregisterProgressCallback();

        [DllImport("NeoOptimize.Engine.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int NO_StartCleanerScan(IntPtr categoriesJsonUtf8);

        [DllImport("NeoOptimize.Engine.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int NO_ExecuteCleaner(IntPtr requestJsonUtf8);

        [DllImport("NeoOptimize.Engine.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int NO_StartOptimizer(IntPtr optionsJsonUtf8);

        [DllImport("NeoOptimize.Engine.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int NO_StartSecurity(IntPtr optionsJsonUtf8);

        [DllImport("NeoOptimize.Engine.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int NO_StartScheduler(IntPtr optionsJsonUtf8);

        [DllImport("NeoOptimize.Engine.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int NO_StartAppManager(IntPtr optionsJsonUtf8);

        [DllImport("NeoOptimize.Engine.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int NO_ListInstalledApps([Out] byte[] outJsonBuf, int outBufSize);

        [DllImport("NeoOptimize.Engine.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int NO_UninstallApp(IntPtr appIdJsonUtf8);

        [DllImport("NeoOptimize.Engine.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern void NO_Stop();

        [DllImport("NeoOptimize.Engine.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern IntPtr NO_GetVersion();

        // Helper to register managed callback with native side.
        public static void RegisterCallback()
        {
            lock (s_lock)
            {
                if (s_nativeCb != null) return;
                s_nativeCb = new NativeProgressCallback(OnNativeProgress);
                IntPtr fnPtr = Marshal.GetFunctionPointerForDelegate(s_nativeCb);
                NO_RegisterProgressCallback(fnPtr);
            }
        }

        public static void UnregisterCallback()
        {
            lock (s_lock)
            {
                NO_UnregisterProgressCallback();
                s_nativeCb = null;
            }
        }

        private static void OnNativeProgress(IntPtr utf8JsonPtr)
        {
            try
            {
                string? json = Marshal.PtrToStringUTF8(utf8JsonPtr);
                if (json is null) json = string.Empty;
                ProgressReceived?.Invoke(json);
            }
            catch { }
        }

        public static Task StartCleanerAsync(string categoriesJson = "{}")
        {
            RegisterCallback();
            IntPtr p = AllocUtf8(categoriesJson ?? "{}");
            try
            {
                int r = NO_StartCleanerScan(p);
                if (r != 0) return Task.FromException(new InvalidOperationException($"NO_StartCleanerScan returned {r}"));
            }
            finally
            {
                FreeUtf8(p);
            }
            return Task.CompletedTask;
        }

        public static Task StartOptimizerAsync(string optionsJson = "{}")
        {
            RegisterCallback();
            IntPtr p = AllocUtf8(optionsJson ?? "{}");
            try
            {
                int r = NO_StartOptimizer(p);
                if (r != 0) return Task.FromException(new InvalidOperationException($"NO_StartOptimizer returned {r}"));
            }
            finally
            {
                FreeUtf8(p);
            }
            return Task.CompletedTask;
        }

        public static Task StartOptimizerOperationsAsync(IEnumerable<string> operations)
        {
            string payload = JsonSerializer.Serialize(new { operations = operations ?? Array.Empty<string>() });
            return StartOptimizerAsync(payload);
        }

        public static Task StartAppManagerAsync(string optionsJson = "{}")
        {
            RegisterCallback();
            IntPtr p = AllocUtf8(optionsJson ?? "{}");
            try
            {
                int r = NO_StartAppManager(p);
                if (r != 0) return Task.FromException(new InvalidOperationException($"NO_StartAppManager returned {r}"));
            }
            finally
            {
                FreeUtf8(p);
            }
            return Task.CompletedTask;
        }

        public static Task StartAppManagerOperationsAsync(IEnumerable<string> operations)
        {
            string payload = JsonSerializer.Serialize(new { operations = operations ?? Array.Empty<string>() });
            return StartAppManagerAsync(payload);
        }

        public static Task StartSecurityAsync(string optionsJson = "{}")
        {
            RegisterCallback();
            IntPtr p = AllocUtf8(optionsJson ?? "{}");
            try
            {
                int r = NO_StartSecurity(p);
                if (r != 0) return Task.FromException(new InvalidOperationException($"NO_StartSecurity returned {r}"));
            }
            finally
            {
                FreeUtf8(p);
            }
            return Task.CompletedTask;
        }

        public static Task StartSecurityOperationsAsync(IEnumerable<string> operations)
        {
            string payload = JsonSerializer.Serialize(new { operations = operations ?? Array.Empty<string>() });
            return StartSecurityAsync(payload);
        }

        public static Task StartSchedulerAsync(string optionsJson = "{}")
        {
            RegisterCallback();
            IntPtr p = AllocUtf8(optionsJson ?? "{}");
            try
            {
                int r = NO_StartScheduler(p);
                if (r != 0) return Task.FromException(new InvalidOperationException($"NO_StartScheduler returned {r}"));
            }
            finally
            {
                FreeUtf8(p);
            }
            return Task.CompletedTask;
        }

        public static Task StartSchedulerOperationsAsync(IEnumerable<string> operations)
        {
            string payload = JsonSerializer.Serialize(new { operations = operations ?? Array.Empty<string>() });
            return StartSchedulerAsync(payload);
        }

        public static Task<string> ListInstalledAppsAsync()
        {
            int bufSize = 16 * 1024;
            for (int i = 0; i < 4; i++)
            {
                var buf = new byte[bufSize];
                int written = NO_ListInstalledApps(buf, bufSize);
                if (written == -2)
                {
                    bufSize *= 2;
                    continue;
                }
                if (written < 0)
                {
                    return Task.FromException<string>(new InvalidOperationException($"NO_ListInstalledApps failed with {written}"));
                }
                var str = System.Text.Encoding.UTF8.GetString(buf, 0, written);
                return Task.FromResult(str);
            }
            return Task.FromException<string>(new InvalidOperationException("NO_ListInstalledApps output exceeded max buffer"));
        }

        public static Task UninstallAppAsync(string appId)
        {
            RegisterCallback();
            string json = JsonSerializer.Serialize(new { id = appId ?? string.Empty });
            IntPtr p = AllocUtf8(json);
            try
            {
                int r = NO_UninstallApp(p);
                if (r != 0) return Task.FromException(new InvalidOperationException($"NO_UninstallApp returned {r}"));
            }
            finally
            {
                FreeUtf8(p);
            }
            return Task.CompletedTask;
        }

        public static Task ExecuteCleanerAsync(string requestJson)
        {
            RegisterCallback();
            IntPtr p = AllocUtf8(requestJson ?? "{}");
            try
            {
                int r = NO_ExecuteCleaner(p);
                if (r != 0) return Task.FromException(new InvalidOperationException($"NO_ExecuteCleaner returned {r}"));
            }
            finally
            {
                FreeUtf8(p);
            }
            return Task.CompletedTask;
        }

        private static IntPtr AllocUtf8(string s)
        {
            if (s == null) s = string.Empty;
            byte[] bytes = System.Text.Encoding.UTF8.GetBytes(s + "\0");
            IntPtr p = Marshal.AllocHGlobal(bytes.Length);
            Marshal.Copy(bytes, 0, p, bytes.Length);
            return p;
        }

        private static void FreeUtf8(IntPtr p)
        {
            if (p == IntPtr.Zero) return;
            Marshal.FreeHGlobal(p);
        }

        public static void Stop()
        {
            NO_Stop();
            // keep callback registered so UI can continue receiving any last messages; caller may unregister explicitly
        }

        public static string GetVersion()
        {
            try
            {
                IntPtr p = NO_GetVersion();
                if (p == IntPtr.Zero) return string.Empty;
                // header documents this as ANSI; engine returns ASCII/UTF8 - try UTF8 first, fallback to ANSI
                try
                {
                    string? s = Marshal.PtrToStringUTF8(p);
                    if (!string.IsNullOrEmpty(s)) return s;
                }
                catch { }
                try
                {
                    string? s2 = Marshal.PtrToStringAnsi(p);
                    return s2 ?? string.Empty;
                }
                catch { }
                return string.Empty;
            }
            catch
            {
                return string.Empty;
            }
        }
    }
}
