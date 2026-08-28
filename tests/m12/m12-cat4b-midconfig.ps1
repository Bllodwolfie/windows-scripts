# Cat4b — kill mid-config-save
. (Join-Path $PSScriptRoot "m12-lib.ps1")
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Write-HarnessLog "=== CAT4B START kill mid-config-save ==="

$cfgPath="$env:LOCALAPPDATA\ScriptSuite\Configs\TempCleanup.json"
$orig=Get-Content $cfgPath -Raw
Write-HarnessLog "ORIG len $((Get-Item $cfgPath).Length)"

# Start a job that rapidly writes config
$job=Start-Job -ScriptBlock {
    $cfgPath=$using:cfgPath
    for($i=1;$i -le 200;$i++){
        $j=Get-Content $cfgPath -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
        if(-not $j){ $j=[PSCustomObject]@{ TargetFolder="C:\Temp"; CutoffDays=7 } }
        $j.CutoffDays=7 + ($i % 10)
        $j | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cfgPath -Encoding utf8
    }
}
Start-Sleep -Milliseconds 500
Write-HarnessLog "KILL mid-save (job running)"
Stop-Job $job -ErrorAction SilentlyContinue
Remove-Job $job -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 200

# Verify file is still valid JSON or fallback
try{
    $final=Get-Content $cfgPath -Raw | ConvertFrom-Json
    Write-HarnessLog "POST valid JSON CutoffDays=$($final.CutoffDays) (expect 7-16)"
    $valid=$true
} catch {
    Write-HarnessLog "POST invalid JSON: $_"
    $valid=$false
    # Check if file is truncated
    $len=(Get-Item $cfgPath -ErrorAction SilentlyContinue).Length
    Write-HarnessLog "POST len $len"
}

# Try to run DryRun via SDK to see if app can still read it
$scriptPs=Join-Path $RepoRoot "scripts\TempCleanup\TempCleanup.ps1"
$iss=[System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
$iss.ExecutionPolicy=[Microsoft.PowerShell.ExecutionPolicy]::Bypass
$ps=[PowerShell]::Create($iss)
$ps.AddCommand($scriptPs) | Out-Null
$ps.AddParameter("ConfigPath",$cfgPath) | Out-Null
$ps.AddParameter("DryRun",[System.Management.Automation.SwitchParameter]::Present) | Out-Null
$out=$ps.Invoke()
Write-HarnessLog "DRYRUN after kill Warning=$($ps.Streams.Warning.Count) Error=$($ps.Streams.Error.Count) count=$($out.Count)"

# Restore if corrupted, else keep last
if(-not $valid){
    $orig | Set-Content -LiteralPath $cfgPath -Encoding utf8
    Write-HarnessLog "RESTORED original due to corruption"
} else {
    Write-HarnessLog "No restore needed, file valid"
}

Write-HarnessLog "RESULT: $(if($valid){'Success, no corruption, last-writer-wins'} else {'Failed, corruption'})"
Write-HarnessLog "=== CAT4B END ==="

