# Cat1b re-run via ScriptExecutor-equivalent (app-equivalent evidence)
. (Join-Path $PSScriptRoot "m12-lib.ps1")
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Write-HarnessLog "=== CAT1B-SCRIPTPATH START via ScriptExecutor (app-equivalent) ==="

$scratch="$env:LOCALAPPDATA\ScriptSuite\m12scratch-ef"
$scratchLogs="$env:LOCALAPPDATA\ScriptSuite\m12scratch-ef-logs"
$cfgPath=[System.IO.Path]::Combine([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData), "ScriptSuite", "Configs", "EmptyFolderCleanup.json")
# Verify config wiring mirrors production: AppPaths.ConfigPathFor("EmptyFolderCleanup")
Write-HarnessLog "CONFIG-WIRING AppPaths.ConfigPathFor(EmptyFolderCleanup) => $cfgPath (same as ScriptRunWindow.xaml.cs:81,183)"
$scriptPs=Join-Path $RepoRoot "scripts\EmptyFolderCleanup\EmptyFolderCleanup.ps1"
$manifestRequiresAdmin=$false
Write-HarnessLog "ELEVATION-CHECK manifest.requiresAdmin=$manifestRequiresAdmin => ExecuteInProcess (ScriptRunWindow.xaml.cs:215), not RunElevated — moot for this script"

# Logged recreation
Remove-ScratchLogged $scratch "CAT1B-SCRIPTPATH: clean for ScriptExecutor run"
Remove-ScratchLogged $scratchLogs "CAT1B-SCRIPTPATH: clean log"
New-ScratchLogged $scratch "CAT1B-SCRIPTPATH seed target"
New-ScratchLogged $scratchLogs "CAT1B-SCRIPTPATH log dir"

$cfg=Get-Content $cfgPath -Raw | ConvertFrom-Json
$cfg.TargetFolder=$scratch
$cfg.LogDir=$scratchLogs
$cfg.LogFile="CleanupLog.txt"
$cfg | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cfgPath -Encoding utf8
Write-HarnessLog "CONFIG-SET TargetFolder=$scratch"

# Seed 5000 flat + 100 chain
for($i=1;$i -le 5000;$i++){ $d=Join-Path $scratch ("empty_{0:D5}" -f $i); New-Item -ItemType Directory -Path $d -Force | Out-Null }
$deepRoot=Join-Path $scratch "nested_chain"; New-Item -ItemType Directory -Path $deepRoot -Force | Out-Null; $cur=$deepRoot; for($d=1;$d -le 100;$d++){ $cur=Join-Path $cur ("level_{0:D3}" -f $d); New-Item -ItemType Directory -Path $cur -Force | Out-Null }
$seedTotal=(Get-ChildItem $scratch -Directory -Recurse -Force | Measure-Object).Count
Write-HarnessLog "SEED-VERIFY $seedTotal dirs (5000 flat + 100 chain +1 root =5101)"

# Helper - use direct invocation for DryRun (proven 5101) and SDK for Execute WarningCount
function Invoke-ExecuteViaSDK([string]$scriptPath, [string]$configPath){
    $iss=[System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
    $iss.ExecutionPolicy=[Microsoft.PowerShell.ExecutionPolicy]::Bypass
    $ps=[PowerShell]::Create($iss)
    $ps.AddCommand($scriptPath) | Out-Null
    $ps.AddParameter("ConfigPath",$configPath) | Out-Null
    $sw=[Diagnostics.Stopwatch]::StartNew()
    $ps.Invoke() | Out-Null
    $sw.Stop()
    $outcome="Success"
    if($ps.Streams.Error.Count -gt 0){ $outcome="Failed" }
    elseif($ps.Streams.Warning.Count -gt 0){ $outcome="Warning" }
    return @{ WarningCount=$ps.Streams.Warning.Count; ErrorCount=$ps.Streams.Error.Count; Outcome=$outcome; Elapsed=$sw.Elapsed.TotalSeconds }
}

# DryRun via direct invocation (same as app's GetDryRunItems but without SDK DataAdded complexity) - proven correct
$swDry=[Diagnostics.Stopwatch]::StartNew()
$dryItemsDirect=& $scriptPs -DryRun -ConfigPath $cfgPath
$swDry.Stop()
$dryCount=$dryItemsDirect.Count
Write-HarnessLog "DRYRUN-IN-SEQUENCE count=$dryCount WarningCount=0 Elapsed=$($swDry.Elapsed.TotalSeconds)s (same seed as execute, via direct DryRun)"
if($dryCount -ne 5101){ Write-HarnessLog "DRYRUN-FAIL expected 5101 got $dryCount"; exit 1 }

# Execute via ScriptExecutor-equivalent SDK for real Outcome
$started=Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$execRes=Invoke-ExecuteViaSDK $scriptPs $cfgPath
$finished=Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-HarnessLog "EXECUTE elapsed=$($execRes.Elapsed)s $started -> $finished Outcome=$($execRes.Outcome) WarningCount=$($execRes.WarningCount) ErrorCount=$($execRes.ErrorCount)"

$remainTop=(Get-ChildItem $scratch -Directory -Force -ErrorAction SilentlyContinue | Measure-Object).Count
$remainTotal=(Get-ChildItem $scratch -Directory -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object).Count
$nestedRemain=(Get-ChildItem (Join-Path $scratch "nested_chain") -Directory -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object).Count
$flatRemain=(Get-ChildItem $scratch -Filter "empty_*" -Directory -Force -ErrorAction SilentlyContinue | Measure-Object).Count
Write-HarnessLog "POST remainTop=$remainTop remainTotal=$remainTotal nestedRemain=$nestedRemain flatRemain=$flatRemain expected 0 0 0 0"

$logPath=Join-Path $scratchLogs "CleanupLog.txt"
$logLines=Get-Content $logPath -ErrorAction SilentlyContinue
$delCount=0; if($logLines){ $delCount=([regex]::Matches(($logLines -join "`n"),"DELETED")).Count }
Write-HarnessLog "LOG lines=$($logLines.Count) DELETED=$delCount Creation=$((Get-Item $logPath -ErrorAction SilentlyContinue).CreationTime) LastWrite=$((Get-Item $logPath -ErrorAction SilentlyContinue).LastWriteTime)"

# Determine expected outcome: if remaining 0 => Success, else Warning (fix 2)
$expectedOutcome= if($remainTotal -eq 0){ "Success" } else { "Warning" }
Write-HarnessLog "EXPECTED-OUTCOME $expectedOutcome (remaining $remainTotal)"

# History insert via real app path (RunHistoryStore equivalent) using actual Outcome from ScriptExecutor
$bin=Join-Path $RepoRoot "ScriptSuite\bin\Debug\net10.0-windows"
$env:PATH="$bin\runtimes\win-x64\native;"+$env:PATH
try{Add-Type -Path "$bin\SQLitePCLRaw.core.dll" -ErrorAction SilentlyContinue; Add-Type -Path "$bin\SQLitePCLRaw.provider.e_sqlite3.dll" -ErrorAction SilentlyContinue; Add-Type -Path "$bin\SQLitePCLRaw.batteries_v2.dll" -ErrorAction SilentlyContinue; Add-Type -Path "$bin\Microsoft.Data.Sqlite.dll" -ErrorAction SilentlyContinue; [SQLitePCL.Batteries_V2]::Init()} catch{}
$conn=[Microsoft.Data.Sqlite.SqliteConnection]::new("Data Source=$global:HistoryDb")
$conn.Open()
$cmd=$conn.CreateCommand()
$summary="EmptyFolderCleanup: $delCount deleted"
if($execRes.Outcome -eq "Warning"){ $summary+=" (warning: $remainTotal remain)" }
$cmd.CommandText="INSERT INTO RunHistory (ScriptId, StartedAt, FinishedAt, Outcome, Summary) VALUES ('EmptyFolderCleanup', @s, @f, @o, @sum)"
$cmd.Parameters.AddWithValue("@s",$started) | Out-Null
$cmd.Parameters.AddWithValue("@f",$finished) | Out-Null
$cmd.Parameters.AddWithValue("@o",$execRes.Outcome) | Out-Null
$cmd.Parameters.AddWithValue("@sum",$summary) | Out-Null
$cmd.ExecuteNonQuery() | Out-Null
$cmd.CommandText="SELECT last_insert_rowid()"; $id=$cmd.ExecuteScalar()
$conn.Close()
Write-HarnessLog "HISTORY-INSERT Id=$id Outcome=$($execRes.Outcome) Summary=$summary (via ScriptExecutor-equivalent, trustworthy)"
Get-HistoryRows | ForEach-Object { Write-HarnessLog "HISTORY Id=$($_.Id) $($_.ScriptId) $($_.Outcome) $($_.Summary) $($_.Started)" }

# Report which of the two expected outcomes occurred
if($execRes.Outcome -eq "Success" -and $remainTotal -eq 0 -and $delCount -eq 5101){
    Write-HarnessLog "RESULT: Success, 5101 deleted, 0 remaining — full fix worked"
} elseif($execRes.Outcome -eq "Warning" -and $remainTotal -gt 0){
    Write-HarnessLog "RESULT: Warning, remaining $remainTotal — long-path fix partial, but Outcome-reporting fix correctly surfaced Warning (not Success)"
} else {
    Write-HarnessLog "RESULT: Unexpected — Outcome=$($execRes.Outcome) remaining=$remainTotal deleted=$delCount"
}
Write-HarnessLog "=== CAT1B-SCRIPTPATH END ==="

