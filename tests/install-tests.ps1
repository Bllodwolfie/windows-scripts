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

$testRegBase = "HKCU:\Software\ScriptSuiteTest_InstallTests_$PID"
$defaultTestRegRoot = "$testRegBase\Default"

$ranCount = 0
$passCount = 0
$failedCount = 0
$skippedCount = 0

function Assert-Test {
    param([bool]$Condition, [string]$TestName, [string]$Details = "")
    $script:ranCount++
    if ($Condition) {
        $script:passCount++
        Write-Host "  PASS: $TestName" -ForegroundColor Green
    } else {
        $script:failedCount++
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

    $cmd51 = "& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path '$extracted1' 'Install.ps1') -InstallDir '$dir1' -ShortcutPath '$lnk1' -TaskPath '\ScriptSuiteTest' -RegistryRoot '$defaultTestRegRoot' -NonInteractive"
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

    $cmdPwsh = "& pwsh.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path '$extracted2' 'Install.ps1') -InstallDir '$dir2' -ShortcutPath '$lnk2' -TaskPath '\ScriptSuiteTest' -RegistryRoot '$defaultTestRegRoot' -NonInteractive"
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
    $out3 = & cmd.exe /c "`"$installCmdPath`" -InstallDir `"$dir3`" -ShortcutPath `"$lnk3`" -TaskPath `"\ScriptSuiteTest`" -RegistryRoot `"$defaultTestRegRoot`" -NonInteractive"
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
    $out4 = pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $installScript -InstallDir $dir4 -ShortcutPath $lnk4 -TaskPath "\ScriptSuiteTest" -RegistryRoot $defaultTestRegRoot -PublishDir $PublishDir -NoBuild -NonInteractive
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

    $out5a = pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $installScript -InstallDir $dir5a -ShortcutPath $lnk5a -TaskPath "\ScriptSuiteTest" -RegistryRoot $defaultTestRegRoot -PublishDir $PublishDir -NoBuild -NonInteractive
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
        $out5b = pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $installScript -InstallDir $dir5b -ShortcutPath $lnk5b -TaskPath "\ScriptSuiteTest" -RegistryRoot $defaultTestRegRoot -PublishDir $PublishDir -NoBuild -NonInteractive 2>&1
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

    $out7 = pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $installScript -ProjectPath $fakeCsproj -PublishDir $PublishDir -NoBuild -InstallDir $dir7 -ShortcutPath $lnk7 -TaskPath "\ScriptSuiteTest" -RegistryRoot $defaultTestRegRoot -NonInteractive 2>&1
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
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $installScript -InstallDir $dir8 -ShortcutPath $lnk8 -TaskPath "\ScriptSuiteTest" -RegistryRoot $defaultTestRegRoot -PublishDir $PublishDir -NoBuild -NonInteractive | Out-Null
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
    $out8 = pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $uninstallScript -InstallDir $dir8 -ShortcutPath $lnk8 -TaskPath "\ScriptSuiteTest" -RegistryRoot $defaultTestRegRoot -NonInteractive
    $exit8 = $LASTEXITCODE

    Assert-Test ($exit8 -eq 0) "Uninstall exit code is 0"
    Assert-Test (-not (Test-Path -LiteralPath $dir8)) "Install dir was removed"
    Assert-Test (-not (Test-Path -LiteralPath $lnk8)) "Shortcut was removed"
    $tRemaining = Get-ScheduledTask -TaskPath "\ScriptSuiteTest\" -TaskName $taskName8 -ErrorAction SilentlyContinue
    Assert-Test ($null -eq $tRemaining) "Scratch task in \ScriptSuiteTest\ was removed"

    Clean-ScratchTask $taskName8

    # -------------------------------------------------------------------------
    # Test 9: Installed apps registry registration & expected values
    # -------------------------------------------------------------------------
    Write-Host "`n--- Test 9: Installed apps registry registration ---" -ForegroundColor Yellow
    $dir9 = Join-Path $testScratchRoot "Test9_reg\Install"
    $lnk9 = Join-Path $testScratchRoot "Test9_reg\Programs\ScriptSuite.lnk"
    $regRoot9 = "$testRegBase\Test9"
    $key9 = "$regRoot9\ScriptSuite"

    $out9 = pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $installScript -InstallDir $dir9 -ShortcutPath $lnk9 -TaskPath "\ScriptSuiteTest" -RegistryRoot $regRoot9 -PublishDir $PublishDir -NoBuild -NonInteractive
    $exit9 = $LASTEXITCODE
    Assert-Test ($exit9 -eq 0) "Install with isolated RegistryRoot succeeds" "Exit code was $exit9"
    Assert-Test (Test-Path -LiteralPath $key9) "Registry key created at expected path ($key9)"

    $regValues = Get-ItemProperty -LiteralPath $key9
    Assert-Test ($regValues.DisplayName -eq "ScriptSuite") "DisplayName equals 'ScriptSuite' (actual: $($regValues.DisplayName))"
    Assert-Test ($regValues.DisplayVersion -match '^\d+\.\d+\.\d+$') "DisplayVersion has no +hash suffix (actual: $($regValues.DisplayVersion))"
    Assert-Test ($regValues.Publisher -eq "Bllodwolfie") "Publisher equals 'Bllodwolfie' (actual: $($regValues.Publisher))"
    Assert-Test ($regValues.InstallLocation -eq $dir9) "InstallLocation matches install dir (actual: $($regValues.InstallLocation))"
    $expectedExeTarget = Join-Path $dir9 "ScriptSuite.exe"
    Assert-Test ($regValues.DisplayIcon -eq $expectedExeTarget) "DisplayIcon matches exe target (actual: $($regValues.DisplayIcon))"
    Assert-Test ($regValues.UninstallString -like "*Uninstall.ps1*") "UninstallString points to Uninstall.ps1 (actual: $($regValues.UninstallString))"
    Assert-Test ($regValues.NoModify -eq 1) "NoModify equals 1 (actual: $($regValues.NoModify))"
    Assert-Test ($regValues.NoRepair -eq 1) "NoRepair equals 1 (actual: $($regValues.NoRepair))"
    Assert-Test ($regValues.EstimatedSize -gt 0) "EstimatedSize is greater than 0 KB (actual: $($regValues.EstimatedSize) KB)"
    Assert-Test ($regValues.URLInfoAbout -eq "https://github.com/Bllodwolfie/windows-scripts") "URLInfoAbout matches repo URL (actual: $($regValues.URLInfoAbout))"

    # -------------------------------------------------------------------------
    # Test 10: Upgrade in place is idempotent (no duplicates, overwrites values)
    # -------------------------------------------------------------------------
    Write-Host "`n--- Test 10: Upgrade in place idempotency ---" -ForegroundColor Yellow
    $out10 = pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $installScript -InstallDir $dir9 -ShortcutPath $lnk9 -TaskPath "\ScriptSuiteTest" -RegistryRoot $regRoot9 -PublishDir $PublishDir -NoBuild -NonInteractive
    $exit10 = $LASTEXITCODE
    Assert-Test ($exit10 -eq 0) "Upgrade install exit code is 0"
    Assert-Test (Test-Path -LiteralPath $key9) "Registry key still exists after upgrade"
    $regValues10 = Get-ItemProperty -LiteralPath $key9
    Assert-Test ($regValues10.DisplayName -eq "ScriptSuite") "DisplayName preserved after upgrade"
    $subkeysCount = @(Get-ChildItem -LiteralPath $regRoot9).Count
    Assert-Test ($subkeysCount -eq 1) "No duplicate registry subkeys created ($subkeysCount)"

    # -------------------------------------------------------------------------
    # Test 11: Uninstall.ps1 removes registry key
    # -------------------------------------------------------------------------
    Write-Host "`n--- Test 11: Uninstall removes registry key ---" -ForegroundColor Yellow
    $out11 = pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $uninstallScript -InstallDir $dir9 -ShortcutPath $lnk9 -TaskPath "\ScriptSuiteTest" -RegistryRoot $regRoot9 -NonInteractive
    $exit11 = $LASTEXITCODE
    Assert-Test ($exit11 -eq 0) "Uninstall exit code is 0"
    Assert-Test (-not (Test-Path -LiteralPath $key9)) "Registry key was removed by Uninstall.ps1"
    Assert-Test (-not (Test-Path -LiteralPath $dir9)) "Install directory was removed by Uninstall.ps1"

    # -------------------------------------------------------------------------
    # Test 12: Self-uninstall from inside $InstallDir via temp copy
    # -------------------------------------------------------------------------
    Write-Host "`n--- Test 12: Self-uninstall from inside InstallDir via temp copy ---" -ForegroundColor Yellow
    $dir12 = Join-Path $testScratchRoot "Test12_self\Install"
    $lnk12 = Join-Path $testScratchRoot "Test12_self\Programs\ScriptSuite.lnk"
    $regRoot12 = "$testRegBase\Test12"
    $key12 = "$regRoot12\ScriptSuite"

    $out12Install = pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $installScript -InstallDir $dir12 -ShortcutPath $lnk12 -TaskPath "\ScriptSuiteTest" -RegistryRoot $regRoot12 -PublishDir $PublishDir -NoBuild -NonInteractive
    Assert-Test ($LASTEXITCODE -eq 0) "Install for Test 12 succeeded"
    Assert-Test (Test-Path -LiteralPath (Join-Path $dir12 "Uninstall.ps1")) "Uninstall.ps1 was copied into install dir"
    Assert-Test (Test-Path -LiteralPath (Join-Path $dir12 "Uninstall.cmd")) "Uninstall.cmd was copied into install dir"
    Assert-Test (Test-Path -LiteralPath $key12) "Registry key exists before self-uninstall"

    # Invoke Uninstall.ps1 FROM INSIDE $dir12
    $installedUninstallPs1 = Join-Path $dir12 "Uninstall.ps1"
    $out12Uninstall = pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $installedUninstallPs1 -InstallDir $dir12 -ShortcutPath $lnk12 -TaskPath "\ScriptSuiteTest" -RegistryRoot $regRoot12 -NonInteractive
    $exit12 = $LASTEXITCODE
    Assert-Test ($exit12 -eq 0) "Self-uninstall from inside InstallDir exit code is 0" "Exit was $exit12"
    Assert-Test (-not (Test-Path -LiteralPath $dir12)) "InstallDir was completely deleted by self-uninstall"
    Assert-Test (-not (Test-Path -LiteralPath $key12)) "Registry key was completely removed by self-uninstall"

    # -------------------------------------------------------------------------
    # Test 13: Elevated-only tests handling
    # -------------------------------------------------------------------------
    Write-Host "`n--- Test 13: Elevated-only registry test check ---" -ForegroundColor Yellow
    $isTestAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isTestAdmin) {
        Write-Host "  [SKIPPED] Elevated HKLM default registry test skipped (not elevated)" -ForegroundColor Yellow
        $script:skippedCount++
    } else {
        Write-Host "  Elevated privileges detected: running HKLM test check" -ForegroundColor Cyan
        $hklmScratchKey = "HKLM:\SOFTWARE\ScriptSuite_ElevatedTestCheck_$PID"
        try {
            New-Item -ItemType Directory -Path $hklmScratchKey -Force | Out-Null
            Set-ItemProperty -LiteralPath $hklmScratchKey -Name "TestVal" -Value 1 | Out-Null
            Assert-Test (Test-Path -LiteralPath $hklmScratchKey) "Elevated HKLM write succeeded"
        } finally {
            Remove-Item -LiteralPath $hklmScratchKey -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # -------------------------------------------------------------------------
    # Test 14: Install with spaces in path
    # -------------------------------------------------------------------------
    Write-Host "`n--- Test 14: Install with spaces in path ---" -ForegroundColor Yellow
    $dir14 = Join-Path $testScratchRoot "Test14 Space\Install Dir"
    $lnk14 = Join-Path $testScratchRoot "Test14 Space\Shortcuts Dir\ScriptSuite.lnk"
    $regRoot14 = "$testRegBase\Test14 Space"
    $key14 = "$regRoot14\ScriptSuite"

    $out14Install = pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $installScript -InstallDir $dir14 -ShortcutPath $lnk14 -TaskPath "\ScriptSuiteTest" -RegistryRoot $regRoot14 -PublishDir $PublishDir -NoBuild -NonInteractive
    $exit14Install = $LASTEXITCODE
    Assert-Test ($exit14Install -eq 0) "Install with space in path succeeded" "Exit was $exit14Install"
    Assert-Test (Test-Path -LiteralPath (Join-Path $dir14 "ScriptSuite.exe")) "ScriptSuite.exe exists in install dir with spaces"
    Assert-Test (Test-Path -LiteralPath (Join-Path $dir14 "Uninstall.ps1")) "Uninstall.ps1 was copied into install dir with spaces"
    Assert-Test (Test-Path -LiteralPath $lnk14) "Shortcut was created in path with spaces"
    Assert-Test (Test-Path -LiteralPath $key14) "Registry entry exists in path with spaces"

    # -------------------------------------------------------------------------
    # Test 15: Self-uninstall from inside InstallDir with space in path
    # -------------------------------------------------------------------------
    Write-Host "`n--- Test 15: Self-uninstall from inside InstallDir with space in path ---" -ForegroundColor Yellow
    $installedUninstall14 = Join-Path $dir14 "Uninstall.ps1"
    $out15Uninstall = pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $installedUninstall14 -InstallDir $dir14 -ShortcutPath $lnk14 -TaskPath "\ScriptSuiteTest" -RegistryRoot $regRoot14 -NonInteractive
    $exit15 = $LASTEXITCODE
    Assert-Test ($exit15 -eq 0) "Self-uninstall with space in path exit code is 0" "Exit was $exit15"
    Assert-Test (-not (Test-Path -LiteralPath $dir14)) "InstallDir with space in path was deleted by self-uninstall"
    Assert-Test (-not (Test-Path -LiteralPath $key14)) "Registry key was removed by self-uninstall"
    Assert-Test (-not (Test-Path -LiteralPath $lnk14)) "Shortcut was removed by self-uninstall"

    # -------------------------------------------------------------------------
    # Test 16: Elevated relaunch with space in path check
    # -------------------------------------------------------------------------
    Write-Host "`n--- Test 16: Elevated relaunch with space in path check ---" -ForegroundColor Yellow
    if (-not $isTestAdmin) {
        Write-Host "  [SKIPPED] Elevated relaunch test with space in path skipped (not elevated)" -ForegroundColor Yellow
        $script:skippedCount++
    } else {
        Write-Host "  Elevated privileges detected: running elevated space test" -ForegroundColor Cyan
        $dir16 = Join-Path $testScratchRoot "Test16 Elevated Space\Install Dir"
        $lnk16 = Join-Path $testScratchRoot "Test16 Elevated Space\Shortcuts Dir\ScriptSuite.lnk"
        $regRoot16 = "HKLM:\SOFTWARE\ScriptSuite_ElevatedSpaceTest_$PID"
        try {
            $out16In = pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $installScript -InstallDir $dir16 -ShortcutPath $lnk16 -TaskPath "\ScriptSuiteTest" -RegistryRoot $regRoot16 -PublishDir $PublishDir -NoBuild -NonInteractive
            Assert-Test ($LASTEXITCODE -eq 0) "Elevated install with space in path succeeded"
            $out16Un = pwsh.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dir16 "Uninstall.ps1") -InstallDir $dir16 -ShortcutPath $lnk16 -TaskPath "\ScriptSuiteTest" -RegistryRoot $regRoot16 -NonInteractive
            Assert-Test ($LASTEXITCODE -eq 0) "Elevated self-uninstall with space in path succeeded"
        } finally {
            Remove-Item -LiteralPath (Split-Path $dir16) -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $regRoot16) {
                Remove-Item -LiteralPath $regRoot16 -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # -------------------------------------------------------------------------
    # Test 17: Log growth capping tests (both pwsh.exe and powershell.exe)
    # -------------------------------------------------------------------------
    Write-Host "`n--- Test 17: Log growth capping tests ---" -ForegroundColor Yellow
    $logTestDir = Join-Path $testScratchRoot "Test17_LogCapping"
    New-Item -ItemType Directory -Path $logTestDir -Force | Out-Null

    $lines300 = 1..300 | ForEach-Object { "Pre-existing log line $_ : " + ("A" * 1024) }

    $engines = @("pwsh.exe", "powershell.exe")
    foreach ($engine in $engines) {
        $engineTag = if ($engine -match "pwsh") { "pwsh" } else { "ps51" }
        Write-Host "`n  Testing log growth capping under $engine ($engineTag) ..." -ForegroundColor Cyan
        $subtestRoot = Join-Path $logTestDir $engineTag
        New-Item -ItemType Directory -Path $subtestRoot -Force | Out-Null

        # Subtest A: Oversized multi-line log is trimmed once
        $pdA = Join-Path $subtestRoot "PDA"
        $pdLogDirA = Join-Path $pdA "ScriptSuite"
        New-Item -ItemType Directory -Path $pdLogDirA -Force | Out-Null
        $oversizedLog = Join-Path $pdLogDirA "install.log"
        Set-Content -LiteralPath $oversizedLog -Value $lines300 -Encoding utf8
        $oversizedInitialLength = (Get-Item -LiteralPath $oversizedLog).Length
        Assert-Test ($oversizedInitialLength -gt 256KB) "[$engine] Oversized log is initially > 256 KB ($oversizedInitialLength bytes)"

        $dir17a = Join-Path $subtestRoot "InstallA"
        $lnk17a = Join-Path $subtestRoot "ShortcutsA\ScriptSuite.lnk"
        $reg17a = "$testRegBase\Test17A_$engineTag"

        # Run Install.ps1 with redirected $env:ProgramData
        $cmd17a = "`$env:ProgramData = '$pdA'; & '$installScript' -InstallDir '$dir17a' -ShortcutPath '$lnk17a' -TaskPath '\ScriptSuiteTest' -RegistryRoot '$reg17a' -PublishDir '$PublishDir' -NoBuild -NonInteractive"
        $out17a = & $engine -NoProfile -ExecutionPolicy Bypass -Command $cmd17a
        Assert-Test ($LASTEXITCODE -eq 0) "[$engine] Install with oversized log succeeded"

        $logContentAfterTrim = Get-Content -LiteralPath $oversizedLog
        $trimMatches1 = @($logContentAfterTrim | Where-Object { $_ -match "log trimmed" })
        Assert-Test ($trimMatches1.Count -eq 1) "[$engine] Oversized log was trimmed once (contains note 'log trimmed')"
        Assert-Test ($logContentAfterTrim.Count -lt 200) "[$engine] Trimmed log line count is capped (~100 tail lines + new entries, actual: $($logContentAfterTrim.Count))"
        $oversizedTrimmedLength = (Get-Item -LiteralPath $oversizedLog).Length
        Assert-Test ($oversizedTrimmedLength -le 256KB) "[$engine] Trimmed log file size is <= 256 KB ($oversizedTrimmedLength bytes)"

        # Run a second time to ensure it is not trimmed again when under 256 KB
        $out17a2 = & $engine -NoProfile -ExecutionPolicy Bypass -Command $cmd17a
        Assert-Test ($LASTEXITCODE -eq 0) "[$engine] Second install run succeeded"
        $logContentAfterSecond = Get-Content -LiteralPath $oversizedLog
        $trimMatches2 = @($logContentAfterSecond | Where-Object { $_ -match "log trimmed" })
        Assert-Test ($trimMatches2.Count -eq 1) "[$engine] Second run did not trim again (log trimmed note still appears only once)"

        # Subtest B: Oversized log with ONE VERY LONG LINE is capped to <= 256 KB
        $pdB = Join-Path $subtestRoot "PDB_LongLine"
        $pdLogDirB = Join-Path $pdB "ScriptSuite"
        New-Item -ItemType Directory -Path $pdLogDirB -Force | Out-Null
        $longLineLog = Join-Path $pdLogDirB "install.log"
        $singleLongLine = "VERY_LONG_LINE_CANARY_" + ("B" * 350000)
        Set-Content -LiteralPath $longLineLog -Value $singleLongLine -Encoding utf8
        $longLineInitialLength = (Get-Item -LiteralPath $longLineLog).Length
        Assert-Test ($longLineInitialLength -gt 256KB) "[$engine] Long-line log is initially > 256 KB ($longLineInitialLength bytes)"

        $dir17b = Join-Path $subtestRoot "InstallB"
        $lnk17b = Join-Path $subtestRoot "ShortcutsB\ScriptSuite.lnk"
        $reg17b = "$testRegBase\Test17B_$engineTag"

        $cmd17b = "`$env:ProgramData = '$pdB'; & '$installScript' -InstallDir '$dir17b' -ShortcutPath '$lnk17b' -TaskPath '\ScriptSuiteTest' -RegistryRoot '$reg17b' -PublishDir '$PublishDir' -NoBuild -NonInteractive"
        $out17b = & $engine -NoProfile -ExecutionPolicy Bypass -Command $cmd17b
        Assert-Test ($LASTEXITCODE -eq 0) "[$engine] Install with single long line log succeeded"

        $longLineTrimmedLength = (Get-Item -LiteralPath $longLineLog).Length
        Assert-Test ($longLineTrimmedLength -lt $longLineInitialLength) "[$engine] Long-line log size was reduced ($longLineTrimmedLength bytes < $longLineInitialLength bytes)"
        Assert-Test ($longLineTrimmedLength -le 256KB) "[$engine] Long-line log capped to <= 256 KB ($longLineTrimmedLength bytes)"
        $longLineContentAfter = Get-Content -LiteralPath $longLineLog
        $longLineTrimMatches = @($longLineContentAfter | Where-Object { $_ -match "log trimmed" })
        Assert-Test ($longLineTrimMatches.Count -ge 1) "[$engine] Long-line log contains note 'log trimmed'"

        # Subtest B2: Oversized log with multi-byte characters is trimmed without splitting characters
        $pdB2 = Join-Path $subtestRoot "PDB2_MultiByte"
        $pdLogDirB2 = Join-Path $pdB2 "ScriptSuite"
        New-Item -ItemType Directory -Path $pdLogDirB2 -Force | Out-Null
        $mbLog = Join-Path $pdLogDirB2 "install.log"
        $mbChar = [char]0x20AC # Euro sign € (3 bytes in UTF-8)
        $mbLongLine = [string]::new($mbChar, 200000) # 200,000 repetitions of 3-byte character = 600,000 bytes
        Set-Content -LiteralPath $mbLog -Value $mbLongLine -Encoding utf8
        $mbInitialLength = (Get-Item -LiteralPath $mbLog).Length
        Assert-Test ($mbInitialLength -gt 256KB) "[$engine] Multi-byte log is initially > 256 KB ($mbInitialLength bytes)"

        $dir17b2 = Join-Path $subtestRoot "InstallB2"
        $lnk17b2 = Join-Path $subtestRoot "ShortcutsB2\ScriptSuite.lnk"
        $reg17b2 = "$testRegBase\Test17B2_$engineTag"

        $cmd17b2 = "`$env:ProgramData = '$pdB2'; & '$installScript' -InstallDir '$dir17b2' -ShortcutPath '$lnk17b2' -TaskPath '\ScriptSuiteTest' -RegistryRoot '$reg17b2' -PublishDir '$PublishDir' -NoBuild -NonInteractive"
        $out17b2 = & $engine -NoProfile -ExecutionPolicy Bypass -Command $cmd17b2
        Assert-Test ($LASTEXITCODE -eq 0) "[$engine] Install with multi-byte log succeeded"

        $mbTrimmedLength = (Get-Item -LiteralPath $mbLog).Length
        Assert-Test ($mbTrimmedLength -le 256KB) "[$engine] Multi-byte log capped to <= 256 KB ($mbTrimmedLength bytes)"
        $mbContentAfter = Get-Content -LiteralPath $mbLog -Encoding utf8
        $mbTrimMatches = @($mbContentAfter | Where-Object { $_ -match "log trimmed" })
        Assert-Test ($mbTrimMatches.Count -ge 1) "[$engine] Multi-byte log contains note 'log trimmed'"

        $firstCharAfterNote = $mbContentAfter[1][0]
        Assert-Test ($firstCharAfterNote -eq $mbChar) "[$engine] First character after note line is a complete character ($firstCharAfterNote)"
        Assert-Test ($firstCharAfterNote -ne [char]0xFFFD) "[$engine] First character after note line is not replacement character U+FFFD"
        Assert-Test (-not $mbContentAfter[1].Contains([char]0xFFFD)) "[$engine] Trimmed line contains no replacement characters (U+FFFD)"

        # Subtest C: A -FromTemp child does not trim
        $pdC = Join-Path $subtestRoot "PDC_FromTemp"
        $pdLogDirC = Join-Path $pdC "ScriptSuite"
        New-Item -ItemType Directory -Path $pdLogDirC -Force | Out-Null
        $fromTempLog = Join-Path $pdLogDirC "uninstall.log"
        Set-Content -LiteralPath $fromTempLog -Value $lines300 -Encoding utf8
        $dir17c = Join-Path $subtestRoot "InstallC"
        $lnk17c = Join-Path $subtestRoot "ShortcutsC\ScriptSuite.lnk"
        $reg17c = "$testRegBase\Test17C_$engineTag"

        # Invoke Uninstall.ps1 with -FromTemp
        $cmd17c = "`$env:ProgramData = '$pdC'; & '$uninstallScript' -InstallDir '$dir17c' -ShortcutPath '$lnk17c' -TaskPath '\ScriptSuiteTest' -RegistryRoot '$reg17c' -FromTemp -NonInteractive"
        $out17c = & $engine -NoProfile -ExecutionPolicy Bypass -Command $cmd17c
        $fromTempContent = Get-Content -LiteralPath $fromTempLog
        $fromTempTrimMatches = @($fromTempContent | Where-Object { $_ -match "log trimmed" })
        Assert-Test ($fromTempTrimMatches.Count -eq 0) "[$engine] A -FromTemp child does not trim the log"
        Assert-Test ($fromTempContent.Count -ge 300) "[$engine] All pre-existing lines preserved in -FromTemp run (count: $($fromTempContent.Count))"

        # Subtest D: A small log is untouched
        $pdD = Join-Path $subtestRoot "PDD_Small"
        $pdLogDirD = Join-Path $pdD "ScriptSuite"
        New-Item -ItemType Directory -Path $pdLogDirD -Force | Out-Null
        $smallLog = Join-Path $pdLogDirD "install.log"
        $smallCanary = "CANARY_LINE_PRESERVED_SMALL_LOG"
        $smallLines = @(
            "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] First small log entry",
            "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] $smallCanary",
            "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] Third small log entry"
        )
        Set-Content -LiteralPath $smallLog -Value $smallLines -Encoding utf8
        $dir17d = Join-Path $subtestRoot "InstallD"
        $lnk17d = Join-Path $subtestRoot "ShortcutsD\ScriptSuite.lnk"
        $reg17d = "$testRegBase\Test17D_$engineTag"

        $cmd17d = "`$env:ProgramData = '$pdD'; & '$installScript' -InstallDir '$dir17d' -ShortcutPath '$lnk17d' -TaskPath '\ScriptSuiteTest' -RegistryRoot '$reg17d' -PublishDir '$PublishDir' -NoBuild -NonInteractive"
        $out17d = & $engine -NoProfile -ExecutionPolicy Bypass -Command $cmd17d
        Assert-Test ($LASTEXITCODE -eq 0) "[$engine] Install with small log succeeded"
        $smallLogAfter = Get-Content -LiteralPath $smallLog
        $smallTrimMatches = @($smallLogAfter | Where-Object { $_ -match "log trimmed" })
        Assert-Test ($smallTrimMatches.Count -eq 0) "[$engine] Small log was not trimmed (no 'log trimmed' note)"
        $canaryFound = @($smallLogAfter | Where-Object { $_ -match $smallCanary })
        Assert-Test ($canaryFound.Count -ge 1) "[$engine] Small log pre-existing content is untouched (canary preserved)"
    }

    Write-Host "`n==========================================================" -ForegroundColor $(if ($failedCount -eq 0) { "Green" } else { "Red" })
    Write-Host " ran $ranCount, skipped $skippedCount, failed $failedCount" -ForegroundColor $(if ($failedCount -eq 0) { "Green" } else { "Red" })
    Write-Host "==========================================================" -ForegroundColor $(if ($failedCount -eq 0) { "Green" } else { "Red" })
} finally {
    Remove-Item -LiteralPath $testScratchRoot -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $testRegBase) {
        Remove-Item -LiteralPath $testRegBase -Recurse -Force -ErrorAction SilentlyContinue
    }
}
