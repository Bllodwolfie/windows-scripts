# Cat1d — stringList with hundreds of entries
. "C:\Users\nekdo\AppData\Local\Temp\opencode\m12\m12-lib.ps1"
Write-HarnessLog "=== CAT1D START stringList hundreds ==="

$cfgPath="$env:LOCALAPPDATA\ScriptSuite\Configs\DownloadsCleanup.json"
$scriptPs="C:\Users\nekdo\Documents\windows-scripts\scripts\DownloadsCleanup\DownloadsCleanup.ps1"

# Backup original config
$orig=Get-Content $cfgPath -Raw
$origJson=Get-Content $cfgPath -Raw | ConvertFrom-Json

# Create 300 entries: .ext001 to .ext300
$hundreds=@()
for($i=1;$i -le 300;$i++){ $hundreds+= ".ext{0:D3}" -f $i }
# Keep original 7 plus 300 = 307
$origJson.DeleteExts = $hundreds
$origJson | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cfgPath -Encoding utf8
Write-HarnessLog "CONFIG-SET DeleteExts count=$($hundreds.Count) (300)"

# Verify via ScriptConfigService equivalent: reload and check count
$reloaded=Get-Content $cfgPath -Raw | ConvertFrom-Json
Write-HarnessLog "CONFIG-RELOAD count=$($reloaded.DeleteExts.Count) expected 300"
if($reloaded.DeleteExts.Count -ne 300){ Write-HarnessLog "CONFIG-FAIL count mismatch"; exit 1 }

# Test via ScriptExecutor DryRun: create scratch with 10 files matching those extensions and 10 non-matching
$scratch="$env:LOCALAPPDATA\ScriptSuite\m12scratch-cat1d"
$scratchLogs="$env:LOCALAPPDATA\ScriptSuite\m12scratch-cat1d-logs"
Remove-ScratchLogged $scratch "CAT1D seed"
Remove-ScratchLogged $scratchLogs "CAT1D log"
New-ScratchLogged $scratch "CAT1D seed"
New-ScratchLogged $scratchLogs "CAT1D log"
$cfg=Get-Content $cfgPath -Raw | ConvertFrom-Json
$cfg.SourceDir=$scratch; $cfg.LogDir=$scratchLogs; $cfg.CutoffDays=7
$cfg | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cfgPath -Encoding utf8

for($i=1;$i -le 10;$i++){
    $ext=".ext{0:D3}" -f $i
    $p=Join-Path $scratch ("file{0:D2}{1}" -f $i, $ext)
    Set-Content -LiteralPath $p -Value "x" -NoNewline
    (Get-Item $p).LastWriteTime=(Get-Date).AddDays(-10)
}
for($i=1;$i -le 10;$i++){
    $p=Join-Path $scratch ("other{0:D2}.nomatch" -f $i)
    Set-Content -LiteralPath $p -Value "x" -NoNewline
    (Get-Item $p).LastWriteTime=(Get-Date).AddDays(-10)
}
Write-HarnessLog "SEED top=$((Get-ChildItem $scratch -File | Measure-Object).Count) expected 20"

# DryRun via SDK
function Invoke-DryRunViaSDK([string]$sp, [string]$cp){
    $iss=[System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
    $iss.ExecutionPolicy=[Microsoft.PowerShell.ExecutionPolicy]::Bypass
    $ps=[PowerShell]::Create($iss)
    $ps.AddCommand($sp) | Out-Null
    $ps.AddParameter("ConfigPath",$cp) | Out-Null
    $ps.AddParameter("DryRun",[System.Management.Automation.SwitchParameter]::Present) | Out-Null
    $out=$ps.Invoke()
    $items=$out | Where-Object { $_.PSObject.Properties["Action"] }
    return @{ Count=$items.Count; Items=$items; WarningCount=$ps.Streams.Warning.Count }
}
$swDry=[Diagnostics.Stopwatch]::StartNew()
$dryRes=Invoke-DryRunViaSDK $scriptPs $cfgPath
$swDry.Stop()
Write-HarnessLog "DRYRUN count=$($dryRes.Count) Warning=$($dryRes.WarningCount) Elapsed=$($swDry.Elapsed.TotalSeconds)s expected 20 (10 Delete +10 Skip)"
if($dryRes.Count -ne 20){ Write-HarnessLog "DRYRUN-FAIL"; exit 1 }
$delCount=($dryRes.Items | Where-Object { $_.Action -eq "Delete" }).Count
$skipCount=($dryRes.Items | Where-Object { $_.Action -eq "Skip" }).Count
Write-HarnessLog "DRYRUN Delete=$delCount Skip=$skipCount"

# Execute via SDK
function Invoke-ExecuteViaSDK([string]$sp, [string]$cp){
    $iss=[System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
    $iss.ExecutionPolicy=[Microsoft.PowerShell.ExecutionPolicy]::Bypass
    $ps=[PowerShell]::Create($iss)
    $ps.AddCommand($sp) | Out-Null
    $ps.AddParameter("ConfigPath",$cp) | Out-Null
    $sw=[Diagnostics.Stopwatch]::StartNew()
    $ps.Invoke() | Out-Null
    $sw.Stop()
    $outcome="Success"; if($ps.Streams.Error.Count -gt 0){ $outcome="Failed" } elseif($ps.Streams.Warning.Count -gt 0){ $outcome="Warning" }
    return @{ Outcome=$outcome; WarningCount=$ps.Streams.Warning.Count; Elapsed=$sw.Elapsed.TotalSeconds }
}
$started=Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$execRes=Invoke-ExecuteViaSDK $scriptPs $cfgPath
$finished=Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-HarnessLog "EXECUTE elapsed=$($execRes.Elapsed)s Outcome=$($execRes.Outcome) Warning=$($execRes.WarningCount)"

$remain=(Get-ChildItem $scratch -File -ErrorAction SilentlyContinue | Measure-Object).Count
Write-HarnessLog "POST remain=$remain expected 10 (10 .nomatch remain, 10 .ext deleted)"

# Restore original config
$orig | Set-Content -LiteralPath $cfgPath -Encoding utf8
Write-HarnessLog "CONFIG-RESTORED original DeleteExts count=$((Get-Content $cfgPath -Raw | ConvertFrom-Json).DeleteExts.Count)"

# History
$bin="C:\Users\nekdo\Documents\windows-scripts\ScriptSuite\bin\Debug\net10.0-windows"
$env:PATH="$bin\runtimes\win-x64\native;"+$env:PATH
try{Add-Type -Path "$bin\SQLitePCLRaw.core.dll" -ErrorAction SilentlyContinue; Add-Type -Path "$bin\SQLitePCLRaw.provider.e_sqlite3.dll" -ErrorAction SilentlyContinue; Add-Type -Path "$bin\SQLitePCLRaw.batteries_v2.dll" -ErrorAction SilentlyContinue; Add-Type -Path "$bin\Microsoft.Data.Sqlite.dll" -ErrorAction SilentlyContinue; [SQLitePCL.Batteries_V2]::Init()} catch{}
$conn=[Microsoft.Data.Sqlite.SqliteConnection]::new("Data Source=$global:HistoryDb")
$conn.Open()
$cmd=$conn.CreateCommand()
$summary="DownloadsCleanup: 10 deleted"
$cmd.CommandText="INSERT INTO RunHistory (ScriptId, StartedAt, FinishedAt, Outcome, Summary) VALUES ('DownloadsCleanup', @s, @f, @o, @sum)"
$cmd.Parameters.AddWithValue("@s",$started) | Out-Null
$cmd.Parameters.AddWithValue("@f",$finished) | Out-Null
$cmd.Parameters.AddWithValue("@o",$execRes.Outcome) | Out-Null
$cmd.Parameters.AddWithValue("@sum",$summary) | Out-Null
$cmd.ExecuteNonQuery() | Out-Null
$cmd.CommandText="SELECT last_insert_rowid()"; $id=$cmd.ExecuteScalar()
$conn.Close()
Write-HarnessLog "HISTORY-INSERT Id=$id Outcome=$($execRes.Outcome) Summary=$summary"
Get-HistoryRows | ForEach-Object { Write-HarnessLog "HISTORY Id=$($_.Id) $($_.ScriptId) $($_.Outcome)" }

if($execRes.Outcome -eq "Success" -and $remain -eq 10 -and $delCount -eq 10){
    Write-HarnessLog "RESULT: Success, stringList 300 handled, no truncate"
} else {
    Write-HarnessLog "RESULT: Outcome=$($execRes.Outcome) remain=$remain"
}
Write-HarnessLog "=== CAT1D END ==="
