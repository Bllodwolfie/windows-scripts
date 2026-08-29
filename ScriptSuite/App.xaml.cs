using System.IO;
using System.Text.Json;
using System.Windows;
using ScriptSuite.Models;
using ScriptSuite.Services;

namespace ScriptSuite;

/// <summary>
/// Interaction logic for App.xaml. Handles the hidden elevated-helper mode
/// (Milestone 4) and Stage 2 scheduled headless (mutex + SkippedBusy).
/// </summary>
public partial class App : Application
{
    private const string ElevatedRunFlag = "--elevated-run";
    private const string ConfigPathFlag = "--config-path";
    private const string ResultPathFlag = "--result-path";
    private const string LiveLogFlag = "--live-log";
    private const string IncludeOnlyFlag = "--include-only";
    private const string DumpHistoryFlag = "--dump-history";
    private const string ScheduledRunFlag = "--scheduled-run";
    private const string RegisterTaskFlag = "--register-scheduled-task";
    private static System.Threading.Mutex? _singleInstanceMutex;
    private static string MutexName => $"Global\\ScriptSuite_SingleInstance_{System.Security.Principal.WindowsIdentity.GetCurrent().User?.Value ?? "default"}";

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

        // Stage 2 elevation helper for registering HighestAvailable tasks (UAC once at schedule time, not at run time)
        string? registerId = GetArg(args, RegisterTaskFlag);
        if (registerId is not null)
        {
            int code = RunRegisterTaskHeadless(args);
            Shutdown(code);
            return;
        }

        // Scheduled headless (Stage 2). App remains closed between runs; Task Scheduler launches headlessly.
        string? scheduledScriptId = GetArg(args, ScheduledRunFlag);
        if (scheduledScriptId is not null)
        {
            RunScheduledHeadless(scheduledScriptId);
            Shutdown();
            return;
        }

        // Normal interactive startup: hold single-instance mutex for Stage 2 busy detection (header check).
        // Scheduled headless instances TryOpenExisting this mutex; if held, they log SkippedBusy and exit.
        try
        {
            bool createdNew;
            _singleInstanceMutex = new System.Threading.Mutex(true, MutexName, out createdNew);
            // keep held for lifetime; OS releases on process exit even if abandoned
        }
        catch { }

        AppPaths.EnsureConfigsSeeded();

        var catalog = new ManifestCatalog(AppPaths.ManifestsDir);
        var stateStore = new DashboardStateStore(AppPaths.DashboardStatePath);
        var scheduleStore = new ScheduleStore(AppPaths.SchedulesPath);
        var riskStore = new RiskConsentStore(AppPaths.RiskConsentsPath);
        var executor = new ScriptExecutor(catalog);
        var configService = new ScriptConfigService();
        var historyStore = new RunHistoryStore(AppPaths.HistoryDbPath);

        var window = new MainWindow(catalog, stateStore, scheduleStore, riskStore, executor, configService, historyStore);
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

    /// <summary>Headless scheduled runner (Stage 2). No window, exits after.
    /// Checks single-instance mutex; if held, logs SkippedBusy and exits.
    /// Otherwise runs the script via ScriptExecutor (already elevated via
    /// Task Scheduler if RequiresAdmin) and inserts into ScheduledRuns.</summary>
    private void RunScheduledHeadless(string scriptId)
    {
        var startedAt = DateTime.Now;
        try
        {
            // Busy detection: if interactive app holds mutex, skip entirely per spec
            bool isBusy = false;
            try
            {
                if (System.Threading.Mutex.TryOpenExisting(MutexName, out var existing))
                {
                    bool acquired = false;
                    try { acquired = existing.WaitOne(0); if (acquired) existing.ReleaseMutex(); } catch { acquired = false; }
                    existing.Dispose();
                    isBusy = !acquired;
                    if (!isBusy)
                    {
                        string lockPath = Path.Combine(AppPaths.AppDataRoot, ".scheduled-lock");
                        try { using var fs = new FileStream(lockPath, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None); } catch { isBusy = true; }
                    }
                }
            }
            catch { }

            if (isBusy)
            {
                try
                {
                    var sStore = new RunHistoryStore(AppPaths.HistoryDbPath);
                    var sched = new ScheduleStore(AppPaths.SchedulesPath);
                    string trig = sched.Get(scriptId)?.Unit + " " + sched.Get(scriptId)?.Interval + " @ " + sched.Get(scriptId)?.TimeOfDay ?? "scheduled";
                    sStore.InsertScheduled(scriptId, startedAt, startedAt, startedAt, "SkippedBusy", "Skipped — app was busy", trig);
                }
                catch { }
                return;
            }

            AppPaths.EnsureConfigsSeeded();
            var catalog = new ManifestCatalog(AppPaths.ManifestsDir);
            var manifest = catalog.Find(scriptId);
            if (manifest == null) return;
            string configPath = AppPaths.ConfigPathFor(scriptId);
            var executor = new ScriptExecutor(catalog);
            var execStarted = DateTime.Now;
            var result = executor.ExecuteInProcess(scriptId, configPath, dryRun: false);
            var execFinished = DateTime.Now;
            try
            {
                var store = new RunHistoryStore(AppPaths.HistoryDbPath);
                var schedStore = new ScheduleStore(AppPaths.SchedulesPath);
                var entry = schedStore.Get(scriptId);
                string trigger = entry != null ? $"{entry.Interval} {entry.Unit} @ {entry.TimeOfDay}" : "scheduled";
                string outcomeStr = result.Outcome switch { RunOutcome.Success => "Success", RunOutcome.Warning => "Warning", RunOutcome.Failed => "Failed", RunOutcome.Cancelled => "Cancelled", _ => "Failed" };
                string summary = RunHistoryStore.BuildSummary(result.Logs) ?? outcomeStr;
                store.InsertScheduled(scriptId, execStarted, execStarted, execFinished, outcomeStr, summary, trigger);
            }
            catch { }
        }
        catch
        {
            try { var s = new RunHistoryStore(AppPaths.HistoryDbPath); s.InsertScheduled(scriptId, startedAt, startedAt, DateTime.Now, "Failed", "Scheduled run failed", "scheduled"); } catch { }
        }
    }

    private int RunRegisterTaskHeadless(string[] args)
    {
        try
        {
            string? id = GetArg(args, RegisterTaskFlag);
            string? unit = GetArg(args, "--unit");
            string? intervalStr = GetArg(args, "--interval");
            string? time = GetArg(args, "--time");
            if (id == null || unit == null || intervalStr == null || time == null) return 1;
            if (!int.TryParse(intervalStr, out int interval)) return 1;
            var entry = new ScheduleEntry { ScriptId = id, Unit = unit, Interval = interval, TimeOfDay = time, Enabled = true, CreatedAt = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") };
            var store = new ScheduleStore(AppPaths.SchedulesPath);
            var catalog = new ManifestCatalog(AppPaths.ManifestsDir);
            var manifest = catalog.Find(id);
            bool requiresAdmin = manifest?.RequiresAdmin ?? false;
            var (ok, err, needsElev) = ScheduledTaskService.Register(entry, requiresAdmin);
            if (!ok && needsElev) return 2;
            if (ok) { store.Set(entry); return 0; }
            Console.Error.WriteLine(err);
            return 1;
        }
        catch (Exception ex) { Console.Error.WriteLine(ex.Message); return 1; }
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