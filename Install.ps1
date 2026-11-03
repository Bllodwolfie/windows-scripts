<#Requires -Version 7.0>
<#
.SYNOPSIS
  Install for ScriptSuite — self-contained publish + Start Menu shortcut.

.DESCRIPTION
  Runs `dotnet publish -c Release -r win-x64 --self-contained true` into a
  staging folder, then copies to the secure system install root
  %ProgramFiles%\ScriptSuite\ and creates the Start Menu shortcut
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
    [string]$InstallDir = (Join-Path $env:ProgramFiles "ScriptSuite"),
    [string]$ShortcutPath = (Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\ScriptSuite.lnk"),
    [string]$ProjectPath = (Join-Path $PSScriptRoot "ScriptSuite\ScriptSuite.csproj"),
    [string]$PublishDir = (Join-Path $env:TEMP "ScriptSuite-publish"),
    [switch]$NoBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 0) UAC self-elevation check (SEC-02: Program Files and task migration require admin)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Elevating Install.ps1 via UAC..." -ForegroundColor Yellow
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath)
    if ($PSBoundParameters.ContainsKey('InstallDir')) { $argList += @("-InstallDir", $InstallDir) }
    if ($PSBoundParameters.ContainsKey('ShortcutPath')) { $argList += @("-ShortcutPath", $ShortcutPath) }
    if ($PSBoundParameters.ContainsKey('ProjectPath')) { $argList += @("-ProjectPath", $ProjectPath) }
    if ($PSBoundParameters.ContainsKey('PublishDir')) { $argList += @("-PublishDir", $PublishDir) }
    if ($NoBuild) { $argList += "-NoBuild" }
    $proc = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $argList -Verb RunAs -PassThru -Wait
    exit $proc.ExitCode
}

# Auto-detect pre-built release zip layout (Install.ps1 next to ScriptSuite.exe)
if (-not (Test-Path $ProjectPath) -and (Test-Path (Join-Path $PSScriptRoot "ScriptSuite.exe"))) {
    $PublishDir = $PSScriptRoot
    $NoBuild = $true
} elseif (-not (Test-Path $ProjectPath) -and -not $NoBuild) {
    throw "Project not found: $ProjectPath"
}

# 1) Stop running instances so files are not locked
$running = Get-Process -Name "ScriptSuite" -ErrorAction SilentlyContinue
if ($running) {
    Write-Warning "Stopping running ScriptSuite processes..."
    $running | Stop-Process -Force
    Start-Sleep -Milliseconds 500
}

# 2) Publish self-contained win-x64 (non-technical users: no .NET runtime prerequisite)
if (-not $NoBuild) {
    Write-Host "Publishing self-contained win-x64..."
    Remove-Item $PublishDir -Recurse -Force -ErrorAction SilentlyContinue
    $pubArgs = @("publish", $ProjectPath, "-c", "Release", "-r", "win-x64", "--self-contained", "true", "-o", $PublishDir, "/p:DebugType=None", "/p:DebugSymbols=false")
    & dotnet @pubArgs
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed: $LASTEXITCODE" }
} else {
    if (-not (Test-Path (Join-Path $PublishDir "ScriptSuite.exe"))) { throw "NoBuild but no publish output at $PublishDir" }
}

# 3) Copy to protected install root (%ProgramFiles%\ScriptSuite)
Write-Host "Installing to $InstallDir ..."
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Copy-Item -Path (Join-Path $PublishDir "*") -Destination $InstallDir -Recurse -Force

# 4) Start Menu shortcut — what Windows Search indexes
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
$sc.Save()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($sc) | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($wsh) | Out-Null

# 5) SEC-02 & DST Migration: Re-point existing \ScriptSuite\* tasks and convert legacy Z/offset StartBoundary to local no-Z
Write-Host "Checking \ScriptSuite scheduled tasks for upgrade migration..."
$tasks = Get-ScheduledTask -TaskPath "\ScriptSuite\" -ErrorAction SilentlyContinue
$oldPerUserExe = Join-Path $env:LOCALAPPDATA "Programs\ScriptSuite\ScriptSuite.exe"

$schedulesPath = Join-Path $env:LOCALAPPDATA "ScriptSuite\schedules.json"
$schedules = if (Test-Path $schedulesPath) {
    try { Get-Content $schedulesPath -Raw | ConvertFrom-Json } catch { $null }
} else { $null }

foreach ($t in $tasks) {
    # 5a: Re-point Command if pointing to old per-user exe
    $action = $t.Actions | Select-Object -First 1
    if ($action -and ($action.Execute -like "*Programs\ScriptSuite\ScriptSuite.exe*" -or $action.Execute -eq $oldPerUserExe)) {
        Write-Host "  Re-pointing task $($t.TaskName) to $target ..."
        $newAction = New-ScheduledTaskAction -Execute $target -Argument $action.Arguments
        Set-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -Action $newAction -Principal $t.Principal | Out-Null
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
                        Write-Warning "Task $($t.TaskName) timeOfDay ($expectedTime) in schedules.json disagrees with converted local time ($localTimeStr) from StartBoundary '$sb' — skipping trigger update"
                        continue
                    }
                }
            }

            $newSb = $parsedLocal.ToString("yyyy-MM-ddTHH:mm:ss")
            Write-Host "  Updating task $($t.TaskName) StartBoundary '$sb' -> '$newSb' (local no-Z)"
            $tr.StartBoundary = $newSb
            $triggersUpdated = $true
        }
    }
    if ($triggersUpdated) {
        Set-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -Trigger $t.Triggers | Out-Null
    }
}

# 6) SEC-04: Seed config-trust.json if missing for existing configs (migration)
$trustFile = Join-Path $env:LOCALAPPDATA "ScriptSuite\config-trust.json"
$configsFolder = Join-Path $env:LOCALAPPDATA "ScriptSuite\Configs"
if (-not (Test-Path $trustFile) -and (Test-Path $configsFolder)) {
    Write-Host "Seeding config-trust.json for existing configs (SEC-04 migration)..."
    $trustMap = [ordered]@{}
    Get-ChildItem -Path $configsFolder -Filter "*.json" | ForEach-Object {
        $id = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
        $h = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $trustMap[$id] = $h
    }
    $trustMap | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $trustFile -Encoding utf8
}

# 7) Cleanup old per-user install and old shortcut ONLY after verifying no tasks point to the old copy
$tasksStillPointingToOld = Get-ScheduledTask -TaskPath "\ScriptSuite\" -ErrorAction SilentlyContinue |
    Where-Object { ($_.Actions | Select-Object -First 1).Execute -like "*Programs\ScriptSuite\ScriptSuite.exe*" }

if (-not $tasksStillPointingToOld) {
    $oldInstall = Join-Path $env:LOCALAPPDATA "Programs\ScriptSuite"
    if (Test-Path $oldInstall) {
        Write-Host "Removing old per-user install: $oldInstall ..."
        Remove-Item -LiteralPath $oldInstall -Recurse -Force
    }
    $oldShortcut = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\ScriptSuite.lnk"
    if (Test-Path $oldShortcut) {
        Write-Host "Removing old per-user shortcut: $oldShortcut ..."
        Remove-Item -LiteralPath $oldShortcut -Force
    }
} else {
    Write-Warning "Skipped deleting old install dir because some tasks still point to it: $($tasksStillPointingToOld.TaskName -join ', ')"
}

# 8) Evidence
Write-Host ""
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

Write-Host ""
Write-Host "Done. Launch via Start Menu: type 'ScriptSuite'." -ForegroundColor Green
Write-Host "Uninstall: .\Uninstall.ps1  (removes $InstallDir, tasks, and the .lnk, leaves %LOCALAPPDATA%\ScriptSuite data)"
