using System;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using NeoOptimize.Core;
using Xunit;

namespace NeoOptimize.Tests;

public class LogManagerUnitTests
{
    [Fact]
    public async Task AppendAsync_CreatesLogFile_And_GetAllLogsReturnsIt()
    {
        // Arrange
        var msg = "UnitTest entry " + Guid.NewGuid();

        // Act
        await LogManager.AppendAsync(msg);

        var logs = LogManager.GetAllLogs().ToList();

        // Assert
        Assert.NotEmpty(logs);
        var any = false;
        foreach (var l in logs)
        {
            var content = File.ReadAllText(l.Path);
            if (content.Contains(msg)) { any = true; break; }
        }
        Assert.True(any, "Appended message should be present in at least one log file");
    }
}
