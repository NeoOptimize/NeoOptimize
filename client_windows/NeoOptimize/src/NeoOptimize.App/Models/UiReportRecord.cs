namespace NeoOptimize.App.Models;

public sealed class UiReportRecord
{
    public required string FileName { get; init; }
    public required string Title { get; init; }
    public required string CreatedAt { get; init; }
    public required string SizeLabel { get; init; }
}
