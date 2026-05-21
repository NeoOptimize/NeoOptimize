using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;

namespace NeoOptimizeUIWrapper
{
    class Program
    {
        private static readonly string LogDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
            "NeoOptimize",
            "logs");

        private static readonly string LogPath = Path.Combine(LogDir, "NeoOptimizeUILauncher.log");

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int MessageBoxW(IntPtr hWnd, string text, string caption, uint type);

        private static void Log(string message)
        {
            try
            {
                Directory.CreateDirectory(LogDir);
                File.AppendAllText(LogPath, $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {message}{Environment.NewLine}");
            }
            catch { }
        }

        static void Main(string[] args)
        {
            string exeDir = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
            string? processDir = Path.GetDirectoryName(Process.GetCurrentProcess().MainModule?.FileName ?? "");
            string? currentDir = Environment.CurrentDirectory;
            string programFilesDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
                "NeoOptimize");

            string? scriptPath = new[]
            {
                Path.Combine(exeDir, "NeoOptimize.UI.ps1"),
                processDir == null ? "" : Path.Combine(processDir, "NeoOptimize.UI.ps1"),
                currentDir == null ? "" : Path.Combine(currentDir, "NeoOptimize.UI.ps1"),
                Path.Combine(programFilesDir, "NeoOptimize.UI.ps1"),
                Path.Combine(exeDir, "client", "NeoOptimize.UI.ps1")
            }.Where(File.Exists).FirstOrDefault();

            Log($"Launcher started. exeDir='{exeDir}', processDir='{processDir}', currentDir='{currentDir}', script='{scriptPath ?? "<missing>"}'.");

            if (!string.IsNullOrWhiteSpace(scriptPath) && File.Exists(scriptPath))
            {
                string powershell = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                    "System32",
                    "WindowsPowerShell",
                    "v1.0",
                    "powershell.exe");

                if (!File.Exists(powershell))
                {
                    powershell = "powershell.exe";
                }

                var psi = new ProcessStartInfo
                {
                    FileName = powershell,
                    Arguments = $"-Sta -NoProfile -ExecutionPolicy RemoteSigned -File \"{scriptPath}\"",
                    UseShellExecute = true,
                    WorkingDirectory = Path.GetDirectoryName(scriptPath) ?? exeDir,
                    WindowStyle = ProcessWindowStyle.Normal
                };

                try
                {
                    Process.Start(psi);
                    Log("PowerShell UI process started.");
                }
                catch (Exception ex)
                {
                    Log("Error launching UI: " + ex);
                    MessageBoxW(
                        IntPtr.Zero,
                        "NeoOptimize UI could not be started.\n\n" + ex.Message + "\n\nLog: " + LogPath,
                        "NeoOptimize",
                        0x00000010);
                }
            }
            else
            {
                string message = "NeoOptimize.UI.ps1 was not found next to NeoOptimize.exe.\n\nLog: " + LogPath;
                Log(message);
                MessageBoxW(IntPtr.Zero, message, "NeoOptimize", 0x00000010);
            }
        }
    }
}
