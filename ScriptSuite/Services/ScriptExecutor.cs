using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Text.Json;
using System.Text.RegularExpressions;
using ScriptSuite.Models;

namespace ScriptSuite.Services;

/// <summary>
/// Runs the .ps1 scripts. Non-admin work runs in-process via the PowerShell
/// SDK (no console window). Admin-required execute steps are delegated to a
/// re-launched copy of this exe using Verb="runas" (Milestone 4): the child
/// runs the one script's execute phase headless and writes a JSON result the
/// parent reads back. A declined UAC (Win32Exception 1223) is Cancelled.
///
/// Milestone 8: single-script manual runs can pass -IncludeOnly (the Target
/// values the user kept checked in the preview) so the real run touches only
/// the confirmed items, and can stream output live via onLogLine — for
/// in-process runs through the PowerShell SDK's BeginInvoke + DataAdded
/// events, and for elevated runs by having the child append each line to a
/// live log file the parent tails.
/// </summary>
public sealed class ScriptExecutor
{
    private const int LivePollMs = 150;
    private readonly ManifestCatalog _catalog;

    public ScriptExecutor(ManifestCatalog catalog) => _catalog = catalog;

    // ------------------------------------------------------------ dry-run items

    /// <summary>Runs a script's dry-run in-process (never elevated — Milestone
    /// 4) and returns the structured items the scripts emit, plus the run's
    /// log/error output.</summary>
    public (List<DryRunItem> Items, ScriptRunResult Result) GetDryRunItems(string scriptId, string configPath)
    {
        return InvokeInProcess(scriptId, configPath, dryRun: true, includeOnly: null, onLogLine: null);
    }

    // ------------------------------------------------------------- in-process

    /// <summary>Runs a script in-process (dry-run or real). For admin scripts
    /// the caller must use RunElevated for the real execute phase.
    /// includeOnly narrows the run to the listed Target values (Milestone 8
    /// deselection); onLogLine receives each output line as it is produced.</summary>
    public ScriptRunResult ExecuteInProcess(string scriptId, string configPath, bool dryRun,
        IReadOnlyList<string>? includeOnly = null, Action<string>? onLogLine = null)
    {
        return InvokeInProcess(scriptId, configPath, dryRun, includeOnly, onLogLine).Result;
    }

    private (List<DryRunItem> Items, ScriptRunResult Result) InvokeInProcess(
        string scriptId, string configPath, bool dryRun,
        IReadOnlyList<string>? includeOnly, Action<string>? onLogLine)
    {
        var manifest = _catalog.Find(scriptId)
            ?? throw new InvalidOperationException($"Manifest not found: {scriptId}");
        string scriptPath = manifest.AbsoluteScriptPath;
        if (!File.Exists(scriptPath))
            throw new InvalidOperationException($"Script file not found: {scriptPath}");

        var logs = new List<string>();
        var items = new List<DryRunItem>();
        void AddLog(string line)
        {
            logs.Add(line);
            onLogLine?.Invoke(line);
        }

        // The app process's default execution policy is Restricted, which would
        // block invoking script FILES (AddCommand). We control every shipped
        // script, so run each in a runspace that permits it. Invoking the file
        // (not its text) is deliberate: it makes PowerShell set $PSScriptRoot,
        // which scripts need to locate sibling resources (SystemHealthReport's
        // mascot images live two levels up from the script).
        var iss = InitialSessionState.CreateDefault2();
        iss.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
        using var ps = PowerShell.Create(iss);
        ps.AddCommand(scriptPath);
        if (!string.IsNullOrEmpty(configPath))
            ps.AddParameter("ConfigPath", configPath);
        if (dryRun)
            ps.AddParameter("DryRun", SwitchParameter.Present);
        if (includeOnly is { Count: > 0 })
            ps.AddParameter("IncludeOnly", includeOnly.ToArray());

        // Stream output instead of buffering until Invoke returns, so a real
        // run can show lines in the UI as they happen (Milestone 8).
        var output = new PSDataCollection<PSObject>();
        output.DataAdded += (_, e) =>
        {
            PSObject o;
            try { o = output[e.Index]; } catch { return; }
            if (o.BaseObject is PSCustomObject)
            {
                var item = new DryRunItem();
                foreach (var p in o.Properties)
                {
                    if (p.Name == "Action") item.Action = p.Value?.ToString() ?? "";
                    else if (p.Name == "Target") item.Target = p.Value?.ToString() ?? "";
                    else if (p.Name == "Detail") item.Detail = p.Value?.ToString() ?? "";
                }
                if (!string.IsNullOrEmpty(item.Action) || !string.IsNullOrEmpty(item.Target))
                    items.Add(item);
                AddLog("OUTPUT: " + string.Join("; ", o.Properties.Select(p => p.Name + "=" + p.Value)));
            }
            else if (o.BaseObject is string s)
            {
                AddLog("OUTPUT: " + s);
            }
            else
            {
                AddLog("OUTPUT: " + o.BaseObject?.ToString() ?? "<null>");
            }
        };
        ps.Streams.Information.DataAdded += (_, e) =>
        {
            InformationRecord r;
            try { r = ps.Streams.Information[e.Index]; } catch { return; }
            AddLog("INFO: " + (r.MessageData?.ToString() ?? r.ToString()));
        };
        ps.Streams.Warning.DataAdded += (_, e) =>
        {
            WarningRecord r;
            try { r = ps.Streams.Warning[e.Index]; } catch { return; }
            AddLog("WARN: " + r.Message);
        };
        ps.Streams.Error.DataAdded += (_, e) =>
        {
            ErrorRecord r;
            try { r = ps.Streams.Error[e.Index]; } catch { return; }
            AddLog("ERROR: " + (r.Exception?.Message ?? r.ToString()));
        };

        bool threw = false;
        try
        {
            var async = ps.BeginInvoke<PSObject, PSObject>(null, output);
            while (!async.IsCompleted)
                async.AsyncWaitHandle.WaitOne(LivePollMs);
            ps.EndInvoke(async);
        }
        catch (Exception ex)
        {
            threw = true;
            AddLog("SCRIPT ERROR: " + ex.Message);
        }
        finally
        {
            output.Dispose();
        }

        // Outcome precedence, matching the spec's Success/Failed/Warning/
        // Cancelled model:
        //   Failed    - the script threw or wrote to the Error stream. Note
        //               ps.HadErrors is unreliable: it latches onto native
        //               stderr the script intentionally captured via 2>&1
        //               (e.g. wevtutil output), so we never use it.
        //   Warning   - the run completed but left something behind (a locked
        //               file/folder skipped, or any other per-item failure the
        //               script surfaced via Write-Warning). Never show plain
        //               Success for a run that didn't finish everything.
        //   Success   - completed with no errors and no warnings.
        RunOutcome outcome;
        if (threw || ps.Streams.Error.Count > 0)
            outcome = RunOutcome.Failed;
        else if (ps.Streams.Warning.Count > 0)
            outcome = RunOutcome.Warning;
        else
            outcome = RunOutcome.Success;

        var result = new ScriptRunResult
        {
            Outcome = outcome,
            ScriptId = scriptId,
            Logs = logs,
        };
        ParseClearEventLogsCounts(logs, result.ItemCounts);
        return (items, result);
    }

    private static void ParseClearEventLogsCounts(List<string> logs, Dictionary<string, int> counts)
    {
        foreach (var l in logs)
        {
            var m = Regex.Match(l, @"Event log cleanup:\s*(\d+)\s+cleared,\s*(\d+)\s+failed");
            if (m.Success)
            {
                counts["Cleared"] = int.Parse(m.Groups[1].Value);
                counts["Failed"] = int.Parse(m.Groups[2].Value);
                return;
            }
        }
    }

    // -------------------------------------------------------------- elevated

    /// <summary>Launches a hidden elevated copy of this exe to run one script's
    /// real execute phase, waits for it, and reads back the JSON result.
    /// A declined UAC prompt (1223) returns Cancelled. When onLogLine is given,
    /// the child appends each output line to a sidecar live log file that this
    /// method tails until the child exits, so elevated runs stream too.
    /// includeOnly is the confirmed Target list passed to the child (Milestone
    /// 8 deselection).</summary>
    public ScriptRunResult RunElevated(string scriptId, string configPath,
        IReadOnlyList<string>? includeOnly = null, Action<string>? onLogLine = null)
    {
        var manifest = _catalog.Find(scriptId)
            ?? throw new InvalidOperationException($"Manifest not found: {scriptId}");
        if (!manifest.RequiresAdmin)
            throw new InvalidOperationException($"RunElevated called for {scriptId}, which does not require admin.");

        string resultPath = Path.Combine(Path.GetTempPath(), "scriptsuite_" + Guid.NewGuid().ToString("N") + ".json");
        string liveLog = resultPath + ".live.log";
        string includePath = resultPath + ".include.json";
        File.WriteAllText(includePath, JsonSerializer.Serialize(includeOnly is { Count: > 0 }
            ? includeOnly.ToList()
            : new List<string>()));

        var psi = new ProcessStartInfo
        {
            FileName = Environment.ProcessPath!,
            UseShellExecute = true,
            Verb = "runas",
            WindowStyle = ProcessWindowStyle.Hidden,
            CreateNoWindow = true,
            Arguments = $"--elevated-run {scriptId} --config-path {Quote(configPath)} --result-path {Quote(resultPath)} --live-log {Quote(liveLog)} --include-only {Quote(includePath)}",
        };

        Process child;
        try
        {
            child = Process.Start(psi)
                ?? throw new InvalidOperationException("Process.Start returned null.");
        }
        catch (Win32Exception ex)
        {
            TryDelete(includePath);
            if (ex.NativeErrorCode == 1223)
            {
                return new ScriptRunResult
                {
                    Outcome = RunOutcome.Cancelled,
                    ScriptId = scriptId,
                    Logs = new List<string> { "Cancelled: the UAC prompt was declined (error 1223)." },
                };
            }
            throw;
        }

        if (onLogLine != null)
        {
            string carry = "";
            int emitted = 0;
            while (!child.HasExited)
            {
                (emitted, carry) = PumpLiveLog(liveLog, emitted, carry, onLogLine);
                Thread.Sleep(LivePollMs);
            }
            (emitted, carry) = PumpLiveLog(liveLog, emitted, carry, onLogLine);
        }

        child.WaitForExit();
        TryDelete(liveLog);
        TryDelete(includePath);

        if (!File.Exists(resultPath))
        {
            return new ScriptRunResult
            {
                Outcome = RunOutcome.Failed,
                ScriptId = scriptId,
                Logs = new List<string> { "The elevated helper did not write a result file." },
            };
        }

        try
        {
            return ReadResultFile(resultPath, scriptId);
        }
        finally
        {
            File.Delete(resultPath);
        }
    }

    /// <summary>Runs one script's execute phase and writes the result JSON.
    /// This is the elevated child's entire job; the process then exits.
    /// Output lines are appended to liveLogPath as they are produced (so the
    /// parent can stream them) and includeOnlyPath supplies the confirmed
    /// Target list from the preview.</summary>
    public int RunElevatedChild(string scriptId, string configPath, string resultPath, string? liveLogPath, string? includeOnlyPath)
    {
        var payload = new Dictionary<string, object?>
        {
            ["ScriptId"] = scriptId,
            ["Outcome"] = "Failed",
            ["Logs"] = new List<string>(),
            ["ItemCounts"] = new Dictionary<string, int>(),
            ["ExitCode"] = 1,
        };
        try
        {
            IReadOnlyList<string>? includeOnly = null;
            if (includeOnlyPath is not null && File.Exists(includeOnlyPath))
            {
                try
                {
                    includeOnly = JsonSerializer.Deserialize<List<string>>(File.ReadAllText(includeOnlyPath));
                }
                catch (JsonException) { /* treat as unrestricted */ }
            }

            Action<string>? onLine = null;
            if (liveLogPath is not null)
                onLine = line =>
                {
                    try { File.AppendAllText(liveLogPath, line + Environment.NewLine); }
                    catch { /* file deleted by parent mid-run; best effort */ }
                };

            var result = ExecuteInProcess(scriptId, configPath, dryRun: false, includeOnly, onLine);
            payload["Outcome"] = OutcomeToString(result.Outcome);
            payload["Logs"] = result.Logs;
            payload["ItemCounts"] = result.ItemCounts;
            payload["ExitCode"] = 0;
        }
        catch (Exception ex)
        {
            payload["Outcome"] = "Failed";
            payload["Logs"] = new List<string> { "ELEVATED CHILD ERROR: " + ex.Message };
            payload["ExitCode"] = -1;
        }

        Directory.CreateDirectory(Path.GetDirectoryName(resultPath)!);
        File.WriteAllText(resultPath, JsonSerializer.Serialize(payload, new JsonSerializerOptions { WriteIndented = true }));
        return 0;
    }

    /// <summary>Appends the child's newly written live-log lines to onLine.
    /// Reads the whole file each poll and diff-s by completed line count so
    /// byte/char boundaries can't drift on non-ASCII paths; the final fragment
    /// (no trailing newline yet) is carried to the next poll.</summary>
    private static (int emitted, string carry) PumpLiveLog(string path, int emitted, string carry, Action<string> onLine)
    {
        if (!File.Exists(path)) return (emitted, carry);
        try
        {
            string all;
            using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            using (var sr = new StreamReader(fs))
            {
                all = sr.ReadToEnd();
            }
            string[] lines = all.Split('\n');
            int complete = lines.Length > 0 ? lines.Length - 1 : 0;
            for (int i = emitted; i < complete; i++)
            {
                string line = lines[i].TrimEnd('\r');
                if (line.Length > 0) onLine(line);
            }
            if (complete >= emitted) emitted = complete;
            return (emitted, lines.Length > 0 ? lines[^1] : carry);
        }
        catch
        {
            return (emitted, carry);
        }
    }

    private static void TryDelete(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); } catch { }
    }

    private static ScriptRunResult ReadResultFile(string path, string scriptId)
    {
        var doc = JsonDocument.Parse(File.ReadAllText(path)).RootElement;
        var result = new ScriptRunResult
        {
            ScriptId = doc.TryGetProperty("ScriptId", out var idEl) ? idEl.GetString() ?? scriptId : scriptId,
            Outcome = doc.TryGetProperty("Outcome", out var oEl) ? OutcomeFromString(oEl.GetString()) : RunOutcome.Failed,
            Logs = new List<string>(),
            ItemCounts = new Dictionary<string, int>(),
        };
        if (doc.TryGetProperty("Logs", out var logsEl) && logsEl.ValueKind == JsonValueKind.Array)
            foreach (var l in logsEl.EnumerateArray())
                result.Logs.Add(l.GetString() ?? "");
        if (doc.TryGetProperty("ItemCounts", out var icEl) && icEl.ValueKind == JsonValueKind.Object)
            foreach (var p in icEl.EnumerateObject())
                if (p.Value.ValueKind == JsonValueKind.Number && p.Value.TryGetInt32(out var n))
                    result.ItemCounts[p.Name] = n;
        return result;
    }

    private static string OutcomeToString(RunOutcome o) => o switch
    {
        RunOutcome.Success => "Success",
        RunOutcome.Warning => "Warning",
        RunOutcome.Failed => "Failed",
        RunOutcome.Cancelled => "Cancelled",
        _ => "Failed",
    };

    private static RunOutcome OutcomeFromString(string? s) => s switch
    {
        "Success" => RunOutcome.Success,
        "Warning" => RunOutcome.Warning,
        "Cancelled" => RunOutcome.Cancelled,
        _ => RunOutcome.Failed,
    };

    private static string Quote(string s) => "\"" + s + "\"";
}