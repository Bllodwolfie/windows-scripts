# Permanently empties the Recycle Bin. This is a real, irreversible delete —
# files emptied here cannot be recovered. In dry-run mode nothing is deleted;
# the script instead lists what is currently in the Recycle Bin and would be
# permanently lost, as structured objects for the app's preview UI.

param(
    [switch]$DryRun,
    [string]$ConfigPath = "$env:LOCALAPPDATA\ScriptSuite\Configs\EmptyRecycleBin.json",
    [string[]]$IncludeOnly = @()
)

# This script has no configurable settings; the parameter exists so the app can
# pass -ConfigPath uniformly for every script.

# Milestone 8: the app can confirm a preview with items deselected, passing
# -IncludeOnly (the reconstructed "original location\name" Targets the user
# kept checked). Only those items are permanently deleted. An empty list means
# "empty the whole bin" (the original Clear-RecycleBin behavior).

# Reconstructs the Target the dry-run preview reports for one bin item, so the
# IncludeOnly list lines up exactly between preview and real run.
function Get-RecycleTarget($item) {
    $orig = $item.ExtendedProperty('System.Recycle.DeletedFrom')
    if ($orig) { Join-Path $orig $item.Name } else { $item.Name }
}

if ($DryRun) {
    $shell = New-Object -ComObject Shell.Application
    $bin = $shell.Namespace(10)
    foreach ($item in $bin.Items()) {
        $target = Get-RecycleTarget $item
        $size = if ($item.Size -lt 1MB) { ($item.Size / 1KB).ToString('N1', [System.Globalization.CultureInfo]::InvariantCulture) + ' KB' } else { ($item.Size / 1MB).ToString('N1', [System.Globalization.CultureInfo]::InvariantCulture) + ' MB' }
        [PSCustomObject]@{
            Action = 'Delete'
            Target = $target
            Detail = "$size, would be permanently deleted"
        }
    }
    exit
}

if ($IncludeOnly.Count -eq 0) {
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    return
}

# Per-item permanent delete WITHOUT the shell, so no confirmation dialog can
# appear. The Recycle Bin is stored as $I<code> (metadata containing the
# original path) + $R<code> (data) files under <drive>:\$Recycle.Bin\<SID>.
# Deleting those two files directly is dialog-proof: it never goes through the
# shell, so the "Are you sure you want to permanently delete this file?"
# confirmation that InvokeVerb('delete') forces on recycle-bin items cannot
# appear, regardless of the machine's "Display delete confirmation dialog"
# setting. A locked $R/$I pair fails with a plain access-denied (thrown and
# reported), never a blocking modal dialog.
$sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$warned = 0
foreach ($target in $IncludeOnly) {
    $root = [System.IO.Path]::GetPathRoot($target)
    if (-not $root -or $root -notmatch '^[A-Za-z]:\\') {
        Write-Warning "Skipped recycle bin item (no local drive root): $target"
        $warned++
        continue
    }
    $sidDir = Join-Path (Join-Path $root '$Recycle.Bin') $sid
    if (-not (Test-Path -LiteralPath $sidDir)) {
        Write-Warning "Skipped recycle bin item (no recycle bin on drive $root): $target"
        $warned++
        continue
    }

    # Find the $I metadata file whose embedded original path matches this
    # target. The path is stored as a UTF-16 string inside the file, so a
    # case-insensitive substring match is layout-version agnostic.
    $matchedI = $null
    foreach ($iFile in Get-ChildItem -LiteralPath $sidDir -Filter '$I*' -File -Force -ErrorAction SilentlyContinue) {
        try {
            $decoded = [System.Text.Encoding]::Unicode.GetString([System.IO.File]::ReadAllBytes($iFile.FullName))
        } catch {
            continue
        }
        if ($decoded.IndexOf($target, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $matchedI = $iFile
            break
        }
    }
    if (-not $matchedI) {
        Write-Warning "Skipped recycle bin item (no longer in the Recycle Bin): $target"
        $warned++
        continue
    }

    $rFile = Join-Path $sidDir ('$R' + $matchedI.Name.Substring(2))
    try {
        # Delete the data file first, then its metadata, so a failed $R delete
        # leaves a still-listed (intact) item rather than a broken one.
        if (Test-Path -LiteralPath $rFile) {
            [System.IO.File]::Delete($rFile)
        }
        [System.IO.File]::Delete($matchedI.FullName)
    } catch {
        Write-Warning "Skipped locked recycle bin item: $target"
        $warned++
    }
}
if ($warned -gt 0) {
    Write-Warning "$warned recycle bin item(s) could not be permanently deleted."
}