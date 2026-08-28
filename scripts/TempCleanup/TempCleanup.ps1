# Deletes files in the user's %TEMP% folder that are older than CutoffDays.
# Runs recursively; files/folders that fail to delete (locked, in-use) are silently skipped.

param(
    [switch]$DryRun,
    [string]$ConfigPath = "$env:LOCALAPPDATA\ScriptSuite\Configs\TempCleanup.json",
    [string[]]$IncludeOnly = @()
)

# Fallback defaults, used only when the config file is missing (e.g. run
# standalone before the app has ever written a config). The app normally
# copies its shipped default config to the path above on first run.
$Config = @{
    TargetFolder = "$env:TEMP"
    CutoffDays   = 7
}

if (Test-Path -LiteralPath $ConfigPath) {
    $Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
}

# JSON stores env-var paths as "%TEMP%"/"%USERPROFILE%\..."; expand them at load time.
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

# Target folder from config; fall back to the original %TEMP% default if the
# config is missing or empty (e.g. an older config file without the field).
$target = if ($Config.TargetFolder) { Expand-ConfigPath $Config.TargetFolder } else { $env:TEMP }

$cutoff = (Get-Date).AddDays(-$Config.CutoffDays)

# Recurse through the target folder and either preview (DryRun) or delete files
# older than the cutoff. Each delete goes to the Recycle Bin; files/folders that
# fail (locked, in-use) are skipped and REPORTED (WARN line + summary), never
# silently swallowed, so a run can't claim success while leaving files behind.
# In dry-run the affected files are emitted as structured objects
# (Action/Target/Detail) for the app's preview UI.
$script:deletedCount = 0
$script:skippedCount  = 0
Get-ChildItem -LiteralPath $target -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt $cutoff } |
    ForEach-Object {
        # Milestone 8: when the app confirms a preview with items deselected,
        # it passes -IncludeOnly (the Target full paths the user kept checked).
        # Only those targets are touched; everything else is left alone.
        if ($IncludeOnly.Count -gt 0 -and $IncludeOnly -notcontains $_.FullName) { return }
        if ($DryRun) {
            [PSCustomObject]@{
                Action = 'Delete'
                Target = $_.FullName
                Detail = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0:N1} MB, last modified {1:yyyy-MM-dd}', $_.Length / 1MB, $_.LastWriteTime)
            }
        } else {
            try {
                Remove-FileToRecycleBin $_.FullName
                $script:deletedCount++
            } catch {
                Write-Warning "Skipped locked file: $($_.Exception.Message)"
                $script:skippedCount++
            }
        }
    }
if (-not $DryRun) {
    Write-Host "Temp cleanup: $script:deletedCount deleted, $script:skippedCount skipped (locked or in use)."
}
