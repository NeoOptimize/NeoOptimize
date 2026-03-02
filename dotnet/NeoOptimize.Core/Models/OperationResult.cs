using System.Collections.Generic;

namespace NeoOptimize.Core.Models;

public sealed record OperationResult(
    bool Success,
    string Message,
    IReadOnlyDictionary<string, string>? Metrics = null)
{
    public static OperationResult Ok(string message, IReadOnlyDictionary<string, string>? metrics = null)
        => new(true, message, metrics);

    public static OperationResult Fail(string message)
        => new(false, message);
}
