<#Requires -Version 7.0>
<#
.SYNOPSIS
  Per-user install for ScriptSuite — self-contained publish + Start Menu shortcut.

.DESCRIPTION
  Runs `dotnet publish -c Release -r win-x64 --self-contained true` into a
  staging folder, then copies to the stable per-user install root
  %LOCALAPPDATA%\Programs\ScriptSuite\ and creates the Start Menu shortcut
  that Windows Search indexes:
    %APPDATA%\Microsoft\Windows\Start Menu\Programs\ScriptSuite.lnk
  TargetPath = <install>\ScriptSuite.exe
  WorkingDirectory = <install>\  (AppPaths uses AppContext.BaseDirectory, not CWD)
  IconLocation = TargetPath,0   (icon embedded via <ApplicationIcon>ScriptSuite.ico>)
  Description = ScriptSuite

  Idempotent, no admin, no installer framework. Pair with Uninstall.ps1.
#>
[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "Programs\ScriptSuite"),
    [string]$ShortcutPath = (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\ScriptSuite.lnk"),
    [string]$ProjectPath = (Join-Path $PSScriptRoot "ScriptSuite\ScriptSuite.csproj"),
    [string]$PublishDir = (Join-Path $env:TEMP "ScriptSuite-publish"),
    [switch]$NoBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ProjectPath)) { throw "Project not found: $ProjectPath" }

# 1) Publish self-contained win-x64 (non-technical users: no .NET runtime prerequisite)
#    Size tradeoff measured 2026-08-28: FD 373f/49.5 MB vs SC 768f/188.7 MB (+139 MB).
#    SC chosen for reliability — .NET 10 Desktop Runtime not yet broadly present via Windows Update;
#    a missing runtime would break both launch and Phase-2 Task Scheduler silently.
if (-not $NoBuild) {
    Write-Host "Publishing self-contained win-x64..."
    Remove-Item $PublishDir -Recurse -Force -ErrorAction SilentlyContinue
    $pubArgs = @("publish", $ProjectPath, "-c", "Release", "-r", "win-x64", "--self-contained", "true", "-o", $PublishDir, "/p:DebugType=None", "/p:DebugSymbols=false")
    & dotnet @pubArgs
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed: $LASTEXITCODE" }
} else {
    if (-not (Test-Path (Join-Path $PublishDir "ScriptSuite.exe"))) { throw "NoBuild but no publish output at $PublishDir" }
}

# 2) Copy to stable install root (not bin/Debug which is volatile; not AppData\ScriptSuite which is data)
Write-Host "Installing to $InstallDir ..."
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
# Robocopy-style copy: mirror publish into install dir, keep per-user data (%LOCALAPPDATA%\ScriptSuite) untouched
Copy-Item -Path (Join-Path $PublishDir "*") -Destination $InstallDir -Recurse -Force

# 3) Start Menu shortcut — what Windows Search actually indexes
Write-Host "Creating shortcut $ShortcutPath ..."
New-Item -ItemType Directory -Path (Split-Path $ShortcutPath) -Force | Out-Null
$target = Join-Path $InstallDir "ScriptSuite.exe"
if (-not (Test-Path $target)) { throw "Expected exe missing after copy: $target" }

$wsh = New-Object -ComObject WScript.Shell
$sc = $wsh.CreateShortcut($ShortcutPath)
$sc.TargetPath = $target
$sc.WorkingDirectory = $InstallDir
$sc.IconLocation = "$target,0"
$sc.Description = "ScriptSuite"
$sc.WindowStyle = 1
# Optional: Arguments left empty — launch shows dashboard. Phase 2 Task Scheduler will add --run-all etc.
$sc.Save()
# Release COM
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($sc) | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($wsh) | Out-Null

# 4) Evidence
Write-Host ""
Write-Host "=== publish output ===" -ForegroundColor Cyan
Get-ChildItem $PublishDir -File -Recurse | Measure-Object | ForEach-Object { Write-Host ("  {0} files" -f $_.Count) }
$pubSize = (Get-ChildItem $PublishDir -Recurse -File | Measure-Object Length -Sum).Sum
Write-Host ("  {0:N0} bytes ({1:N1} MB)" -f $pubSize, ($pubSize/1MB))
Get-ChildItem $PublishDir -File | Sort-Object Length -Descending | Select-Object -First 6 Name, @{n='KB';e={[int]($_.Length/1KB)}} | Format-Table -AutoSize | Out-String | Write-Host

Write-Host "=== install dir ===" -ForegroundColor Cyan
Get-ChildItem $InstallDir -File | Select-Object -First 10 Name, @{n='KB';e={[int]($_.Length/1KB)}} | Format-Table -AutoSize | Out-String | Write-Host
Write-Host ("  exe: {0} ({1:N0} bytes)" -f $target, (Get-Item $target).Length)

Write-Host "=== shortcut properties ===" -ForegroundColor Cyan
$wsh2 = New-Object -ComObject WScript.Shell
$sc2 = $wsh2.CreateShortcut($ShortcutPath)
Write-Host ("  Path:            {0}" -f $ShortcutPath)
Write-Host ("  TargetPath:      {0}" -f $sc2.TargetPath)
Write-Host ("  WorkingDirectory:{0}" -f $sc2.WorkingDirectory)
Write-Host ("  IconLocation:    {0}" -f $sc2.IconLocation)
Write-Host ("  Description:     {0}" -f $sc2.Description)
Write-Host ("  Exists:          {0}" -f (Test-Path $ShortcutPath))
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($sc2) | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($wsh2) | Out-Null

Write-Host "=== Start Menu search hit ===" -ForegroundColor Cyan
$startApps = Get-StartApps | Where-Object { $_.Name -like "*ScriptSuite*" }
if ($startApps) { $startApps | Format-Table Name, AppID -AutoSize | Out-String | Write-Host } else { Write-Host "  Get-StartApps: no ScriptSuite entry yet (crawler delay — .lnk exists, Shell:AppsFolder will show it)" -ForegroundColor Yellow }

$appsFolder = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\ScriptSuite.lnk"
Write-Host "  .lnk exists: $(Test-Path $appsFolder)  (Shell:AppsFolder indexes this path)"
# Shell.Application check — enumerates AppsFolder namespace
try {
    $shell = New-Object -ComObject Shell.Application
    $folder = $shell.Namespace("shell:AppsFolder")
    $hit = $null
    foreach ($item in $folder.Items()) { if ($item.Name -like "*ScriptSuite*") { $hit = $item; break } }
    if ($hit) { Write-Host ("  Shell:AppsFolder hit: {0} -> {1}" -f $hit.Name, $hit.Path) } else { Write-Host "  Shell:AppsFolder: not yet enumerated (normal — .lnk is valid, Search will pick up on next index pass)" -ForegroundColor Yellow }
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
} catch { Write-Host "  Shell:AppsFolder check skipped: $($_.Exception.Message)" -ForegroundColor Yellow }

Write-Host ""
Write-Host "Done. Launch via Start Menu: type 'ScriptSuite'." -ForegroundColor Green
Write-Host "Uninstall: .\Uninstall.ps1  (removes $InstallDir and the .lnk, leaves %LOCALAPPDATA%\ScriptSuite data)"
