using System;
using System.Collections.Generic;

namespace NeoOptimize.Core.Models;

public sealed record LogEntry(
    DateTimeOffset Timestamp,
    string Module,
    string Action,
    string Result,
    string Message,
    IReadOnlyDictionary<string, string>? Metrics = null);
