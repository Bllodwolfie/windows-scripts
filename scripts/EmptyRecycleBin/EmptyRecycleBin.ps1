# Permanently empties the Recycle Bin. This is a real, irreversible delete —
# files emptied here cannot be recovered. In dry-run mode nothing is deleted;
# the script instead lists what is currently in the Recycle Bin and would be
# permanently lost, as structured objects for the app's preview UI.

param(
    [switch]$DryRun,
    [string]$ConfigPath = "$env:LOCALAPPDATA\ScriptSuite\Configs\EmptyRecycleBin.json",
    [string[]]$IncludeOnly = @()
)

# Config: MinAgeDays (int, default 0) — only delete items older than N days.
# 0 = delete everything (current behavior, backward compatible). Existing configs
# without this key fall back to 0 via the default below and the manifest default.
$Config = [PSCustomObject]@{ MinAgeDays = 0 }
if (Test-Path -LiteralPath $ConfigPath) {
    try {
        $loaded = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
        if ($null -ne $loaded) { $Config = $loaded }
    } catch {
        Write-Warning "EmptyRecycleBin config is corrupt or unreadable at $ConfigPath — using defaults (MinAgeDays=0)."
    }
}
# Normalize MinAgeDays: int, default 0, clamp negative to 0 (UI blocks negative, but hand-edited JSON must still be safe)
$minAgeDays = 0
if ($null -ne $Config.PSObject.Properties["MinAgeDays"]) {
    try { $minAgeDays = [int]$Config.MinAgeDays } catch { $minAgeDays = 0 }
}
if ($minAgeDays -lt 0) {
    Write-Warning "MinAgeDays is negative ($minAgeDays) — treating as 0 (delete everything)."
    $minAgeDays = 0
}
$cutoff = (Get-Date).AddDays(-$minAgeDays)

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

# Root-cause: original whole-bin path used Clear-RecycleBin -Force, which cannot
# filter by age. To support MinAgeDays we must enumerate Shell.Application
# Namespace(10) items and read each item's DateDeleted via the extended property
# System.Recycle.DateDeleted (not basic .DateCreated). Individual per-item
# deletion already used direct $Recycle.Bin file deletion for dialog-proofing;
# whole-bin filtered path now reuses that same per-item path after age filtering.
function Get-RecycleDateDeleted($item) {
    try {
        $val = $item.ExtendedProperty('System.Recycle.DateDeleted')
        if ($null -ne $val) {
            # ExtendedProperty may return a string or DateTime depending on locale/PS version
            if ($val -is [DateTime]) { return $val }
            # Try parse string like "09/02/2026 21:51:25" or locale-specific GetDetailsOf fallback
            $parsed = $null
            if ([DateTime]::TryParse([string]$val, [ref]$parsed)) { return $parsed }
        }
    } catch {}
    return $null
}

if ($DryRun) {
    $shell = New-Object -ComObject Shell.Application
    $bin = $shell.Namespace(10)
    $now = Get-Date
    $deleteCount = 0
    $skipCount = 0
    $deleteSize = 0
    $skipSize = 0
    foreach ($item in $bin.Items()) {
        $target = Get-RecycleTarget $item
        $size = $item.Size
        $sizeStr = if ($size -lt 1MB) { ($size / 1KB).ToString('N1', [System.Globalization.CultureInfo]::InvariantCulture) + ' KB' } else { ($size / 1MB).ToString('N1', [System.Globalization.CultureInfo]::InvariantCulture) + ' MB' }
        $dateDeleted = Get-RecycleDateDeleted $item
        $ageDays = if ($null -ne $dateDeleted) { ($now - $dateDeleted).TotalDays } else { -1 }
        # If DateDeleted unavailable and MinAgeDays==0, treat as old enough to delete (preserve current behavior: delete everything). If >0 and date missing, conservatively skip.
        $isOld = if ($minAgeDays -eq 0) { $true } else { $null -ne $dateDeleted -and $ageDays -ge $minAgeDays }
        # Also respect IncludeOnly if preview was filtered? Dry-run ignores IncludeOnly and shows all, but keep gate for consistency
        if ($IncludeOnly.Count -gt 0 -and $IncludeOnly -notcontains $target) { continue }
        if ($isOld) {
            $deleteCount++
            $deleteSize += $size
            $ageInfo = if ($null -ne $dateDeleted) { "{0:N0} days old" -f $ageDays } else { "age unknown" }
            [PSCustomObject]@{
                Action = 'Delete'
                Target = $target
                Detail = "$sizeStr, $ageInfo, would be permanently deleted"
            }
        } else {
            $skipCount++
            $skipSize += $size
            $ageInfo = if ($null -ne $dateDeleted) { "{0:N1} days old" -f $ageDays } else { "age unknown" }
            [PSCustomObject]@{
                Action = 'Skip'
                Target = $target
                Detail = "$sizeStr, $ageInfo — younger than $minAgeDays days, would be skipped"
            }
        }
    }
    # Summary line for console evidence, matching other cleanup scripts' reporting style (counts + total size)
    if ($deleteCount -gt 0 -or $skipCount -gt 0) {
        $delSizeStr = if ($deleteSize -lt 1MB) { "{0:N1} KB" -f ($deleteSize / 1KB) } else { "{0:N1} MB" -f ($deleteSize / 1MB) }
        $skipSizeStr = if ($skipSize -lt 1MB) { "{0:N1} KB" -f ($skipSize / 1KB) } else { "{0:N1} MB" -f ($skipSize / 1MB) }
        Write-Host ("Recycle Bin dry-run: {0} item(s) ({1}) would be deleted, {2} skipped (younger than {3} days, {4})." -f $deleteCount, $delSizeStr, $skipCount, $minAgeDays, $skipSizeStr)
    }
    exit
}

if ($IncludeOnly.Count -eq 0) {
    if ($minAgeDays -eq 0) {
        # Preserve exact current behavior for MinAgeDays=0: fast whole-bin clear, no age filtering
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        return
    } else {
        # Filtered whole-bin: enumerate and only delete items old enough, reusing per-item dialog-proof path below
        $shell = New-Object -ComObject Shell.Application
        $bin = $shell.Namespace(10)
        $now = Get-Date
        $filtered = @()
        foreach ($item in $bin.Items()) {
            $dateDeleted = Get-RecycleDateDeleted $item
            $ageDays = if ($null -ne $dateDeleted) { ($now - $dateDeleted).TotalDays } else { -1 }
            if ($null -ne $dateDeleted -and $ageDays -ge $minAgeDays) {
                $filtered += Get-RecycleTarget $item
            }
        }
        if ($filtered.Count -eq 0) {
            Write-Host ("Recycle Bin: 0 items older than {0} days — nothing to delete." -f $minAgeDays)
            return
        }
        $IncludeOnly = $filtered
        # fall through to per-item deletion for filtered list
    }
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