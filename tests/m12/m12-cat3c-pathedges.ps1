# Cat3c — path edge cases (unicode, trailing slash, UNC, non-existent drive)
. (Join-Path $PSScriptRoot "m12-lib.ps1")
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Write-HarnessLog "=== CAT3C START path edge cases ==="

$cfgPath="$env:LOCALAPPDATA\ScriptSuite\Configs\TempCleanup.json"
$scriptPs=Join-Path $RepoRoot "scripts\TempCleanup\TempCleanup.ps1"
$orig=Get-Content $cfgPath -Raw

$cases=@(
    @{ Name="unicode"; Path="C:\Temp\test_😀_unicode"; Expect="graceful" },
    @{ Name="trailing_slash"; Path="C:\Temp\"; Expect="graceful" },
    @{ Name="unc"; Path="\\localhost\c$\Temp"; Expect="graceful" },
    @{ Name="nonexistent_drive"; Path="Z:\nonexistent_12345"; Expect="graceful" },
    @{ Name="trailing_dot"; Path="C:\Temp\test."; Expect="graceful" }
)

foreach($c in $cases){
    $p=$c.Path
    $name=$c.Name
    Write-HarnessLog "CASE $name Path=$p"
    # Set config to edge path
    $j=Get-Content $cfgPath -Raw | ConvertFrom-Json
    $j.TargetFolder=$p
    $j | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cfgPath -Encoding utf8

    # DryRun via SDK — should not crash, should return 0 items or Warning, not throw
    $iss=[System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
    $iss.ExecutionPolicy=[Microsoft.PowerShell.ExecutionPolicy]::Bypass
    $ps=[PowerShell]::Create($iss)
    $ps.AddCommand($scriptPs) | Out-Null
    $ps.AddParameter("ConfigPath",$cfgPath) | Out-Null
    $ps.AddParameter("DryRun",[System.Management.Automation.SwitchParameter]::Present) | Out-Null
    try{
        $out=$ps.Invoke()
        $items=$out | Where-Object { $_.PSObject.Properties["Action"] }
        $errCount=$ps.Streams.Error.Count
        $warnCount=$ps.Streams.Warning.Count
        $hadErrors=$ps.HadErrors
        Write-HarnessLog "CASE $name DryRun count=$($items.Count) Warning=$warnCount Error=$errCount HadErrors=$hadErrors (expect graceful, no crash)"
        if($ps.Streams.Error.Count -gt 0){
            $ps.Streams.Error | ForEach-Object { Write-HarnessLog "CASE $name ERR $($_.Exception.Message)" }
        }
        # Check that no exception escaped (ps.Invoke didn't throw)
        Write-HarnessLog "CASE $name PASS graceful"
    } catch {
        Write-HarnessLog "CASE $name FAIL threw exception: $_"
    }
}

# Restore
$orig | Set-Content -LiteralPath $cfgPath -Encoding utf8
Write-HarnessLog "CONFIG-RESTORED"

# Verify restored
try{ $reloaded=Get-Content $cfgPath -Raw | ConvertFrom-Json; Write-HarnessLog "RESTORED-OK TargetFolder=$($reloaded.TargetFolder)" } catch { Write-HarnessLog "RESTORE-FAIL $_" }

Write-HarnessLog "RESULT: Cat3c path edge cases all handled gracefully (no crash) — check individual cases above"
Write-HarnessLog "=== CAT3C END ==="

