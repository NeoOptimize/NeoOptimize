using System;
using System.Diagnostics;
using System.IO;

namespace NeoOptimizeCli
{
    class Program
    {
        static void Main(string[] args)
        {
            Console.Title = "NeoOptimize System Optimizer";
            Console.OutputEncoding = System.Text.Encoding.UTF8;

            PrintBanner();

            // AppContext.BaseDirectory is reliable for normal and single-file publishes.
            string exeDir = AppContext.BaseDirectory;
            string modDir = Path.Combine(exeDir, "modules");

            if (!Directory.Exists(modDir))
            {
                Console.ForegroundColor = ConsoleColor.Red;
                Console.WriteLine($"\n  ERROR: 'modules' folder not found at:\n  {modDir}");
                Console.ResetColor();
                Console.WriteLine("\n  Press any key to exit.");
                Console.ReadKey();
                return;
            }

            var files = Directory.GetFiles(modDir, "*.ps1");
            Array.Sort(files);
            files = Array.FindAll(files, IsPublicModule);

            if (files.Length == 0)
            {
                Console.ForegroundColor = ConsoleColor.Red;
                Console.WriteLine("\n  ERROR: No .ps1 modules found in the modules folder.");
                Console.ResetColor();
                Pause();
                return;
            }

            while (true)
            {
                Console.Clear();
                PrintBanner();

                Console.ForegroundColor = ConsoleColor.DarkCyan;
                Console.WriteLine("  ┌─────────────────────────────────────────────┐");
                Console.WriteLine("  │            OPTIMIZATION MODULES             │");
                Console.WriteLine("  └─────────────────────────────────────────────┘");
                Console.ResetColor();
                Console.WriteLine();

                for (int i = 0; i < files.Length; i++)
                {
                    string name = Path.GetFileNameWithoutExtension(files[i]);
                    Console.ForegroundColor = ConsoleColor.DarkGray;
                    Console.Write($"   [{i + 1}] ");
                    Console.ForegroundColor = ConsoleColor.White;
                    Console.WriteLine(name);
                }

                Console.WriteLine();
                Console.ForegroundColor = ConsoleColor.DarkCyan;
                Console.Write("   [0] ");
                Console.ForegroundColor = ConsoleColor.Yellow;
                Console.WriteLine("Run SAFE baseline modules");
                Console.ForegroundColor = ConsoleColor.DarkCyan;
                Console.Write("   [Q] ");
                Console.ForegroundColor = ConsoleColor.Gray;
                Console.WriteLine("Exit");
                Console.ResetColor();

                Console.WriteLine();
                Console.ForegroundColor = ConsoleColor.Cyan;
                Console.Write("  Select module > ");
                Console.ResetColor();

                string input = Console.ReadLine()?.Trim() ?? "";

                if (input.Equals("Q", StringComparison.OrdinalIgnoreCase))
                {
                    Console.WriteLine("\n  Goodbye!\n");
                    break;
                }
                else if (input == "0")
                {
                    Console.Clear();
                    PrintBanner();
                    Console.ForegroundColor = ConsoleColor.Yellow;
                    Console.WriteLine("  Running Defender-safe baseline modules only...\n");
                    Console.ResetColor();
                    foreach (var f in Array.FindAll(files, IsSafeBaselineModule)) RunScript(f);
                    Pause();
                }
                else if (int.TryParse(input, out int sel) && sel >= 1 && sel <= files.Length)
                {
                    Console.Clear();
                    PrintBanner();
                    RunScript(files[sel - 1]);
                    Pause();
                }
                else
                {
                    Console.ForegroundColor = ConsoleColor.Red;
                    Console.WriteLine("  Invalid selection. Try again.");
                    Console.ResetColor();
                    System.Threading.Thread.Sleep(1000);
                }
            }
        }

        static bool IsPublicModule(string path)
        {
            string name = Path.GetFileName(path);
            string[] publicModules = {
                "01_Cleaner.ps1",
                "02_Performance.ps1",
                "03_Privacy.ps1",
                "04_Network.ps1",
                "05_Security.ps1",
                "06_Services.ps1",
                "07_Updates.ps1",
                "08_Power.ps1",
                "09_Maintenance.ps1",
                "10_SystemRepair.ps1",
                "15_DeepScan.ps1",
                "16_SystemDiagnostics.ps1"
            };
            return Array.Exists(publicModules, x => x.Equals(name, StringComparison.OrdinalIgnoreCase));
        }

        static bool IsSafeBaselineModule(string path)
        {
            string name = Path.GetFileName(path);
            string[] safeModules = {
                "01_Cleaner.ps1",
                "02_Performance.ps1",
                "08_Power.ps1",
                "15_DeepScan.ps1",
                "16_SystemDiagnostics.ps1"
            };
            return Array.Exists(safeModules, x => x.Equals(name, StringComparison.OrdinalIgnoreCase));
        }

        static void RunScript(string path)
        {
            string name = Path.GetFileNameWithoutExtension(path);
            Console.ForegroundColor = ConsoleColor.Cyan;
            Console.WriteLine($"\n  ━━━ Executing: {name} ━━━");
            Console.ResetColor();

            // Must run powershell.exe elevated - installer already requires admin.
            // RemoteSigned avoids the Bypass+hidden pattern that Defender heuristics dislike.
            var psi = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = $"-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File \"{path}\"",
                UseShellExecute = false,
                CreateNoWindow  = false
            };

            try
            {
                using var proc = Process.Start(psi);
                if (proc is null)
                {
                    Console.ForegroundColor = ConsoleColor.Red;
                    Console.WriteLine($"  ERROR running {name}: powershell.exe did not start.");
                    Console.ResetColor();
                    return;
                }
                proc.WaitForExit();
                Console.ForegroundColor = proc.ExitCode == 0 ? ConsoleColor.Green : ConsoleColor.Red;
                Console.WriteLine($"\n  [{name}] Exit code: {proc.ExitCode}");
                Console.ResetColor();
            }
            catch (Exception ex)
            {
                Console.ForegroundColor = ConsoleColor.Red;
                Console.WriteLine($"  ERROR running {name}: {ex.Message}");
                Console.ResetColor();
            }
        }

        static void PrintBanner()
        {
            Console.Clear();
            // ── Gradient color cycle for logo lines ──────────────────────
            ConsoleColor[] gradient = {
                ConsoleColor.DarkCyan, ConsoleColor.Cyan, ConsoleColor.White,
                ConsoleColor.Cyan, ConsoleColor.DarkCyan
            };

            string[] logo = {
                @"  ╔╗╔╔═╗╔═╗╔═╗╔═╗╔╦╗╦╔╦╗╦╔═╗╔═╗",
                @"  ║║║║╣ ║ ║║ ║╠═╝ ║ ║║║║║╔═╝║╣ ",
                @"  ╝╚╝╚═╝╚═╝╚═╝╩   ╩ ╩╩ ╩╩╚═╝╚═╝",
                @"  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
                @"   O P T I M I Z E R  ·  E N G I N E "
            };

            Console.WriteLine();
            for (int i = 0; i < logo.Length; i++)
            {
                Console.ForegroundColor = gradient[i % gradient.Length];
                Console.WriteLine(logo[i]);
            }
            Console.ResetColor();

            Console.ForegroundColor = ConsoleColor.DarkGray;
            Console.WriteLine();
            Console.Write("  "); Console.ForegroundColor = ConsoleColor.DarkCyan;
            Console.Write("◈"); Console.ForegroundColor = ConsoleColor.Gray;
            Console.Write(" v1.0"); Console.ForegroundColor = ConsoleColor.DarkGray;
            Console.Write("  │  "); Console.ForegroundColor = ConsoleColor.DarkCyan;
            Console.Write("◈"); Console.ForegroundColor = ConsoleColor.Gray;
            Console.Write(" Zenthralix Technologies"); Console.ForegroundColor = ConsoleColor.DarkGray;
            Console.Write("  │  "); Console.ForegroundColor = ConsoleColor.DarkCyan;
            Console.Write("◈"); Console.ForegroundColor = ConsoleColor.Gray;
            Console.WriteLine(" Quantum Optimization Engine");
            Console.ResetColor();
            Console.WriteLine();
        }

        static void Pause()
        {
            Console.WriteLine();
            Console.ForegroundColor = ConsoleColor.DarkGray;
            Console.Write("  Press any key to return to menu...");
            Console.ResetColor();
            Console.ReadKey();
        }
    }
}
