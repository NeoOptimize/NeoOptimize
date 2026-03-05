using System;
using System.IO;
using System.Runtime.InteropServices;

class Program
{
    [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr LoadLibrary(string lpFileName);

    [DllImport("kernel32", SetLastError = true)]
    static extern bool FreeLibrary(IntPtr hModule);

    [DllImport("kernel32")]
    static extern uint GetLastError();

    static void TryLoad(string path)
    {
        Console.WriteLine($"Trying: {path}");
        try
        {
            var h = LoadLibrary(path);
            if (h == IntPtr.Zero)
            {
                Console.WriteLine($"  FAILED (GetLastError={GetLastError()})");
            }
            else
            {
                Console.WriteLine("  OK (loaded)");
                FreeLibrary(h);
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine("  EX: " + ex.Message);
        }
    }

    static void Main()
    {
        Console.WriteLine("NeoOptimize DLL load tester\n");

        var candidates = new System.Collections.Generic.List<string>();

        // Current working directory
        candidates.Add(Path.Combine(Directory.GetCurrentDirectory(), "NeoOptimize.Engine.dll"));

        // Project output locations (Debug/Release net8.0)
        var user = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var repoRoot = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", ".."));
        candidates.Add(Path.Combine(repoRoot, "NeoOptimize.Engine", "x64", "Debug", "NeoOptimize.Engine.dll"));
        candidates.Add(Path.Combine(repoRoot, "NeoOptimize.Engine", "x64", "Release", "NeoOptimize.Engine.dll"));

        // Common managed output folders used earlier
        candidates.Add(Path.Combine(repoRoot, "NeoOptimize.UI.ConsoleTest", "bin", "Debug", "net8.0", "NeoOptimize.Engine.dll"));
        candidates.Add(Path.Combine(repoRoot, "NeoOptimize.UI.ConsoleTest", "bin", "Release", "net8.0", "NeoOptimize.Engine.dll"));
        candidates.Add(Path.Combine(repoRoot, "NeoOptimize.UI", "bin", "Debug", "net8.0", "NeoOptimize.Engine.dll"));
        candidates.Add(Path.Combine(repoRoot, "NeoOptimize.UI", "bin", "Release", "net8.0", "NeoOptimize.Engine.dll"));

        // PATH search
        var pathEnv = Environment.GetEnvironmentVariable("PATH") ?? string.Empty;
        foreach (var p in pathEnv.Split(';'))
        {
            if (string.IsNullOrWhiteSpace(p)) continue;
            candidates.Add(Path.Combine(p.Trim(), "NeoOptimize.Engine.dll"));
        }

        // Unique the list
        var seen = new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var c in candidates)
        {
            if (string.IsNullOrWhiteSpace(c)) continue;
            var full = Path.GetFullPath(c);
            if (seen.Add(full)) TryLoad(full);
        }

        Console.WriteLine("\nDone. If all attempts failed, build the native DLL and copy it to your app output or add its folder to PATH.");
    }
}
