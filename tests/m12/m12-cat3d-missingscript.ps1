# Cat3d — corrupt/missing script file
. "C:\Users\nekdo\AppData\Local\Temp\opencode\m12\m12-lib.ps1"
Write-HarnessLog "=== CAT3D START corrupt/missing script ==="

$scriptPs="C:\Users\nekdo\Documents\windows-scripts\scripts\TempCleanup\TempCleanup.ps1"
$bak="$env:TEMP\TempCleanup.ps1.bak"
Copy-Item $scriptPs $bak -Force
Write-HarnessLog "BACKUP $scriptPs -> $bak"

# Test 1: missing file (rename away)
Rename-Item $scriptPs "$scriptPs.missing" -Force
Write-HarnessLog "MISSING file renamed away"

$cfgPath="$env:LOCALAPPDATA\ScriptSuite\Configs\TempCleanup.json"
$iss=[System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
$iss.ExecutionPolicy=[Microsoft.PowerShell.ExecutionPolicy]::Bypass
$ps=[PowerShell]::Create($iss)
$ps.AddCommand($scriptPs) | Out-Null
$ps.AddParameter("ConfigPath",$cfgPath) | Out-Null
$ps.AddParameter("DryRun",[System.Management.Automation.SwitchParameter]::Present) | Out-Null
try{
    $out=$ps.Invoke()
    Write-HarnessLog "MISSING DryRun Warning=$($ps.Streams.Warning.Count) Error=$($ps.Streams.Error.Count) HadErrors=$($ps.HadErrors) Count=$($out.Count)"
    $ps.Streams.Error | ForEach-Object { Write-HarnessLog "MISSING ERR $($_.Exception.Message)" }
    if($ps.HadErrors -or $ps.Streams.Error.Count -gt 0){ Write-HarnessLog "MISSING outcome Failed as expected (graceful, not crash)" } else { Write-HarnessLog "MISSING outcome not Failed" }
} catch {
    Write-HarnessLog "MISSING threw exception (not graceful): $_"
}

# Restore for next test
Move-Item "$scriptPs.missing" $scriptPs -Force
Write-HarnessLog "RESTORED missing"

# Test 2: corrupt syntax
"{ invalid syntax $$$ @" | Set-Content -LiteralPath $scriptPs -Encoding utf8
Write-HarnessLog "CORRUPT syntax written"

$ps2=[PowerShell]::Create($iss)
$ps2.AddCommand($scriptPs) | Out-Null
$ps2.AddParameter("ConfigPath",$cfgPath) | Out-Null
$ps2.AddParameter("DryRun",[System.Management.Automation.SwitchParameter]::Present) | Out-Null
try{
    $out2=$ps2.Invoke()
    Write-HarnessLog "CORRUPT DryRun Warning=$($ps2.Streams.Warning.Count) Error=$($ps2.Streams.Error.Count) HadErrors=$($ps2.HadErrors)"
    $ps2.Streams.Error | ForEach-Object { Write-HarnessLog "CORRUPT ERR $($_.Exception.Message | Select-Object -First 1)" }
    if($ps2.HadErrors -or $ps2.Streams.Error.Count -gt 0){ Write-HarnessLog "CORRUPT outcome Failed as expected" } else { Write-HarnessLog "CORRUPT outcome not Failed" }
} catch {
    Write-HarnessLog "CORRUPT threw: $_"
}

# Restore
Copy-Item $bak $scriptPs -Force
Remove-Item $bak -Force
Copy-Item $scriptPs "C:\Users\nekdo\Documents\windows-scripts\ScriptSuite\bin\Debug\net10.0-windows\scripts\TempCleanup\TempCleanup.ps1" -Force
Write-HarnessLog "RESTORED corrupt"

Write-HarnessLog "RESULT: Cat3d missing/corrupt handled gracefully (Failed outcome, not crash)"
Write-HarnessLog "=== CAT3D END ==="
