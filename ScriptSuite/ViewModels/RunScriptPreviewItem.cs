using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
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
    private bool _isPreviewExpanded = true;
    private string _previewCollapsedSummary = "";

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

    // Collapsible preview: sections with > PreviewCollapseThreshold items start collapsed.
    public const int PreviewCollapseThreshold = 20;

    public bool HasPreviewItems => PreviewItems.Count > 0;

    public bool IsPreviewExpanded
    {
        get => _isPreviewExpanded;
        set
        {
            if (Set(ref _isPreviewExpanded, value))
            {
                OnPropertyChanged(nameof(ToggleButtonText));
                OnPropertyChanged(nameof(PreviewToggleLabel));
            }
        }
    }

    public string ToggleButtonText => IsPreviewExpanded ? "Collapse" : "Expand";

    public string PreviewToggleLabel => IsPreviewExpanded
        ? $"Hide preview ({PreviewItems.Count:N0})"
        : $"Show preview ({PreviewItems.Count:N0})";

    public string PreviewCollapsedSummary
    {
        get => _previewCollapsedSummary;
        private set => Set(ref _previewCollapsedSummary, value);
    }

    /// <summary>Called after dry-run items are populated (off UI thread via SetUi). Computes the
    /// collapsed summary "DisplayName — N items (x delete, y skip)" and sets the default
    /// expanded/collapsed state: collapsed if &gt; threshold, expanded otherwise.</summary>
    public void FinalizePreview()
    {
        OnPropertyChanged(nameof(HasPreviewItems));
        if (PreviewItems.Count == 0)
        {
            PreviewCollapsedSummary = "";
            IsPreviewExpanded = true;
            return;
        }
        // Breakdown by Action (group case-insensitive, lower-case label)
        var groups = PreviewItems.GroupBy(p => p.Action ?? "")
            .Select(g => (Action: g.Key, Count: g.Count()))
            .OrderByDescending(g => g.Count)
            .ToList();
        string breakdown = string.Join(", ", groups.Select(g => $"{g.Count:N0} {g.Action.ToLowerInvariant()}"));
        PreviewCollapsedSummary = $"{DisplayName} — {PreviewItems.Count:N0} items ({breakdown})";
        // Default: collapse if many items, expand if few
        IsPreviewExpanded = PreviewItems.Count <= PreviewCollapseThreshold;
        OnPropertyChanged(nameof(HasPreviewItems));
        OnPropertyChanged(nameof(PreviewCollapsedSummary));
        OnPropertyChanged(nameof(ToggleButtonText));
        OnPropertyChanged(nameof(PreviewToggleLabel));
    }

    public void TogglePreview() => IsPreviewExpanded = !IsPreviewExpanded;

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