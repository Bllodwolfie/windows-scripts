using ScriptSuite.Models;

namespace ScriptSuite.ViewModels;

public sealed class ScheduledTaskRowViewModel : ViewModelBase
{
    public string ScriptId { get; init; } = "";
    public string DisplayName { get; init; } = "";
    public string Category { get; init; } = "";
    public string Description { get; init; } = "";
    public bool HasSchedule { get; init; }
    public string ScheduleSummary { get; init; } = "";
    public string LastRanAt { get; init; } = "";
    public string LastOutcome { get; init; } = "";
    public ScriptManifest Manifest { get; init; } = null!;
}
