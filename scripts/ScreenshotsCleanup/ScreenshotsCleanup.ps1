# Deletes screenshots older than CutoffDays from the Pictures\Screenshots folder.
# Non-recursive: only touches files directly in TargetDir. If the folder
# doesn't exist yet (e.g. a fresh profile that never took a screenshot),
# logs a skip and exits cleanly instead of erroring.

$Config = @{
    TargetDir  = "$env:USERPROFILE\Pictures\Screenshots"  # Folder to clean
    CutoffDays = 7                                          # Delete files older than this many days
    LogDir     = "$env:USERPROFILE\Documents\Script_Logs"
    LogFile    = "CleanupLog.txt"
}

$path    = $Config.TargetDir
$cutoff  = (Get-Date).AddDays(-$Config.CutoffDays)
$logFile = Join-Path $Config.LogDir $Config.LogFile

$null = New-Item -ItemType Directory -Path $Config.LogDir -Force -ErrorAction SilentlyContinue

function Write-Log($message) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$timestamp] $message" | Out-File -FilePath $logFile -Append -Encoding utf8
}

Write-Log "ScreenshotsCleanup started"

if (-not (Test-Path -LiteralPath $path)) {
    Write-Log "SKIPPED : Screenshots folder not found: $path"
    Write-Log "ScreenshotsCleanup finished"
    exit
}

$removed = 0
foreach ($f in @(Get-ChildItem -LiteralPath $path -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoff })) {
    try {
        Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
        Write-Log "DELETED : $($f.Name)"
        $removed++
    } catch {
        Write-Log "ERROR   : Failed to delete $($f.Name) : $_"
    }
}

Write-Log "ScreenshotsCleanup removed $removed file(s)"
Write-Log "ScreenshotsCleanup finished"