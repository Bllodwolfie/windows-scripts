<#Requires -Version 7.0>
<#
.SYNOPSIS
  Uninstall for ScriptSuite — removes scheduled tasks, install root + Start Menu shortcut.

.DESCRIPTION
  Reverses Install.ps1. Removes:
    All \ScriptSuite\* scheduled tasks
    %ProgramFiles%\ScriptSuite\ (and old %LOCALAPPDATA%\Programs\ScriptSuite\ if present)
    %ProgramData%\Microsoft\Windows\Start Menu\Programs\ScriptSuite.lnk (and old per-user .lnk if present)
  Leaves per-user data (%LOCALAPPDATA%\ScriptSuite\ — history.db, configs, etc.)
  intact. Requires admin elevation (UAC prompt).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$InstallDir = (Join-Path $env:ProgramFiles "ScriptSuite"),
    [string]$ShortcutPath = (Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\ScriptSuite.lnk")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 0) UAC self-elevation check
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Elevating Uninstall.ps1 via UAC..." -ForegroundColor Yellow
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath)
    if ($PSBoundParameters.ContainsKey('InstallDir')) { $argList += @("-InstallDir", $InstallDir) }
    if ($PSBoundParameters.ContainsKey('ShortcutPath')) { $argList += @("-ShortcutPath", $ShortcutPath) }
    $proc = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $argList -Verb RunAs -PassThru -Wait
    exit $proc.ExitCode
}

Write-Host "Uninstalling ScriptSuite..." -ForegroundColor Cyan

# 1) Stop running processes
$running = Get-Process -Name "ScriptSuite" -ErrorAction SilentlyContinue
if ($running) {
    Write-Host "  stopping running ScriptSuite processes..."
    $running | Stop-Process -Force
    Start-Sleep -Milliseconds 500
}

# 2) Unregister scheduled tasks
$tasks = Get-ScheduledTask -TaskPath "\ScriptSuite\" -ErrorAction SilentlyContinue
foreach ($t in $tasks) {
    if ($PSCmdlet.ShouldProcess($t.TaskName, "Unregister scheduled task")) {
        Write-Host "  unregistered scheduled task $($t.TaskName)"
        Unregister-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -Confirm:$false
    }
}

# 3) Remove shortcuts
if (Test-Path $ShortcutPath) {
    if ($PSCmdlet.ShouldProcess($ShortcutPath, "Remove shortcut")) {
        Remove-Item -LiteralPath $ShortcutPath -Force
        Write-Host "  removed shortcut $ShortcutPath"
    }
} else { Write-Host "  shortcut not present: $ShortcutPath" }

$oldShortcut = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\ScriptSuite.lnk"
if (Test-Path $oldShortcut) {
    if ($PSCmdlet.ShouldProcess($oldShortcut, "Remove old per-user shortcut")) {
        Remove-Item -LiteralPath $oldShortcut -Force
        Write-Host "  removed old shortcut $oldShortcut"
    }
}

# 4) Remove install dir
if (Test-Path $InstallDir) {
    if ($PSCmdlet.ShouldProcess($InstallDir, "Remove install dir")) {
        Remove-Item -LiteralPath $InstallDir -Recurse -Force
        Write-Host "  removed install dir $InstallDir"
    }
} else { Write-Host "  install dir not present: $InstallDir" }

$oldInstall = Join-Path $env:LOCALAPPDATA "Programs\ScriptSuite"
if (Test-Path $oldInstall) {
    if ($PSCmdlet.ShouldProcess($oldInstall, "Remove old per-user install dir")) {
        Remove-Item -LiteralPath $oldInstall -Recurse -Force
        Write-Host "  removed old install dir $oldInstall"
    }
}

Write-Host "  data preserved: $env:LOCALAPPDATA\ScriptSuite\ (history.db, configs)" -ForegroundColor Yellow
Write-Host "Done." -ForegroundColor Green
