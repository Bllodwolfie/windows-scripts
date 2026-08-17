# Clears Windows event logs. Enumerates logs with Get-WinEvent -ListLog,
# restricts clearing to enabled, non-empty, circular-mode logs (Retain-mode
# logs are write-once and can't be cleared), clears each via wevtutil, and
# prints a summary of cleared vs failed. Errors are surfaced, not blanket-
# suppressed, so real problems (permissions, corrupt logs) are visible.

# Enumerate logs (restricted/denied logs are skipped silently; the ones we
# actually clear will surface their own errors below)
$logs = @(Get-WinEvent -ListLog * -ErrorAction SilentlyContinue)

$targets = $logs | Where-Object {
    $_.IsEnabled -and
    $_.LogMode -eq 'Circular' -and
    $_.RecordCount -gt 0
}

$cleared = 0
$failed  = @()

foreach ($log in $targets) {
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

Write-Host "Event log cleanup: $cleared cleared, $($failed.Count) failed, $($targets.Count - $cleared - $failed.Count) skipped."

if ($failed.Count -gt 0) {
    Write-Warning "Failed to clear the following logs:"
    $failed | ForEach-Object { Write-Warning "  $($_.LogName) - $($_.Reason)" }
}