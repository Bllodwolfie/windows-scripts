# Cat3b — corrupt manifest JSON
. (Join-Path $PSScriptRoot "m12-lib.ps1")
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Write-HarnessLog "=== CAT3B START corrupt manifest JSON ==="

$manifestPath=Join-Path $RepoRoot "ScriptSuite\Manifests\TempCleanup.json"
$orig=Get-Content $manifestPath -Raw
# Backup
$bak="$env:TEMP\TempCleanup.json.bak"
Copy-Item $manifestPath $bak -Force
# Corrupt
"{ invalid manifest json" | Set-Content -LiteralPath $manifestPath -Encoding utf8
Write-HarnessLog "MANIFEST-CORRUPTED $manifestPath"

# Try to launch app and see if it handles gracefully (should not crash, should show error or fallback)
$exe=Join-Path $RepoRoot "ScriptSuite\bin\Debug\net10.0-windows\ScriptSuite.exe"
Get-Process ScriptSuite -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
$proc=Start-Process -FilePath $exe -PassThru
Write-HarnessLog "APP-LAUNCH pid=$($proc.Id) with corrupt manifest"
Start-Sleep -Seconds 3
$running=Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
if($running){
    Write-HarnessLog "APP-STILL-RUNNING after corrupt manifest (graceful, not crash)"
    # Try to find main window
    Add-Type -AssemblyName UIAutomationClient
    $root=[System.Windows.Automation.AutomationElement]::RootElement
    $cond=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, "Script Suite")
    $win=$root.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
    if($win){ Write-HarnessLog "MAIN-WINDOW found $($win.Current.Name)" } else { Write-HarnessLog "MAIN-WINDOW not found but process still running" }
    $proc | Stop-Process -Force
    Write-HarnessLog "APP-STOP"
    $outcome="Success (graceful)"
} else {
    Write-HarnessLog "APP-CRASHED after corrupt manifest (not graceful)"
    $outcome="Failed"
}

# Restore
Copy-Item $bak $manifestPath -Force
Remove-Item $bak -Force
Write-HarnessLog "MANIFEST-RESTORED"

# Also copy to bin
Copy-Item $manifestPath Join-Path $RepoRoot "ScriptSuite\bin\Debug\net10.0-windows\Manifests\TempCleanup.json" -Force
Write-HarnessLog "MANIFEST-RESTORED bin"

if($outcome -like "Success*"){
    Write-HarnessLog "RESULT: Success, corrupt manifest handled gracefully"
} else {
    Write-HarnessLog "RESULT: Failed, app crashed on corrupt manifest"
    exit 1
}
Write-HarnessLog "=== CAT3B END ==="

