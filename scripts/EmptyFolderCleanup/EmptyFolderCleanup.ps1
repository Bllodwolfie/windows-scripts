# Recursively removes empty folders under TargetFolder.
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

param(
    [switch]$DryRun,
    [string]$ConfigPath = "$env:LOCALAPPDATA\ScriptSuite\Configs\EmptyFolderCleanup.json",
    [string[]]$IncludeOnly = @()
)

# Milestone 8: when the app confirms a preview with items deselected it passes
# -IncludeOnly (the Target full paths the user kept checked); only those empty
# folders may be removed. An empty list means "no restriction".
function Test-Selected([string]$FullName) {
    $IncludeOnly.Count -eq 0 -or $IncludeOnly -contains $FullName
}

# Fallback defaults, used only when the config file is missing (see TempCleanup).
$Config = @{
    TargetFolder = "$env:USERPROFILE\Downloads"
    LogDir       = "$env:USERPROFILE\Documents\Script_Logs"
    LogFile      = "CleanupLog.txt"
}

if (Test-Path -LiteralPath $ConfigPath) {
    try {
        $loaded = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
        if ($null -ne $loaded) { $Config = $loaded } else { throw "empty config" }
    } catch {
        Write-Warning "EmptyFolderCleanup config is corrupt or unreadable at $ConfigPath — using defaults (TargetFolder=$($Config.TargetFolder)). Check or reset the config via Settings."
    }
    $raw = (Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction SilentlyContinue)
    if ($null -ne $raw -and $raw.Trim() -eq "") {
        Write-Warning "EmptyFolderCleanup config is empty at $ConfigPath — using defaults (TargetFolder=$($Config.TargetFolder))."
    }
}

function Test-PathScope([string]$Path, [string]$ExpectedRoot) {
    if ([string]::IsNullOrWhiteSpace($Path)) { Write-Error "Path must be absolute: $Path (empty)"; exit 1 }
    $expanded = [Environment]::ExpandEnvironmentVariables($Path.Trim())
    if (-not [System.IO.Path]::IsPathRooted($expanded)) { Write-Error "Path must be absolute: $Path"; exit 1 }
    if ($ExpectedRoot) {
        $exp = [Environment]::ExpandEnvironmentVariables($ExpectedRoot)
        try { $full = [System.IO.Path]::GetFullPath($expanded) } catch { $full = $expanded }
        try { $root = [System.IO.Path]::GetFullPath($exp) } catch { $root = $exp }
        if (-not $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
            Write-Warning "Path '$Path' is outside expected scope (expected under '$ExpectedRoot') — proceeding anyway"
        }
    }
    if ($Path -match '[\. ]$') { Write-Warning "Trailing space/dot will be stripped by Windows: '$Path'" }
}

# JSON stores env-var paths as "%USERPROFILE%\..."; expand them at load time.
function Expand-ConfigPath([string]$Path) {
    [Environment]::ExpandEnvironmentVariables($Path)
}

# IgnoreFolders (list of paths, default empty): folders that must never be
# deleted, even when empty. Ignoring a folder protects everything under it,
# because the folder itself is never a delete candidate and therefore keeps
# occupying its parent (both in the DryRun simulation below and on disk in
# the real pass). A missing key is treated as an empty list so existing
# configs behave exactly as before.
$ignoreRaw = @()
if ($Config -is [hashtable]) {
    if ($Config.ContainsKey("IgnoreFolders") -and $null -ne $Config["IgnoreFolders"]) { $ignoreRaw = @($Config["IgnoreFolders"]) }
} elseif ($null -ne $Config.PSObject.Properties["IgnoreFolders"] -and $null -ne $Config.IgnoreFolders) {
    $ignoreRaw = @($Config.IgnoreFolders)
}

function Normalize-IgnorePath([string]$P) {
    if ([string]::IsNullOrWhiteSpace($P)) { return $null }
    $e = [Environment]::ExpandEnvironmentVariables($P.Trim()).TrimEnd('\', '/')
    # Compare against normalized non-prefixed paths: the \\?\ long-path prefix
    # is applied only at delete time inside Remove-EmptyFolder (enumeration
    # stays unprefixed since the M12 Cat1b 5001-vs-5101 regression), so strip
    # it here to keep both sides in the same form.
    if ($e.StartsWith("\\?\")) { $e = $e.Substring(4) }
    try { return [System.IO.Path]::GetFullPath($e).TrimEnd('\', '/') } catch { return $e }
}

$ignoreList = @()
foreach ($raw in $ignoreRaw) {
    $n = Normalize-IgnorePath ([string]$raw)
    if ($n) { $ignoreList += $n }
}

# True when $FullName is an ignored folder itself or lives under one.
# A path outside the scan root simply never matches (harmless, no error).
# Supplied IncludeOnly entries do NOT override this: ignore always wins.
function Test-Ignored([string]$FullName) {
    if ($ignoreList.Count -eq 0) { return $false }
    $n = Normalize-IgnorePath $FullName
    if (-not $n) { return $false }
    foreach ($ig in $ignoreList) {
        if ($n.Equals($ig, [StringComparison]::OrdinalIgnoreCase) -or
            $n.StartsWith($ig + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function ConvertTo-LongPath([string]$Path) {
    if ($Path.StartsWith("\\?\")) { return $Path }
    try { $full = [System.IO.Path]::GetFullPath($Path) } catch { return $Path }
    if ($full.Length -ge 240) { return "\\?\" + $full }
    return $full
}

# Delete-path history (M2 / M8 / M9): why this code looks the way it does.
#   M2 - the delete could surface a MODAL native "folder in use" error dialog
#        when a folder was locked, hanging an unattended run forever.
#   M8 - added the DELETE-access probe below (a held handle) that closes the
#        probe->delete race and skips locked folders without any dialog.
#   M9 - removed the last dialog-capable call (VisualBasic DeleteDirectory):
#        this now deletes via [System.IO.Directory]::Delete($Path, $false).
#        The "$false" is INTENTIONAL and TESTED - non-recursive, so a folder
#        that turned non-empty since the scan THROWS into the warn/skip path
#        instead of this silently deleting new contents (the non-recursive
#        guarantee required since M2 and re-verified in M9).

# Folders are deleted with the NON-RECURSIVE overload so a folder that is
# unexpectedly non-empty at delete time (e.g. content landed between the
# emptiness scan and this call) THROWS, routing through the warn/skip path
# below instead of this silently deleting the new contents. Note: it deletes
# permanently rather than to the Recycle Bin — but only genuinely EMPTY folders
# are ever passed here, and an empty folder carries no data, so nothing
# recoverable is lost.
#
# Dialog-proofing: .NET's Directory.Delete goes straight to the Win32
# RemoveDirectory API with no shell involvement, so it can never surface a
# native "folder in use" dialog. Remove-EmptyFolder below still probes first:
# request DELETE access (succeeds only if every holder grants
# FILE_SHARE_DELETE) and HOLD that handle across the delete so no other process
# can steal a conflicting lock in between.

if (-not ('RecycleBin' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class RecycleBin {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr CreateFileW(string lpFileName, uint dwDesiredAccess, uint dwShareMode, IntPtr lpSecurityAttributes, uint dwCreationDisposition, uint dwFlagsAndAttributes, IntPtr hTemplateFile);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);
    // DELETE access (0x00010000), share READ|WRITE|DELETE (7), OPEN_EXISTING (3),
    // FILE_FLAG_BACKUP_SEMANTICS (0x02000000) so it also works on directories.
    public static IntPtr OpenDeleteHandle(string path) {
        return CreateFileW(path, 0x00010000u, 7u, IntPtr.Zero, 3u, 0x02000000u, IntPtr.Zero);
    }
}
'@
}

# Deletes a (confirmed empty) folder without risking a blocking native dialog.
# Probes with a DELETE-access handle; if any current holder doesn't grant
# FILE_SHARE_DELETE the open fails and we throw (caller warns + skips) rather
# than triggering the "folder in use" dialog. Holds the handle across the
# delete to close the probe-to-delete race.
function Remove-EmptyFolder([string]$Path) {
    $longPath = ConvertTo-LongPath $Path
    $invalid = [IntPtr]::new(-1)
    $h = [RecycleBin]::OpenDeleteHandle($longPath)
    if ($h -eq [IntPtr]::Zero -or $h -eq $invalid) {
        throw [System.IO.IOException]::new("Folder is locked and cannot be removed: $Path")
    }
    try {
        # Permanent delete of a confirmed-empty folder. The non-recursive
        # overload throws if the folder turned non-empty since the scan,
        # routing through the warn/skip path below. No shell API, so no dialog
        # is possible even if a lock races the probe. The non-recursive $false
        # is intentional and tested (see M2/M8/M9 history above).
        # Long-path prefix \\?\ applied via ConvertTo-LongPath.
        [System.IO.Directory]::Delete($longPath, $false)
    } finally {
        [void][RecycleBin]::CloseHandle($h)
    }
}

# Target folder from config; fall back to the original Downloads default if
# the config is missing or empty (e.g. an older config file without the field).
$path    = if ($Config.TargetFolder) { Expand-ConfigPath $Config.TargetFolder } else { "$env:USERPROFILE\Downloads" }
$logDir  = Expand-ConfigPath $Config.LogDir
$logFile = Join-Path $logDir $Config.LogFile

Test-PathScope $path $null

$null = New-Item -ItemType Directory -Path $logDir -Force -ErrorAction SilentlyContinue

function Write-Log($message) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$timestamp] $message" | Out-File -FilePath $logFile -Append -Encoding utf8
}

if (Test-Path -LiteralPath $path) {
    if ($DryRun) {
        # Simulate the multi-pass loop: repeatedly find currently-empty folders,
        # "remove" them from a set (not the disk), and keep scanning until no
        # more become empty. This yields the same folder set the real run would
        # delete (including parents that only become empty after their empty
        # children are removed), as structured objects for the app's preview.
        $simRemoved = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $changed = $true
        while ($changed) {
            $changed = $false
            $empty = @(Get-ChildItem -LiteralPath $path -Directory -Recurse -ErrorAction SilentlyContinue |
                Where-Object {
                    -not $simRemoved.Contains($_.FullName) -and
                    -not (Test-Ignored $_.FullName) -and
                    (Test-Selected $_.FullName) -and
                    (@(Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue | Where-Object { -not $simRemoved.Contains($_.FullName) }).Count -eq 0)
                })
            foreach ($dir in $empty) {
                [void]$simRemoved.Add($dir.FullName)
                $changed = $true
                [PSCustomObject]@{
                    Action = 'Delete'
                    Target = $dir.FullName
                    Detail = 'empty folder'
                }
            }
        }
        exit
    }

    Write-Log "Cleanup started"
    do {
        # Find all subfolders (recursively) that currently contain zero items
        $empty = @(Get-ChildItem -LiteralPath $path -Directory -Recurse -ErrorAction SilentlyContinue |
            Where-Object {
                -not (Test-Ignored $_.FullName) -and
                (Test-Selected $_.FullName) -and
                (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue).Count -eq 0
            })

        $deletedAnything = $false
        $undeletable = @()
        foreach ($dir in $empty) {
            $fullName = $dir.FullName
            try {
                Remove-EmptyFolder $fullName
            } catch {}
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
                # R7: structured failure for UI/history — matches Action/Target/Detail pattern + Path/Reason/Status
                [PSCustomObject]@{
                    Action = 'Delete'
                    Target = $u
                    Detail = 'Failed: locked or long path or protected'
                    Path   = $u
                    Reason = 'locked or long path or protected'
                    Status = 'Failed'
                }
            }
        }
    } while ($deletedAnything)
    # Ignored folders stay empty on disk by design — exclude them here too, or
    # a run that correctly kept them would still report Warning + Summary.
    $remainingEmpty = @(Get-ChildItem -LiteralPath $path -Directory -Recurse -ErrorAction SilentlyContinue | Where-Object { -not (Test-Ignored $_.FullName) -and (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue).Count -eq 0 }).Count
    if ($remainingEmpty -gt 0) {
        Write-Warning "$remainingEmpty empty folder(s) could not be removed (long path or locked)"
        [PSCustomObject]@{
            Action = 'Summary'
            Target = $path
            Detail = "$remainingEmpty empty folder(s) could not be removed (long path or locked)"
            Path   = $path
            Reason = 'remaining empty folders after passes'
            Status = 'Warning'
        }
    }
    Write-Log "Cleanup finished"
}