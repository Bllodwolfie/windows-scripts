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
    $clean = $Path.Trim().Trim('"', "'")
    $expanded = [Environment]::ExpandEnvironmentVariables($clean)
    if (-not [System.IO.Path]::IsPathRooted($expanded)) { Write-Error "Path must be absolute: $Path"; exit 1 }

    try { $full = [System.IO.Path]::GetFullPath($expanded) } catch { $full = $expanded }
    $norm = $full.TrimEnd('\')

    # Denylist check: hard-abort with exit 1 regardless of elevation if path EQUALS or is an ancestor of:
    # drive root, %SystemRoot%, %ProgramFiles%, %ProgramFiles(x86)%, %ProgramData%, %USERPROFILE%, %APPDATA%, %LOCALAPPDATA%, %LOCALAPPDATA%\ScriptSuite, install dir
    $driveRoot = [System.IO.Path]::GetPathRoot($full)
    if (-not [string]::IsNullOrEmpty($driveRoot) -and $norm.Equals($driveRoot.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
        Write-Error "Path '$clean' is a drive root — aborting."
        exit 1
    }

    $deniedTargets = [System.Collections.Generic.List[string]]::new()
    $envVars = @(
        $env:SystemRoot,
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:ProgramData,
        $env:USERPROFILE,
        $env:APPDATA,
        $env:LOCALAPPDATA
    )
    foreach ($ev in $envVars) {
        if (-not [string]::IsNullOrWhiteSpace($ev)) {
            try { $deniedTargets.Add([System.IO.Path]::GetFullPath($ev).TrimEnd('\')) } catch {}
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        try { $deniedTargets.Add([System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA "ScriptSuite")).TrimEnd('\')) } catch {}
    }
    try {
        $parentInstall = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..")).TrimEnd('\')
        if (-not $deniedTargets.Contains($parentInstall)) { $deniedTargets.Add($parentInstall) }
    } catch {}
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        try {
            $pfInstall = [System.IO.Path]::GetFullPath((Join-Path $env:ProgramFiles "ScriptSuite")).TrimEnd('\')
            if (-not $deniedTargets.Contains($pfInstall)) { $deniedTargets.Add($pfInstall) }
        } catch {}
    }

    foreach ($d in $deniedTargets) {
        if ($norm.Equals($d, [StringComparison]::OrdinalIgnoreCase) -or
            $d.StartsWith($norm + [System.IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            Write-Error "Path '$clean' is denylisted or an ancestor of protected path '$d' — aborting."
            exit 1
        }
    }

    if ($ExpectedRoot) {
        $exp = [Environment]::ExpandEnvironmentVariables($ExpectedRoot.Trim().Trim('"', "'"))
        try { $root = [System.IO.Path]::GetFullPath($exp).TrimEnd('\') } catch { $root = $exp.TrimEnd('\') }
        $isInside = $norm.Equals($root, [StringComparison]::OrdinalIgnoreCase) -or
                    $norm.StartsWith($root + [System.IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
        if (-not $isInside) {
            $isElevated = if ($env:SCRIPTSUITE_FORCE_NONELEVATED -eq "1") { $false } else { ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
            if ($isElevated) {
                Write-Error "Path '$clean' is outside expected scope (expected under '$ExpectedRoot') — aborting (elevated execution)"
                exit 1
            } else {
                Write-Warning "Path '$clean' is outside expected scope (expected under '$ExpectedRoot') — proceeding anyway"
            }
        }
    }
    if ($clean -match '[\. ]$') { Write-Warning "Trailing space/dot will be stripped by Windows: '$clean'" }
}

# JSON stores env-var paths as "%USERPROFILE%\..."; expand them at load time.
function Expand-ConfigPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"', "'"))
}

$outputFile = Expand-ConfigPath $Config.OutputFile
Test-PathScope $outputFile "$env:USERPROFILE"

# Validate OutputFile: denylist on parent dir, and refuse to overwrite existing file with different extension
try {
    $outDir = Split-Path $outputFile -Parent
    if ([string]::IsNullOrWhiteSpace($outDir)) { $outDir = "." }
    $outDirFull = [System.IO.Path]::GetFullPath($outDir)
    Test-PathScope $outDirFull "$env:USERPROFILE"

    if (Test-Path -LiteralPath $outDir) {
        $item = Get-Item -LiteralPath $outDir -ErrorAction SilentlyContinue
        if ($null -ne $item -and -not $item.PSIsContainer) {
            throw "OutputFile parent is not a folder (is a file): $outDir"
        }
    }
    if (Test-Path -LiteralPath $outputFile) {
        $targetItem = Get-Item -LiteralPath $outputFile -ErrorAction SilentlyContinue
        if ($null -ne $targetItem) {
            if ($targetItem.PSIsContainer) {
                throw "OutputFile is a folder, not a file: $outputFile"
            }
            $scriptExt = ".txt"
            $existingExt = [System.IO.Path]::GetExtension($targetItem.FullName)
            if (-not $existingExt.Equals($scriptExt, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Refusing to overwrite existing file with differing extension '$existingExt' (expected '$scriptExt')"
            }
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