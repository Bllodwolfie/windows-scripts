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

    public static bool TaskExists(string scriptId)
    {
        try
        {
            var psi = new ProcessStartInfo("schtasks", $"/query /tn \"{TaskNameFor(scriptId)}\"") { CreateNoWindow = true, UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true };
            using var p = Process.Start(psi)!;
            p.WaitForExit(5000);
            return p.ExitCode == 0;
        }
        catch { return false; }
    }

    public static (bool ok, string? error, bool needsElevation) Register(ScheduleEntry entry, bool requiresAdmin)
    {
        string exe = ExePath.Replace("'", "''");
        string id = entry.ScriptId;
        if (!TimeSpan.TryParse(entry.TimeOfDay, out var ts)) ts = new TimeSpan(9, 0, 0);
        DateTime next = DateTime.Today.Add(ts);
        if (next <= DateTime.Now) next = next.AddDays(1);
        string nextStr = next.ToString("yyyy-MM-ddTHH:mm:ss");
        string tsStr = ts.ToString(@"hh\:mm");
        string unit = entry.Unit;
        int interval = entry.Interval;

        string ps;
        if (requiresAdmin)
        {
            ps = "$exe='" + exe + "'; $arg='--scheduled-run " + id + "'; "
               + "$act=New-ScheduledTaskAction -Execute $exe -Argument $arg; "
               + "$tr=New-ScheduledTaskTrigger -Once -At '" + nextStr + "'; "
               + "if ('" + unit + "' -eq 'Days') { $tr=New-ScheduledTaskTrigger -Daily -DaysInterval " + interval + " -At '" + tsStr + "' } "
               + "elseif ('" + unit + "' -eq 'Weeks') { $tr=New-ScheduledTaskTrigger -Weekly -WeeksInterval " + interval + " -DaysOfWeek " + next.DayOfWeek + " -At '" + tsStr + "' } "
               + "elseif ('" + unit + "' -eq 'Hours') { $tr=New-ScheduledTaskTrigger -Once -At '" + nextStr + "' -RepetitionInterval (New-TimeSpan -Hours " + interval + ") -RepetitionDuration (New-TimeSpan -Days 1) } "
               + "$pr=New-ScheduledTaskPrincipal -UserId \"$env:USERDOMAIN\\$env:USERNAME\" -LogonType S4U -RunLevel Highest; "
               + "$st=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Hidden -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 2); "
               + "try { if (Get-ScheduledTask -TaskName '" + id + "' -TaskPath '" + Folder + "\\' -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName '" + id + "' -TaskPath '" + Folder + "\\' -Confirm:$false } } catch {} "
               + "Register-ScheduledTask -TaskName '" + id + "' -TaskPath '" + Folder + "\\' -Action $act -Trigger $tr -Principal $pr -Settings $st -Force | Out-Null; Write-Host \"OK\"";
        }
        else
        {
            ps = "$exe='" + exe + "'; $arg='--scheduled-run " + id + "'; "
               + "$act=New-ScheduledTaskAction -Execute $exe -Argument $arg; "
               + "$tr=New-ScheduledTaskTrigger -Once -At '" + nextStr + "'; "
               + "if ('" + unit + "' -eq 'Days') { $tr=New-ScheduledTaskTrigger -Daily -DaysInterval " + interval + " -At '" + tsStr + "' } "
               + "elseif ('" + unit + "' -eq 'Weeks') { $tr=New-ScheduledTaskTrigger -Weekly -WeeksInterval " + interval + " -DaysOfWeek " + next.DayOfWeek + " -At '" + tsStr + "' } "
               + "elseif ('" + unit + "' -eq 'Hours') { $tr=New-ScheduledTaskTrigger -Once -At '" + nextStr + "' -RepetitionInterval (New-TimeSpan -Hours " + interval + ") -RepetitionDuration (New-TimeSpan -Days 1) } "
               + "$pr=New-ScheduledTaskPrincipal -UserId \"$env:USERDOMAIN\\$env:USERNAME\" -LogonType Interactive -RunLevel Limited; "
               + "$st=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Hidden -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 2); "
               + "try { if (Get-ScheduledTask -TaskName '" + id + "' -TaskPath '" + Folder + "\\' -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName '" + id + "' -TaskPath '" + Folder + "\\' -Confirm:$false } } catch {} "
               + "Register-ScheduledTask -TaskName '" + id + "' -TaskPath '" + Folder + "\\' -Action $act -Trigger $tr -Principal $pr -Settings $st -Force | Out-Null; Write-Host \"OK\"";
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
        string ps = "Unregister-ScheduledTask -TaskName '" + scriptId + "' -TaskPath '" + Folder + "\\' -Confirm:$false";
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
        var psi = new ProcessStartInfo(exe, $"--register-scheduled-task {entry.ScriptId} --unit {entry.Unit} --interval {entry.Interval} --time {entry.TimeOfDay}") { UseShellExecute = true, Verb = "runas", WindowStyle = ProcessWindowStyle.Hidden };
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
