using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

class Program
{
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void ProgressCallback(IntPtr utf8JsonPtr);

    [DllImport("NeoOptimize.Engine.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr NO_GetVersion();

    [DllImport("NeoOptimize.Engine.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int NO_RegisterProgressCallback(IntPtr cb);

    [DllImport("NeoOptimize.Engine.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern void NO_UnregisterProgressCallback();

    [DllImport("NeoOptimize.Engine.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int NO_StartCleanerScan(IntPtr categoriesJsonUtf8);

    [DllImport("NeoOptimize.Engine.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern void NO_Stop();

    private static ProgressCallback? _cb;

    static void Main()
    {
        Console.WriteLine("NeoOptimize TestHarness\n");

        // version
        try
        {
            var verPtr = NO_GetVersion();
            if (verPtr != IntPtr.Zero)
            {
                string? s = Marshal.PtrToStringUTF8(verPtr);
                if (string.IsNullOrEmpty(s)) s = Marshal.PtrToStringAnsi(verPtr);
                Console.WriteLine("Engine version: " + (s ?? "(unknown)"));
            }
            else
            {
                Console.WriteLine("NO_GetVersion returned null");
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine("GetVersion failed: " + ex.Message);
        }

        // register callback
        _cb = new ProgressCallback(OnProgress);
        IntPtr fn = Marshal.GetFunctionPointerForDelegate(_cb);
        int r = NO_RegisterProgressCallback(fn);
        Console.WriteLine($"RegisterProgressCallback -> {r}");

        // start a cleaner scan (categories = empty/default)
        IntPtr p = AllocUtf8("{}");
        try
        {
            int sres = NO_StartCleanerScan(p);
            Console.WriteLine($"NO_StartCleanerScan -> {sres}");
        }
        finally
        {
            FreeUtf8(p);
        }

        Console.WriteLine("Waiting 3s to receive callbacks...");
        Thread.Sleep(3000);

        Console.WriteLine("Stopping engine...");
        NO_Stop();
        NO_UnregisterProgressCallback();

        Console.WriteLine("Done.");
    }

    private static void OnProgress(IntPtr utf8JsonPtr)
    {
        try
        {
            string? json = Marshal.PtrToStringUTF8(utf8JsonPtr);
            if (string.IsNullOrEmpty(json)) json = Marshal.PtrToStringAnsi(utf8JsonPtr);
            Console.WriteLine("<- " + (json ?? ""));
        }
        catch { }
    }

    private static IntPtr AllocUtf8(string s)
    {
        var bytes = Encoding.UTF8.GetBytes(s + "\0");
        IntPtr p = Marshal.AllocHGlobal(bytes.Length);
        Marshal.Copy(bytes, 0, p, bytes.Length);
        return p;
    }

    private static void FreeUtf8(IntPtr p)
    {
        if (p == IntPtr.Zero) return;
        Marshal.FreeHGlobal(p);
    }
}
