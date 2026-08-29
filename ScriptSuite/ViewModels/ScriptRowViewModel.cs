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