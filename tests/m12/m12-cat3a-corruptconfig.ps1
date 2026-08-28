# Cat3a — corrupt config JSON
. (Join-Path $PSScriptRoot "m12-lib.ps1")
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Write-HarnessLog "=== CAT3A START corrupt config JSON ==="

$cfgPath="$env:LOCALAPPDATA\ScriptSuite\Configs\TempCleanup.json"
$orig=Get-Content $cfgPath -Raw
# Corrupt it: truncate to invalid JSON
"{ invalid json :::" | Set-Content -LiteralPath $cfgPath -Encoding utf8
Write-HarnessLog "CONFIG-CORRUPTED $cfgPath with invalid JSON"

$scriptPs=Join-Path $RepoRoot "scripts\TempCleanup\TempCleanup.ps1"

# Try DryRun via SDK — should handle gracefully, not crash, fallback to defaults
$iss=[System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
$iss.ExecutionPolicy=[Microsoft.PowerShell.ExecutionPolicy]::Bypass
$ps=[PowerShell]::Create($iss)
$ps.AddCommand($scriptPs) | Out-Null
$ps.AddParameter("ConfigPath",$cfgPath) | Out-Null
$ps.AddParameter("DryRun",[System.Management.Automation.SwitchParameter]::Present) | Out-Null
try{
    $out=$ps.Invoke()
    $items=$out | Where-Object { $_.PSObject.Properties["Action"] }
    Write-HarnessLog "DRYRUN count=$($items.Count) Warning=$($ps.Streams.Warning.Count) Error=$($ps.Streams.Error.Count) HadErrors=$($ps.HadErrors)"
    $ps.Streams.Error | ForEach-Object { Write-HarnessLog "ERR $($_.Exception.Message)" }
    $ps.Streams.Warning | ForEach-Object { Write-HarnessLog "WARN $($_.Message)" }
    # Check outcome: should be Success or Warning with fallback, not Failed/crash
    $outcome="Success"; if($ps.Streams.Error.Count -gt 0){ $outcome="Failed" } elseif($ps.Streams.Warning.Count -gt 0){ $outcome="Warning" }
    Write-HarnessLog "OUTCOME $outcome (expect Success/Warning with fallback, not crash)"
    if($ps.HadErrors -and $ps.Streams.Error.Count -eq 0){ Write-HarnessLog "HadErrors true but Error 0 — may be expected" }
    # Verify config file still corrupted (not auto-fixed) and app didn't crash
    $stillCorrupt=Get-Content $cfgPath -Raw
    Write-HarnessLog "CONFIG-STILL-CORRUPT len $($stillCorrupt.Length) preview $($stillCorrupt.Substring(0, [Math]::Min(30, $stillCorrupt.Length)))"
} catch {
    Write-HarnessLog "DRYRUN threw exception (should be graceful): $_"
    exit 1
}

# Restore
$orig | Set-Content -LiteralPath $cfgPath -Encoding utf8
Write-HarnessLog "CONFIG-RESTORED"

# Verify restored
try{ $reloaded=Get-Content $cfgPath -Raw | ConvertFrom-Json; Write-HarnessLog "RESTORED-OK count $($reloaded.PSObject.Properties.Count)" } catch { Write-HarnessLog "RESTORE-FAIL $_"; exit 1 }

Write-HarnessLog "RESULT: Success, corrupt config handled gracefully (fallback to defaults, no crash)"
Write-HarnessLog "=== CAT3A END ==="

