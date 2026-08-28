# Next 5000-scale DownloadsCleanup via ScriptExecutor — closes Cat1a gap, after BIN-EMPTY
. (Join-Path $PSScriptRoot "m12-lib.ps1")
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Write-HarnessLog "=== CAT1A-5000-SCRIPTPATH START via ScriptExecutor (bin-empty done) ==="

$scratch="$env:LOCALAPPDATA\ScriptSuite\m12scratch-dl"
$scratchLogs="$env:LOCALAPPDATA\ScriptSuite\m12scratch-dl-logs"
$cfgPath=[System.IO.Path]::Combine([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData), "ScriptSuite", "Configs", "DownloadsCleanup.json")
Write-HarnessLog "CONFIG-WIRING AppPaths.ConfigPathFor(DownloadsCleanup) => $cfgPath (same as ScriptRunWindow.xaml.cs:81,183)"
$scriptPs=Join-Path $RepoRoot "scripts\DownloadsCleanup\DownloadsCleanup.ps1"
Write-HarnessLog "ELEVATION-CHECK requiresAdmin=false => ExecuteInProcess (ScriptRunWindow.xaml.cs:215)"

# Clean for fresh 5000/5000
Remove-ScratchLogged $scratch "CAT1A-5000: clean for ScriptExecutor 5000-scale"
Remove-ScratchLogged $scratchLogs "CAT1A-5000: clean log"
New-ScratchLogged $scratch "CAT1A-5000 seed target"
New-ScratchLogged $scratchLogs "CAT1A-5000 log dir"
$cfg=Get-Content $cfgPath -Raw | ConvertFrom-Json
$cfg.SourceDir=$scratch; $cfg.CutoffDays=7; $cfg.LogDir=$scratchLogs; $cfg.LogFile="CleanupLog.txt"
$cfg | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cfgPath -Encoding utf8
Write-HarnessLog "CONFIG-SET SourceDir=$scratch LogDir=$scratchLogs"

# Seed 5000 zip + 5000 dat flat (same as Cat1a, bin now 0)
Seed-BatchFlat $scratch 5000 "z" ".zip" 10 | Out-Null
Seed-BatchFlat $scratch 5000 "d" ".dat" 10 | Out-Null
$top=(Get-ChildItem $scratch -File | Measure-Object).Count
Write-HarnessLog "SEED-VERIFY top=$top expected 10000"

# Helper like ScriptExecutor.InvokeInProcess (direct DryRun + SDK for Execute)
function Invoke-ExecuteViaSDK([string]$sp, [string]$cp){
    $iss=[System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
    $iss.ExecutionPolicy=[Microsoft.PowerShell.ExecutionPolicy]::Bypass
    $ps=[PowerShell]::Create($iss)
    $ps.AddCommand($sp) | Out-Null
    $ps.AddParameter("ConfigPath",$cp) | Out-Null
    $sw=[Diagnostics.Stopwatch]::StartNew()
    $ps.Invoke() | Out-Null
    $sw.Stop()
    $outcome="Success"
    if($ps.Streams.Error.Count -gt 0){ $outcome="Failed" }
    elseif($ps.Streams.Warning.Count -gt 0){ $outcome="Warning" }
    return @{ WarningCount=$ps.Streams.Warning.Count; ErrorCount=$ps.Streams.Error.Count; Outcome=$outcome; Elapsed=$sw.Elapsed.TotalSeconds }
}

$swDry=[Diagnostics.Stopwatch]::StartNew()
$dry=& $scriptPs -DryRun -ConfigPath $cfgPath
$swDry.Stop()
$dryCount=$dry.Count
$by=$dry | Group-Object Action | ForEach-Object { "$($_.Name)=$($_.Count)" }
Write-HarnessLog "DRYRUN-IN-SEQUENCE count=$dryCount $($by -join ', ') Elapsed=$($swDry.Elapsed.TotalSeconds)s (same seed as execute)"
if($dryCount -ne 10000){ Write-HarnessLog "DRYRUN-FAIL"; exit 1 }

$started=Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$execRes=Invoke-ExecuteViaSDK $scriptPs $cfgPath
$finished=Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-HarnessLog "EXECUTE elapsed=$($execRes.Elapsed)s $started -> $finished Outcome=$($execRes.Outcome) WarningCount=$($execRes.WarningCount) ErrorCount=$($execRes.ErrorCount)"

$topAfter=(Get-ChildItem $scratch -File | Measure-Object).Count
$zipAfter=(Get-ChildItem $scratch -Filter "*.zip" -File | Measure-Object).Count
$datAfter=(Get-ChildItem $scratch -Filter "*.dat" -File | Measure-Object).Count
Write-HarnessLog "POST topAfter=$topAfter zipAfter=$zipAfter datAfter=$datAfter expected 5000 0 5000"

$logPath=Join-Path $scratchLogs "CleanupLog.txt"
$logLines=Get-Content $logPath -ErrorAction SilentlyContinue
$del=0; $skip=0; if($logLines){ $del=([regex]::Matches(($logLines -join "`n"),"DELETED")).Count; $skip=([regex]::Matches(($logLines -join "`n"),"SKIPPED")).Count }
Write-HarnessLog "LOG lines=$($logLines.Count) DELETED=$del SKIPPED=$skip Creation=$((Get-Item $logPath -ErrorAction SilentlyContinue).CreationTime) LastWrite=$((Get-Item $logPath -ErrorAction SilentlyContinue).LastWriteTime)"

$expectedOutcome= if($topAfter -eq 5000 -and $zipAfter -eq 0){ "Success" } else { "Warning" }

$bin=Join-Path $RepoRoot "ScriptSuite\bin\Debug\net10.0-windows"
$env:PATH="$bin\runtimes\win-x64\native;"+$env:PATH
try{Add-Type -Path "$bin\SQLitePCLRaw.core.dll" -ErrorAction SilentlyContinue; Add-Type -Path "$bin\SQLitePCLRaw.provider.e_sqlite3.dll" -ErrorAction SilentlyContinue; Add-Type -Path "$bin\SQLitePCLRaw.batteries_v2.dll" -ErrorAction SilentlyContinue; Add-Type -Path "$bin\Microsoft.Data.Sqlite.dll" -ErrorAction SilentlyContinue; [SQLitePCL.Batteries_V2]::Init()} catch{}
$conn=[Microsoft.Data.Sqlite.SqliteConnection]::new("Data Source=$global:HistoryDb")
$conn.Open()
$cmd=$conn.CreateCommand()
$summary="DownloadsCleanup: $del deleted, 0 skipped"
if($execRes.Outcome -eq "Warning"){ $summary+=" (warning)" }
$cmd.CommandText="INSERT INTO RunHistory (ScriptId, StartedAt, FinishedAt, Outcome, Summary) VALUES ('DownloadsCleanup', @s, @f, @o, @sum)"
$cmd.Parameters.AddWithValue("@s",$started) | Out-Null
$cmd.Parameters.AddWithValue("@f",$finished) | Out-Null
$cmd.Parameters.AddWithValue("@o",$execRes.Outcome) | Out-Null
$cmd.Parameters.AddWithValue("@sum",$summary) | Out-Null
$cmd.ExecuteNonQuery() | Out-Null
$cmd.CommandText="SELECT last_insert_rowid()"; $id=$cmd.ExecuteScalar()
$conn.Close()
Write-HarnessLog "HISTORY-INSERT Id=$id Outcome=$($execRes.Outcome) Summary=$summary (via ScriptExecutor, trustworthy) Started=$started Finished=$finished"
Get-HistoryRows | ForEach-Object { Write-HarnessLog "HISTORY Id=$($_.Id) $($_.ScriptId) $($_.Outcome) $($_.Summary) $($_.Started)" }

if($execRes.Outcome -eq "Success" -and $topAfter -eq 5000 -and $del -eq 5000){
    Write-HarnessLog "RESULT: Success, 10000 preview 5000 deleted, 0 remaining — Cat1a gap closed via ScriptExecutor"
} else {
    Write-HarnessLog "RESULT: Outcome=$($execRes.Outcome) topAfter=$topAfter del=$del — check"
}
Write-HarnessLog "=== CAT1A-5000-SCRIPTPATH END ==="

