using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;

namespace NeoOptimizeUIWrapper;

internal static class Program
{
    private const string ProductName = "NeoOptimize";

    [STAThread]
    private static int Main(string[] args)
    {
        var root = ResolveRoot();
        var logPath = PrepareLogPath();

        try
        {
            LaunchNeoOptimize(root, args);
            WriteLog(logPath, "Classic UI launcher started.");
            return 0;
        }
        catch (Exception ex)
        {
            WriteLog(logPath, "Launcher error: " + ex);
            MessageBoxW(
                IntPtr.Zero,
                $"NeoOptimize could not start.\n\n{ex.Message}\n\nLog: {logPath}",
                ProductName,
                0x00000010);
            return 1;
        }
    }

    private static void LaunchNeoOptimize(string root, string[] args)
    {
        var launcher = Path.Combine(root, "NeoOptimize.Launcher.ps1");
        var ui = Path.Combine(root, "NeoOptimize.UI.ps1");

        if (!File.Exists(launcher) && !File.Exists(ui))
        {
            throw new FileNotFoundException(
                "Classic NeoOptimize UI files were not found. Reinstall NeoOptimize.",
                launcher);
        }

        var powershell = ResolvePowerShell();
        var startInfo = new ProcessStartInfo(powershell)
        {
            WorkingDirectory = root,
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden
        };

        startInfo.ArgumentList.Add("-NoProfile");
        startInfo.ArgumentList.Add("-WindowStyle");
        startInfo.ArgumentList.Add("Hidden");
        startInfo.ArgumentList.Add("-ExecutionPolicy");
        startInfo.ArgumentList.Add("RemoteSigned");

        if (File.Exists(launcher))
        {
            startInfo.ArgumentList.Add("-File");
            startInfo.ArgumentList.Add(launcher);
            AddLauncherModeArgs(startInfo, args);
        }
        else
        {
            startInfo.ArgumentList.Add("-Sta");
            startInfo.ArgumentList.Add("-File");
            startInfo.ArgumentList.Add(ui);
        }

        Process.Start(startInfo);
    }

    private static void AddLauncherModeArgs(ProcessStartInfo startInfo, string[] args)
    {
        if (HasArg(args, "--tray", "-tray", "/tray"))
        {
            startInfo.ArgumentList.Add("-Tray");
        }

        if (HasArg(args, "--update", "-update", "--update-manager", "-updatemanager", "/update"))
        {
            startInfo.ArgumentList.Add("-UpdateManager");
        }

        if (HasArg(args, "--console", "-console", "/console"))
        {
            startInfo.ArgumentList.Add("-Console");
        }
    }

    private static bool HasArg(string[] args, params string[] names)
    {
        return args.Any(arg => names.Any(name =>
            string.Equals(arg, name, StringComparison.OrdinalIgnoreCase)));
    }

    private static string ResolveRoot()
    {
        var root = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        if (!string.IsNullOrWhiteSpace(root) && Directory.Exists(root))
        {
            return root;
        }

        var processPath = Environment.ProcessPath;
        if (!string.IsNullOrWhiteSpace(processPath))
        {
            var parent = Path.GetDirectoryName(processPath);
            if (!string.IsNullOrWhiteSpace(parent))
            {
                return parent;
            }
        }

        return Environment.CurrentDirectory;
    }

    private static string ResolvePowerShell()
    {
        var windir = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        var system32 = Path.Combine(windir, "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
        if (File.Exists(system32))
        {
            return system32;
        }

        return "powershell.exe";
    }

    private static string PrepareLogPath()
    {
        var programData = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
        var logDir = Path.Combine(programData, "NeoOptimize", "logs");
        Directory.CreateDirectory(logDir);
        return Path.Combine(logDir, "NeoOptimizeLauncher.log");
    }

    private static void WriteLog(string logPath, string message)
    {
        try
        {
            File.AppendAllText(
                logPath,
                $"[{DateTimeOffset.Now:yyyy-MM-dd HH:mm:ss zzz}] {message}{Environment.NewLine}");
        }
        catch
        {
            // Logging must never block application launch.
        }
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int MessageBoxW(IntPtr hWnd, string text, string caption, uint type);
}
