using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Input;
using ScriptSuite.Models;
using ScriptSuite.Services;
using ScriptSuite.ViewModels;

namespace ScriptSuite;

public partial class RunAllPreviewWindow : Window
{
    private readonly ScriptExecutor _executor;
    private readonly RunHistoryStore _history;
    private readonly IReadOnlyList<ScriptManifest> _order;
    private readonly ObservableCollection<RunScriptPreviewItem> _sections = new();
    private bool _running;

    public RunAllPreviewWindow(ScriptExecutor executor, IReadOnlyList<ScriptManifest> order, RunHistoryStore history)
    {
        InitializeComponent();
        _executor = executor;
        _order = order;
        _history = history;
        SectionList.ItemsSource = _sections;
        Loaded += OnLoaded;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        foreach (var manifest in _order)
            _sections.Add(new RunScriptPreviewItem(manifest));

        // Populate the combined preview: each script's dry-run, run in-process
        // (never elevated). Runs off the UI thread so the window stays live.
        RunPreviewAsync();
    }

    private async void RunPreviewAsync()
    {
        await Task.Run(() =>
        {
            foreach (var section in _sections)
            {
                var manifest = section.Manifest;
                string configPath = AppPaths.ConfigPathFor(manifest.Id);

                if (!manifest.SupportsDryRun)
                {
                    SetUi(section, s => s.PreviewMessage =
                        "No preview — this script only generates a report and changes nothing.");
                    continue;
                }

                try
                {
                    var (items, result) = _executor.GetDryRunItems(manifest.Id, configPath);
                    foreach (var item in items)
                        SetUi(section, s => s.PreviewItems.Add(item));
                    foreach (var line in result.Logs)
                        SetUi(section, s => s.AddLog(line));

                    if (items.Count == 0 && result.Outcome == RunOutcome.Failed)
                    {
                        var error = result.Logs.FirstOrDefault(l => l.StartsWith("ERROR") || l.StartsWith("SCRIPT ERROR"));
                        SetUi(section, s => s.PreviewMessage = "Preview failed: " + (error ?? "unknown error"));
                    }
                    else if (items.Count == 0)
                    {
                        SetUi(section, s => s.PreviewMessage = "Nothing to do right now.");
                    }
                }
                catch (Exception ex)
                {
                    SetUi(section, s => s.PreviewMessage = "Preview failed: " + ex.Message);
                }
            }
        });
    }

    private async void ConfirmButton_Click(object sender, RoutedEventArgs e)
    {
        _running = true;
        ConfirmButton.IsEnabled = false;
        await Task.Run(() =>
        {
            int total = _sections.Count;
            int index = 0;
            int success = 0, warned = 0, failed = 0, cancelled = 0;

            foreach (var section in _sections)
            {
                index++;
                var manifest = section.Manifest;
                string configPath = AppPaths.ConfigPathFor(manifest.Id);

                SetUi(section, s => s.Status = RunPhaseStatus.Running);
                SetUi(ProgressText, t => { t.Text = $"Running {manifest.DisplayName} ({index} of {total})…"; t.Visibility = Visibility.Visible; });

                ScriptRunResult result;
                var startedAt = DateTime.Now;
                try
                {
                    result = manifest.RequiresAdmin
                        ? _executor.RunElevated(manifest.Id, configPath)
                        : _executor.ExecuteInProcess(manifest.Id, configPath, dryRun: false);
                }
                catch (Exception ex)
                {
                    result = new ScriptRunResult
                    {
                        Outcome = RunOutcome.Failed,
                        ScriptId = manifest.Id,
                        Logs = new List<string> { "Run error: " + ex.Message },
                    };
                }
                var finishedAt = DateTime.Now;

                // Milestone 10: every executed run - including Run All's per-
                // script legs - is recorded in run history, so the history list
                // is complete no matter how a run was launched.
                _history.Insert(manifest.Id, startedAt, finishedAt, result.Outcome, RunHistoryStore.BuildSummary(result.Logs));

                foreach (var line in result.Logs)
                    SetUi(section, s => s.AddLog(line));

                switch (result.Outcome)
                {
                    case RunOutcome.Success: success++; break;
                    case RunOutcome.Warning: warned++; break;
                    case RunOutcome.Cancelled: cancelled++; break;
                    default: failed++; break;
                }
                SetUi(section, s => s.Status = result.Outcome switch
                {
                    RunOutcome.Success => RunPhaseStatus.Success,
                    RunOutcome.Warning => RunPhaseStatus.Warning,
                    RunOutcome.Cancelled => RunPhaseStatus.Cancelled,
                    _ => RunPhaseStatus.Failed,
                });
            }

            SetUi(ProgressText, t =>
            {
                var parts = new List<string>();
                if (success > 0) parts.Add($"{success} succeeded");
                if (warned > 0) parts.Add($"{warned} with warnings");
                if (failed > 0) parts.Add($"{failed} failed");
                if (cancelled > 0) parts.Add($"{cancelled} cancelled");
                t.Text = parts.Count == 0 ? "Run All finished — nothing ran." : "Run All finished — " + string.Join(", ", parts) + ".";
                t.Visibility = Visibility.Visible;
            });
        });
    }

    private void SetUi(RunScriptPreviewItem section, Action<RunScriptPreviewItem> action) =>
        Dispatcher.BeginInvoke(() => action(section));

    private void SetUi(System.Windows.Controls.TextBlock text, Action<System.Windows.Controls.TextBlock> action) =>
        Dispatcher.BeginInvoke(() => action(text));

    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (e.Key == Key.Escape && !_running)
        {
            Close();
            e.Handled = true;
            return;
        }
        base.OnKeyDown(e);
    }
}