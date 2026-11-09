using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Text;
using System.Xml.Linq;
using ScriptSuite.Models;

namespace ScriptSuite.Services;

/// <summary>Creates/modifies/deletes per-script Task Scheduler tasks (Stage 2).
/// Two configurations: normal (Interactive Limited) and elevated (S4U HighestAvailable).
/// Tasks live under \ScriptSuite\<scriptId> and run ScriptSuite.exe --scheduled-run <id>.</summary>
public sealed class ScheduledTaskService
{
    private const string Folder = "\\ScriptSuite";
    private static string TaskNameFor(string scriptId) => $"{Folder}\\{scriptId}";
    private static string ExePath => Environment.ProcessPath ?? Path.Combine(AppContext.BaseDirectory, "ScriptSuite.exe");

    // Security (A-H2): PowerShell single-quote escaping + strict allowlists so
    // manifest/CLI-controlled ids and schedule fields cannot break out of the
    // generated -EncodedCommand scripts (was: raw string concatenation).
    private static string PsQuote(string s) => "'" + s.Replace("'", "''") + "'";
    public static string RequireSafeId(string? scriptId)
    {
        if (string.IsNullOrEmpty(scriptId))
            throw new ArgumentException("Empty ScriptId for scheduled task.", nameof(scriptId));
        foreach (char c in scriptId)
            if (!(char.IsLetterOrDigit(c) || c == '-' || c == '_'))
                throw new ArgumentException($"Unsafe ScriptId: {scriptId}", nameof(scriptId));
        return scriptId;
    }
    private static string RequireUnit(string unit) => unit switch
    {
        "Days" or "Weeks" or "Hours" => unit,
        _ => throw new ArgumentException($"Unsafe schedule Unit: {unit}", nameof(unit)),
    };

    public static bool TaskExists(string scriptId)
    {
        try
        {
            // Security (A-H2): discrete argv tokens (was: "/query /tn \"...\"" string concat).
            var psi = new ProcessStartInfo("schtasks") { CreateNoWindow = true, UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true };
            psi.ArgumentList.Add("/query");
            psi.ArgumentList.Add("/tn");
            psi.ArgumentList.Add(TaskNameFor(scriptId));
            using var p = Process.Start(psi)!;
            p.WaitForExit(5000);
            return p.ExitCode == 0;
        }
        catch { return false; }
    }

    internal static Func<ProcessStartInfo, int>? ElevatedLauncher { get; set; }
    internal static Func<ProcessStartInfo, (int ExitCode, string StdOut, string StdErr)>? ProcessRunner { get; set; }

    public record TaskScheduleInfo(bool Exists, string? StartBoundary, string? StartDate, string[]? Weekdays, int WeeksInterval, string? Unit);

    public static TaskScheduleInfo GetTaskScheduleInfo(string scriptId)
    {
        string id = RequireSafeId(scriptId);
        try
        {
            var psi = new ProcessStartInfo("schtasks")
            {
                CreateNoWindow = true,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            };
            psi.ArgumentList.Add("/query");
            psi.ArgumentList.Add("/tn");
            psi.ArgumentList.Add(TaskNameFor(id));
            psi.ArgumentList.Add("/xml");

            using var p = Process.Start(psi)!;
            string xml = p.StandardOutput.ReadToEnd();
            p.WaitForExit(5000);
            if (p.ExitCode != 0 || string.IsNullOrWhiteSpace(xml))
                return new TaskScheduleInfo(false, null, null, null, 1, null);

            var doc = XDocument.Parse(xml);
            var ns = doc.Root?.Name.Namespace ?? XNamespace.None;
            var cal = doc.Descendants(ns + "CalendarTrigger").FirstOrDefault();
            if (cal == null)
                return new TaskScheduleInfo(true, null, null, null, 1, null);

            string? sb = cal.Element(ns + "StartBoundary")?.Value;
            string? startDate = null;
            if (!string.IsNullOrEmpty(sb) && sb.Length >= 10)
            {
                startDate = sb.Substring(0, 10);
            }

            var byWeek = cal.Element(ns + "ScheduleByWeek");
            if (byWeek != null)
            {
                int interval = int.TryParse(byWeek.Element(ns + "WeeksInterval")?.Value, out var wi) ? wi : 1;
                var daysEl = byWeek.Element(ns + "DaysOfWeek");
                var days = daysEl?.Elements().Select(e => e.Name.LocalName).ToArray();
                return new TaskScheduleInfo(true, sb, startDate, days, interval, "Weeks");
            }

            var byDay = cal.Element(ns + "ScheduleByDay");
            if (byDay != null)
            {
                int interval = int.TryParse(byDay.Element(ns + "DaysInterval")?.Value, out var di) ? di : 1;
                return new TaskScheduleInfo(true, sb, startDate, null, interval, "Days");
            }

            var rep = cal.Element(ns + "Repetition");
            if (rep != null)
            {
                return new TaskScheduleInfo(true, sb, startDate, null, 1, "Hours");
            }

            return new TaskScheduleInfo(true, sb, startDate, null, 1, null);
        }
        catch
        {
            return new TaskScheduleInfo(false, null, null, null, 1, null);
        }
    }

    public static (bool ok, string? error, bool needsElevation) Register(ScheduleEntry entry, bool requiresAdmin)
    {
        string exe = ExePath.Replace("'", "''");
        string id = RequireSafeId(entry.ScriptId);

        // Compute deterministic schedule parameters and local no-Z boundary
        var (_, boundaryStr, _) = ScheduleCalculation.ComputeSchedule(entry);

        string unit = RequireUnit(entry.Unit);
        int interval = entry.Interval <= 0 ? 1 : entry.Interval;
        if (interval > 24 && unit == "Hours") interval = 24;

        if (!TimeSpan.TryParseExact(entry.TimeOfDay, @"h\:mm", CultureInfo.InvariantCulture, out var ts) &&
            !TimeSpan.TryParse(entry.TimeOfDay, out ts))
        {
            ts = new TimeSpan(9, 0, 0);
        }
        string tsStr = ts.ToString(@"hh\:mm");

        var sb = new StringBuilder();
        sb.Append("$ErrorActionPreference = 'Stop'; ");
        sb.Append("$exe='" + exe + "'; $arg=" + PsQuote("--scheduled-run " + id) + "; ");
        sb.Append("$act=New-ScheduledTaskAction -Execute $exe -Argument $arg; ");

        if (unit == "Days")
        {
            sb.Append("$tr=New-ScheduledTaskTrigger -Daily -DaysInterval " + interval + " -At " + PsQuote(tsStr) + "; ");
        }
        else if (unit == "Weeks")
        {
            var days = ScheduleCalculation.ParseWeekdays(entry.Weekdays, DateTime.Today.DayOfWeek);
            string daysArray = "@(" + string.Join(",", days.Select(d => PsQuote(d.ToString()))) + ")";
            sb.Append("$tr=New-ScheduledTaskTrigger -Weekly -WeeksInterval " + interval + " -DaysOfWeek " + daysArray + " -At " + PsQuote(tsStr) + "; ");
        }
        else if (unit == "Hours")
        {
            sb.Append("$tr=New-ScheduledTaskTrigger -Once -At " + PsQuote(boundaryStr) + " -RepetitionInterval (New-TimeSpan -Hours " + interval + "); ");
        }

        sb.Append("$tr.StartBoundary = " + PsQuote(boundaryStr) + "; ");

        if (requiresAdmin)
        {
            sb.Append("$pr=New-ScheduledTaskPrincipal -UserId \"$env:USERDOMAIN\\$env:USERNAME\" -LogonType S4U -RunLevel Highest; ");
        }
        else
        {
            sb.Append("$pr=New-ScheduledTaskPrincipal -UserId \"$env:USERDOMAIN\\$env:USERNAME\" -LogonType Interactive -RunLevel Limited; ");
        }

        sb.Append("$st=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Hidden -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 2); ");
        sb.Append("Register-ScheduledTask -TaskName " + PsQuote(id) + " -TaskPath " + PsQuote(Folder + "\\") + " -Action $act -Trigger $tr -Principal $pr -Settings $st -Force | Out-Null; Write-Host \"OK\"");

        string b64 = Convert.ToBase64String(Encoding.Unicode.GetBytes(sb.ToString()));
        var psi = new ProcessStartInfo("powershell.exe", $"-NoProfile -EncodedCommand {b64}")
        {
            CreateNoWindow = true,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };

        try
        {
            int exitCode;
            string stdout = string.Empty;
            string stderr = string.Empty;

            if (ProcessRunner != null)
            {
                (exitCode, stdout, stderr) = ProcessRunner(psi);
            }
            else
            {
                using var p = Process.Start(psi)!;
                var stdoutTask = p.StandardOutput.ReadToEndAsync();
                var stderrTask = p.StandardError.ReadToEndAsync();
                bool exited = p.WaitForExit(20000);
                if (!exited)
                {
                    try { p.Kill(); } catch { }
                    return (false, "Registration timed out after 20 seconds.", false);
                }
                stdout = stdoutTask.GetAwaiter().GetResult();
                stderr = stderrTask.GetAwaiter().GetResult();
                exitCode = p.ExitCode;
            }

            if (exitCode != 0)
            {
                // Strict access-denied detection on real signals (HRESULT 0x80070005, PermissionDenied, Access is denied)
                bool isAccessDenied = stderr.Contains("0x80070005") ||
                                      stderr.Contains("PermissionDenied", StringComparison.OrdinalIgnoreCase) ||
                                      stderr.Contains("Access is denied", StringComparison.OrdinalIgnoreCase);
                bool needsElev = isAccessDenied;
                string err = !string.IsNullOrWhiteSpace(stderr) ? stderr.Trim() : $"powershell exit {exitCode}";
                return (false, err, needsElev);
            }

            // Strict verification: task must exist and read back with the exact requested trigger parameters
            var (vOk, vErr) = VerifyTaskSchedule(entry, boundaryStr);
            if (!vOk)
            {
                return (false, vErr, false);
            }

            return (true, null, false);
        }
        catch (Exception ex)
        {
            return (false, ex.Message, false);
        }
    }

    internal static (bool ok, string? error) VerifyTaskSchedule(ScheduleEntry entry, string expectedBoundary)
    {
        string id = RequireSafeId(entry.ScriptId);
        var taskInfo = GetTaskScheduleInfo(id);
        if (!taskInfo.Exists)
        {
            return (false, "Verification failed: Task does not exist after registration.");
        }
        if (!string.Equals(taskInfo.StartBoundary, expectedBoundary, StringComparison.OrdinalIgnoreCase))
        {
            return (false, $"Verification failed: Task StartBoundary '{taskInfo.StartBoundary}' does not match requested '{expectedBoundary}'.");
        }
        string unit = RequireUnit(entry.Unit);
        int interval = entry.Interval <= 0 ? 1 : entry.Interval;
        if (unit == "Weeks")
        {
            var expectedDays = ScheduleCalculation.ParseWeekdays(entry.Weekdays, DateTime.Today.DayOfWeek).Select(d => d.ToString()).OrderBy(x => x).ToList();
            var actualDays = (taskInfo.Weekdays ?? []).OrderBy(x => x).ToList();
            if (!expectedDays.SequenceEqual(actualDays, StringComparer.OrdinalIgnoreCase))
            {
                return (false, $"Verification failed: DaysOfWeek mismatch (expected {string.Join(",", expectedDays)}, actual {string.Join(",", actualDays)}).");
            }
            if (taskInfo.WeeksInterval != interval)
            {
                return (false, $"Verification failed: WeeksInterval mismatch (expected {interval}, actual {taskInfo.WeeksInterval}).");
            }
        }
        return (true, null);
    }

    public static (bool ok, string? error) Unregister(string scriptId)
    {
        string id = RequireSafeId(scriptId);
        string ps = "Unregister-ScheduledTask -TaskName " + PsQuote(id) + " -TaskPath " + PsQuote(Folder + "\\") + " -Confirm:$false";
        string b64 = Convert.ToBase64String(Encoding.Unicode.GetBytes(ps));
        var psi = new ProcessStartInfo("powershell.exe", $"-NoProfile -EncodedCommand {b64}") { CreateNoWindow = true, UseShellExecute = false };
        try
        {
            using var p = Process.Start(psi)!;
            p.WaitForExit(8000);
            return (true, null);
        }
        catch (Exception ex) { return (false, ex.Message); }
    }

    public static (bool ok, string? error) RegisterElevated(ScheduleEntry entry)
    {
        string exe = ExePath;
        var psi = new ProcessStartInfo(exe) { UseShellExecute = true, Verb = "runas", WindowStyle = ProcessWindowStyle.Hidden };
        psi.ArgumentList.Add("--register-scheduled-task");
        psi.ArgumentList.Add(entry.ScriptId);
        psi.ArgumentList.Add("--unit");
        psi.ArgumentList.Add(entry.Unit);
        psi.ArgumentList.Add("--interval");
        psi.ArgumentList.Add(entry.Interval.ToString());
        psi.ArgumentList.Add("--time");
        psi.ArgumentList.Add(entry.TimeOfDay);

        if (entry.Weekdays != null && entry.Weekdays.Length > 0)
        {
            psi.ArgumentList.Add("--weekdays");
            psi.ArgumentList.Add(string.Join(",", entry.Weekdays));
        }

        if (!string.IsNullOrWhiteSpace(entry.StartDate))
        {
            psi.ArgumentList.Add("--start-date");
            psi.ArgumentList.Add(entry.StartDate);
        }

        try
        {
            int exitCode;
            if (ElevatedLauncher != null)
            {
                exitCode = ElevatedLauncher(psi);
            }
            else
            {
                using var p = Process.Start(psi)!;
                bool exited = p.WaitForExit(120000);
                if (!exited)
                {
                    try { p.Kill(); } catch { }
                    return (false, "Elevated helper timed out after 120 seconds.");
                }
                exitCode = p.ExitCode;
            }

            if (exitCode == 1223)
            {
                return (false, "UAC prompt was cancelled. The schedule was not modified.");
            }

            if (exitCode != 0)
            {
                return (false, $"Elevated helper exit {exitCode}");
            }

            var (_, boundaryStr, _) = ScheduleCalculation.ComputeSchedule(entry);
            var (vOk, vErr) = VerifyTaskSchedule(entry, boundaryStr);
            if (!vOk)
            {
                return (false, vErr);
            }

            return (true, null);
        }
        catch (System.ComponentModel.Win32Exception ex) when (ex.NativeErrorCode == 1223)
        {
            return (false, "UAC prompt was cancelled. The schedule was not modified.");
        }
        catch (Exception ex) { return (false, ex.Message); }
    }
}
