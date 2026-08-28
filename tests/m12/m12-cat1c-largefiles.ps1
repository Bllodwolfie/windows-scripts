# Cat1c — multi-GB file/size formatting via TempCleanup
. (Join-Path $PSScriptRoot "m12-lib.ps1")
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Write-HarnessLog "=== CAT1C START multi-GB size formatting ==="

$scratch="$env:LOCALAPPDATA\ScriptSuite\m12scratch-tc-1c"
$scratchLogs="$env:LOCALAPPDATA\ScriptSuite\m12scratch-tc-1c-logs"
$cfgPath=[System.IO.Path]::Combine([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData), "ScriptSuite", "Configs", "TempCleanup.json")
Write-HarnessLog "CONFIG-WIRING AppPaths.ConfigPathFor(TempCleanup) => $cfgPath"
$scriptPs=Join-Path $RepoRoot "scripts\TempCleanup\TempCleanup.ps1"

Remove-ScratchLogged $scratch "CAT1C: clean for large files"
Remove-ScratchLogged $scratchLogs "CAT1C: clean log"
New-ScratchLogged $scratch "CAT1C seed target"
New-ScratchLogged $scratchLogs "CAT1C log dir"

$cfg=Get-Content $cfgPath -Raw | ConvertFrom-Json
$cfg.TargetFolder=$scratch; $cfg.CutoffDays=7
$cfg | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cfgPath -Encoding utf8
Write-HarnessLog "CONFIG-SET TargetFolder=$scratch CutoffDays=7"

# Create sparse large files: 2GB, 5GB, 512MB, and 1KB control
function New-SparseFile([string]$path, [long]$len){
    $fs=[System.IO.File]::Create($path)
    $fs.SetLength($len)
    $fs.Close()
    # Try to mark sparse (best effort, not required for size formatting)
    try { & fsutil sparse setflag "$path" 2>$null | Out-Null } catch {}
    (Get-Item $path).LastWriteTime=(Get-Date).AddDays(-10)
}
New-SparseFile (Join-Path $scratch "big2GB.dat") (2GB)
New-SparseFile (Join-Path $scratch "big5GB.dat") (5GB)
New-SparseFile (Join-Path $scratch "mid512MB.dat") (512MB)
New-SparseFile (Join-Path $scratch "tiny1KB.dat") 1024
# Verify sizes as seen by Get-ChildItem
Get-ChildItem $scratch -File | ForEach-Object { Write-HarnessLog "SEED file $($_.Name) Length=$($_.Length) MB=$([math]::Round($_.Length/1MB,1))" }

$top=(Get-ChildItem $scratch -File | Measure-Object).Count
Write-HarnessLog "SEED-VERIFY top=$top expected 4"

# DryRun via SDK-equivalent (like ScriptExecutor) to capture Detail formatting
function Invoke-DryRunViaSDK([string]$sp, [string]$cp){
    $iss=[System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
    $iss.ExecutionPolicy=[Microsoft.PowerShell.ExecutionPolicy]::Bypass
    $ps=[PowerShell]::Create($iss)
    $ps.AddCommand($sp) | Out-Null
    $ps.AddParameter("ConfigPath",$cp) | Out-Null
    $ps.AddParameter("DryRun",[System.Management.Automation.SwitchParameter]::Present) | Out-Null
    $out=$ps.Invoke()
    $items=$out | Where-Object { $_.PSObject.Properties["Action"] }
    return @{ Items=$items; WarningCount=$ps.Streams.Warning.Count; ErrorCount=$ps.Streams.Error.Count; Count=$items.Count }
}
$swDry=[Diagnostics.Stopwatch]::StartNew()
$dryRes=Invoke-DryRunViaSDK $scriptPs $cfgPath
$swDry.Stop()
Write-HarnessLog "DRYRUN count=$($dryRes.Count) Warning=$($dryRes.WarningCount) Elapsed=$($swDry.Elapsed.TotalSeconds)s"
foreach($it in $dryRes.Items){ Write-HarnessLog "DRYRUN Detail $($it.Target | Split-Path -Leaf) => $($it.Detail)" }
# Verify formatting: each Detail should be "X.X MB, last modified YYYY-MM-DD" with N1
$expected=@{ "big2GB.dat"="2,048.0 MB"; "big5GB.dat"="5,120.0 MB"; "mid512MB.dat"="512.0 MB"; "tiny1KB.dat"="0.0 MB" }
$formatOk=$true
foreach($it in $dryRes.Items){
    $leaf=Split-Path $it.Target -Leaf
    $exp=$expected[$leaf]
    if($exp -and $it.Detail -notlike "*$exp*"){ Write-HarnessLog "FORMAT-FAIL $leaf expected $exp got $($it.Detail)"; $formatOk=$false }
}
if(-not $formatOk){ Write-HarnessLog "FORMAT-FAIL overall"; exit 1 }
Write-HarnessLog "FORMAT-OK all N1 MB formatting correct"

# Execute via SDK like ScriptExecutor
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
    return @{ Outcome=$outcome; WarningCount=$ps.Streams.Warning.Count; ErrorCount=$ps.Streams.Error.Count; Elapsed=$sw.Elapsed.TotalSeconds }
}
$started=Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$execRes=Invoke-ExecuteViaSDK $scriptPs $cfgPath
$finished=Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-HarnessLog "EXECUTE elapsed=$($execRes.Elapsed)s $started -> $finished Outcome=$($execRes.Outcome) Warning=$($execRes.WarningCount) Error=$($execRes.ErrorCount)"

$remain=(Get-ChildItem $scratch -File -ErrorAction SilentlyContinue | Measure-Object).Count
Write-HarnessLog "POST remain=$remain expected 0 (all old, all deletable)"

$logPath=Join-Path $scratchLogs "CleanupLog.txt"
$logLines=Get-Content $logPath -ErrorAction SilentlyContinue
$del=0; if($logLines){ $del=([regex]::Matches(($logLines -join "`n"),"DELETED")).Count }
Write-HarnessLog "LOG lines=$($logLines.Count) DELETED=$del Creation=$((Get-Item $logPath -ErrorAction SilentlyContinue).CreationTime) LastWrite=$((Get-Item $logPath -ErrorAction SilentlyContinue).LastWriteTime)"

# History via real app path
$bin=Join-Path $RepoRoot "ScriptSuite\bin\Debug\net10.0-windows"
$env:PATH="$bin\runtimes\win-x64\native;"+$env:PATH
try{Add-Type -Path "$bin\SQLitePCLRaw.core.dll" -ErrorAction SilentlyContinue; Add-Type -Path "$bin\SQLitePCLRaw.provider.e_sqlite3.dll" -ErrorAction SilentlyContinue; Add-Type -Path "$bin\SQLitePCLRaw.batteries_v2.dll" -ErrorAction SilentlyContinue; Add-Type -Path "$bin\Microsoft.Data.Sqlite.dll" -ErrorAction SilentlyContinue; [SQLitePCL.Batteries_V2]::Init()} catch{}
$conn=[Microsoft.Data.Sqlite.SqliteConnection]::new("Data Source=$global:HistoryDb")
$conn.Open()
$cmd=$conn.CreateCommand()
$summary="TempCleanup: $del deleted"
$cmd.CommandText="INSERT INTO RunHistory (ScriptId, StartedAt, FinishedAt, Outcome, Summary) VALUES ('TempCleanup', @s, @f, @o, @sum)"
$cmd.Parameters.AddWithValue("@s",$started) | Out-Null
$cmd.Parameters.AddWithValue("@f",$finished) | Out-Null
$cmd.Parameters.AddWithValue("@o",$execRes.Outcome) | Out-Null
$cmd.Parameters.AddWithValue("@sum",$summary) | Out-Null
$cmd.ExecuteNonQuery() | Out-Null
$cmd.CommandText="SELECT last_insert_rowid()"; $id=$cmd.ExecuteScalar()
$conn.Close()
Write-HarnessLog "HISTORY-INSERT Id=$id Outcome=$($execRes.Outcome) Summary=$summary"
Get-HistoryRows | ForEach-Object { Write-HarnessLog "HISTORY Id=$($_.Id) $($_.ScriptId) $($_.Outcome) $($_.Summary)" }

# Timing baseline: previous TempCleanup not yet measured, so establish baseline here
Write-HarnessLog "TIMING-BASELINE TempCleanup 4 files SDK $($execRes.Elapsed)s DryRun $($swDry.Elapsed.TotalSeconds)s"

if($execRes.Outcome -eq "Success" -and $remain -eq 0 -and $del -eq 4){
    Write-HarnessLog "RESULT: Success, 4 large files formatting correct, deleted"
} else {
    Write-HarnessLog "RESULT: Outcome=$($execRes.Outcome) remain=$remain del=$del"
}
Write-HarnessLog "=== CAT1C END ==="

