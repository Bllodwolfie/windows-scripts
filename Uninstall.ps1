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
    [string]$RegistryRoot = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    [string]$LogPath,
    [switch]$Child,
    [switch]$FromTemp,
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
if (-not $RegistryRoot) {
    $RegistryRoot = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
}
if ($RegistryRoot -match '^(HKLM|HKCU)\\' -and $RegistryRoot -notmatch '^[A-Za-z]+:\\') {
    $RegistryRoot = $RegistryRoot -replace '^([A-Za-z]+)\\', '$1:\'
}
$uninstallKey = if ($RegistryRoot -match '\\ScriptSuite$') {
    $RegistryRoot
} else {
    Join-Path $RegistryRoot "ScriptSuite"
}

function Format-QuotedArgument {
    param([string]$ArgValue)
    if ([string]::IsNullOrEmpty($ArgValue)) { return '""' }
    if ($ArgValue.EndsWith('\')) {
        return "`"$($ArgValue)\`""
    }
    return "`"$ArgValue`""
}

# Setup log path early and write initial log line so early failures leave evidence
if (-not $LogPath) {
    $logDir = Join-Path $env:ProgramData "ScriptSuite"
    if (-not (Test-Path -LiteralPath $logDir)) {
        try { New-Item -ItemType Directory -Path $logDir -Force | Out-Null } catch { }
    }
    if (-not (Test-Path -LiteralPath $logDir) -and $env:LOCALAPPDATA) {
        $logDir = Join-Path $env:LOCALAPPDATA "ScriptSuite"
        if (-not (Test-Path -LiteralPath $logDir)) {
            try { New-Item -ItemType Directory -Path $logDir -Force | Out-Null } catch { }
        }
    }
    $logPath = Join-Path $logDir "uninstall.log"

    $canWriteLog = $false
    try {
        [System.IO.File]::AppendAllText($logPath, "")
        $canWriteLog = $true
    } catch {
        $canWriteLog = $false
    }
    if (-not $canWriteLog -and $env:LOCALAPPDATA) {
        $userLogDir = Join-Path $env:LOCALAPPDATA "ScriptSuite"
        if (-not (Test-Path -LiteralPath $userLogDir)) {
            try { New-Item -ItemType Directory -Path $userLogDir -Force | Out-Null } catch { }
        }
        $logPath = Join-Path $userLogDir "uninstall.log"
    }
} else {
    $logPath = $LogPath
    $parentLogDir = Split-Path -Parent $logPath
    if ($parentLogDir -and -not (Test-Path -LiteralPath $parentLogDir)) {
        try { New-Item -ItemType Directory -Path $parentLogDir -Force | Out-Null } catch { }
    }
}

# Cap log growth if top-level invocation (not -FromTemp and not an elevated child) and log file > 256 KB
if (-not $FromTemp -and -not $Child) {
    try {
        if (Test-Path -LiteralPath $logPath) {
            $logItem = Get-Item -LiteralPath $logPath -ErrorAction SilentlyContinue
            if ($logItem -and $logItem.Length -gt 256KB) {
                $tailLines = Get-Content -LiteralPath $logPath -Tail 100 -ErrorAction SilentlyContinue
                if ($tailLines) {
                    $trimNote = "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] === Log capped (log trimmed, previous size: $([math]::Round($logItem.Length / 1KB)) KB) ==="
                    $trimmedContent = @($trimNote) + $tailLines
                    Set-Content -LiteralPath $logPath -Value $trimmedContent -Encoding utf8 -Force -ErrorAction SilentlyContinue
                }
            }
        }
    } catch { }
}

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

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-UninstallLog "=== ScriptSuite Uninstall started (PID $PID, Admin: $isAdmin, FromTemp: $([bool]$FromTemp), Interactive: $(-not $NonInteractive)) ==="

trap {
    $err = $_.Exception.Message
    try {
        Write-UninstallLog "FATAL: $err" -Error
        Write-UninstallLog "=== ScriptSuite Uninstallation Summary ==="
        Write-UninstallLog "  Result:           FAIL"
        Write-UninstallLog "  Error:            $err"
        Write-UninstallLog "  Log:              $logPath"
    } catch { }
    Write-Host "Uninstall error: $err" -ForegroundColor Red
    exit 1
}

$needsElevation = $false
$programFilesRoot = if ($env:ProgramFiles) { [System.IO.Path]::GetFullPath($env:ProgramFiles) } else { "" }
$programDataRoot = if ($env:ProgramData) { [System.IO.Path]::GetFullPath($env:ProgramData) } else { "" }

if ($InstallDir) {
    try {
        $fullInstall = [System.IO.Path]::GetFullPath($InstallDir)
        if ($programFilesRoot -and $fullInstall.StartsWith($programFilesRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            $needsElevation = $true
        }
    } catch { $needsElevation = $true }
} else {
    $needsElevation = $true
}

if ($ShortcutPath) {
    try {
        $fullShortcut = [System.IO.Path]::GetFullPath($ShortcutPath)
        if ($programDataRoot -and $fullShortcut.StartsWith($programDataRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            $needsElevation = $true
        }
    } catch { }
}

if ($RegistryRoot -match '^HKLM' -or $uninstallKey -match '^HKLM') {
    $needsElevation = $true
}
if ($TaskPath -eq "\ScriptSuite\" -or $TaskPath -eq "\ScriptSuite") {
    $needsElevation = $true
}

# Check if running from inside the install directory that is being uninstalled
$resolvedInstall = Resolve-Path -LiteralPath $InstallDir -ErrorAction SilentlyContinue
$realInstallDir = if ($resolvedInstall) { $resolvedInstall.Path } else { $InstallDir }
$resolvedScript = Resolve-Path -LiteralPath $scriptDir -ErrorAction SilentlyContinue
$realScriptDir = if ($resolvedScript) { $resolvedScript.Path } else { $scriptDir }

$isUnderInstallDir = $false
if ($realInstallDir -and $realScriptDir) {
    $normInstall = $realInstallDir.TrimEnd('\')
    $normScript = $realScriptDir.TrimEnd('\')
    if ($normScript.Equals($normInstall, [System.StringComparison]::OrdinalIgnoreCase) -or
        $normScript.StartsWith("$normInstall\", [System.StringComparison]::OrdinalIgnoreCase)) {
        $isUnderInstallDir = $true
    }
}

# If running from inside $InstallDir, copy to a temp directory and re-launch from temp
if ($isUnderInstallDir -and -not $FromTemp) {
    $tempDir = Join-Path $env:TEMP "ScriptSuite-Uninstall-$([Guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    $tempScript = Join-Path $tempDir "Uninstall.ps1"
    Copy-Item -LiteralPath $scriptPath -Destination $tempScript -Force

    $psExe = (Get-Process -Id $PID).Path
    $argParts = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Format-QuotedArgument $tempScript))
    $argParts += @("-InstallDir", (Format-QuotedArgument $InstallDir))
    if ($PSBoundParameters.ContainsKey('ShortcutPath')) { $argParts += @("-ShortcutPath", (Format-QuotedArgument $ShortcutPath)) }
    if ($PSBoundParameters.ContainsKey('TaskPath')) { $argParts += @("-TaskPath", (Format-QuotedArgument $TaskPath)) }
    if ($PSBoundParameters.ContainsKey('RegistryRoot')) { $argParts += @("-RegistryRoot", (Format-QuotedArgument $RegistryRoot)) }
    if ($PSBoundParameters.ContainsKey('LogPath')) { $argParts += @("-LogPath", (Format-QuotedArgument $LogPath)) }
    if ($NonInteractive) { $argParts += "-NonInteractive" }
    $argParts += "-FromTemp"
    $argParts += "-Child"
    $argString = $argParts -join " "

    Set-Location $env:TEMP
    [System.IO.Directory]::SetCurrentDirectory($env:TEMP)

    $elevatedExitCode = 1
    try {
        $procArgs = @{
            FilePath = $psExe
            ArgumentList = $argString
            PassThru = $true
            Wait = $true
        }
        if ($needsElevation -and -not $isAdmin) {
            Write-Host "Elevating Uninstall.ps1 via UAC from temp copy..." -ForegroundColor Yellow
            $procArgs["Verb"] = "RunAs"
        } else {
            Write-Host "Re-launching Uninstall.ps1 from temp copy..." -ForegroundColor Yellow
        }
        $proc = Start-Process @procArgs
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
    } finally {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host ""
    Write-Host "=== ScriptSuite Uninstallation Summary ===" -ForegroundColor $(if ($elevatedExitCode -eq 0) { "Green" } else { "Red" })
    Write-Host "  Result: $(if ($elevatedExitCode -eq 0) { 'PASS' } else { 'FAIL' })" -ForegroundColor $(if ($elevatedExitCode -eq 0) { "Green" } else { "Red" })
    Write-Host "  Log:    $logPath" -ForegroundColor Gray
    if ($elevatedExitCode -ne 0) {
        Write-UninstallLog "Elevated uninstallation failed with exit code $elevatedExitCode" -Error
    }
    if (-not $NonInteractive -and [Environment]::UserInteractive) {
        Write-Host ""
        Read-Host -Prompt "Press Enter to exit..."
    }
    exit $elevatedExitCode
}

# Standard elevation if running outside $InstallDir and not admin
if ($needsElevation -and -not $isAdmin) {
    Write-Host "Elevating Uninstall.ps1 via UAC..." -ForegroundColor Yellow
    $psExe = (Get-Process -Id $PID).Path
    $argParts = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Format-QuotedArgument $scriptPath))
    if ($PSBoundParameters.ContainsKey('InstallDir')) { $argParts += @("-InstallDir", (Format-QuotedArgument $InstallDir)) }
    if ($PSBoundParameters.ContainsKey('ShortcutPath')) { $argParts += @("-ShortcutPath", (Format-QuotedArgument $ShortcutPath)) }
    if ($PSBoundParameters.ContainsKey('TaskPath')) { $argParts += @("-TaskPath", (Format-QuotedArgument $TaskPath)) }
    if ($PSBoundParameters.ContainsKey('RegistryRoot')) { $argParts += @("-RegistryRoot", (Format-QuotedArgument $RegistryRoot)) }
    if ($PSBoundParameters.ContainsKey('LogPath')) { $argParts += @("-LogPath", (Format-QuotedArgument $LogPath)) }
    if ($FromTemp) { $argParts += "-FromTemp" }
    if ($NonInteractive) { $argParts += "-NonInteractive" }
    $argParts += "-Child"
    $argString = $argParts -join " "

    $elevatedExitCode = 1
    try {
        $proc = Start-Process -FilePath $psExe -ArgumentList $argString -Verb RunAs -PassThru -Wait
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
    if ($elevatedExitCode -ne 0) {
        Write-UninstallLog "Elevated uninstallation failed with exit code $elevatedExitCode" -Error
    }
    if (-not $NonInteractive -and [Environment]::UserInteractive) {
        Write-Host ""
        Read-Host -Prompt "Press Enter to exit..."
    }
    exit $elevatedExitCode
}

# Elevated uninstaller execution
Write-UninstallLog "=== ScriptSuite Uninstall Execution ==="

try {
    Set-Location $env:TEMP
    [System.IO.Directory]::SetCurrentDirectory($env:TEMP)
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

    # 5) Remove Installed apps registry key
    $registryRemoved = "Not present"
    if (Test-Path -LiteralPath $uninstallKey) {
        if ($PSCmdlet.ShouldProcess($uninstallKey, "Remove Installed apps registry key")) {
            Remove-Item -LiteralPath $uninstallKey -Recurse -Force
            Write-UninstallLog "  Removed registry key $uninstallKey"
            $registryRemoved = "Removed"
        }
    }

    # Verification
    if (Test-Path -LiteralPath $InstallDir) {
        throw "Verification failed: Install directory still exists after removal: $InstallDir"
    }
    if (Test-Path -LiteralPath $ShortcutPath) {
        throw "Verification failed: Shortcut still exists after removal: $ShortcutPath"
    }
    if (Test-Path -LiteralPath $uninstallKey) {
        throw "Verification failed: Registry key still exists after removal: $uninstallKey"
    }

    Write-UninstallLog "  Data preserved: $env:LOCALAPPDATA\ScriptSuite\ (history.db, configs)"
    Write-Host ""
    Write-Host "=== ScriptSuite Uninstallation Summary ===" -ForegroundColor Green
    Write-Host "  Tasks Removed:    $unregisteredCount"
    Write-Host "  Shortcut:         $shortcutRemoved"
    Write-Host "  Install Dir:      $installDirRemoved"
    Write-Host "  Registry Key:     $registryRemoved"
    Write-Host "  Data Preserved:   $env:LOCALAPPDATA\ScriptSuite\"
    Write-Host "  Result:           PASS" -ForegroundColor Green
    Write-Host "  Log:              $logPath" -ForegroundColor Gray

    Write-UninstallLog "=== ScriptSuite Uninstallation Summary ==="
    Write-UninstallLog "  Tasks Removed:    $unregisteredCount"
    Write-UninstallLog "  Shortcut:         $shortcutRemoved"
    Write-UninstallLog "  Install Dir:      $installDirRemoved"
    Write-UninstallLog "  Registry Key:     $registryRemoved"
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
