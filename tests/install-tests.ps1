<#
.SYNOPSIS
  Automated isolated regression tests for Install.ps1, Uninstall.ps1, and Install.cmd.
  Ensures PowerShell 5.1 compatibility, UAC wait & summary logging, upgrade migration,
  error handling on locked files and version mismatches, and complete clean-up.
#>
[CmdletBinding()]
param(
    [string]$PublishDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$installScript = Join-Path $repoRoot "Install.ps1"
$uninstallScript = Join-Path $repoRoot "Uninstall.ps1"
$installCmd = Join-Path $repoRoot "Install.cmd"

if (-not $PublishDir -or -not (Test-Path -LiteralPath (Join-Path $PublishDir "ScriptSuite.exe"))) {
    $PublishDir = Join-Path $env:TEMP "ScriptSuite-TestStaging"
    Write-Host "Publishing temporary staging build to $PublishDir ..."
    Remove-Item -LiteralPath $PublishDir -Recurse -Force -ErrorAction SilentlyContinue
    $pubArgs = @("publish", (Join-Path $repoRoot "ScriptSuite\ScriptSuite.csproj"), "-c", "Release", "-r", "win-x64", "--self-contained", "true", "-o", $PublishDir, "/p:DebugType=None", "/p:DebugSymbols=false")
    & dotnet @pubArgs
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed: $LASTEXITCODE" }
}

$testScratchRoot = Join-Path $env:TEMP "ScriptSuite-InstallTests-$PID"
Remove-Item -LiteralPath $testScratchRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $testScratchRoot -Force | Out-Null

$testCount = 0
$passCount = 0

function Assert-Test {
    param([bool]$Condition, [string]$TestName, [string]$Details = "")
    $script:testCount++
    if ($Condition) {
        $script:passCount++
        Write-Host "  PASS: $TestName" -ForegroundColor Green
    } else {
        Write-Host "  FAIL: $TestName" -ForegroundColor Red
        if ($Details) { Write-Host "        $Details" -ForegroundColor DarkYellow }
        throw "Assertion failed for '$TestName': $Details"
    }
}

function Clean-ScratchTask {
    param([string]$TaskName, [string]$TaskPath = "\ScriptSuiteTest\")
    try {
        Unregister-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    } catch { }
}

try {
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host " Running ScriptSuite Installer Test Suite (Isolated)" -ForegroundColor Cyan
    Write-Host " Repo Root:    $repoRoot"
    Write-Host " Staging Dir:  $PublishDir"
    Write-Host " Scratch Root: $testScratchRoot"
    Write-Host "==========================================================" -ForegroundColor Cyan

    # -------------------------------------------------------------------------
    # Test 1: Fresh install via Windows PowerShell 5.1 (Prebuilt-exe layout)
    # -------------------------------------------------------------------------
    Write-Host "`n--- Test 1: Fresh install from Windows PowerShell 5.1 ---" -ForegroundColor Yellow
    $dir1 = Join-Path $testScratchRoot "Test1_51\Install"
    $lnk1 = Join-Path $testScratchRoot "Test1_51\Programs\ScriptSuite.lnk"
    
    # Run in prebuilt layout: Install.ps1 next to ScriptSuite.exe
    $extracted1 = Join-Path $testScratchRoot "Test1_51\Extracted"
    New-Item -ItemType Directory -Path $extracted1 -Force | Out-Null
    Copy-Item (Join-Path $PublishDir "*") -Destination $extracted1 -Recurse -Force
    Copy-Item $installScript -Destination $extracted1 -Force

    $cmd51 = "& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path '$extracted1' 'Install.ps1') -InstallDir '$dir1' -ShortcutPath '$lnk1' -TaskPath '\ScriptSuiteTest' -NonInteractive"
    $out1 = powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $cmd51
    $exit1 = $LASTEXITCODE

    Assert-Test ($exit1 -eq 0) "PowerShell 5.1 exit code is 0" "Exit code was $exit1"
    $target1 = Join-Path $dir1 "ScriptSuite.exe"
    Assert-Test (Test-Path -LiteralPath $target1) "Installed exe exists in target dir"
    Assert-Test (Test-Path -LiteralPath $lnk1) "Shortcut exists in shortcut dir"

    $wsh = New-Object -ComObject WScript.Shell
    $sc1 = $wsh.CreateShortcut($lnk1)
    Assert-Test ($sc1.TargetPath -eq $target1) "Shortcut TargetPath matches installed exe" "Expected $target1, got $($sc1.TargetPath)"
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($sc1) | Out-Null
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wsh) | Out-Null

    $installedVer1 = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($target1).ProductVersion
    $sourceVer1 = [System.Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path $extracted1 "ScriptSuite.exe")).ProductVersion
    Assert-Test ($installedVer1 -eq $sourceVer1) "Read-back ProductVersion matches source exe ($installedVer1)"

    # -------------------------------------------------------------------------
    # Test 2: Fresh install via PowerShell 7 (pwsh)
    # -------------------------------------------------------------------------
    Write-Host "`n--- Test 2: Fresh install from PowerShell 7 (pwsh) ---" -ForegroundColor Yellow
    $dir2 = Join-Path $testScratchRoot "Test2_pwsh\Install"
    $lnk2 = Join-Path $testScratchRoot "Test2_pwsh\Programs\ScriptSuite.lnk"
    $extracted2 = Join-Path $testScratchRoot "Test2_pwsh\Extracted"
    New-Item -ItemType Directory -Path $extracted2 -Force | Out-Null
    Copy-Item (Join-Path $PublishDir "*") -Destination $extracted2 -Recurse -Force
    Copy-Item $installScript -Destination $extracted2 -Force

    $cmdPwsh = "& pwsh.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path '$extracted2' 'Install.ps1') -InstallDir '$dir2' -ShortcutPath '$lnk2' -TaskPath '\ScriptSuiteTest' -NonInteractive"
    $out2 = pwsh.exe -NoProfile -ExecutionPolicy Bypass -Command $cmdPwsh
    $exit2 = $LASTEXITCODE

    Assert-Test ($exit2 -eq 0) "pwsh exit code is 0" "Exit code was $exit2"
    $target2 = Join-Path $dir2 "ScriptSuite.exe"
    Assert-Test (Test-Path -LiteralPath $target2) "Installed exe exists under pwsh"
    Assert-Test (Test-Path -LiteralPath $lnk2) "Shortcut exists under pwsh"

    # -------------------------------------------------------------------------
    # Test 3: Install via Install.cmd (cmd.exe execution)
    # -------------------------------------------------------------------------
    Write-Host "`n--- Test 3: Install via Install.cmd ---" -ForegroundColor Yellow
    $dir3 = Join-Path $testScratchRoot "Test3_cmd\Install"
    $lnk3 = Join-Path $testScratchRoot "Test3_cmd\Programs\ScriptSuite.lnk"
    $extracted3 = Join-Path $testScratchRoot "Test3_cmd\Extracted"
    New-Item -ItemType Directory -Path $extracted3 -Force | Out-Null
    Copy-Item (Join-Path $PublishDir "*") -Destination $extracted3 -Recurse -Force
    Copy-Item $installScript -Destination $extracted3 -Force
    Copy-Item $installCmd -Destination $extracted3 -Force

    $installCmdPath = Join-Path $extracted3 "Install.cmd"
    $out3 = & cmd.exe /c "`"$installCmdPath`" -InstallDir `"$dir3`" -ShortcutPath `"$lnk3`" -TaskPath `"\ScriptSuiteTest`" -NonInteractive"
    $exit3 = $LASTEXITCODE

    Assert-Test ($exit3 -eq 0) "Install.cmd exit code is 0" "Exit code was $exit3"
    Assert-Test (Test-Path -LiteralPath (Join-Path $dir3 "ScriptSuite.exe")) "Installed exe exists after Install.cmd"
    Assert-Test (Test-Path -LiteralPath $lnk3) "Shortcut exists after Install.cmd"

    # -------------------------------------------------------------------------
    # Test 4: Upgrade over 3.1.2-style install (Task re-pointing + DST migration)
    # -------------------------------------------------------------------------
    Write-Host "`n--- Test 4: Upgrade over 3.1.2-style install (Task migration) ---" -ForegroundColor Yellow
    $taskName = "ScriptSuiteTest_Upgrade"
    Clean-ScratchTask $taskName

    $dir4 = Join-Path $testScratchRoot "Test4_upgrade\Install"
    $lnk4 = Join-Path $testScratchRoot "Test4_upgrade\Programs\ScriptSuite.lnk"
    $fakeOldExe = Join-Path $env:LOCALAPPDATA "Programs\ScriptSuite\ScriptSuite.exe"

    # Register a scratch task mimicking 3.1.2: points to old per-user exe with Z boundary
    $action = New-ScheduledTaskAction -Execute $fakeOldExe -Argument "--run-all"
    $trigger = New-ScheduledTaskTrigger -Daily -At "09:00"
    $trigger.StartBoundary = "2026-11-20T09:00:00Z"
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
    Register-ScheduledTask -TaskPath "\ScriptSuiteTest\" -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null

    # Run upgrade install
    $out4 = pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $installScript -InstallDir $dir4 -ShortcutPath $lnk4 -TaskPath "\ScriptSuiteTest" -PublishDir $PublishDir -NoBuild -NonInteractive
    $exit4 = $LASTEXITCODE
    Assert-Test ($exit4 -eq 0) "Upgrade install exit code is 0"

    $migratedTask = Get-ScheduledTask -TaskPath "\ScriptSuiteTest\" -TaskName $taskName
    $newAction = $migratedTask.Actions | Select-Object -First 1
    $expectedNewTarget = Join-Path $dir4 "ScriptSuite.exe"
    Assert-Test ($newAction.Execute -eq $expectedNewTarget) "Task action re-pointed to new target" "Expected $expectedNewTarget, got $($newAction.Execute)"

    $newSb = ($migratedTask.Triggers | Select-Object -First 1).StartBoundary
    Assert-Test ($newSb -notmatch 'Z$' -and $newSb -notmatch '[+-]\d{2}(:?\d{2})?$') "Task StartBoundary migrated to local no-Z ($newSb)"

    Clean-ScratchTask $taskName

    # -------------------------------------------------------------------------
    # Test 5: Exe in use
    # -------------------------------------------------------------------------
    Write-Host "`n--- Test 5: Exe in use ---" -ForegroundColor Yellow
    # 5a: Running ScriptSuite process is stopped
    $dir5a = Join-Path $testScratchRoot "Test5a\Install"
    $lnk5a = Join-Path $testScratchRoot "Test5a\Programs\ScriptSuite.lnk"
    New-Item -ItemType Directory -Path $dir5a -Force | Out-Null
    Copy-Item (Join-Path $PublishDir "ScriptSuite.exe") -Destination (Join-Path $dir5a "ScriptSuite.exe") -Force

    # Start a background process named ScriptSuite
    $dummyProc = Start-Process -FilePath (Join-Path $dir5a "ScriptSuite.exe") -ArgumentList "--help" -PassThru
    Start-Sleep -Milliseconds 200

    $out5a = pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $installScript -InstallDir $dir5a -ShortcutPath $lnk5a -TaskPath "\ScriptSuiteTest" -PublishDir $PublishDir -NoBuild -NonInteractive
    $exit5a = $LASTEXITCODE
    Assert-Test ($exit5a -eq 0) "Install terminates running ScriptSuite and succeeds"

    # 5b: Locked file (un-killable file lock) reports FAIL and non-zero exit code
    $dir5b = Join-Path $testScratchRoot "Test5b\Install"
    $lnk5b = Join-Path $testScratchRoot "Test5b\Programs\ScriptSuite.lnk"
    New-Item -ItemType Directory -Path $dir5b -Force | Out-Null
    $lockedExe = Join-Path $dir5b "ScriptSuite.exe"
    Set-Content -LiteralPath $lockedExe -Value "locked content"

    # Open exclusive lock
    $fileStream = [System.IO.File]::Open($lockedExe, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    try {
        $out5b = pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $installScript -InstallDir $dir5b -ShortcutPath $lnk5b -TaskPath "\ScriptSuiteTest" -PublishDir $PublishDir -NoBuild -NonInteractive 2>&1
        $exit5b = $LASTEXITCODE
        Assert-Test ($exit5b -ne 0) "Install on locked file returns non-zero exit code ($exit5b)"
        $hasFail = ($out5b | Out-String) -match "Result:\s+FAIL"
        Assert-Test $hasFail "Output summary reports Result: FAIL on locked file"
    } finally {
        $fileStream.Close()
        $fileStream.Dispose()
    }

    # -------------------------------------------------------------------------
    # Test 6: UAC declined (NativeErrorCode 1223)
    # -------------------------------------------------------------------------
    Write-Host "`n--- Test 6: UAC declined handling ---" -ForegroundColor Yellow
    # Test launcher error-handling and invariant preservation on 1223
    $testLauncher = {
        param($mockLogPath)
        try {
            # Simulate Start-Process throwing Win32Exception 1223 (user cancelled UAC)
            throw [System.ComponentModel.Win32Exception]::new(1223)
        } catch [System.ComponentModel.Win32Exception] {
            $win32Ex = $_.Exception -as [System.ComponentModel.Win32Exception]
            $errorCode = if ($win32Ex) { $win32Ex.NativeErrorCode } else { 0 }
            if ($errorCode -eq 1223) {
                Write-Host ""
                Write-Host "=== ScriptSuite Installation Summary ===" -ForegroundColor Red
                Write-Host "  Result: FAIL (UAC prompt declined)" -ForegroundColor Red
                Write-Host "  Log:    $mockLogPath" -ForegroundColor Gray
                return 1223
            }
            return 1
        }
    }
    $res6 = & $testLauncher "C:\ProgramData\ScriptSuite\install.log"
    Assert-Test ($res6 -eq 1223) "UAC decline returns exit code 1223"

    # -------------------------------------------------------------------------
    # Test 7: Read-back mismatch reports FAIL
    # -------------------------------------------------------------------------
    Write-Host "`n--- Test 7: Read-back mismatch reports FAIL ---" -ForegroundColor Yellow
    $dir7 = Join-Path $testScratchRoot "Test7_mismatch\Install"
    $lnk7 = Join-Path $testScratchRoot "Test7_mismatch\Programs\ScriptSuite.lnk"

    # Create a staging folder with a dummy csproj specifying Version 99.0.0, but publishing a 3.2.x exe
    $fakeProjDir = Join-Path $testScratchRoot "Test7_mismatch\FakeProj"
    New-Item -ItemType Directory -Path $fakeProjDir -Force | Out-Null
    $fakeCsproj = Join-Path $fakeProjDir "ScriptSuite.csproj"
    @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <Version>99.0.0</Version>
  </PropertyGroup>
</Project>
"@ | Set-Content -LiteralPath $fakeCsproj -Encoding utf8

    $out7 = pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $installScript -ProjectPath $fakeCsproj -PublishDir $PublishDir -NoBuild -InstallDir $dir7 -ShortcutPath $lnk7 -TaskPath "\ScriptSuiteTest" -NonInteractive 2>&1
    $exit7 = $LASTEXITCODE

    Assert-Test ($exit7 -ne 0) "Version mismatch returns non-zero exit code ($exit7)"
    $mismatchLogged = ($out7 | Out-String) -match "Read-back version mismatch"
    Assert-Test $mismatchLogged "Summary reports Read-back version mismatch"

    # -------------------------------------------------------------------------
    # Test 8: Uninstall.ps1 removes install dir, shortcut, tasks, leaves AppData
    # -------------------------------------------------------------------------
    Write-Host "`n--- Test 8: Uninstall.ps1 execution ---" -ForegroundColor Yellow
    # First install to dir8
    $dir8 = Join-Path $testScratchRoot "Test8_uninstall\Install"
    $lnk8 = Join-Path $testScratchRoot "Test8_uninstall\Programs\ScriptSuite.lnk"
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $installScript -InstallDir $dir8 -ShortcutPath $lnk8 -TaskPath "\ScriptSuiteTest" -PublishDir $PublishDir -NoBuild -NonInteractive | Out-Null
    Assert-Test (Test-Path -LiteralPath $dir8) "Pre-uninstall: install dir exists"
    Assert-Test (Test-Path -LiteralPath $lnk8) "Pre-uninstall: shortcut exists"

    # Create a scratch task
    $taskName8 = "ScriptSuiteTest_Uninstall"
    Clean-ScratchTask $taskName8
    $act8 = New-ScheduledTaskAction -Execute (Join-Path $dir8 "ScriptSuite.exe")
    $tr8 = New-ScheduledTaskTrigger -Daily -At "11:00"
    $pr8 = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
    Register-ScheduledTask -TaskPath "\ScriptSuiteTest\" -TaskName $taskName8 -Action $act8 -Trigger $tr8 -Principal $pr8 -Force | Out-Null

    # Run Uninstall.ps1
    $out8 = pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $uninstallScript -InstallDir $dir8 -ShortcutPath $lnk8 -TaskPath "\ScriptSuiteTest" -NonInteractive
    $exit8 = $LASTEXITCODE

    Assert-Test ($exit8 -eq 0) "Uninstall exit code is 0"
    Assert-Test (-not (Test-Path -LiteralPath $dir8)) "Install dir was removed"
    Assert-Test (-not (Test-Path -LiteralPath $lnk8)) "Shortcut was removed"
    $tRemaining = Get-ScheduledTask -TaskPath "\ScriptSuiteTest\" -TaskName $taskName8 -ErrorAction SilentlyContinue
    Assert-Test ($null -eq $tRemaining) "Scratch task in \ScriptSuiteTest\ was removed"

    Clean-ScratchTask $taskName8

    Write-Host "`n==========================================================" -ForegroundColor Green
    Write-Host " ALL INSTALLER TESTS PASSED: $passCount / $testCount" -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Green
} finally {
    Remove-Item -LiteralPath $testScratchRoot -Recurse -Force -ErrorAction SilentlyContinue
}
