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
    $Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
}

# JSON stores env-var paths as "%USERPROFILE%\..."; expand them at load time.
function Expand-ConfigPath([string]$Path) {
    [Environment]::ExpandEnvironmentVariables($Path)
}

$outputFile = Expand-ConfigPath $Config.OutputFile

# Ensure the Script_Logs folder exists before writing (same guard the other
# scripts in this suite use), in case this runs before any cleanup script
$null = New-Item -ItemType Directory -Path (Split-Path $outputFile) -Force -ErrorAction SilentlyContinue

# The three registry paths together cover machine-wide 64-bit apps,
# machine-wide 32-bit apps (WOW6432Node), and apps installed for the current user only
Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*,
                HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*,
                HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* |
    Where-Object { $_.DisplayName } |          # Skip registry entries with no display name (not real apps)
    Sort-Object DisplayName |
    Select-Object DisplayName, DisplayVersion, Publisher, InstallDate |
    Format-Table -AutoSize -Wrap |
    Out-String -Width 4096 |                    # Wide width avoids truncating long app names/columns
    Out-File -FilePath $outputFile -Encoding UTF8