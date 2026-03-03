using System;
using System.IO;
using System.Windows;

namespace NeoOptimize.App;

public partial class App : Application
{
	protected override void OnStartup(StartupEventArgs e)
	{
		var logDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "NeoOptimize");
		try
		{
			Directory.CreateDirectory(logDir);
		}
		catch { }

		AppDomain.CurrentDomain.UnhandledException += (s, ev) =>
		{
			try
			{
				File.WriteAllText(Path.Combine(logDir, "startup_error.log"), ev.ExceptionObject?.ToString() ?? "Unhandled exception (no details)");
			}
			catch { }
		};

		this.DispatcherUnhandledException += (s, ev) =>
		{
			try
			{
				File.WriteAllText(Path.Combine(logDir, "startup_error.log"), ev.Exception?.ToString() ?? "Dispatcher exception (no details)");
			}
			catch { }
			ev.Handled = true;
		};

		try
		{
			base.OnStartup(e);
		}
		catch (Exception ex)
		{
			try { File.WriteAllText(Path.Combine(logDir, "startup_error.log"), ex.ToString()); } catch { }
			throw;
		}
	}
}
