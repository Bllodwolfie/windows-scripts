<#
.SYNOPSIS
  Install for ScriptSuite — self-contained publish + Start Menu shortcut.

.DESCRIPTION
  Runs `dotnet publish -c Release -r win-x64 --self-contained true` into a
  staging folder (or uses prebuilt exe if present), then copies to the secure
  system install root %ProgramFiles%\ScriptSuite\ and creates the Start Menu shortcut
  that Windows Search indexes:
    %ProgramData%\Microsoft\Windows\Start Menu\Programs\ScriptSuite.lnk
  TargetPath = <install>\ScriptSuite.exe
  WorkingDirectory = <install>\  (AppPaths uses AppContext.BaseDirectory, not CWD)
  IconLocation = TargetPath,0   (icon embedded via <ApplicationIcon>ScriptSuite.ico>)
  Description = ScriptSuite

  SEC-02: Installing to %ProgramFiles% ensures write access is restricted to
  Administrators and SYSTEM. Standard users cannot tamper with executables or
  PowerShell scripts invoked by elevated scheduled tasks. Requires one UAC prompt.
  Re-points any existing \ScriptSuite\* scheduled tasks from old per-user paths.
  Leaves per-user data (%LOCALAPPDATA%\ScriptSuite) untouched. Pair with Uninstall.ps1.
#>
[CmdletBinding()]
param(
    [string]$InstallDir,
    [string]$ShortcutPath,
    [string]$ProjectPath,
    [string]$PublishDir,
    [string]$TaskPath = "\ScriptSuite\",
    [string]$RegistryRoot = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    [switch]$Child,
    [switch]$NoBuild,
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
    $scriptPath = Join-Path $scriptDir "Install.ps1"
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

# 0) Setup log path early and write initial log line so early failures leave evidence
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
$logPath = Join-Path $logDir "install.log"

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
    $logPath = Join-Path $userLogDir "install.log"
}

# Cap log growth if top-level invocation (not an elevated child launched by parent) and log file > 256 KB
if (-not $Child) {
    try {
        if (Test-Path -LiteralPath $logPath) {
            $logItem = Get-Item -LiteralPath $logPath -ErrorAction SilentlyContinue
            if ($logItem -and $logItem.Length -gt 256KB) {
                $tailLines = Get-Content -LiteralPath $logPath -Tail 100 -Encoding utf8 -ErrorAction SilentlyContinue
                if ($tailLines) {
                    $trimNote = "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] === Log capped (log trimmed, previous size: $([math]::Round($logItem.Length / 1KB)) KB) ==="
                    $tailText = ($tailLines -join "`r`n")
                    $utf8 = [System.Text.Encoding]::UTF8
                    $maxTailBytes = [int](256KB - $utf8.GetByteCount($trimNote) - 8192)
                    $tailBytes = $utf8.GetBytes($tailText)
                    if ($tailBytes.Length -gt $maxTailBytes) {
                        $startIndex = $tailBytes.Length - $maxTailBytes
                        while ($startIndex -lt $tailBytes.Length -and ($tailBytes[$startIndex] -ge 0x80 -and $tailBytes[$startIndex] -le 0xBF)) {
                            $startIndex++
                        }
                        $tailText = $utf8.GetString($tailBytes, $startIndex, $tailBytes.Length - $startIndex)
                    }
                    $trimmedContent = "$trimNote`r`n$tailText"
                    Set-Content -LiteralPath $logPath -Value $trimmedContent -Encoding utf8 -Force -ErrorAction SilentlyContinue
                }
            }
        }
    } catch { }
}

function Write-InstallLog {
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
Write-InstallLog "=== ScriptSuite Install started (PID $PID, Admin: $isAdmin, Interactive: $(-not $NonInteractive)) ==="

trap {
    $err = $_.Exception.Message
    try {
        Write-InstallLog "FATAL: $err" -Error
        Write-InstallLog "=== ScriptSuite Installation Summary ==="
        Write-InstallLog "  Result:            FAIL"
        Write-InstallLog "  Error:             $err"
        Write-InstallLog "  Log:               $logPath"
    } catch { }
    Write-Host "Install error: $err" -ForegroundColor Red
    exit 1
}

# Prebuilt-exe mode detection: if ScriptSuite.exe exists next to Install.ps1,
# we do not need ProjectPath or dotnet at all.
$prebuiltExe = Join-Path $scriptDir "ScriptSuite.exe"
$isPrebuilt = Test-Path -LiteralPath $prebuiltExe

if ($isPrebuilt) {
    if (-not $PublishDir) {
        $PublishDir = $scriptDir
    }
    $NoBuild = $true
} else {
    if (-not $ProjectPath) {
        $ProjectPath = Join-Path $scriptDir "ScriptSuite\ScriptSuite.csproj"
    }
    if (-not $PublishDir) {
        $PublishDir = Join-Path $env:TEMP "ScriptSuite-publish"
    }
    if (-not $NoBuild -and -not (Test-Path -LiteralPath $ProjectPath)) {
        throw "Project not found: $ProjectPath"
    }
}

# UAC self-elevation check (SEC-02: Program Files and task migration require admin)
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
} else {
    $needsElevation = $true
}

if ($RegistryRoot -match '^HKLM' -or $uninstallKey -match '^HKLM') {
    $needsElevation = $true
}
if ($TaskPath -eq "\ScriptSuite\" -or $TaskPath -eq "\ScriptSuite") {
    $needsElevation = $true
}

if ($needsElevation -and -not $isAdmin) {
    Write-Host "Elevating Install.ps1 via UAC..." -ForegroundColor Yellow
    $psExe = (Get-Process -Id $PID).Path
    $argParts = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Format-QuotedArgument $scriptPath))
    if ($PSBoundParameters.ContainsKey('InstallDir')) { $argParts += @("-InstallDir", (Format-QuotedArgument $InstallDir)) }
    if ($PSBoundParameters.ContainsKey('ShortcutPath')) { $argParts += @("-ShortcutPath", (Format-QuotedArgument $ShortcutPath)) }
    if ($PSBoundParameters.ContainsKey('ProjectPath')) { $argParts += @("-ProjectPath", (Format-QuotedArgument $ProjectPath)) }
    if ($PSBoundParameters.ContainsKey('PublishDir')) { $argParts += @("-PublishDir", (Format-QuotedArgument $PublishDir)) }
    if ($PSBoundParameters.ContainsKey('TaskPath')) { $argParts += @("-TaskPath", (Format-QuotedArgument $TaskPath)) }
    if ($PSBoundParameters.ContainsKey('RegistryRoot')) { $argParts += @("-RegistryRoot", (Format-QuotedArgument $RegistryRoot)) }
    if ($NoBuild) { $argParts += "-NoBuild" }
    # Pass -NonInteractive to elevated child so only parent shows summary and pauses once
    $argParts += "-NonInteractive"
    $argParts += "-Child"
    $argString = $argParts -join " "

    $elevatedExitCode = 1
    try {
        $proc = Start-Process -FilePath $psExe -ArgumentList $argString -Verb RunAs -PassThru
        $proc.WaitForExit()
        $elevatedExitCode = $proc.ExitCode
    } catch [System.ComponentModel.Win32Exception] {
        $win32Ex = $_.Exception -as [System.ComponentModel.Win32Exception]
        $errorCode = if ($win32Ex) { $win32Ex.NativeErrorCode } else { 0 }
        if ($errorCode -eq 1223) {
            Write-Host ""
            Write-Host "=== ScriptSuite Installation Summary ===" -ForegroundColor Red
            Write-Host "  Result: FAIL (UAC prompt declined)" -ForegroundColor Red
            Write-Host "  Log:    $logPath" -ForegroundColor Gray
            if (-not $NonInteractive -and [Environment]::UserInteractive) {
                Write-Host ""
                Read-Host -Prompt "Press Enter to exit..."
            }
            exit 1223
        }
        Write-Host ""
        Write-Host "=== ScriptSuite Installation Summary ===" -ForegroundColor Red
        Write-Host "  Result: FAIL ($($_.Exception.Message))" -ForegroundColor Red
        Write-Host "  Log:    $logPath" -ForegroundColor Gray
        if (-not $NonInteractive -and [Environment]::UserInteractive) {
            Write-Host ""
            Read-Host -Prompt "Press Enter to exit..."
        }
        exit 1
    }

    Write-Host ""
    Write-Host "=== ScriptSuite Installation Summary ===" -ForegroundColor $(if ($elevatedExitCode -eq 0) { "Green" } else { "Red" })
    Write-Host "  Result: $(if ($elevatedExitCode -eq 0) { 'PASS' } else { 'FAIL' })" -ForegroundColor $(if ($elevatedExitCode -eq 0) { "Green" } else { "Red" })
    Write-Host "  Log:    $logPath" -ForegroundColor Gray
    if ($elevatedExitCode -ne 0) {
        Write-InstallLog "Elevated installation failed with exit code $elevatedExitCode" -Error
    }
    if (-not $NonInteractive -and [Environment]::UserInteractive) {
        Write-Host ""
        Read-Host -Prompt "Press Enter to exit..."
    }
    exit $elevatedExitCode
}

# Elevated installation execution
Write-InstallLog "=== ScriptSuite Install Execution ==="

try {
    # 1) Stop running instances so files are not locked
    Write-InstallLog "Checking for running ScriptSuite processes..."
    $running = Get-Process -Name "ScriptSuite" -ErrorAction SilentlyContinue
    if ($running) {
        Write-InstallLog "Stopping running ScriptSuite processes..." -Warning
        $running | Stop-Process -Force
        Start-Sleep -Milliseconds 500
    }

    # 2) Publish self-contained win-x64 (or use prebuilt)
    if (-not $NoBuild) {
        Write-InstallLog "Publishing self-contained win-x64 from $ProjectPath ..."
        Remove-Item -LiteralPath $PublishDir -Recurse -Force -ErrorAction SilentlyContinue
        $pubArgs = @("publish", $ProjectPath, "-c", "Release", "-r", "win-x64", "--self-contained", "true", "-o", $PublishDir, "/p:DebugType=None", "/p:DebugSymbols=false", "-nodeReuse:false", "-p:UseSharedCompilation=false")
        try {
            & dotnet @pubArgs
            if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed with exit code $LASTEXITCODE" }
        } finally {
            try { & dotnet build-server shutdown *>$null } catch { }
        }
    } else {
        Write-InstallLog "Using prebuilt files from $PublishDir"
        if (-not (Test-Path -LiteralPath (Join-Path $PublishDir "ScriptSuite.exe"))) {
            throw "NoBuild specified but ScriptSuite.exe not found in $PublishDir"
        }
    }

    # 3) Copy to protected install root
    Write-InstallLog "Installing to $InstallDir ..."
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Copy-Item -Path (Join-Path $PublishDir "*") -Destination $InstallDir -Recurse -Force
    $target = Join-Path $InstallDir "ScriptSuite.exe"
    if (-not (Test-Path -LiteralPath $target)) { throw "Expected exe missing after copy: $target" }

    # Copy Uninstall scripts into $InstallDir if available in source directory
    $sourceUninstallPs1 = Join-Path $scriptDir "Uninstall.ps1"
    if (Test-Path -LiteralPath $sourceUninstallPs1) {
        Copy-Item -LiteralPath $sourceUninstallPs1 -Destination (Join-Path $InstallDir "Uninstall.ps1") -Force
    }
    $sourceUninstallCmd = Join-Path $scriptDir "Uninstall.cmd"
    if (Test-Path -LiteralPath $sourceUninstallCmd) {
        Copy-Item -LiteralPath $sourceUninstallCmd -Destination (Join-Path $InstallDir "Uninstall.cmd") -Force
    }

    # 4) Start Menu shortcut — what Windows Search indexes
    Write-InstallLog "Creating shortcut $ShortcutPath ..."
    $shortcutDir = Split-Path $ShortcutPath
    if ($shortcutDir -and -not (Test-Path -LiteralPath $shortcutDir)) {
        New-Item -ItemType Directory -Path $shortcutDir -Force | Out-Null
    }

    $wsh = New-Object -ComObject WScript.Shell
    $sc = $wsh.CreateShortcut($ShortcutPath)
    $sc.TargetPath = $target
    $sc.WorkingDirectory = $InstallDir
    $sc.IconLocation = "$target,0"
    $sc.Description = "ScriptSuite"
    $sc.WindowStyle = 1
    $sc.Save()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($sc) | Out-Null
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wsh) | Out-Null

    # 5) SEC-02 & DST Migration: Re-point existing tasks and convert legacy Z/offset StartBoundary to local no-Z
    Write-InstallLog "Checking $TaskPath scheduled tasks for upgrade migration..."
    $tasks = Get-ScheduledTask -TaskPath $TaskPath -ErrorAction SilentlyContinue
    $oldPerUserExe = Join-Path $env:LOCALAPPDATA "Programs\ScriptSuite\ScriptSuite.exe"

    $schedulesPath = Join-Path $env:LOCALAPPDATA "ScriptSuite\schedules.json"
    $schedules = if (Test-Path -LiteralPath $schedulesPath) {
        try { Get-Content -LiteralPath $schedulesPath -Raw | ConvertFrom-Json } catch { $null }
    } else { $null }

    $migratedTasksCount = 0

    foreach ($t in $tasks) {
        $taskMigrated = $false
        # 5a: Re-point Command if pointing to old per-user exe
        $action = $t.Actions | Select-Object -First 1
        if ($action -and ($action.Execute -like "*Programs\ScriptSuite\ScriptSuite.exe*" -or $action.Execute -eq $oldPerUserExe)) {
            Write-InstallLog "  Re-pointing task $($t.TaskName) to $target ..."
            $newAction = New-ScheduledTaskAction -Execute $target -Argument $action.Arguments
            Set-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -Action $newAction -Principal $t.Principal | Out-Null
            $taskMigrated = $true
        }

        # 5b: Convert any trigger StartBoundary with Z or offset to local no-Z format (DST fix)
        $triggersUpdated = $false
        foreach ($tr in $t.Triggers) {
            $sb = $tr.StartBoundary
            if (-not [string]::IsNullOrEmpty($sb) -and ($sb -match 'Z$' -or $sb -match '[+-]\d{2}(:?\d{2})?$')) {
                $parsedLocal = [DateTimeOffset]::Parse($sb).LocalDateTime
                $localTimeStr = $parsedLocal.ToString("HH:mm")

                # Cross-check against schedules.json timeOfDay if entry exists
                if ($schedules -and ($schedules.PSObject.Properties.Name -contains $t.TaskName)) {
                    $schedEntry = $schedules.$($t.TaskName)
                    if ($schedEntry -and $schedEntry.timeOfDay) {
                        $expectedTime = $schedEntry.timeOfDay.Trim()
                        if ($expectedTime -ne $localTimeStr) {
                            Write-InstallLog "Task $($t.TaskName) timeOfDay ($expectedTime) in schedules.json disagrees with converted local time ($localTimeStr) from StartBoundary '$sb' — skipping trigger update" -Warning
                            continue
                        }
                    }
                }

                $newSb = $parsedLocal.ToString("yyyy-MM-ddTHH:mm:ss")
                Write-InstallLog "  Updating task $($t.TaskName) StartBoundary '$sb' -> '$newSb' (local no-Z)"
                $tr.StartBoundary = $newSb
                $triggersUpdated = $true
            }
        }
        if ($triggersUpdated) {
            Set-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -Trigger $t.Triggers | Out-Null
            $taskMigrated = $true
        }

        if ($taskMigrated) {
            $migratedTasksCount++
        }
    }

    # 6) SEC-04: Seed config-trust.json if missing for existing configs (migration)
    $trustFile = Join-Path $env:LOCALAPPDATA "ScriptSuite\config-trust.json"
    $configsFolder = Join-Path $env:LOCALAPPDATA "ScriptSuite\Configs"
    $configTrustState = "Not present"
    if (Test-Path -LiteralPath $trustFile) {
        $configTrustState = "Present (untouched)"
    } elseif (Test-Path -LiteralPath $configsFolder) {
        Write-InstallLog "Seeding config-trust.json for existing configs (SEC-04 migration)..."
        $trustMap = [ordered]@{}
        Get-ChildItem -Path $configsFolder -Filter "*.json" | ForEach-Object {
            $id = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
            $h = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            $trustMap[$id] = $h
        }
        $trustMap | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $trustFile -Encoding utf8
        $configTrustState = "Seeded ($($trustMap.Count) configs)"
    } else {
        $configTrustState = "Clean (no existing configs)"
    }

    # 7) Cleanup old per-user install and old shortcut ONLY after verifying no tasks point to old copy
    $tasksStillPointingToOld = Get-ScheduledTask -TaskPath $TaskPath -ErrorAction SilentlyContinue |
        Where-Object { ($_.Actions | Select-Object -First 1).Execute -like "*Programs\ScriptSuite\ScriptSuite.exe*" }

    if (-not $tasksStillPointingToOld) {
        $oldInstall = Join-Path $env:LOCALAPPDATA "Programs\ScriptSuite"
        if (Test-Path -LiteralPath $oldInstall) {
            Write-InstallLog "Removing old per-user install: $oldInstall ..."
            Remove-Item -LiteralPath $oldInstall -Recurse -Force
        }
        $oldShortcut = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\ScriptSuite.lnk"
        if (Test-Path -LiteralPath $oldShortcut) {
            Write-InstallLog "Removing old per-user shortcut: $oldShortcut ..."
            Remove-Item -LiteralPath $oldShortcut -Force
        }
    } else {
        Write-InstallLog "Skipped deleting old install dir because some tasks still point to it: $($tasksStillPointingToOld.TaskName -join ', ')" -Warning
    }

    # 8) Read-back verification
    Write-InstallLog "Performing read-back verification..."
    if (-not (Test-Path -LiteralPath $target)) {
        throw "Verification failed: Installed executable not found at $target"
    }

    $expectedVersion = $null
    if (-not [string]::IsNullOrEmpty($ProjectPath) -and (Test-Path -LiteralPath $ProjectPath)) {
        try {
            $projXml = [xml](Get-Content -LiteralPath $ProjectPath)
            $expectedVersion = $projXml.Project.PropertyGroup.Version | Where-Object { $_ } | Select-Object -First 1
        } catch { }
    }
    if (-not $expectedVersion -and -not [string]::IsNullOrEmpty($PublishDir)) {
        $sourceExe = Join-Path $PublishDir "ScriptSuite.exe"
        if (Test-Path -LiteralPath $sourceExe) {
            $expectedVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($sourceExe).ProductVersion
        }
    }

    $installedVerInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($target)
    $installedVersion = $installedVerInfo.ProductVersion
    if ([string]::IsNullOrWhiteSpace($installedVersion)) {
        $installedVersion = $installedVerInfo.FileVersion
    }

    if ([string]::IsNullOrWhiteSpace($installedVersion)) {
        throw "Verification failed: Unable to read ProductVersion or FileVersion from $target"
    }

    if ($expectedVersion -and ($installedVersion -ne $expectedVersion -and $installedVersion -notlike "$expectedVersion*")) {
        throw "Verification failed: Read-back version mismatch (expected '$expectedVersion', installed '$installedVersion')"
    }

    # Verify shortcut target read back
    $wshCheck = New-Object -ComObject WScript.Shell
    $scCheck = $wshCheck.CreateShortcut($ShortcutPath)
    $readBackShortcutTarget = $scCheck.TargetPath
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($scCheck) | Out-Null
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wshCheck) | Out-Null

    if (-not (Test-Path -LiteralPath $ShortcutPath)) {
        throw "Verification failed: Shortcut was not created at $ShortcutPath"
    }
    if ($readBackShortcutTarget -ne $target) {
        throw "Verification failed: Shortcut TargetPath mismatch (expected '$target', read back '$readBackShortcutTarget')"
    }

    # 9) Register ScriptSuite in Windows "Installed apps"
    Write-InstallLog "Registering ScriptSuite in Windows Installed apps ($uninstallKey)..."
    $displayVersion = ($installedVersion -split '\+')[0].Trim()
    $sizeBytes = 0
    try {
        $sizeBytes = (Get-ChildItem -LiteralPath $InstallDir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    } catch { }
    $estimatedSizeKB = if ($sizeBytes -gt 0) { [int][math]::Round($sizeBytes / 1KB) } else { 0 }

    $uninstallPs1Target = Join-Path $InstallDir "Uninstall.ps1"
    $uninstallString = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$uninstallPs1Target`""

    $parentKey = Split-Path $uninstallKey -Parent
    if ($parentKey -and -not (Test-Path -LiteralPath $parentKey)) {
        New-Item -ItemType Directory -Path $parentKey -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $uninstallKey)) {
        New-Item -ItemType Directory -Path $uninstallKey -Force | Out-Null
    }

    Set-ItemProperty -LiteralPath $uninstallKey -Name "DisplayName" -Value "ScriptSuite" -Type String
    Set-ItemProperty -LiteralPath $uninstallKey -Name "DisplayVersion" -Value $displayVersion -Type String
    Set-ItemProperty -LiteralPath $uninstallKey -Name "Publisher" -Value "Bllodwolfie" -Type String
    Set-ItemProperty -LiteralPath $uninstallKey -Name "InstallLocation" -Value $InstallDir -Type String
    Set-ItemProperty -LiteralPath $uninstallKey -Name "DisplayIcon" -Value $target -Type String
    Set-ItemProperty -LiteralPath $uninstallKey -Name "UninstallString" -Value $uninstallString -Type String
    Set-ItemProperty -LiteralPath $uninstallKey -Name "NoModify" -Value 1 -Type DWord
    Set-ItemProperty -LiteralPath $uninstallKey -Name "NoRepair" -Value 1 -Type DWord
    Set-ItemProperty -LiteralPath $uninstallKey -Name "EstimatedSize" -Value $estimatedSizeKB -Type DWord
    Set-ItemProperty -LiteralPath $uninstallKey -Name "URLInfoAbout" -Value "https://github.com/Bllodwolfie/windows-scripts" -Type String

    # Verify registry entry read back
    $regCheck = Get-ItemProperty -LiteralPath $uninstallKey -ErrorAction SilentlyContinue
    if (-not $regCheck -or $regCheck.DisplayName -ne "ScriptSuite") {
        throw "Verification failed: Registry key not created at $uninstallKey"
    }

    Write-Host ""
    Write-Host "=== ScriptSuite Installation Summary ===" -ForegroundColor Green
    Write-Host "  Installed Version: $installedVersion" -ForegroundColor Green
    Write-Host "  Task Migrations:   $migratedTasksCount migrated"
    Write-Host "  Config Trust:      $configTrustState"
    Write-Host "  Shortcut Target:   $readBackShortcutTarget"
    Write-Host "  Installed Apps:    Registered ($uninstallKey)"
    Write-Host "  Result:            PASS" -ForegroundColor Green
    Write-Host "  Log:               $logPath" -ForegroundColor Gray

    Write-InstallLog "=== ScriptSuite Installation Summary ==="
    Write-InstallLog "  Installed Version: $installedVersion"
    Write-InstallLog "  Task Migrations:   $migratedTasksCount migrated"
    Write-InstallLog "  Config Trust:      $configTrustState"
    Write-InstallLog "  Shortcut Target:   $readBackShortcutTarget"
    Write-InstallLog "  Installed Apps:    Registered ($uninstallKey)"
    Write-InstallLog "  Result:            PASS"
    Write-InstallLog "  Log:               $logPath"

    if (-not $NonInteractive -and [Environment]::UserInteractive) {
        Write-Host ""
        Read-Host -Prompt "Press Enter to exit..."
    }
    exit 0
} catch {
    $err = $_.Exception.Message
    Write-InstallLog "ERROR: $err" -Error
    Write-Host ""
    Write-Host "=== ScriptSuite Installation Summary ===" -ForegroundColor Red
    Write-Host "  Installed Version: FAIL ($err)" -ForegroundColor Red
    Write-Host "  Result:            FAIL" -ForegroundColor Red
    Write-Host "  Log:               $logPath" -ForegroundColor Gray

    Write-InstallLog "=== ScriptSuite Installation Summary ==="
    Write-InstallLog "  Result:            FAIL"
    Write-InstallLog "  Error:             $err"
    Write-InstallLog "  Log:               $logPath"

    if (-not $NonInteractive -and [Environment]::UserInteractive) {
        Write-Host ""
        Read-Host -Prompt "Press Enter to exit..."
    }
    exit 1
}
