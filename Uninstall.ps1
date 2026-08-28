<#Requires -Version 7.0>
<#
.SYNOPSIS
  Per-user uninstall for ScriptSuite — removes install root + Start Menu shortcut.

.DESCRIPTION
  Reverses Install.ps1. Removes:
    %LOCALAPPDATA%\Programs\ScriptSuite\
    %APPDATA%\Microsoft\Windows\Start Menu\Programs\ScriptSuite.lnk
  Leaves per-user data (%LOCALAPPDATA%\ScriptSuite\ — history.db, configs, etc.)
  intact. No admin.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "Programs\ScriptSuite"),
    [string]$ShortcutPath = (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\ScriptSuite.lnk")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "Uninstalling ScriptSuite (per-user)..." -ForegroundColor Cyan

if (Test-Path $ShortcutPath) {
    if ($PSCmdlet.ShouldProcess($ShortcutPath, "Remove shortcut")) {
        Remove-Item -LiteralPath $ShortcutPath -Force
        Write-Host "  removed shortcut $ShortcutPath"
    }
} else { Write-Host "  shortcut not present: $ShortcutPath" }

if (Test-Path $InstallDir) {
    if ($PSCmdlet.ShouldProcess($InstallDir, "Remove install dir")) {
        Remove-Item -LiteralPath $InstallDir -Recurse -Force
        Write-Host "  removed install dir $InstallDir"
    }
} else { Write-Host "  install dir not present: $InstallDir" }

Write-Host "  data preserved: $env:LOCALAPPDATA\ScriptSuite\ (history.db, configs)" -ForegroundColor Yellow
Write-Host "Done." -ForegroundColor Green
