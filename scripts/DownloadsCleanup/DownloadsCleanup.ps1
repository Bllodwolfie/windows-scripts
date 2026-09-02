# Sorts and cleans up the Downloads folder:
#   - Files older than CutoffDays with an extension in DeleteExts are deleted outright.
#   - Files older than CutoffDays with an extension listed under Categories are
#     moved into the matching destination folder (created if missing).
#   - Files with an unrecognized extension are left in place and logged as skipped.
# All actions are appended to LogFile for auditing.

param(
    [switch]$DryRun,
    [string]$ConfigPath = "$env:LOCALAPPDATA\ScriptSuite\Configs\DownloadsCleanup.json",
    [string[]]$IncludeOnly = @()
)

# Fallback defaults, used only when the config file is missing (see TempCleanup).
$Config = @{
    SourceDir  = "$env:USERPROFILE\Downloads"
    CutoffDays = 7
    LogDir     = "$env:USERPROFILE\Documents\Script_Logs"
    LogFile    = "CleanupLog.txt"

    DeleteExts = @('.zip', '.rar', '.7z', '.ttf', '.otf', '.exe', '.msi')

    AdvancedRules = @{}

    Categories = @{
        "$env:USERPROFILE\Music\Misc"              = @('.aac', '.aiff', '.alac', '.ape', '.dsf', '.flac', '.m4a', '.m4b', '.mid', '.midi', '.mp3', '.oga', '.ogg', '.opus', '.wav', '.wma')
        "$env:USERPROFILE\Videos\Misc"             = @('.3gp', '.asf', '.avi', '.flv', '.m2ts', '.m4v', '.mkv', '.mov', '.mp4', '.mpeg', '.mpg', '.ogv', '.ts', '.vob', '.webm', '.wmv')
        "$env:USERPROFILE\Pictures\Misc"           = @('.avif', '.bmp', '.cr2', '.dng', '.eps', '.gif', '.heic', '.heif', '.ico', '.jpeg', '.jpg', '.nef', '.png', '.psd', '.raw', '.svg', '.tif', '.tiff', '.webp')
        "$env:USERPROFILE\Documents\Modeling"      = @('.3dm', '.3ds', '.3mf', '.blend', '.c4d', '.dae', '.dxf', '.fbx', '.glb', '.gltf', '.iges', '.igs', '.lwo', '.lxo', '.max', '.mb', '.ma', '.obj', '.ply', '.skp', '.sldasm', '.sldprt', '.step', '.stp', '.stl', '.usdz', '.vrml', '.wrl', '.x3d')
        "$env:USERPROFILE\Documents\Spreadsheets"  = @('.csv', '.numbers', '.ods', '.tsv', '.xls', '.xlsb', '.xlsm', '.xlsx', '.xlt', '.xltm', '.xltx', '.xlw')
        "$env:USERPROFILE\Documents\Presentations" = @('.key', '.odp', '.pps', '.ppsx', '.ppt', '.pptm', '.pptx', '.pot', '.potm', '.potx')
        "$env:USERPROFILE\Documents\Text"          = @('.doc', '.docb', '.docm', '.docx', '.dot', '.dotm', '.dotx', '.epub', '.log', '.md', '.msg', '.odt', '.pdf', '.rtf', '.tex', '.txt', '.wpd', '.wps')
        "$env:USERPROFILE\Documents\Configuration" = @('.cfg', '.conf', '.config', '.edmx', '.env', '.hjson', '.ics', '.inc', '.inf', '.ini', '.ipynb', '.json', '.jsonc', '.nfo', '.plist', '.properties', '.reg', '.resx', '.sql', '.strings', '.template', '.tmpl', '.toml', '.vdf', '.xaml', '.xml', '.xsd', '.xslt', '.yaml', '.yml')
    }
}

if (Test-Path -LiteralPath $ConfigPath) {
    $Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
}

# The JSON file stores env-var paths as "%USERPROFILE%\..." so they stay
# portable; expand them back into absolute paths at load time.
function Expand-ConfigPath([string]$Path) {
    [Environment]::ExpandEnvironmentVariables($Path)
}

# Delete-path history (M2 / M8 / M9): why this code looks the way it does.
#   M2 - the delete originally used the VisualBasic FileSystem API, which
#        surfaces a MODAL native "File In Use" error dialog when a file is
#        locked, hanging an unattended run forever (UIOption.OnlyErrorDialogs
#        still shows error dialogs by design).
#   M8 - Recycle-Bin operations could also raise confirm/UAC-style prompts.
#        Fixed by deleting through direct APIs plus the DELETE-access probe
#        below (a held handle) that closes the probe->delete race.
#   M9 - residual gap: a holder that grants FILE_SHARE_DELETE passes the probe,
#        so the delete itself must be UI-less. Hence the SHFileOperationW call
#        below with FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT |
#        FOF_NOERRORUI: no code path can show a dialog anymore, and a locked
#        file is either silently recycled (delete-share granted) or reported
#        as a skip.

# Route deletions through the Recycle Bin (recoverable), never permanent
# delete. See Remove-FileToRecycleBin below for the probe that keeps this safe
# for unattended runs.

# Native file API for the dialog-proofing probe. Requesting DELETE access on a
# file succeeds only if every process currently holding it grants
# FILE_SHARE_DELETE - i.e. the file can genuinely be moved to the Recycle Bin
# right now. Holding that handle across the recycle call prevents another
# process from stealing a conflicting lock in between, which closes the
# probe-to-delete race that could otherwise surface the native "File In Use"
# dialog.
if (-not ('RecycleBin' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class RecycleBin {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct SHFILEOPSTRUCT {
        public IntPtr hwnd;
        public uint wFunc;
        [MarshalAs(UnmanagedType.LPWStr)] public string pFrom;
        [MarshalAs(UnmanagedType.LPWStr)] public string pTo;
        public ushort fFlags;
        public bool fAnyOperationsAborted;
        public IntPtr hNameMappings;
        [MarshalAs(UnmanagedType.LPWStr)] public string lpszProgressTitle;
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr CreateFileW(string lpFileName, uint dwDesiredAccess, uint dwShareMode, IntPtr lpSecurityAttributes, uint dwCreationDisposition, uint dwFlagsAndAttributes, IntPtr hTemplateFile);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    public static extern int SHFileOperationW(ref SHFILEOPSTRUCT lpFileOp);
    // DELETE access (0x00010000), share READ|WRITE|DELETE (7), OPEN_EXISTING (3),
    // FILE_FLAG_BACKUP_SEMANTICS (0x02000000) so it also works on directories.
    public static IntPtr OpenDeleteHandle(string path) {
        return CreateFileW(path, 0x00010000u, 7u, IntPtr.Zero, 3u, 0x02000000u, IntPtr.Zero);
    }
    // Recycle a file to the Recycle Bin with no UI of any kind:
    // FOF_ALLOWUNDO (0x40) sends it to the Recycle Bin instead of deleting it
    // permanently; FOF_NOCONFIRMATION (0x10), FOF_SILENT (0x4) and
    // FOF_NOERRORUI (0x2) suppress every dialog, including the native
    // "File In Use" error dialog the VisualBasic FileSystem API could raise on
    // a file another process holds. A file that can't be recycled just returns
    // a non-zero code (no dialog); the caller reports the skip. Returns 0 on
    // success.
    public static int RecycleFile(string path) {
        SHFILEOPSTRUCT op = new SHFILEOPSTRUCT();
        op.wFunc = 3; // FO_DELETE
        op.fFlags = 0x40 | 0x10 | 0x4 | 0x2; // FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI
        op.pFrom = path + "\0\0";
        return SHFileOperationW(ref op);
    }
}
'@
}

# Deletes a file to the Recycle Bin without ever risking a blocking native
# dialog (a modal dialog during an unattended run would hang forever). Two
# layers keep this safe: the DELETE-access probe below (fails for files held
# without FILE_SHARE_DELETE -> skip), and the recycle itself running through
# SHFileOperationW with FOF_NOERRORUI|FOF_SILENT so even a race can never
# surface the native "File In Use" error dialog. We HOLD the DELETE handle
# across the recycle call so no other process can grab a conflicting lock in
# between. Throws if the file is still present afterwards, so callers log the
# failure rather than a false success.
function Remove-FileToRecycleBin([string]$Path) {
    $invalid = [IntPtr]::new(-1)
    $h = [RecycleBin]::OpenDeleteHandle($Path)
    if ($h -eq [IntPtr]::Zero -or $h -eq $invalid) {
        throw [System.IO.IOException]::new("File is locked and cannot be recycled: $Path")
    }
    try {
        $rc = [RecycleBin]::RecycleFile($Path)
        if ($rc -ne 0 -or (Test-Path -LiteralPath $Path)) {
            throw [System.IO.IOException]::new("File could not be recycled (SHFileOperation error $rc): $Path")
        }
    } finally {
        [void][RecycleBin]::CloseHandle($h)
    }
}

$source  = Expand-ConfigPath $Config.SourceDir
$cutoff  = (Get-Date).AddDays(-$Config.CutoffDays)
$logDir  = Expand-ConfigPath $Config.LogDir
$logFile = Join-Path $logDir $Config.LogFile
$deleteExts = @($Config.DeleteExts)
$categoriesRaw = $Config.Categories

$null = New-Item -ItemType Directory -Path $logDir -Force -ErrorAction SilentlyContinue

# Appends one line to the log file with the suite-standard timestamp prefix
function Write-Log($message) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$timestamp] $message" | Out-File -FilePath $logFile -Append -Encoding utf8
}

# Flatten Categories into a lookup table: extension -> destination folder
# (built once up front so each file only needs a single hashtable lookup).
# JSON deserializes the nested object into a PSCustomObject, so enumerate its
# properties here and expand any %USERPROFILE% paths in the keys.
$extMap = @{}
foreach ($prop in $categoriesRaw.PSObject.Properties) {
    $dest = Expand-ConfigPath $prop.Name
    foreach ($ext in @($prop.Value)) {
        $extMap[$ext.ToLower()] = $dest
    }
}

# Advanced per-extension rules (additive, opt-in). Missing key = {} so existing
# configs behave exactly as before (backward compat). Normalized to lower case.
# Overlap decision (item 1 approved): AdvancedRules always wins when present.
# If .zip is in DeleteExts and also has AdvancedRules { Action: MoveTo }, the
# MoveTo wins. Same for a Categories-mapped .jpg with an AdvancedRules Delete.
# The simple-mode "Extensions to delete" tag list is not auto-synced; the
# Settings UI shows a one-line warning when the same ext appears in both
# places so the user is not surprised. This comment is the spec anchor.
$advancedMap = @{}
if ($null -ne $Config.AdvancedRules) {
    foreach ($prop in $Config.AdvancedRules.PSObject.Properties) {
        $extKey = $prop.Name.ToLower()
        if (-not $extKey.StartsWith(".")) { $extKey = "." + $extKey }
        $rule = $prop.Value
        $action = if ($rule.PSObject.Properties["Action"]) { [string]$rule.Action } else { "" }
        $destRaw = if ($rule.PSObject.Properties["Destination"]) { [string]$rule.Destination } else { "" }
        $destExpanded = if ($destRaw) { Expand-ConfigPath $destRaw } else { "" }
        $advancedMap[$extKey] = @{ Action = $action; Destination = $destExpanded; RawDestination = $destRaw }
    }
}

if (-not $DryRun) { Write-Log "Cleanup started" }

# Skipped files (locked, in use) are counted and surfaced below so the run
# reports accurately instead of claiming success while leaving files behind.
$script:deletedCount = 0
$script:skippedCount  = 0

# Process every file in Downloads that's older than the cutoff
Get-ChildItem -LiteralPath $source -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoff } | ForEach-Object {
    $ext = $_.Extension.ToLower()
    $name = $_.Name
    # Capture file props before any switch (switch overwrites $_)
    $fileFullName = $_.FullName
    $fileLength = $_.Length
    $fileTime = $_.LastWriteTime

    # Milestone 8: only touch the targets the user kept checked in the preview.
    if ($IncludeOnly.Count -gt 0 -and $IncludeOnly -notcontains $fileFullName) { return }

    # Advanced per-extension override — checked first, before DeleteExts/Categories (see overlap decision above).
    # This ensures an explicit per-ext rule always wins: e.g. .zip in DeleteExts + AdvancedRules MoveTo → MoveTo wins.
    if ($advancedMap.ContainsKey($ext)) {
        $rule = $advancedMap[$ext]
        $advAction = [string]$rule.Action
        switch ($advAction) {
            "Ignore" {
                if ($DryRun) {
                    [PSCustomObject]@{ Action = 'Skip'; Target = $fileFullName; Detail = 'ignored per advanced rule: ' + $ext }
                } else {
                    Write-Log "SKIPPED : $name (ignored per advanced rule: $ext)"
                }
                return
            }
            "Delete" {
                if ($DryRun) {
                    [PSCustomObject]@{
                        Action = 'Delete'
                        Target = $fileFullName
                        Detail = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0:N1} MB, last modified {1:yyyy-MM-dd}', $fileLength / 1MB, $fileTime) + ' [advanced rule]'
                    }
                } else {
                    try {
                        Remove-FileToRecycleBin $fileFullName
                        Write-Log "DELETED : $name [advanced rule]"
                        $script:deletedCount++
                    } catch {
                        Write-Log "ERROR   : Failed to delete $name : $_"
                        Write-Warning "Skipped locked file: $($_.Exception.Message)"
                        $script:skippedCount++
                    }
                }
                return
            }
            "MoveTo" {
                $destDir = $rule.Destination
                if ([string]::IsNullOrWhiteSpace($destDir)) {
                    if ($DryRun) {
                        [PSCustomObject]@{ Action = 'Skip'; Target = $fileFullName; Detail = 'advanced MoveTo missing destination: ' + $ext + ' [advanced rule]' }
                    } else {
                        Write-Log "SKIPPED : $name (advanced MoveTo missing destination: $ext)"
                    }
                    return
                }
                if ($DryRun) {
                    [PSCustomObject]@{ Action = 'Move'; Target = $fileFullName; Detail = 'to ' + $destDir + ' [advanced rule]' }
                } else {
                    try {
                        $null = New-Item -ItemType Directory -Path $destDir -Force -ErrorAction Stop
                        Move-Item -LiteralPath $fileFullName -Destination $destDir -Force -ErrorAction Stop
                        Write-Log "MOVED   : $name -> $destDir [advanced rule]"
                    } catch {
                        Write-Log "ERROR   : Failed to move $name to $destDir [advanced rule] : $_"
                    }
                }
                return
            }
        }
    }

    # Case 1: extension is on the delete list -> remove the file (to Recycle Bin)
    if ($deleteExts -contains $ext) {
        if ($DryRun) {
            [PSCustomObject]@{
                Action = 'Delete'
                Target = $fileFullName
                Detail = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0:N1} MB, last modified {1:yyyy-MM-dd}', $fileLength / 1MB, $fileTime)
            }
        } else {
            try {
                Remove-FileToRecycleBin $fileFullName
                Write-Log "DELETED : $name"
                $script:deletedCount++
            } catch {
                Write-Log "ERROR   : Failed to delete $name : $_"
                Write-Warning "Skipped locked file: $($_.Exception.Message)"
                $script:skippedCount++
            }
        }
        return
    }

    # Case 2: extension maps to a category folder -> move it there
    if ($extMap.ContainsKey($ext)) {
        $destDir = $extMap[$ext]
        if ($DryRun) {
            [PSCustomObject]@{
                Action = 'Move'
                Target = $fileFullName
                Detail = 'to {0}' -f $destDir
            }
        } else {
            try {
                $null = New-Item -ItemType Directory -Path $destDir -Force -ErrorAction Stop
                Move-Item -LiteralPath $fileFullName -Destination $destDir -Force -ErrorAction Stop
                Write-Log "MOVED   : $name -> $destDir"
            } catch {
                Write-Log "ERROR   : Failed to move $name to $destDir : $_"
            }
        }
    } else {
        # Case 3: extension not recognized anywhere -> no action; the real run
        # logs it as SKIPPED, so the preview shows it too as an omitted-action row.
        if ($DryRun) {
            [PSCustomObject]@{
                Action = 'Skip'
                Target = $fileFullName
                Detail = 'no action (unrecognized extension: {0})' -f $ext
            }
        } else {
            Write-Log "SKIPPED : $name (unrecognized extension: $ext)"
        }
    }
}

if (-not $DryRun) { Write-Log "Cleanup finished" }
if (-not $DryRun) {
    Write-Host "DownloadsCleanup: $script:deletedCount deleted, $script:skippedCount skipped (locked or in use)."
}