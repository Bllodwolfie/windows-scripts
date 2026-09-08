# Generates a text report of all installed software by reading the standard
# Windows "Uninstall" registry keys (covers 64-bit, 32-bit-on-64-bit, and
# per-user installs), then writes it to OutputFile.

param(
    [string]$ConfigPath = "$env:LOCALAPPDATA\ScriptSuite\Configs\SoftwareInventory.json"
)

# Fallback defaults, used only when the config file is missing (see TempCleanup).
$Config = @{
    OutputFile = "$env:USERPROFILE\Documents\Script_Logs\Software_Inventory.txt"
}

if (Test-Path -LiteralPath $ConfigPath) {
    try {
        $loaded = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
        if ($null -ne $loaded) { $Config = $loaded } else { throw "empty config" }
    } catch {
        Write-Warning "SoftwareInventory config is corrupt or unreadable at $ConfigPath — using defaults (OutputFile=$($Config.OutputFile)). Check or reset the config via Settings."
    }
    $raw = (Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction SilentlyContinue)
    if ($null -ne $raw -and $raw.Trim() -eq "") {
        Write-Warning "SoftwareInventory config is empty at $ConfigPath — using defaults (OutputFile=$($Config.OutputFile))."
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

$outputFile = Expand-ConfigPath $Config.OutputFile
Test-PathScope $outputFile $null

# B6: validate OutputFile — file-where-folder-expected and missing drive should fail clearly, not silently with exit 0
try {
    $outDir = Split-Path $outputFile -Parent
    if ([string]::IsNullOrWhiteSpace($outDir)) { $outDir = "." }
    if (Test-Path -LiteralPath $outDir) {
        $item = Get-Item -LiteralPath $outDir -ErrorAction SilentlyContinue
        if ($null -ne $item -and -not $item.PSIsContainer) {
            throw "OutputFile parent is not a folder (is a file): $outDir"
        }
    }
    if (Test-Path -LiteralPath $outputFile) {
        $targetItem = Get-Item -LiteralPath $outputFile -ErrorAction SilentlyContinue
        if ($null -ne $targetItem -and $targetItem.PSIsContainer) {
            throw "OutputFile is a folder, not a file: $outputFile"
        }
    }
    $null = New-Item -ItemType Directory -Path $outDir -Force -ErrorAction Stop
} catch {
    Write-Error "SoftwareInventory: Failed to create output folder for '$outputFile': $_"
    exit 1
}

# The three registry paths together cover machine-wide 64-bit apps,
# machine-wide 32-bit apps (WOW6432Node), and apps installed for the current user only
try {
    Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*,
                    HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*,
                    HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* |
        Where-Object { $_.DisplayName } |
        Sort-Object DisplayName |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate |
        Format-Table -AutoSize -Wrap |
        Out-String -Width 4096 |
        Out-File -FilePath $outputFile -Encoding UTF8 -ErrorAction Stop
} catch {
    Write-Error "SoftwareInventory: Failed to write report to '$outputFile': $_"
    exit 1
}