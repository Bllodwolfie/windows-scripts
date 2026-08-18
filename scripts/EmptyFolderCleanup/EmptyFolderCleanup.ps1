# Recursively removes empty folders under TargetDir.
# Loops repeatedly because deleting a folder can leave its now-empty parent
# behind, which needs another pass to catch. Each pass tracks whether any
# folder was actually deleted; if a pass removes nothing (e.g. a locked folder
# keeps re-appearing as empty), the loop stops instead of spinning forever.
#
# Log format note: this script logs the FULL folder path (e.g.
# "DELETED : C:\Users\...\leaf") rather than the bare filename convention used
# by DownloadsCleanup.ps1. That's deliberate: this script operates recursively
# across nested subfolders, so a bare name like "leaf" would be ambiguous if it
# appears under multiple parent paths. Keep the full path in log lines.

$Config = @{
    TargetDir = "$env:USERPROFILE\Downloads"  # Root folder to scan for empty subfolders
    LogDir    = "$env:USERPROFILE\Documents\Script_Logs"
    LogFile   = "CleanupLog.txt"
}

$path = $Config.TargetDir
$logFile = Join-Path $Config.LogDir $Config.LogFile

$null = New-Item -ItemType Directory -Path $Config.LogDir -Force -ErrorAction SilentlyContinue

function Write-Log($message) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$timestamp] $message" | Out-File -FilePath $logFile -Append -Encoding utf8
}

if (Test-Path -LiteralPath $path) {
    Write-Log "Cleanup started"
    do {
        # Find all subfolders (recursively) that currently contain zero items
        $empty = @(Get-ChildItem -LiteralPath $path -Directory -Recurse -ErrorAction SilentlyContinue |
            Where-Object {
                (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue).Count -eq 0
            })

        $deletedAnything = $false
        $undeletable = @()
        foreach ($dir in $empty) {
            $fullName = $dir.FullName
            $null = Remove-Item -LiteralPath $fullName -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $fullName) {
                # Still there after the delete attempt -> locked or protected
                $undeletable += $fullName
            } else {
                $deletedAnything = $true
                Write-Log "DELETED : $fullName"
            }
        }

        if ($undeletable.Count -gt 0) {
            foreach ($u in $undeletable) {
                Write-Warning "Could not remove empty folder: $u"
            }
        }
    } while ($deletedAnything)
    Write-Log "Cleanup finished"
}