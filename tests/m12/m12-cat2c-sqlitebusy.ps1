# Cat2c — two ScriptSuite.exe instances writing history simultaneously (SQLITE_BUSY)
. (Join-Path $PSScriptRoot "m12-lib.ps1")
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Write-HarnessLog "=== CAT2C START two instances history SQLITE_BUSY ==="

$bin=Join-Path $RepoRoot "ScriptSuite\bin\Debug\net10.0-windows"
$env:PATH="$bin\runtimes\win-x64\native;"+$env:PATH

# Get current history count
try{Add-Type -Path "$bin\SQLitePCLRaw.core.dll" -ErrorAction SilentlyContinue; Add-Type -Path "$bin\SQLitePCLRaw.provider.e_sqlite3.dll" -ErrorAction SilentlyContinue; Add-Type -Path "$bin\SQLitePCLRaw.batteries_v2.dll" -ErrorAction SilentlyContinue; Add-Type -Path "$bin\Microsoft.Data.Sqlite.dll" -ErrorAction SilentlyContinue; [SQLitePCL.Batteries_V2]::Init()} catch{}
$c=[Microsoft.Data.Sqlite.SqliteConnection]::new("Data Source=$global:HistoryDb")
$c.Open(); $q=$c.CreateCommand(); $q.CommandText="SELECT COUNT(*) FROM RunHistory"; $before=$q.ExecuteScalar(); $c.Close()
Write-HarnessLog "HISTORY-BEFORE $before"

# Launch two jobs that both insert at same time
$job1=Start-Job -ScriptBlock {
    $bin=Join-Path $RepoRoot "ScriptSuite\bin\Debug\net10.0-windows"
    $env:PATH="$bin\runtimes\win-x64\native;"+$env:PATH
    Add-Type -Path "$bin\SQLitePCLRaw.core.dll"
    Add-Type -Path "$bin\SQLitePCLRaw.provider.e_sqlite3.dll"
    Add-Type -Path "$bin\SQLitePCLRaw.batteries_v2.dll"
    Add-Type -Path "$bin\Microsoft.Data.Sqlite.dll"
    [SQLitePCL.Batteries_V2]::Init()
    $db="$env:LOCALAPPDATA\ScriptSuite\history.db"
    $c=[Microsoft.Data.Sqlite.SqliteConnection]::new("Data Source=$db")
    $c.Open()
    $cmd=$c.CreateCommand()
    $cmd.CommandText="INSERT INTO RunHistory (ScriptId, StartedAt, FinishedAt, Outcome, Summary) VALUES ('TempCleanup', datetime('now','localtime'), datetime('now','localtime'), 'Success', 'Cat2c job1')"
    try{ $cmd.ExecuteNonQuery() | Out-Null; Write-Output "job1 Success" } catch{ Write-Output "job1 Failed: $_" }
    $c.Close()
}
$job2=Start-Job -ScriptBlock {
    $bin=Join-Path $RepoRoot "ScriptSuite\bin\Debug\net10.0-windows"
    $env:PATH="$bin\runtimes\win-x64\native;"+$env:PATH
    Add-Type -Path "$bin\SQLitePCLRaw.core.dll"
    Add-Type -Path "$bin\SQLitePCLRaw.provider.e_sqlite3.dll"
    Add-Type -Path "$bin\SQLitePCLRaw.batteries_v2.dll"
    Add-Type -Path "$bin\Microsoft.Data.Sqlite.dll"
    [SQLitePCL.Batteries_V2]::Init()
    $db="$env:LOCALAPPDATA\ScriptSuite\history.db"
    $c=[Microsoft.Data.Sqlite.SqliteConnection]::new("Data Source=$db")
    $c.Open()
    $cmd=$c.CreateCommand()
    $cmd.CommandText="INSERT INTO RunHistory (ScriptId, StartedAt, FinishedAt, Outcome, Summary) VALUES ('TempCleanup', datetime('now','localtime'), datetime('now','localtime'), 'Success', 'Cat2c job2')"
    try{ $cmd.ExecuteNonQuery() | Out-Null; Write-Output "job2 Success" } catch{ Write-Output "job2 Failed: $_" }
    $c.Close()
}

# Start both near-simultaneously
Wait-Job $job1,$job2 | Out-Null
$res1=Receive-Job $job1
$res2=Receive-Job $job2
Remove-Job $job1,$job2
Write-HarnessLog "JOB1 $res1"
Write-HarnessLog "JOB2 $res2"

# Check for SQLITE_BUSY in either
$busy= ($res1 -like "*BUSY*") -or ($res2 -like "*BUSY*") -or ($res1 -like "*busy*") -or ($res2 -like "*busy*") -or ($res1 -like "*locked*") -or ($res2 -like "*locked*")
if($busy){
    Write-HarnessLog "RESULT: SQLITE_BUSY observed — confirms known WAL/busy_timeout gap (expected)"
} else {
    # Check if both succeeded
    if($res1 -like "*Success*" -and $res2 -like "*Success*"){
        Write-HarnessLog "RESULT: Both inserts succeeded, no BUSY — gap not triggered at this scale (may need tighter timing or WAL)"
    } else {
        Write-HarnessLog "RESULT: One failed but not BUSY: $res1 / $res2"
    }
}

$c2=[Microsoft.Data.Sqlite.SqliteConnection]::new("Data Source=$global:HistoryDb")
$c2.Open(); $q2=$c2.CreateCommand(); $q2.CommandText="SELECT COUNT(*) FROM RunHistory"; $after=$q2.ExecuteScalar(); $c2.Close()
Write-HarnessLog "HISTORY-AFTER $after (before $before, delta $($after-$before))"

# Check history rows for Cat2c
$c3=[Microsoft.Data.Sqlite.SqliteConnection]::new("Data Source=$global:HistoryDb")
$c3.Open(); $q3=$c3.CreateCommand(); $q3.CommandText="SELECT Id, Summary FROM RunHistory ORDER BY Id DESC LIMIT 5"; $r=$q3.ExecuteReader(); while($r.Read()){ Write-HarnessLog "HISTORY Id=$($r.GetInt64(0)) $($r.GetString(1))"}; $r.Close(); $c3.Close()

Write-HarnessLog "=== CAT2C END ==="

