# Clears Windows event logs. Before clearing a log it is first exported to
# Documents\Script_Logs\EventLogBackups\<LogName>_<timestamp>.evtx; if that
# backup fails, the log is left untouched and reported as failed (never clear
# a log you couldn't back up). Enumerates logs with Get-WinEvent -ListLog,
# clears every enabled, non-empty log via wevtutil, and prints a summary of
# cleared vs failed. Errors are surfaced, not blanket-suppressed, so real
# problems (permissions, corrupt logs) are visible.

param(
    [switch]$DryRun,
    [string]$ConfigPath = "$env:LOCALAPPDATA\ScriptSuite\Configs\ClearEventLogs.json",
    [string[]]$IncludeOnly = @()
)

# Fallback defaults, used only when the config file is missing (see TempCleanup).
$Config = @{
    BackupDir = "$env:USERPROFILE\Documents\Script_Logs\EventLogBackups"
}

if (Test-Path -LiteralPath $ConfigPath) {
    $Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
}

# JSON stores env-var paths as "%USERPROFILE%\..."; expand them at load time.
function Expand-ConfigPath([string]$Path) {
    [Environment]::ExpandEnvironmentVariables($Path)
}

$backupDir = Expand-ConfigPath $Config.BackupDir
$null = New-Item -ItemType Directory -Path $backupDir -Force -ErrorAction SilentlyContinue

# Enumerate logs (restricted/denied logs are skipped silently; the ones we
# actually clear will surface their own errors below)
$logs = @(Get-WinEvent -ListLog * -ErrorAction SilentlyContinue)

$targets = $logs | Where-Object {
    $_.IsEnabled -and
    $_.RecordCount -gt 0
}

# Milestone 8: when the app confirms a preview with logs deselected it passes
# -IncludeOnly (the log names the user kept checked); only those are cleared.
if ($IncludeOnly.Count -gt 0) {
    $targets = $targets | Where-Object { $IncludeOnly -contains $_.LogName }
}

if ($DryRun) {
    # Preview: which logs would be backed up and cleared. No clearing happens.
    $targets | ForEach-Object {
        [PSCustomObject]@{
            Action = 'Clear'
            Target = $_.LogName
            Detail = '{0} event(s); would be backed up to .evtx, then cleared' -f $_.RecordCount
        }
    }
    exit
}

$cleared = 0
$failed  = @()

foreach ($log in $targets) {
    # 1) Back up the log first; if the export fails, leave it untouched.
    # Log names can contain '/' (e.g. Provider/Operational), which is a path
    # separator on Windows - sanitize them out of the backup filename.
    $safeName = $log.LogName -replace '[\\/:*?"<>|]', '_'
    $backupPath = Join-Path $backupDir "$($safeName)_$(Get-Date -Format 'yyyyMMdd_HHmmss').evtx"
    $exportErr = (& wevtutil epl $log.LogName $backupPath 2>&1) -join ' '
    if ($LASTEXITCODE -ne 0) {
        $failed += [PSCustomObject]@{
            LogName = $log.LogName
            Reason  = if ($exportErr.Trim()) { "backup failed: $($exportErr.Trim())" } else { "backup failed: wevtutil exit code $LASTEXITCODE" }
        }
        continue
    }

    # 2) Clear it, now that a restorable backup exists.
    $errOut = (& wevtutil cl $log.LogName 2>&1) -join ' '
    if ($LASTEXITCODE -eq 0) {
        $cleared++
    } else {
        $failed += [PSCustomObject]@{
            LogName = $log.LogName
            Reason  = if ($errOut.Trim()) { $errOut.Trim() } else { "wevtutil exit code $LASTEXITCODE" }
        }
    }
}

Write-Host "Event log cleanup: $cleared cleared, $($failed.Count) failed."

if ($failed.Count -gt 0) {
    Write-Warning "Failed to clear the following logs:"
    $failed | ForEach-Object { Write-Warning "  $($_.LogName) - $($_.Reason)" }
}