using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using ScriptSuite.Models;
using ScriptSuite.Services;
using ScriptSuite.ViewModels;

namespace ScriptSuite;

/// <summary>
/// Single-script manual run (Milestone 8): preview the dry-run items, let the
/// user uncheck individual items, then Confirm runs the real action passing
/// only the still-checked targets via -IncludeOnly, streaming the script's
/// output live into the log panel as it runs (not after it finishes). Every
/// executed run writes a run history entry (Success/Failed/Warning/Cancelled).
/// Read-only report scripts (SoftwareInventory, SystemHealthReport) skip the
/// preview entirely and go straight to execute, per the Milestone 3 table.
///
/// Milestone 9: before a real item-based run starts, the confirmed target list
/// is written to the crash-recovery journal; the journal is deleted when the
/// run completes. If the app was killed mid-run, this window can be opened in
/// resume mode (a journal is passed in): the preview re-runs the dry-run and
/// shows only the items that are still outstanding, so resuming never redoes
/// items the interrupted run already processed.
/// </summary>
public partial class ScriptRunWindow : Window
{
    private readonly ScriptManifest _manifest;
    private readonly ScriptExecutor _executor;
    private readonly RunHistoryStore _history;
    private readonly RunJournal? _resumeJournal;
    private readonly ObservableCollection<RunSelectionItem> _selections = new();
    private readonly ObservableCollection<string> _logs = new();
    private bool _running;

    public ScriptRunWindow(ScriptManifest manifest, ScriptExecutor executor, RunHistoryStore history,
        RunJournal? resumeJournal = null)
    {
        InitializeComponent();
        _manifest = manifest;
        _executor = executor;
        _history = history;
        _resumeJournal = resumeJournal;

        Title = resumeJournal is null ? "Run — " + manifest.DisplayName : "Resume — " + manifest.DisplayName;
        NameText.Text = manifest.DisplayName;
        DescriptionText.Text = manifest.Description;
        if (resumeJournal is not null)
        {
            ResumeBanner.Visibility = Visibility.Visible;
            ConfirmButton.Content = "Resume";
        }
        if (manifest.RequiresAdmin)
        {
            AdminIcon.Visibility = Visibility.Visible;
            AdminNote.Visibility = Visibility.Visible;
        }

        SelectionList.ItemsSource = _selections;
        LogList.ItemsSource = _logs;
        _logs.CollectionChanged += (_, _) => ScrollLogToEnd();

        Loaded += OnLoaded;
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        if (_resumeJournal is not null)
            await LoadResumePreviewAsync();
        else if (_manifest.SupportsDryRun)
            await LoadPreviewAsync();
        else
            await RunAsync(includeOnly: null);
    }

    // ---------------------------------------------------------------- preview

    private async Task LoadPreviewAsync()
    {
        string configPath = AppPaths.ConfigPathFor(_manifest.Id);
        List<DryRunItem> items;
        try
        {
            (items, var result) = await Task.Run(() => _executor.GetDryRunItems(_manifest.Id, configPath));
            if (result.Outcome == RunOutcome.Failed && items.Count == 0)
            {
                var error = result.Logs.FirstOrDefault(l => l.StartsWith("ERROR") || l.StartsWith("SCRIPT ERROR"));
                PreviewMessage.Text = "Preview failed: " + (error ?? "unknown error");
                ConfirmButton.IsEnabled = false;
                return;
            }
        }
        catch (Exception ex)
        {
            PreviewMessage.Text = "Preview failed: " + ex.Message;
            ConfirmButton.IsEnabled = false;
            return;
        }

        foreach (var item in items)
            _selections.Add(new RunSelectionItem(item));

        if (_selections.Count == 0)
        {
            PreviewMessage.Text = "Nothing to do right now.";
            ConfirmButton.IsEnabled = false;
        }
        UpdateSelectionCount();
    }

    private void SelectionItem_Toggled(object sender, RoutedEventArgs e)
    {
        if (_selections.Count > 0)
            UpdateSelectionCount();
    }

    /// <summary>Resume preview (Milestone 9): re-run the dry-run and show only
    /// the items that are still outstanding for the interrupted run — the
    /// targets the interrupted run confirmed, minus the ones it already
    /// processed (those no longer appear in a fresh dry-run).</summary>
    private async Task LoadResumePreviewAsync()
    {
        string configPath = AppPaths.ConfigPathFor(_manifest.Id);
        List<DryRunItem> items;
        try
        {
            (items, var result) = await Task.Run(() => _executor.GetDryRunItems(_manifest.Id, configPath));
            if (result.Outcome == RunOutcome.Failed && items.Count == 0)
            {
                var error = result.Logs.FirstOrDefault(l => l.StartsWith("ERROR") || l.StartsWith("SCRIPT ERROR"));
                PreviewMessage.Text = "Preview failed: " + (error ?? "unknown error");
                ConfirmButton.IsEnabled = false;
                return;
            }
        }
        catch (Exception ex)
        {
            PreviewMessage.Text = "Preview failed: " + ex.Message;
            ConfirmButton.IsEnabled = false;
            return;
        }

        foreach (var item in items.Where(i => _resumeJournal!.IncludeOnly.Contains(i.Target)))
            _selections.Add(new RunSelectionItem(item));

        if (_selections.Count == 0)
        {
            PreviewMessage.Text = "Nothing left to resume — the interrupted run already completed these items.";
            ConfirmButton.IsEnabled = false;
            RunJournal.Delete();
            return;
        }

        PreviewMessage.Text = $"{_selections.Count} item(s) still need processing from the interrupted run.";
        UpdateSelectionCount();
    }

    private void UpdateSelectionCount()
    {
        int selected = _selections.Count(s => s.IsChecked);
        SelectionCountText.Text = $"{selected} of {_selections.Count} item(s) selected";
        ConfirmButton.IsEnabled = selected > 0 && !_running;
    }

    // ---------------------------------------------------------------- execute

    private async void ConfirmButton_Click(object sender, RoutedEventArgs e)
    {
        var includeOnly = _selections.Where(s => s.IsChecked).Select(s => s.Target).ToList();
        await RunAsync(includeOnly);
    }

    private async Task RunAsync(IReadOnlyList<string>? includeOnly)
    {
        _running = true;
        ConfirmButton.IsEnabled = false;
        CloseButton.IsEnabled = false;
        PreviewPanel.Visibility = Visibility.Collapsed;
        StatusText.Visibility = Visibility.Visible;
        SetStatus("Running…", "#FFCDD6F4");

        string configPath = AppPaths.ConfigPathFor(_manifest.Id);
        // On resume the run continues the ORIGINAL attempt, so its history row
        // keeps the original StartedAt from the journal rather than the resume
        // time; a fresh manual run takes the current time.
        DateTime startedAt = _resumeJournal?.StartedAt ?? DateTime.Now;
        ScriptRunResult result;
        // How many log lines have reached the panel so far. Streaming (Append)
        // and this flush both run on the UI thread, so the count is reliable.
        int streamed = 0;
        void Append(string line) => Dispatcher.BeginInvoke(() => { _logs.Add(line); streamed++; });

        // Crash-recovery journal (Milestone 9): written before real execution
        // begins so a mid-run kill leaves enough state to resume. Only item runs
        // are journaled (reports have nothing to resume). On resume the journal
        // is rewritten with the new remaining target list, so a second crash
        // resumes from the then-current point.
        bool journalWritten = false;
        if (_manifest.SupportsDryRun && includeOnly is { Count: > 0 })
        {
            new RunJournal
            {
                ScriptId = _manifest.Id,
                ConfigPath = configPath,
                IncludeOnly = includeOnly.ToList(),
                StartedAt = startedAt,
            }.Write();
            journalWritten = true;
        }

        try
        {
            result = await Task.Run(() =>
                _manifest.RequiresAdmin
                    ? _executor.RunElevated(_manifest.Id, configPath, includeOnly, Append)
                    : _executor.ExecuteInProcess(_manifest.Id, configPath, dryRun: false, includeOnly, Append));
        }
        catch (Exception ex)
        {
            result = new ScriptRunResult
            {
                Outcome = RunOutcome.Failed,
                ScriptId = _manifest.Id,
                Logs = new List<string> { "Run error: " + ex.Message },
            };
        }
        DateTime finishedAt = DateTime.Now;

        // Streaming can't cover every outcome: a declined UAC makes Process.Start
        // throw before any line is streamed, and an elevated child's final line
        // can lack a trailing newline (PumpLiveLog carries it past exit). Flush
        // whatever the panel hasn't received so the outcome is always visible.
        Dispatcher.Invoke(() =>
        {
            foreach (var line in result.Logs.Skip(streamed))
                _logs.Add(line);
        });

        SetStatus(result.Outcome switch
        {
            RunOutcome.Success => "Success",
            RunOutcome.Warning => "Completed with warnings",
            RunOutcome.Failed => "Failed",
            RunOutcome.Cancelled => "Cancelled",
            _ => "Done",
        }, result.Outcome switch
        {
            RunOutcome.Success => "#FFA6E3A1",
            RunOutcome.Warning => "#FFF9E2AF",
            RunOutcome.Failed => "#FFF38BA8",
            RunOutcome.Cancelled => "#FF89B4FA",
            _ => "#FFCDD6F4",
        });

        _history.Insert(_manifest.Id, startedAt, finishedAt, result.Outcome, RunHistoryStore.BuildSummary(result.Logs));

        // The run completed (any outcome), so there is nothing to resume — the
        // journal is only left behind by a hard kill mid-run.
        if (journalWritten || _resumeJournal is not null)
            RunJournal.Delete();

        ConfirmButton.IsEnabled = false;
        CloseButton.IsEnabled = true;
        CloseButton.Focus();
        _running = false;
    }

    private void SetStatus(string text, string colorHex)
    {
        StatusText.Text = text;
        StatusText.Foreground = (Brush)new BrushConverter().ConvertFromString(colorHex)!;
    }

    private void ScrollLogToEnd()
    {
        if (LogList.Items.Count > 0)
            LogList.ScrollIntoView(LogList.Items[LogList.Items.Count - 1]);
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e) => Close();

    protected override void OnKeyDown(KeyEventArgs e)
    {
        // Escape closes the run window, but never mid-run (the Close button is
        // disabled while _running for the same reason).
        if (e.Key == Key.Escape && !_running)
        {
            Close();
            e.Handled = true;
            return;
        }
        base.OnKeyDown(e);
    }
}