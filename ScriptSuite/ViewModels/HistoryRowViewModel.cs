namespace ScriptSuite.ViewModels;

/// <summary>One row in the basic Run History list (Milestone 10). Read-only
/// after construction; Phase 4 adds search/filter on top of this same data.</summary>
public sealed class HistoryRowViewModel
{
    public string When { get; init; } = "";
    public string DisplayName { get; init; } = "";
    public string Outcome { get; init; } = "";
    public string OutcomeBrush { get; init; } = "#FFCDD6F4";
    public string? Summary { get; init; }
    public bool HasSummary => !string.IsNullOrEmpty(Summary);
}