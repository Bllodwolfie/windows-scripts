using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Windows;
using ScriptSuite.Services;
using ScriptSuite.ViewModels;

namespace ScriptSuite;

/// <summary>
/// Milestone 10: basic run history list, most recent first. Shows when each
/// run happened, which script it was, its outcome, and a short summary of what
/// it did. Deliberately read-only with no search/filter yet — Phase 4 builds
/// search/filter on top of this same GetRecent() data.
/// </summary>
public partial class HistoryWindow : Window
{
    private readonly RunHistoryStore _history;
    private readonly ManifestCatalog _catalog;
    private readonly ObservableCollection<HistoryRowViewModel> _rows = new();

    public HistoryWindow(RunHistoryStore history, ManifestCatalog catalog)
    {
        InitializeComponent();
        _history = history;
        _catalog = catalog;
        HistoryList.ItemsSource = _rows;
        Loaded += OnLoaded;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        var entries = _history.GetRecent(200);
        foreach (var entry in entries)
        {
            var manifest = _catalog.Find(entry.ScriptId);
            var (logPath, logDir, detail, hint) = BuildDetail(entry.ScriptId, entry.Summary, entry.Outcome);
            _rows.Add(new HistoryRowViewModel
            {
                ScriptId = entry.ScriptId,
                When = entry.StartedAt ?? "",
                DisplayName = manifest?.DisplayName ?? entry.ScriptId,
                Outcome = entry.Outcome,
                OutcomeBrush = entry.Outcome switch
                {
                    "Success" => "#FFA6E3A1",
                    "Warning" => "#FFF9E2AF",
                    "Failed" => "#FFF38BA8",
                    "Cancelled" => "#FF89B4FA",
                    _ => "#FFCDD6F4",
                },
                Summary = entry.Summary,
                LogFilePath = logPath,
                LogFileDirectory = logDir,
                ExpandedDetail = detail,
                LogFileHint = hint,
            });
        }
        CountText.Text = $"{entries.Count} run(s) recorded";
        EmptyMessage.Visibility = entries.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e) => Close();

    private void ToggleDetail_Click(object sender, RoutedEventArgs e)
    {
        if (sender is System.Windows.Controls.Button btn && btn.Tag is HistoryRowViewModel row)
            row.Toggle();
        else if (sender is System.Windows.Controls.Button btn2 && btn2.DataContext is HistoryRowViewModel row2)
            row2.Toggle();
    }

    private void OpenLogFile_Click(object sender, RoutedEventArgs e)
    {
        string? path = null;
        if (sender is System.Windows.Controls.Button btn && btn.Tag is HistoryRowViewModel r) path = r.LogFilePath ?? r.LogFileDirectory;
        else if (sender is System.Windows.Controls.Button btn2 && btn2.DataContext is HistoryRowViewModel r2) path = r2.LogFilePath ?? r2.LogFileDirectory;
        if (string.IsNullOrEmpty(path)) return;
        try
        {
            string target = path!;
            // If directory, open folder; if file, open with default handler (or folder if missing)
            if (Directory.Exists(target)) Process.Start(new ProcessStartInfo { FileName = target, UseShellExecute = true });
            else if (File.Exists(target)) Process.Start(new ProcessStartInfo { FileName = target, UseShellExecute = true });
            else
            {
                string dir = Path.GetDirectoryName(target) ?? target;
                if (Directory.Exists(dir)) Process.Start(new ProcessStartInfo { FileName = dir, UseShellExecute = true });
            }
        }
        catch { }
    }

    private void OpenFolder_Click(object sender, RoutedEventArgs e)
    {
        string? path = null;
        if (sender is System.Windows.Controls.Button btn && btn.Tag is HistoryRowViewModel r) path = r.LogFilePath ?? r.LogFileDirectory;
        else if (sender is System.Windows.Controls.Button btn2 && btn2.DataContext is HistoryRowViewModel r2) path = r2.LogFilePath ?? r2.LogFileDirectory;
        if (string.IsNullOrEmpty(path)) return;
        try
        {
            string dir = File.Exists(path) ? Path.GetDirectoryName(path)! : path!;
            if (Directory.Exists(dir)) Process.Start(new ProcessStartInfo { FileName = dir, UseShellExecute = true });
            else if (Directory.Exists(path)) Process.Start(new ProcessStartInfo { FileName = path, UseShellExecute = true });
        }
        catch { }
    }

    /// <summary>Resolves the real log/report file for a script id by inspecting
    /// its actual config on disk (if present) and falling back to the shipped
    /// defaults. This audits the codebase rather than assuming TempCleanup etc.
    /// have a file: TempCleanup, EmptyRecycleBin, RestorePoint have no file;
    /// DownloadsCleanup/EmptyFolderCleanup/ScreenshotsCleanup share CleanupLog.txt;
    /// SoftwareInventory writes a report txt; SystemHealthReport writes html;
    /// ClearEventLogs writes an EventLogBackups directory.</summary>
    private static (string? logPath, string? logDir, string detail, string hint) BuildDetail(string scriptId, string? summary, string outcome)
    {
        string? logPath = null;
        string? logDir = null;
        string hint = "";
        // Try config-aware resolution
        try
        {
            string configPath = AppPaths.ConfigPathFor(scriptId);
            if (File.Exists(configPath))
            {
                string raw = File.ReadAllText(configPath);
                using var doc = JsonDocument.Parse(raw);
                var root = doc.RootElement;
                if (scriptId is "DownloadsCleanup" or "EmptyFolderCleanup" or "ScreenshotsCleanup")
                {
                    string dir = root.TryGetProperty("LogDir", out var v) ? v.GetString() ?? "" : "";
                    string file = root.TryGetProperty("LogFile", out var vf) ? vf.GetString() ?? "CleanupLog.txt" : "CleanupLog.txt";
                    dir = Environment.ExpandEnvironmentVariables(dir);
                    if (string.IsNullOrEmpty(dir)) dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "Script_Logs");
                    logPath = Path.Combine(dir, file);
                }
                else if (scriptId == "SoftwareInventory")
                {
                    string outFile = root.TryGetProperty("OutputFile", out var v) ? v.GetString() ?? "" : "";
                    outFile = Environment.ExpandEnvironmentVariables(outFile);
                    if (!string.IsNullOrEmpty(outFile)) logPath = outFile;
                }
                else if (scriptId == "SystemHealthReport")
                {
                    string outDir = root.TryGetProperty("OutputDir", out var v) ? v.GetString() ?? "" : "";
                    string outFile = root.TryGetProperty("OutputFile", out var vf) ? vf.GetString() ?? "System_Health_Report.html" : "System_Health_Report.html";
                    outDir = Environment.ExpandEnvironmentVariables(outDir);
                    if (string.IsNullOrEmpty(outDir)) outDir = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
                    logPath = Path.Combine(outDir, outFile);
                }
                else if (scriptId == "ClearEventLogs")
                {
                    string bdir = root.TryGetProperty("BackupDir", out var v) ? v.GetString() ?? "" : "";
                    bdir = Environment.ExpandEnvironmentVariables(bdir);
                    if (!string.IsNullOrEmpty(bdir)) logDir = bdir;
                }
            }
        }
        catch { }

        // Fallbacks for defaults when config missing or unreadable
        if (scriptId is "DownloadsCleanup" or "EmptyFolderCleanup" or "ScreenshotsCleanup" && logPath == null)
            logPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "Script_Logs", "CleanupLog.txt");
        else if (scriptId == "SoftwareInventory" && logPath == null)
            logPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "Script_Logs", "Software_Inventory.txt");
        else if (scriptId == "SystemHealthReport" && logPath == null)
            logPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "System_Health_Report.html");
        else if (scriptId == "ClearEventLogs" && logDir == null)
            logDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "Script_Logs", "EventLogBackups");

        // Scripts with no file by design
        if (scriptId is "TempCleanup" or "EmptyRecycleBin" or "RestorePoint" or "m12_elevated_test")
        {
            logPath = null; logDir = null;
        }

        string detail;
        if (logPath != null)
        {
            string name = Path.GetFileName(logPath);
            if (File.Exists(logPath))
            {
                hint = $"Log file: {logPath}";
                try
                {
                    if (Path.GetExtension(logPath).Equals(".html", StringComparison.OrdinalIgnoreCase))
                    {
                        detail = $"HTML report at {logPath} — open the file to view it (showing first 40 lines of html source as preview):\n\n";
                        var lines = File.ReadLines(logPath).Take(40);
                        detail += string.Join("\n", lines);
                        if (File.ReadLines(logPath).Skip(40).Any()) detail += "\n… (truncated, open file for full report)";
                    }
                    else
                    {
                        var all = File.ReadAllLines(logPath);
                        int take = 80;
                        var tail = all.Length <= take ? all : all[^take..];
                        string tailText = string.Join("\n", tail);
                        detail = $"Last {tail.Length} of {all.Length} lines from {name}:\n\n{tailText}";
                        if (scriptId is "DownloadsCleanup" or "EmptyFolderCleanup" or "ScreenshotsCleanup")
                            detail = $"Shared log {name} (used by Downloads/Screenshots/EmptyFolder). Filtered tail may include interleaved entries.\n\n" + detail;
                    }
                }
                catch (Exception ex) { detail = $"Log file path: {logPath}\nFailed to read: {ex.Message}"; }
            }
            else
            {
                hint = $"Log file (not yet created): {logPath}";
                detail = $"No log file yet at\n{logPath}\n\nRun '{scriptId}' to generate it. The one-line summary above is the only history detail until the file is created.";
            }
        }
        else if (logDir != null)
        {
            hint = $"Backup folder: {logDir}";
            if (Directory.Exists(logDir))
            {
                var files = Directory.GetFiles(logDir, "*.evtx");
                detail = $"Event log backups at {logDir}: {files.Length} .evtx file(s).\n";
                if (files.Length > 0)
                {
                    var recent = files.Select(f => new FileInfo(f)).OrderByDescending(fi => fi.LastWriteTime).Take(10);
                    detail += string.Join("\n", recent.Select(fi => $"{fi.Name}  {fi.Length / 1024} KB  {fi.LastWriteTime:yyyy-MM-dd HH:mm}"));
                    if (files.Length > 10) detail += $"\n… and {files.Length - 10} more";
                }
                detail += $"\n\nSummary for this run: {summary ?? outcome}";
            }
            else
            {
                detail = $"Backup folder not yet created:\n{logDir}\n\nRun Clear Event Logs to generate backups. Summary for this run: {summary ?? outcome}";
            }
        }
        else
        {
            hint = "No persistent log file — detail is the summary + Warning/Error streams";
            detail = $"No persistent log file for this script. It writes only to the console (Write-Host / Write-Warning) and the run history stores the one-line summary.\n\nSummary for this run: {summary ?? outcome}\nOutcome: {outcome}\n\nFor Warning/Failed outcomes (e.g. \"Clear Event Logs — 101 cleared, 1 failed\"), the Warning/Error stream lines that produced this summary were captured at run time as:\n{summary ?? "(no additional lines — see summary line above)"}\n\nIf you need more detail, re-run the script and check its Output pane before closing.";
        }
        return (logPath, logDir, detail, hint);
    }
}