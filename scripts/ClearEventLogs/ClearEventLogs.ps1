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
    CutoffDays = 0
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

# CutoffDays (int, default 0): only clear logs whose NEWEST event is older than
# this many days (stale/inactive logs). 0 clears every enabled, non-empty log —
# today's behavior; missing key is treated as 0. Windows cannot delete individual
# log entries by age (wevtutil only clears whole logs), so per-log newest-event
# age is the truthful age semantic. A log whose newest event can't be read is
# kept when filtering is on (fail safe); with 0 it follows the legacy path and
# surfaces its own backup/clear errors below.
$cutoffDays = 0
$rawCut = $null
if ($Config -is [hashtable] -and $Config.ContainsKey("CutoffDays")) { $rawCut = $Config["CutoffDays"] }
elseif ($null -ne $Config.PSObject.Properties["CutoffDays"]) { $rawCut = $Config.CutoffDays }
if ($null -ne $rawCut) {
    try { $cutoffDays = [int]$rawCut } catch { Write-Warning "CutoffDays value '$rawCut' is invalid — using default 0"; $cutoffDays = 0 }
}
if ($cutoffDays -lt 0) {
    Write-Warning "CutoffDays is negative ($cutoffDays) — treating as 0 (clear all enabled logs with events)."
    $cutoffDays = 0
}
$cutoff = (Get-Date).AddDays(-$cutoffDays)

function Get-NewestEvent([string]$LogName) {
    try {
        $ev = Get-WinEvent -LogName $LogName -MaxEvents 1 -ErrorAction Stop
        if ($null -ne $ev) { return $ev.TimeCreated }
    } catch {}
    return $null
}

# Enumerate logs (restricted/denied logs are skipped silently; the ones we
# actually clear will surface their own errors below)
$logs = @(Get-WinEvent -ListLog * -ErrorAction SilentlyContinue)

$logTargets = $logs | Where-Object {
    $_.IsEnabled -and
    $_.RecordCount -gt 0
}

# Age filter, applied ONCE here so DryRun preview and real execution share the
# exact same target set by construction. $targets stays a plain list of log
# objects (downstream code unchanged); $newestByName carries each target's
# newest-event time for Detail lines, $ageSkipped carries the kept-aside logs.
$newestByName = @{}
$ageSkipped = @()
$targets = @()
foreach ($log in $logTargets) {
    if ($cutoffDays -le 0) {
        $targets += $log
        continue
    }
    $newest = Get-NewestEvent $log.LogName
    if ($null -eq $newest) {
        $ageSkipped += [PSCustomObject]@{ LogName = $log.LogName; Reason = 'newest event unreadable — keeping' }
    } elseif ($newest -lt $cutoff) {
        $targets += $log
        $newestByName[$log.LogName] = $newest
    } else {
        $ageSkipped += [PSCustomObject]@{ LogName = $log.LogName; Reason = ('active (newest {0:yyyy-MM-dd}) — keeping' -f $newest) }
    }
}

# Milestone 8: when the app confirms a preview with logs deselected it passes
# -IncludeOnly (the log names the user kept checked); only those are cleared.
if ($IncludeOnly.Count -gt 0) {
    $targets = $targets | Where-Object { $IncludeOnly -contains $_.LogName }
}

if ($DryRun) {
    # Preview: which logs would be backed up and cleared. No clearing happens.
    # Age-skipped logs are shown as Skip rows so the preview is explicit.
    foreach ($s in $ageSkipped) {
        [PSCustomObject]@{
            Action = 'Skip'
            Target = $s.LogName
            Detail = $s.Reason
        }
    }
    $targets | ForEach-Object {
        $detail = '{0} event(s); would be backed up to .evtx, then cleared' -f $_.RecordCount
        if ($newestByName.ContainsKey($_.LogName)) {
            $detail = '{0} event(s), newest {1:yyyy-MM-dd}; would be backed up to .evtx, then cleared' -f $_.RecordCount, $newestByName[$_.LogName]
        }
        [PSCustomObject]@{
            Action = 'Clear'
            Target = $_.LogName
            Detail = $detail
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

$ageTail = if ($cutoffDays -gt 0) { ", $($ageSkipped.Count) too recent (newest within $cutoffDays day(s))" } else { "" }
Write-Host ("Event log cleanup: $cleared cleared, $($failed.Count) failed$ageTail.")

if ($failed.Count -gt 0) {
    Write-Warning "Failed to clear the following logs:"
    $failed | ForEach-Object { Write-Warning "  $($_.LogName) - $($_.Reason)" }
}