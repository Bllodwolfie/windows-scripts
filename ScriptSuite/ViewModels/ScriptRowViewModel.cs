using ScriptSuite.Models;
using ScriptSuite.Services;

namespace ScriptSuite.ViewModels;

/// <summary>One script row on the dashboard. Encapsulates the manifest for
/// display plus the two dashboard-only flags (Run All inclusion, visibility).
/// Hiding is purely visual and never touches the script's config.</summary>
public sealed class ScriptRowViewModel : ViewModelBase
{
    private readonly DashboardStateStore _stateStore;
    private bool _runAll;
    private bool _hidden;

    private readonly ScheduleStore _scheduleStore;

    public ScriptRowViewModel(ScriptManifest manifest, DashboardStateStore stateStore, ScheduleStore scheduleStore)
    {
        Manifest = manifest;
        _stateStore = stateStore;
        _scheduleStore = scheduleStore;
        _runAll = stateStore.IsRunAllEnabled(manifest.Id);
        _hidden = stateStore.IsHidden(manifest.Id);
    }

    public bool HasSchedule => _scheduleStore.Has(Id);
    public string ScheduleSummary => _scheduleStore.Get(Id) is { } e ? $"{e.Interval} {e.Unit} @ {e.TimeOfDay}" : "";

    public ScriptManifest Manifest { get; }

    public string Id => Manifest.Id;
    public string DisplayName => Manifest.DisplayName;
    public string Description => Manifest.Description;
    public string Category => Manifest.Category;
    public bool RequiresAdmin => Manifest.RequiresAdmin;
    public bool SupportsDryRun => Manifest.SupportsDryRun;
    public bool IsCustom => Manifest.IsCustom;
    public string ScriptPath => Manifest.ScriptPath;

    /// <summary>Shield icon visible only for admin-required scripts.</summary>
    public bool ShowAdminShield => Manifest.RequiresAdmin;

    public bool ShowCustomBadge => Manifest.IsCustom;

    private string _lastRunAgo = "";
    private string _lastRunOutcome = "";

    /// <summary>Dashboard last-run status (read-only display over RunHistory).
    /// Set by MainWindowViewModel.Refresh from GetLatestByScript; empty when
    /// the script has never run.</summary>
    public bool HasLastRun => !string.IsNullOrEmpty(_lastRunOutcome);

    public string LastRunAgo => _lastRunAgo;

    public string LastRunOutcome => _lastRunOutcome;

    public void SetLastRun(RunHistoryEntry? entry)
    {
        string ago = "";
        string outcome = "";
        if (entry is not null)
        {
            outcome = entry.Outcome ?? "";
            ago = FormatAgo(entry.StartedAt);
        }
        bool changed = false;
        if (_lastRunAgo != ago) { _lastRunAgo = ago; OnPropertyChanged(nameof(LastRunAgo)); changed = true; }
        if (_lastRunOutcome != outcome) { _lastRunOutcome = outcome; OnPropertyChanged(nameof(LastRunOutcome)); changed = true; }
        if (changed) OnPropertyChanged(nameof(HasLastRun));
    }

    /// <summary>Relative time for a "yyyy-MM-dd HH:mm:ss" history timestamp.
    /// Unparseable or future timestamps fall back to the raw date part.</summary>
    internal static string FormatAgo(string? startedAt)
    {
        if (string.IsNullOrWhiteSpace(startedAt))
            return "";
        if (!DateTime.TryParseExact(startedAt.Trim(), "yyyy-MM-dd HH:mm:ss",
                System.Globalization.CultureInfo.InvariantCulture,
                System.Globalization.DateTimeStyles.None, out var when))
            return startedAt.Length >= 10 ? startedAt[..10] : startedAt;
        var span = DateTime.Now - when;
        if (span.TotalSeconds < 0) return when.ToString("yyyy-MM-dd");
        if (span.TotalMinutes < 1) return "just now";
        if (span.TotalMinutes < 60) return $"{(int)span.TotalMinutes} minute{((int)span.TotalMinutes == 1 ? "" : "s")} ago";
        if (span.TotalHours < 24) return $"{(int)span.TotalHours} hour{((int)span.TotalHours == 1 ? "" : "s")} ago";
        if (span.TotalDays < 1.5) return "yesterday";
        if (span.TotalDays < 30) return $"{(int)span.TotalDays} days ago";
        return when.ToString("yyyy-MM-dd");
    }

    /// <summary>Checked = included in Run All. Separate from visibility.</summary>
    public bool RunAllIncluded
    {
        get => _runAll;
        set
        {
            if (Set(ref _runAll, value))
                _stateStore.SetRunAll(Id, value);
        }
    }

    /// <summary>Hidden rows are removed from the dashboard view entirely but
    /// keep their config and, if still checked, their Run All slot.</summary>
    public bool IsHidden
    {
        get => _hidden;
        set
        {
            if (Set(ref _hidden, value))
                _stateStore.SetHidden(Id, value);
        }
    }
}