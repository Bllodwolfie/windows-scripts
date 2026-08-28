using System.ComponentModel;
using System.Diagnostics;
using System.Management.Automation;
using System.Text.Json;
using System.Text.RegularExpressions;

const string RepoRoot = @"C:\Users\nekdo\Documents\windows-scripts";
const string ManifestDir = RepoRoot + @"\ScriptSuite\Manifests";

// In top-level programs, `args` is the synthesized Main parameter already.
// Elevated child mode: re-launched copy of this exe, running one script's real
// execute phase elevated, writing its result as JSON for the parent to read.
if (TryGetArg(args, "--elevated-run", out string elevatedScriptId)
    && TryGetArg(args, "--config-path", out string childConfigPath)
    && TryGetArg(args, "--result-path", out string childResultPath))
{
    RunElevatedChild(elevatedScriptId, childConfigPath, childResultPath);
    return 0;
}

if (args.Length >= 2 && args[0] == "dryrun")
{
    RunDryRunInline(args[1], GetArg(args, "--config"));
    return 0;
}

if (args.Length >= 2 && args[0] == "runscript")
{
    var (o, logs, c, code) = InvokeScript(Path.GetFullPath(args[1]), null, false);
    PrintResult(o, logs, c, code);
    return 0;
}

if (args.Length >= 2 && args[0] == "run")
{
    RunParent(args[1], GetArg(args, "--config"), args.Contains("--elevated"));
    return 0;
}

Console.Error.WriteLine("Usage:");
Console.Error.WriteLine("  ElevationHarness run <ScriptId> --config <path> [--elevated]");
Console.Error.WriteLine("  ElevationHarness dryrun <ScriptId> --config <path>");
Console.Error.WriteLine("  ElevationHarness --elevated-run <ScriptId> --config-path <path> --result-path <path>");
return 2;

// ---------------------------------------------------------------- helpers

bool TryGetArg(string[] a, string name, out string value)
{
    for (int i = 0; i < a.Length - 1; i++)
    {
        if (a[i] == name) { value = a[i + 1]; return true; }
    }
    value = string.Empty;
    return false;
}

string GetArg(string[] a, string name) => TryGetArg(a, name, out var v) ? v : string.Empty;

string Quote(string s) => "\"" + s + "\"";

JsonElement LoadManifest(string scriptId)
{
    string path = Path.Combine(ManifestDir, scriptId + ".json");
    if (!File.Exists(path)) throw new InvalidOperationException($"Manifest not found: {path}");
    return JsonDocument.Parse(File.ReadAllText(path)).RootElement;
}

string ResolveScriptPath(string scriptId)
{
    JsonElement m = LoadManifest(scriptId);
    string rel = m.GetProperty("scriptPath").GetString()!;
    return Path.GetFullPath(Path.Combine(RepoRoot, rel));
}

// Runs a script via the PowerShell SDK in-process, the same hosting mechanism
// the real app will use. Capture output streams + pipeline objects into a
// plain string log, and derive an outcome (Success/Failed) from errors.
(string outcome, List<string> logs, Dictionary<string, int> counts, int exitCode) InvokeScript(
    string scriptPath, string? configPath, bool dryRun)
{
    var logs = new List<string>();
    using var ps = PowerShell.Create();
    ps.AddScript(File.ReadAllText(scriptPath));
    if (configPath is not null) ps.AddParameter("ConfigPath", configPath);
    if (dryRun) ps.AddParameter("DryRun", SwitchParameter.Present);

    bool invokeThrew = false;
    try
    {
        foreach (PSObject o in ps.Invoke())
        {
            string text;
            if (o.BaseObject is string s)
            {
                text = s;
            }
            else if (o.BaseObject is PSCustomObject)
            {
                text = string.Join("; ", o.Properties.Select(p => p.Name + "=" + p.Value));
            }
            else
            {
                text = o.BaseObject?.ToString() ?? "<null>";
            }
            logs.Add("OUTPUT: " + text);
        }
    }
    catch (Exception ex)
    {
        invokeThrew = true;
        logs.Add("SCRIPT ERROR: " + ex.Message);
    }

    foreach (var r in ps.Streams.Information)
        logs.Add("INFO: " + (r.MessageData?.ToString() ?? r.ToString()));
    foreach (var r in ps.Streams.Warning)
        logs.Add("WARN: " + r.Message);
    foreach (var r in ps.Streams.Error)
        logs.Add("ERROR: " + (r.Exception?.Message ?? r.ToString()));

    // A run is Failed only if the script itself threw or wrote to the Error
    // stream (e.g. Write-Error). ps.HadErrors is not a reliable signal here:
    // it latches onto native stderr the script intentionally captured via
    // `2>&1` (e.g. wevtutil output) even though the script handled it.
    bool hadErrors = invokeThrew || ps.Streams.Error.Count > 0;
    string outcome = hadErrors ? "Failed" : "Success";

    var counts = new Dictionary<string, int>();
    foreach (var l in logs)
    {
        var m = Regex.Match(l, @"Event log cleanup:\s*(\d+)\s+cleared,\s*(\d+)\s+failed");
        if (m.Success)
        {
            counts["Cleared"] = int.Parse(m.Groups[1].Value);
            counts["Failed"] = int.Parse(m.Groups[2].Value);
        }
    }

    return (outcome, logs, counts, 0);
}

// ------------------------------------------------- parent (main, unelevated)

void RunParent(string scriptId, string configPath, bool forceElevated)
{
    JsonElement manifest = LoadManifest(scriptId);
    bool requiresAdmin = manifest.TryGetProperty("requiresAdmin", out var ra) && ra.GetBoolean();
    string scriptPath = ResolveScriptPath(scriptId);

    if (!forceElevated && !requiresAdmin)
    {
        Console.WriteLine($"[parent] {scriptId} does not require elevation and --elevated not set; running inline.");
        var (outcome, logs, counts, code) = InvokeScript(scriptPath, configPath, dryRun: false);
        PrintResult(outcome, logs, counts, code);
        return;
    }

    string resultPath = Path.Combine(Path.GetTempPath(), "elevharness_" + Guid.NewGuid().ToString("N") + ".json");
    var psi = new ProcessStartInfo
    {
        FileName = Environment.ProcessPath!,
        UseShellExecute = true,
        Verb = "runas",
        WindowStyle = ProcessWindowStyle.Hidden,
        CreateNoWindow = true,
        Arguments = $"--elevated-run {scriptId} --config-path {Quote(configPath)} --result-path {Quote(resultPath)}"
    };

    Console.WriteLine($"[parent] launching elevated child for {scriptId}");
    Console.WriteLine($"[parent] child args: {psi.Arguments}");

Process? child;
    try
    {
        child = Process.Start(psi);
    }
    catch (Win32Exception ex)
    {
        if (ex.NativeErrorCode == 1223)
        {
            Console.WriteLine("[parent] OUTCOME: Cancelled");
            Console.WriteLine("[parent] User declined the UAC prompt (NativeErrorCode 1223). Expected, spec-defined result for a declined elevation - not a crash, not a generic Failed.");
            return;
        }
        Console.WriteLine($"[parent] FATAL: Process.Start threw Win32Exception with unexpected NativeErrorCode {ex.NativeErrorCode}: {ex.Message}");
        throw;
    }

    Process proc = child ?? throw new InvalidOperationException("Process.Start returned null.");
    bool sawWindow = false;
    for (int i = 0; i < 60; i++)
    {
        proc.Refresh();
        if (proc.MainWindowHandle != 0)
        {
            sawWindow = true;
            Console.WriteLine($"[parent] !! child shows a visible main window (handle {proc.MainWindowHandle}) at t={i * 50}ms - console flash detected");
        }
        if (proc.HasExited) break;
        Thread.Sleep(50);
    }

    proc.WaitForExit();
    Console.WriteLine($"[parent] child exited, code {proc.ExitCode}; visible window observed during run: {sawWindow}");

    if (!File.Exists(resultPath))
    {
        Console.WriteLine("[parent] FAILED: elevated child did not write the result file.");
        return;
    }

    var doc = JsonDocument.Parse(File.ReadAllText(resultPath)).RootElement;
    Console.WriteLine("[parent] result file round-trip OK:");
    Console.WriteLine("  Outcome : " + doc.GetProperty("Outcome").GetString());
    Console.WriteLine("  ScriptId: " + doc.GetProperty("ScriptId").GetString());
    if (doc.TryGetProperty("ItemCounts", out var ic) && ic.ValueKind == JsonValueKind.Object)
        foreach (var p in ic.EnumerateObject())
            Console.WriteLine($"  Count   : {p.Name} = {p.Value}");
    if (doc.TryGetProperty("Logs", out var logsEl))
        foreach (var l in logsEl.EnumerateArray())
            Console.WriteLine("  Log     : " + l.GetString());

    File.Delete(resultPath);
}

// ---------------------------------------------------- elevated child process

void RunElevatedChild(string scriptId, string configPath, string resultPath)
{
    var payload = new Dictionary<string, object?>
    {
        ["ScriptId"] = scriptId,
    };
    try
    {
        string scriptPath = ResolveScriptPath(scriptId);
        var (outcome, logs, counts, code) = InvokeScript(scriptPath, configPath, dryRun: false);
        payload["Outcome"] = outcome;
        payload["Logs"] = logs;
        payload["ItemCounts"] = counts;
        payload["ExitCode"] = code;
    }
    catch (Exception ex)
    {
        payload["Outcome"] = "Failed";
        payload["Logs"] = new[] { "ELEVATED CHILD ERROR: " + ex.Message };
        payload["ItemCounts"] = new Dictionary<string, int>();
        payload["ExitCode"] = -1;
    }
    File.WriteAllText(resultPath, JsonSerializer.Serialize(payload, new JsonSerializerOptions { WriteIndented = true }));
}

// ------------------------------------------------------------- dry-run mode

void RunDryRunInline(string scriptId, string configPath)
{
    string scriptPath = ResolveScriptPath(scriptId);
    Console.WriteLine($"[dryrun] running {scriptId} unelevated (no elevation, no UAC), preview only:");
    var (outcome, logs, counts, code) = InvokeScript(scriptPath, configPath, dryRun: true);
    PrintResult(outcome, logs, counts, code);
}

// ------------------------------------------------------------------- output

void PrintResult(string outcome, List<string> logs, Dictionary<string, int> counts, int exitCode)
{
    Console.WriteLine("OUTCOME: " + outcome + " (exit " + exitCode + ")");
    foreach (var c in counts) Console.WriteLine("COUNT  : " + c.Key + " = " + c.Value);
    foreach (var l in logs) Console.WriteLine("  " + l);
}