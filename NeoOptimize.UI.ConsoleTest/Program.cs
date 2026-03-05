using System;
using System.Runtime.InteropServices;
using System.Threading;

class Program
{
    private static class NativeMethods
    {
        [DllImport("NeoOptimize.Engine.dll", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern IntPtr NO_GetVersion();

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        public delegate void NO_ProgressCallback([MarshalAs(UnmanagedType.LPStr)] string utf8JsonProgress);

        [DllImport("NeoOptimize.Engine.dll", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern int NO_RegisterProgressCallback(NO_ProgressCallback cb);

        [DllImport("NeoOptimize.Engine.dll", CallingConvention = CallingConvention.Cdecl)]
        public static extern void NO_UnregisterProgressCallback();

        [DllImport("NeoOptimize.Engine.dll", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern int NO_StartScan(string categoriesJson);

        [DllImport("NeoOptimize.Engine.dll", CallingConvention = CallingConvention.Cdecl)]
        public static extern void NO_Stop();
    }

    private static class SimulatedEngine
    {
        // legacy simulated engine kept for reference; prefer NeoOptimize.Engine.Mock when available
        public static string GetVersion() => "NeoOptimize.Engine (simulated) 0.0.0";
        public static int StartScan(string categoriesJson)
        {
            Console.WriteLine("[SimulatedEngine] Starting scan with: " + categoriesJson);
            var t = new System.Threading.Tasks.Task(() => {
                for (int i = 0; i <= 100; i += 20)
                {
                    Console.WriteLine($"[SimulatedEngine] progress: {i}%");
                    System.Threading.Thread.Sleep(500);
                }
                Console.WriteLine("[SimulatedEngine] scan complete (simulated)");
            });
            t.Start();
            return 0;
        }
        public static void Stop()
        {
            Console.WriteLine("[SimulatedEngine] Stop called (no-op)");
        }
    }

    static void Main()
    {
        // Try to load the native DLL first to provide realistic behavior.
        bool nativeLoaded = false;
        IntPtr handle = IntPtr.Zero;
        try
        {
            nativeLoaded = System.Runtime.InteropServices.NativeLibrary.TryLoad("NeoOptimize.Engine.dll", out handle);
        }
        catch { nativeLoaded = false; }

        try
        {
            if (nativeLoaded)
            {
                // register progress callback and keep delegate alive to prevent GC
                NativeMethods.NO_ProgressCallback progressCb = (json) => {
                    Console.WriteLine("[ENGINE PROGRESS] " + json);
                };
                NativeMethods.NO_RegisterProgressCallback(progressCb);

                var verPtr = NativeMethods.NO_GetVersion();
                string ver = Marshal.PtrToStringAnsi(verPtr) ?? "unknown";
                Console.WriteLine("Engine: " + ver);
                Console.WriteLine("Starting scan (dry-run) via native engine...");
                int res = NativeMethods.NO_StartScan("{\"dryRun\":true}");
                Console.WriteLine("NO_StartScan returned: " + res);
                Console.WriteLine("Waiting 6 seconds to observe background work...");
                Thread.Sleep(6000);
                Console.WriteLine("Stopping engine (if still running)...");
                NativeMethods.NO_Stop();

                // unregister callback
                NativeMethods.NO_UnregisterProgressCallback();
            }
            else
            {
                // Prefer the managed mock engine if available (project reference)
                try
                {
                    var mockType = Type.GetType("NeoOptimize.Engine.Mock.MockEngine, NeoOptimize.Engine.Mock");
                    if (mockType != null)
                    {
                        Console.WriteLine("Managed mock engine found — using mock.");
                        var getVer = mockType.GetMethod("GetVersion");
                        var ver = getVer?.Invoke(null, null) as string ?? "mock";
                        Console.WriteLine("Engine: " + ver);

                        // subscribe to progress
                        var progressEvent = mockType.GetEvent("Progress");
                        Action<string> onProgress = (s) => Console.WriteLine("[MOCK PROGRESS] " + s);
                        progressEvent?.AddEventHandler(null, onProgress);

                        var start = mockType.GetMethod("StartScan");
                        start?.Invoke(null, new object[] { "{\"dryRun\":true}" });
                        Console.WriteLine("Waiting 6 seconds to observe mock work...");
                        Thread.Sleep(6000);

                        var stop = mockType.GetMethod("Stop");
                        stop?.Invoke(null, null);
                        progressEvent?.RemoveEventHandler(null, onProgress);
                    }
                    else
                    {
                        Console.WriteLine("Native engine not found — running simulated engine.");
                        Console.WriteLine("Engine: " + SimulatedEngine.GetVersion());
                        SimulatedEngine.StartScan("{\"dryRun\":true}");
                        Console.WriteLine("Waiting 6 seconds to observe simulated work...");
                        Thread.Sleep(6000);
                        SimulatedEngine.Stop();
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine("Error using mock engine: " + ex.Message);
                    Console.WriteLine("Falling back to simulated engine.");
                    Console.WriteLine("Engine: " + SimulatedEngine.GetVersion());
                    SimulatedEngine.StartScan("{\"dryRun\":true}");
                    Thread.Sleep(6000);
                    SimulatedEngine.Stop();
                }
            }

            Console.WriteLine("Done. If you want native behavior, build the native DLL and place it beside this exe or on PATH.");
        }
        catch (Exception ex)
        {
            Console.WriteLine("Error calling engine: " + ex.Message);
        }
        finally
        {
            if (handle != IntPtr.Zero) NativeLibrary.Free(handle);
        }
    }
}
