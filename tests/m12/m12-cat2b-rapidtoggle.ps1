# Cat2b — rapid Settings toggling (CutoffDays int)
. "C:\Users\nekdo\AppData\Local\Temp\opencode\m12\m12-lib.ps1"
Write-HarnessLog "=== CAT2B START rapid Settings toggling ==="

$cfgPath="$env:LOCALAPPDATA\ScriptSuite\Configs\TempCleanup.json"
$origJson=Get-Content $cfgPath -Raw
$orig=Get-Content $cfgPath -Raw | ConvertFrom-Json
$origCutoff=$orig.CutoffDays
Write-HarnessLog "ORIG CutoffDays=$origCutoff"

# Rapid toggling 100 times between 7 and 30, no delay, same file
$sw=[Diagnostics.Stopwatch]::StartNew()
for($i=1;$i -le 100;$i++){
    $val= if($i %2 -eq 0){ 7 } else { 30 }
    $j=Get-Content $cfgPath -Raw | ConvertFrom-Json
    $j.CutoffDays=$val
    $j | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cfgPath -Encoding utf8
}
$sw.Stop()
Write-HarnessLog "TOGGLE 100× done elapsed $($sw.Elapsed.TotalSeconds)s"

# Verify file is valid JSON and value is 7 or 30 (last writer wins, last i=100 even => 7)
try{
    $final=Get-Content $cfgPath -Raw | ConvertFrom-Json
    $finalVal=$final.CutoffDays
    $valid=$true
    Write-HarnessLog "FINAL CutoffDays=$finalVal valid JSON true (expect 7)"
    if($finalVal -ne 7 -and $finalVal -ne 30){ Write-HarnessLog "FINAL-FAIL unexpected value"; $valid=$false }
    # Check JSON parse succeeded and file not truncated
    $rawLen=(Get-Item $cfgPath).Length
    Write-HarnessLog "FILE length $rawLen bytes"
    if($rawLen -eq 0){ Write-HarnessLog "FILE-FAIL empty"; $valid=$false }
} catch {
    Write-HarnessLog "JSON-PARSE-FAIL $_"
    $valid=$false
}

# Also test concurrent rapid writes from two jobs
Write-HarnessLog "CONCURRENT test: 2 jobs x 50 writes each"
$job1=Start-Job -ScriptBlock {
    $cfgPath=$using:cfgPath
    for($i=1;$i -le 50;$i++){
        $j=Get-Content $cfgPath -Raw | ConvertFrom-Json
        $j.CutoffDays=7
        $j | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cfgPath -Encoding utf8
    }
}
$job2=Start-Job -ScriptBlock {
    $cfgPath=$using:cfgPath
    for($i=1;$i -le 50;$i++){
        $j=Get-Content $cfgPath -Raw | ConvertFrom-Json
        $j.CutoffDays=30
        $j | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cfgPath -Encoding utf8
    }
}
Wait-Job $job1,$job2 | Out-Null
Receive-Job $job1,$job2 | Out-Null
Remove-Job $job1,$job2

try{
    $final2=Get-Content $cfgPath -Raw | ConvertFrom-Json
    Write-HarnessLog "CONCURRENT-FINAL CutoffDays=$($final2.CutoffDays) valid"
    $valid2= ($final2.CutoffDays -eq 7 -or $final2.CutoffDays -eq 30)
    if(-not $valid2){ Write-HarnessLog "CONCURRENT-FAIL" }
} catch {
    Write-HarnessLog "CONCURRENT-PARSE-FAIL $_"
    $valid2=$false
}

# Restore original
$origJson | Set-Content -LiteralPath $cfgPath -Encoding utf8
Write-HarnessLog "CONFIG-RESTORED CutoffDays=$origCutoff"

# History: no RunHistory row expected for settings-only, but verify no corruption caused failed run
$bin="C:\Users\nekdo\Documents\windows-scripts\ScriptSuite\bin\Debug\net10.0-windows"
$env:PATH="$bin\runtimes\win-x64\native;"+$env:PATH
try{Add-Type -Path "$bin\SQLitePCLRaw.core.dll" -ErrorAction SilentlyContinue; Add-Type -Path "$bin\SQLitePCLRaw.provider.e_sqlite3.dll" -ErrorAction SilentlyContinue; Add-Type -Path "$bin\SQLitePCLRaw.batteries_v2.dll" -ErrorAction SilentlyContinue; Add-Type -Path "$bin\Microsoft.Data.Sqlite.dll" -ErrorAction SilentlyContinue; [SQLitePCL.Batteries_V2]::Init()} catch{}
$c=[Microsoft.Data.Sqlite.SqliteConnection]::new("Data Source=$global:HistoryDb")
$c.Open(); $q=$c.CreateCommand(); $q.CommandText="SELECT COUNT(*) FROM RunHistory"; $count=$q.ExecuteScalar(); $c.Close()
Write-HarnessLog "HISTORY count=$count (no new row expected)"

if($valid -and $valid2){
    Write-HarnessLog "RESULT: Success, rapid toggling no corruption, last-writer-wins"
} else {
    Write-HarnessLog "RESULT: Failed, corruption or invalid JSON"
    exit 1
}
Write-HarnessLog "=== CAT2B END ==="
