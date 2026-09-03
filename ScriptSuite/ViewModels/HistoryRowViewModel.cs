namespace ScriptSuite.ViewModels;

/// <summary>One row in the basic Run History list (Milestone 10). Read-only
/// after construction; Phase 4 adds search/filter on top of this same data.
/// Extended for collapsible per-row detail: log-file routing where a real
/// file exists, otherwise Warning/Error stream fallback.</summary>
public sealed class HistoryRowViewModel : ViewModelBase
{
    private bool _isExpanded;

    public string ScriptId { get; init; } = "";
    public string When { get; init; } = "";
    public string DisplayName { get; init; } = "";
    public string Outcome { get; init; } = "";
    // Phase 1: OutcomeBrush is now resolved in XAML via OutcomeToBrushConverter against Brush.Status.* tokens.
    // Kept for compat (no longer set with hex literals).
    public string OutcomeBrush { get; init; } = "";
    public string? Summary { get; init; }
    public bool HasSummary => !string.IsNullOrEmpty(Summary);

    // Log-file routing: null if script has no persistent file by design.
    public string? LogFilePath { get; init; }
    public string? LogFileDirectory { get; init; }
    public bool HasLogFile => !string.IsNullOrEmpty(LogFilePath) || !string.IsNullOrEmpty(LogFileDirectory);
    public string? ExpandedDetail { get; init; }
    public string? LogFileHint { get; init; }

    public bool IsExpanded
    {
        get => _isExpanded;
        set
        {
            if (Set(ref _isExpanded, value))
            {
                OnPropertyChanged(nameof(ExpandButtonText));
            }
        }
    }

    public string ExpandButtonText => IsExpanded ? "Hide detail" : "Show detail";
    public void Toggle() => IsExpanded = !IsExpanded;
}