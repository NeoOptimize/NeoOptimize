using System;
using System.IO;
using NeoOptimize.Core;
using NeoOptimize.Core.Models;

namespace NeoOptimize.Tests;

public class LogManagerTests
{
    [Fact]
    public void Append_WritesHtmlReport()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), "neooptimize-tests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(tempDir);

        try
        {
            var manager = new LogManager(tempDir);
            var result = OperationResult.Ok("Smoke action done.");

            manager.Append("System", "Smoke", result);

            Assert.True(File.Exists(manager.CurrentReportPath));
            var html = File.ReadAllText(manager.CurrentReportPath);
            Assert.Contains("Smoke action done.", html);
            Assert.Contains("System", html);
        }
        finally
        {
            if (Directory.Exists(tempDir))
            {
                Directory.Delete(tempDir, true);
            }
        }
    }
}
