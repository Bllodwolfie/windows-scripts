using System.Diagnostics;
using System.IO;
using System.Text;
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
    private static string RequireSafeId(string scriptId)
    {
        if (scriptId.Length == 0)
            throw new ArgumentException("Empty ScriptId for scheduled task.", nameof(scriptId));
        foreach (char c in scriptId)
            if (!(char.IsLetterOrDigit(c) || c == '-' || c == '_'))
                throw new ArgumentException($"Unsafe ScriptId for scheduled task: {scriptId}", nameof(scriptId));
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

    public static (bool ok, string? error, bool needsElevation) Register(ScheduleEntry entry, bool requiresAdmin)
    {
        string exe = ExePath.Replace("'", "''");
        string id = RequireSafeId(entry.ScriptId);
        if (!TimeSpan.TryParse(entry.TimeOfDay, out var ts)) ts = new TimeSpan(9, 0, 0);
        DateTime next = DateTime.Today.Add(ts);
        if (next <= DateTime.Now) next = next.AddDays(1);
        string nextStr = next.ToString("yyyy-MM-ddTHH:mm:ss");
        string tsStr = ts.ToString(@"hh\:mm");
        string unit = RequireUnit(entry.Unit);
        int interval = entry.Interval;

        string ps;
        if (requiresAdmin)
        {
            ps = "$exe='" + exe + "'; $arg=" + PsQuote("--scheduled-run " + id) + "; "
               + "$act=New-ScheduledTaskAction -Execute $exe -Argument $arg; "
               + "$tr=New-ScheduledTaskTrigger -Once -At " + PsQuote(nextStr) + "; "
               + "if (" + PsQuote(unit) + " -eq 'Days') { $tr=New-ScheduledTaskTrigger -Daily -DaysInterval " + interval + " -At " + PsQuote(tsStr) + " } "
               + "elseif (" + PsQuote(unit) + " -eq 'Weeks') { $tr=New-ScheduledTaskTrigger -Weekly -WeeksInterval " + interval + " -DaysOfWeek " + PsQuote(next.DayOfWeek.ToString()) + " -At " + PsQuote(tsStr) + " } "
               + "elseif (" + PsQuote(unit) + " -eq 'Hours') { $tr=New-ScheduledTaskTrigger -Once -At " + PsQuote(nextStr) + " -RepetitionInterval (New-TimeSpan -Hours " + interval + ") -RepetitionDuration (New-TimeSpan -Days 1) } "
               + "$pr=New-ScheduledTaskPrincipal -UserId \"$env:USERDOMAIN\\$env:USERNAME\" -LogonType S4U -RunLevel Highest; "
               + "$st=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Hidden -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 2); "
               + "try { if (Get-ScheduledTask -TaskName " + PsQuote(id) + " -TaskPath " + PsQuote(Folder + "\\") + " -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName " + PsQuote(id) + " -TaskPath " + PsQuote(Folder + "\\") + " -Confirm:$false } } catch {} "
               + "Register-ScheduledTask -TaskName " + PsQuote(id) + " -TaskPath " + PsQuote(Folder + "\\") + " -Action $act -Trigger $tr -Principal $pr -Settings $st -Force | Out-Null; Write-Host \"OK\"";
        }
        else
        {
            ps = "$exe='" + exe + "'; $arg=" + PsQuote("--scheduled-run " + id) + "; "
               + "$act=New-ScheduledTaskAction -Execute $exe -Argument $arg; "
               + "$tr=New-ScheduledTaskTrigger -Once -At " + PsQuote(nextStr) + "; "
               + "if (" + PsQuote(unit) + " -eq 'Days') { $tr=New-ScheduledTaskTrigger -Daily -DaysInterval " + interval + " -At " + PsQuote(tsStr) + " } "
               + "elseif (" + PsQuote(unit) + " -eq 'Weeks') { $tr=New-ScheduledTaskTrigger -Weekly -WeeksInterval " + interval + " -DaysOfWeek " + PsQuote(next.DayOfWeek.ToString()) + " -At " + PsQuote(tsStr) + " } "
               + "elseif (" + PsQuote(unit) + " -eq 'Hours') { $tr=New-ScheduledTaskTrigger -Once -At " + PsQuote(nextStr) + " -RepetitionInterval (New-TimeSpan -Hours " + interval + ") -RepetitionDuration (New-TimeSpan -Days 1) } "
               + "$pr=New-ScheduledTaskPrincipal -UserId \"$env:USERDOMAIN\\$env:USERNAME\" -LogonType Interactive -RunLevel Limited; "
               + "$st=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Hidden -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 2); "
               + "try { if (Get-ScheduledTask -TaskName " + PsQuote(id) + " -TaskPath " + PsQuote(Folder + "\\") + " -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName " + PsQuote(id) + " -TaskPath " + PsQuote(Folder + "\\") + " -Confirm:$false } } catch {} "
               + "Register-ScheduledTask -TaskName " + PsQuote(id) + " -TaskPath " + PsQuote(Folder + "\\") + " -Action $act -Trigger $tr -Principal $pr -Settings $st -Force | Out-Null; Write-Host \"OK\"";
        }

        string b64 = Convert.ToBase64String(Encoding.Unicode.GetBytes(ps));
        var psi = new ProcessStartInfo("powershell.exe", $"-NoProfile -EncodedCommand {b64}") { CreateNoWindow = true, UseShellExecute = false };
        try
        {
            using var p = Process.Start(psi)!;
            bool exited = p.WaitForExit(20000);
            if (!exited) { try { p.Kill(); } catch { } return (false, "timeout", requiresAdmin); }
            if (p.ExitCode == 0 && TaskExists(id)) return (true, null, false);
            // Fallback: check if task was created despite non-zero exit (e.g., progress spam)
            if (TaskExists(id)) return (true, null, false);
            bool needsElev = p.ExitCode != 0 && requiresAdmin;
            return (false, $"powershell exit {p.ExitCode}", needsElev);
        }
        catch (Exception ex) { return (false, ex.Message, requiresAdmin); }
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
        try
        {
            using var p = Process.Start(psi)!;
            p.WaitForExit(20000);
            return (p.ExitCode == 0, p.ExitCode == 0 ? null : $"Elevated helper exit {p.ExitCode}");
        }
        catch (System.ComponentModel.Win32Exception ex) when (ex.NativeErrorCode == 1223)
        {
            return (false, "UAC declined (1223)");
        }
        catch (Exception ex) { return (false, ex.Message); }
    }
}
