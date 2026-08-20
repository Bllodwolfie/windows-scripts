using System.Text.Json;
using System.Windows;
using ScriptSuite.Models;
using ScriptSuite.Services;

namespace ScriptSuite;

/// <summary>
/// Interaction logic for App.xaml. Handles the hidden elevated-helper mode
/// (Milestone 4): when launched with --elevated-run the app runs exactly one
/// script's execute phase headlessly, writes the JSON result, and exits without
/// ever creating a window.
/// </summary>
public partial class App : Application
{
    private const string ElevatedRunFlag = "--elevated-run";
    private const string ConfigPathFlag = "--config-path";
    private const string ResultPathFlag = "--result-path";
    private const string LiveLogFlag = "--live-log";
    private const string IncludeOnlyFlag = "--include-only";
    private const string DumpHistoryFlag = "--dump-history";

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        var args = e.Args;
        string? elevatedScriptId = GetArg(args, ElevatedRunFlag);
        string? configPath = GetArg(args, ConfigPathFlag);
        string? resultPath = GetArg(args, ResultPathFlag);
        string? liveLogPath = GetArg(args, LiveLogFlag);
        string? includeOnlyPath = GetArg(args, IncludeOnlyFlag);

        if (Array.IndexOf(args, DumpHistoryFlag) >= 0)
        {
            DumpHistoryHeadless();
            Shutdown();
            return;
        }

        if (elevatedScriptId is not null && resultPath is not null)
        {
            RunElevatedChildHeadless(elevatedScriptId, configPath ?? "", resultPath, liveLogPath, includeOnlyPath);
            Shutdown();
            return;
        }

        // Normal interactive startup: seed configs, show the dashboard.
        AppPaths.EnsureConfigsSeeded();

        var catalog = new ManifestCatalog(AppPaths.ManifestsDir);
        var stateStore = new DashboardStateStore(AppPaths.DashboardStatePath);
        var executor = new ScriptExecutor(catalog);
        var configService = new ScriptConfigService();
        var historyStore = new RunHistoryStore(AppPaths.HistoryDbPath);

        var window = new MainWindow(catalog, stateStore, executor, configService, historyStore);
        MainWindow = window;
        window.Show();

        // First-run wizard: config presence can't signal first run (configs are
        // seeded above regardless), so the wizard's completion marker drives it.
        // Note: wizard steps write live config values immediately (shared
        // SettingsForm auto-save); the marker only records that the wizard was
        // finished or skipped. See FirstRunWizardWindow's class doc.
        if (!WizardStateStore.IsCompleted())
        {
            var wizard = new FirstRunWizardWindow(catalog.All, configService) { Owner = window };
            wizard.ShowDialog();
        }

        // Milestone 9: a leftover journal means a previous run was killed
        // mid-execution. Offer to resume it with a preview of just the items
        // still left to process; discarding deletes the journal.
        OfferResumeIfJournalPresent(window, catalog, executor, historyStore);
    }

    /// <summary>If a crash-recovery journal exists, ask the user whether to
    /// resume the interrupted run or discard it. Resume opens the run window in
    /// resume mode; Discard (or closing the dialog) removes the journal.</summary>
    private static void OfferResumeIfJournalPresent(MainWindow owner, ManifestCatalog catalog,
        ScriptExecutor executor, RunHistoryStore historyStore)
    {
        var journal = RunJournal.Load();
        if (journal is null || string.IsNullOrEmpty(journal.ScriptId))
            return;

        var manifest = catalog.Find(journal.ScriptId);
        var prompt = new ResumePromptWindow(manifest?.DisplayName ?? journal.ScriptId,
            journal.StartedAt.ToString("yyyy-MM-dd HH:mm:ss")) { Owner = owner };
        if (prompt.ShowDialog() == true && prompt.ResumeRequested && manifest is not null)
        {
            var resumeWindow = new ScriptRunWindow(manifest, executor, historyStore, journal) { Owner = owner };
            resumeWindow.ShowDialog();
        }
        else
        {
            // The run was attempted but never completed, and the user chose not
            // to resume it. Record it in history so it does not vanish as if
            // nothing happened: a Cancelled row (same semantic as a declined
            // UAC - the run did not complete and nothing was rolled back or
            // lost) carrying the ORIGINAL attempt's StartedAt. FinishedAt is
            // when the discard closed the attempt out.
            historyStore.Insert(journal.ScriptId, journal.StartedAt, DateTime.Now,
                RunOutcome.Cancelled,
                $"Cancelled: interrupted run discarded, not resumed (started {journal.StartedAt:yyyy-MM-dd HH:mm:ss}).");
            RunJournal.Delete();
        }
    }

    /// <summary>Elevated child mode. No window is created; the result is
    /// written to --result-path and the process exits.</summary>
    private void RunElevatedChildHeadless(string scriptId, string configPath, string resultPath, string? liveLogPath, string? includeOnlyPath)
    {
        var catalog = new ManifestCatalog(AppPaths.ManifestsDir);
        var executor = new ScriptExecutor(catalog);
        executor.RunElevatedChild(scriptId, configPath, resultPath, liveLogPath, includeOnlyPath);
    }

    /// <summary>Headless diagnostic used by the verification harness: prints the
    /// run history table as JSON to stdout and exits. The app is a WinExe, so
    /// output only appears when the caller captures stdout (pwsh pipes it).</summary>
    private void DumpHistoryHeadless()
    {
        var store = new RunHistoryStore(AppPaths.HistoryDbPath);
        Console.WriteLine(JsonSerializer.Serialize(store.GetRecent(500)));
    }

    private static string? GetArg(string[] args, string flag)
    {
        for (int i = 0; i < args.Length - 1; i++)
        {
            if (string.Equals(args[i], flag, StringComparison.OrdinalIgnoreCase))
                return args[i + 1];
        }
        return null;
    }
}