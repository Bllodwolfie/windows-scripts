using System.Collections.ObjectModel;
using ScriptSuite.Models;

namespace ScriptSuite.ViewModels;

public enum RunPhaseStatus
{
    Pending,
    Running,
    Success,
    Warning,
    Failed,
    Cancelled,
}

/// <summary>One script's section in the combined Run All preview window:
/// its dry-run results before confirm, then its outcome and logs after.</summary>
public sealed class RunScriptPreviewItem : ViewModelBase
{
    private RunPhaseStatus _status;
    private bool _isBusy;
    private string? _previewMessage;

    public RunScriptPreviewItem(ScriptManifest manifest)
    {
        Manifest = manifest;
    }

    public ScriptManifest Manifest { get; }
    public string DisplayName => Manifest.DisplayName;
    public bool RequiresAdmin => Manifest.RequiresAdmin;
    public bool SupportsDryRun => Manifest.SupportsDryRun;
    public bool ShowAdminShield => Manifest.RequiresAdmin;

    public ObservableCollection<DryRunItem> PreviewItems { get; } = new();
    public ObservableCollection<string> Logs { get; } = new();

    public bool HasLogs => Logs.Count > 0;

    public void AddLog(string line)
    {
        Logs.Add(line);
        OnPropertyChanged(nameof(HasLogs));
    }

    /// <summary>When set, shown instead of the item list: explains that a
    /// script is read-only, or that its preview failed.</summary>
    public string? PreviewMessage
    {
        get => _previewMessage;
        set => Set(ref _previewMessage, value);
    }

    public RunPhaseStatus Status
    {
        get => _status;
        set
        {
            if (Set(ref _status, value))
                OnPropertyChanged(nameof(StatusText));
        }
    }

    public bool IsBusy
    {
        get => _isBusy;
        set => Set(ref _isBusy, value);
    }

    public string StatusText => Status switch
    {
        RunPhaseStatus.Running => "Running…",
        RunPhaseStatus.Success => "Success",
        RunPhaseStatus.Warning => "Warning",
        RunPhaseStatus.Failed => "Failed",
        RunPhaseStatus.Cancelled => "Cancelled",
        _ => "Pending",
    };
}