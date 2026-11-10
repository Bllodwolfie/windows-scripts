<#
.SYNOPSIS
  Uninstall for ScriptSuite — removes scheduled tasks, install root + Start Menu shortcut.

.DESCRIPTION
  Reverses Install.ps1. Removes:
    All scheduled tasks in specified task path (default: \ScriptSuite\*)
    %ProgramFiles%\ScriptSuite\ (and old %LOCALAPPDATA%\Programs\ScriptSuite\ if present)
    %ProgramData%\Microsoft\Windows\Start Menu\Programs\ScriptSuite.lnk (and old per-user .lnk if present)
  Leaves per-user data (%LOCALAPPDATA%\ScriptSuite\ — history.db, configs, etc.)
  intact. Requires admin elevation (UAC prompt).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$InstallDir,
    [string]$ShortcutPath,
    [string]$TaskPath = "\ScriptSuite\",
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Resolve script directory and script path without evaluating $PSScriptRoot in param()
$scriptDir = $PSScriptRoot
if (-not $scriptDir -and $MyInvocation.MyCommand.Path) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
if (-not $scriptDir) {
    $scriptDir = (Get-Location).Path
}

$scriptPath = $PSCommandPath
if (-not $scriptPath -and $MyInvocation.MyCommand.Path) {
    $scriptPath = $MyInvocation.MyCommand.Path
}
if (-not $scriptPath) {
    $scriptPath = Join-Path $scriptDir "Uninstall.ps1"
}

# Resolve defaults inside script body
if (-not $InstallDir) {
    $InstallDir = Join-Path $env:ProgramFiles "ScriptSuite"
}
if (-not $ShortcutPath) {
    $ShortcutPath = Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\ScriptSuite.lnk"
}
if ($TaskPath -and -not $TaskPath.EndsWith("\")) {
    $TaskPath = "$TaskPath\"
}

$logDir = Join-Path $env:ProgramData "ScriptSuite"
if (-not (Test-Path -LiteralPath $logDir)) {
    try { New-Item -ItemType Directory -Path $logDir -Force | Out-Null } catch { }
}
$logPath = Join-Path $logDir "uninstall.log"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Elevating Uninstall.ps1 via UAC..." -ForegroundColor Yellow
    $psExe = (Get-Process -Id $PID).Path
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $scriptPath)
    if ($PSBoundParameters.ContainsKey('InstallDir')) { $argList += @("-InstallDir", $InstallDir) }
    if ($PSBoundParameters.ContainsKey('ShortcutPath')) { $argList += @("-ShortcutPath", $ShortcutPath) }
    if ($PSBoundParameters.ContainsKey('TaskPath')) { $argList += @("-TaskPath", $TaskPath) }
    if ($NonInteractive) { $argList += "-NonInteractive" }

    $elevatedExitCode = 1
    try {
        $proc = Start-Process -FilePath $psExe -ArgumentList $argList -Verb RunAs -PassThru -Wait
        $elevatedExitCode = $proc.ExitCode
    } catch [System.ComponentModel.Win32Exception] {
        $win32Ex = $_.Exception -as [System.ComponentModel.Win32Exception]
        $errorCode = if ($win32Ex) { $win32Ex.NativeErrorCode } else { 0 }
        if ($errorCode -eq 1223) {
            Write-Host ""
            Write-Host "=== ScriptSuite Uninstallation Summary ===" -ForegroundColor Red
            Write-Host "  Result: FAIL (UAC prompt declined)" -ForegroundColor Red
            Write-Host "  Log:    $logPath" -ForegroundColor Gray
            if (-not $NonInteractive -and [Environment]::UserInteractive) {
                Write-Host ""
                Read-Host -Prompt "Press Enter to exit..."
            }
            exit 1223
        }
        Write-Host ""
        Write-Host "=== ScriptSuite Uninstallation Summary ===" -ForegroundColor Red
        Write-Host "  Result: FAIL ($($_.Exception.Message))" -ForegroundColor Red
        Write-Host "  Log:    $logPath" -ForegroundColor Gray
        if (-not $NonInteractive -and [Environment]::UserInteractive) {
            Write-Host ""
            Read-Host -Prompt "Press Enter to exit..."
        }
        exit 1
    }

    Write-Host ""
    Write-Host "=== ScriptSuite Uninstallation Summary ===" -ForegroundColor $(if ($elevatedExitCode -eq 0) { "Green" } else { "Red" })
    Write-Host "  Result: $(if ($elevatedExitCode -eq 0) { 'PASS' } else { 'FAIL' })" -ForegroundColor $(if ($elevatedExitCode -eq 0) { "Green" } else { "Red" })
    Write-Host "  Log:    $logPath" -ForegroundColor Gray
    if (-not $NonInteractive -and [Environment]::UserInteractive) {
        Write-Host ""
        Read-Host -Prompt "Press Enter to exit..."
    }
    exit $elevatedExitCode
}

# Elevated uninstaller
function Write-UninstallLog {
    param(
        [string]$Message,
        [string]$ForegroundColor,
        [switch]$Warning,
        [switch]$Error
    )
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $logLine = "[$timestamp] $Message"
    try {
        Add-Content -LiteralPath $logPath -Value $logLine -Encoding utf8 -ErrorAction SilentlyContinue
    } catch { }

    if ($Warning) {
        Write-Warning $Message
    } elseif ($Error) {
        Write-Host $Message -ForegroundColor Red
    } elseif ($ForegroundColor) {
        Write-Host $Message -ForegroundColor $ForegroundColor
    } else {
        Write-Host $Message
    }
}

try {
    Set-Content -LiteralPath $logPath -Value "=== ScriptSuite Uninstall Log: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" -Encoding utf8 -Force
} catch { }

try {
    Write-UninstallLog "Uninstalling ScriptSuite..." -ForegroundColor Cyan

    # 1) Stop running processes
    $running = Get-Process -Name "ScriptSuite" -ErrorAction SilentlyContinue
    if ($running) {
        Write-UninstallLog "  Stopping running ScriptSuite processes..."
        $running | Stop-Process -Force
        Start-Sleep -Milliseconds 500
    }

    # 2) Unregister scheduled tasks and clean matching entries from schedules.json
    $tasks = Get-ScheduledTask -TaskPath $TaskPath -ErrorAction SilentlyContinue
    $unregisteredCount = 0
    $unregisteredTaskNames = [System.Collections.Generic.List[string]]::new()

    foreach ($t in $tasks) {
        if ($PSCmdlet.ShouldProcess($t.TaskName, "Unregister scheduled task")) {
            Write-UninstallLog "  Unregistered scheduled task $($t.TaskName)"
            Unregister-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -Confirm:$false
            $unregisteredTaskNames.Add($t.TaskName)
            $unregisteredCount++
        }
    }

    $schedulesPath = Join-Path $env:LOCALAPPDATA "ScriptSuite\schedules.json"
    if ($unregisteredTaskNames.Count -gt 0 -and (Test-Path -LiteralPath $schedulesPath)) {
        try {
            $rawJson = Get-Content -LiteralPath $schedulesPath -Raw
            $schedObj = $rawJson | ConvertFrom-Json
            if ($null -eq $schedObj -or $schedObj -isnot [System.Management.Automation.PSCustomObject]) {
                Write-UninstallLog "schedules.json is malformed or not an object; skipping schedule entry removal." -Warning
            } else {
                $modified = $false
                foreach ($tName in $unregisteredTaskNames) {
                    $propToRemove = $null
                    foreach ($prop in $schedObj.PSObject.Properties) {
                        if ($prop.Name -eq $tName -or ($prop.Value -and $prop.Value.scriptId -eq $tName)) {
                            $propToRemove = $prop.Name
                            break
                        }
                    }
                    if ($propToRemove) {
                        if ($PSCmdlet.ShouldProcess($propToRemove, "Remove schedule entry from schedules.json")) {
                            $schedObj.PSObject.Properties.Remove($propToRemove)
                            $modified = $true
                            Write-UninstallLog "  Removed schedule entry for $propToRemove from schedules.json"
                        }
                    }
                }

                if ($modified) {
                    $bakPath = "$schedulesPath.bak"
                    Copy-Item -LiteralPath $schedulesPath -Destination $bakPath -Force
                    $newJson = $schedObj | ConvertTo-Json -Depth 10
                    Set-Content -LiteralPath $schedulesPath -Value $newJson -Encoding utf8
                }
            }
        } catch {
            Write-UninstallLog "Failed to update schedules.json: $($_.Exception.Message)" -Warning
        }
    }

    # 3) Remove shortcuts
    $shortcutRemoved = "Not present"
    if (Test-Path -LiteralPath $ShortcutPath) {
        if ($PSCmdlet.ShouldProcess($ShortcutPath, "Remove shortcut")) {
            Remove-Item -LiteralPath $ShortcutPath -Force
            Write-UninstallLog "  Removed shortcut $ShortcutPath"
            $shortcutRemoved = "Removed"
        }
    }

    $oldShortcut = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\ScriptSuite.lnk"
    if (Test-Path -LiteralPath $oldShortcut) {
        if ($PSCmdlet.ShouldProcess($oldShortcut, "Remove old per-user shortcut")) {
            Remove-Item -LiteralPath $oldShortcut -Force
            Write-UninstallLog "  Removed old shortcut $oldShortcut"
        }
    }

    # 4) Remove install dir
    $installDirRemoved = "Not present"
    if (Test-Path -LiteralPath $InstallDir) {
        if ($PSCmdlet.ShouldProcess($InstallDir, "Remove install dir")) {
            Remove-Item -LiteralPath $InstallDir -Recurse -Force
            Write-UninstallLog "  Removed install dir $InstallDir"
            $installDirRemoved = "Removed"
        }
    }

    $oldInstall = Join-Path $env:LOCALAPPDATA "Programs\ScriptSuite"
    if (Test-Path -LiteralPath $oldInstall) {
        if ($PSCmdlet.ShouldProcess($oldInstall, "Remove old per-user install dir")) {
            Remove-Item -LiteralPath $oldInstall -Recurse -Force
            Write-UninstallLog "  Removed old install dir $oldInstall"
        }
    }

    # Verification
    if (Test-Path -LiteralPath $InstallDir) {
        throw "Verification failed: Install directory still exists after removal: $InstallDir"
    }
    if (Test-Path -LiteralPath $ShortcutPath) {
        throw "Verification failed: Shortcut still exists after removal: $ShortcutPath"
    }

    Write-UninstallLog "  Data preserved: $env:LOCALAPPDATA\ScriptSuite\ (history.db, configs)"
    Write-Host ""
    Write-Host "=== ScriptSuite Uninstallation Summary ===" -ForegroundColor Green
    Write-Host "  Tasks Removed:    $unregisteredCount"
    Write-Host "  Shortcut:         $shortcutRemoved"
    Write-Host "  Install Dir:      $installDirRemoved"
    Write-Host "  Data Preserved:   $env:LOCALAPPDATA\ScriptSuite\"
    Write-Host "  Result:           PASS" -ForegroundColor Green
    Write-Host "  Log:              $logPath" -ForegroundColor Gray

    Write-UninstallLog "=== ScriptSuite Uninstallation Summary ==="
    Write-UninstallLog "  Tasks Removed:    $unregisteredCount"
    Write-UninstallLog "  Shortcut:         $shortcutRemoved"
    Write-UninstallLog "  Install Dir:      $installDirRemoved"
    Write-UninstallLog "  Data Preserved:   $env:LOCALAPPDATA\ScriptSuite\"
    Write-UninstallLog "  Result:           PASS"
    Write-UninstallLog "  Log:              $logPath"

    if (-not $NonInteractive -and [Environment]::UserInteractive) {
        Write-Host ""
        Read-Host -Prompt "Press Enter to exit..."
    }
    exit 0
} catch {
    $err = $_.Exception.Message
    Write-UninstallLog "ERROR: $err" -Error
    Write-Host ""
    Write-Host "=== ScriptSuite Uninstallation Summary ===" -ForegroundColor Red
    Write-Host "  Result: FAIL ($err)" -ForegroundColor Red
    Write-Host "  Log:    $logPath" -ForegroundColor Gray

    Write-UninstallLog "=== ScriptSuite Uninstallation Summary ==="
    Write-UninstallLog "  Result: FAIL"
    Write-UninstallLog "  Error:  $err"
    Write-UninstallLog "  Log:    $logPath"

    if (-not $NonInteractive -and [Environment]::UserInteractive) {
        Write-Host ""
        Read-Host -Prompt "Press Enter to exit..."
    }
    exit 1
}
