# Cat4c — kill mid-DB-insert
. (Join-Path $PSScriptRoot "m12-lib.ps1")
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Write-HarnessLog "=== CAT4C START kill mid-DB-insert ==="

$bin=Join-Path $RepoRoot "ScriptSuite\bin\Debug\net10.0-windows"
$env:PATH="$bin\runtimes\win-x64\native;"+$env:PATH
try{Add-Type -Path "$bin\SQLitePCLRaw.core.dll" -ErrorAction SilentlyContinue; Add-Type -Path "$bin\SQLitePCLRaw.provider.e_sqlite3.dll" -ErrorAction SilentlyContinue; Add-Type -Path "$bin\SQLitePCLRaw.batteries_v2.dll" -ErrorAction SilentlyContinue; Add-Type -Path "$bin\Microsoft.Data.Sqlite.dll" -ErrorAction SilentlyContinue; [SQLitePCL.Batteries_V2]::Init()} catch{}

# Get before count
$c=[Microsoft.Data.Sqlite.SqliteConnection]::new("Data Source=$global:HistoryDb")
$c.Open(); $q=$c.CreateCommand(); $q.CommandText="SELECT COUNT(*) FROM RunHistory"; $before=$q.ExecuteScalar(); $c.Close()
Write-HarnessLog "HISTORY-BEFORE $before"

# Start rapid inserts in a job, kill mid-way
$job=Start-Job -ScriptBlock {
    $bin=Join-Path $RepoRoot "ScriptSuite\bin\Debug\net10.0-windows"
    $env:PATH="$bin\runtimes\win-x64\native;"+$env:PATH
    Add-Type -Path "$bin\SQLitePCLRaw.core.dll"
    Add-Type -Path "$bin\SQLitePCLRaw.provider.e_sqlite3.dll"
    Add-Type -Path "$bin\SQLitePCLRaw.batteries_v2.dll"
    Add-Type -Path "$bin\Microsoft.Data.Sqlite.dll"
    [SQLitePCL.Batteries_V2]::Init()
    $db="$env:LOCALAPPDATA\ScriptSuite\history.db"
    for($i=1;$i -le 100;$i++){
        $c=[Microsoft.Data.Sqlite.SqliteConnection]::new("Data Source=$db")
        $c.Open()
        $cmd=$c.CreateCommand()
        $cmd.CommandText="INSERT INTO RunHistory (ScriptId, StartedAt, FinishedAt, Outcome, Summary) VALUES ('Cat4cStress', datetime('now'), datetime('now'), 'Success', 'stress $i')"
        $cmd.ExecuteNonQuery() | Out-Null
        $c.Close()
    }
}
Start-Sleep -Milliseconds 100
Write-HarnessLog "KILL mid-insert (job running)"
Stop-Job $job
Remove-Job $job -Force

Start-Sleep -Milliseconds 500
# Verify DB integrity
$c2=[Microsoft.Data.Sqlite.SqliteConnection]::new("Data Source=$global:HistoryDb")
try{
    $c2.Open()
    $q2=$c2.CreateCommand()
    $q2.CommandText="PRAGMA integrity_check;"
    $res=$q2.ExecuteScalar()
    Write-HarnessLog "INTEGRITY_CHECK $res (expect ok)"
    $q2.CommandText="SELECT COUNT(*) FROM RunHistory"
    $after=$q2.ExecuteScalar()
    Write-HarnessLog "HISTORY-AFTER $after (before $before, delta $($after-$before), some inserts may have committed)"
    $q2.CommandText="SELECT Id, Summary FROM RunHistory WHERE ScriptId='Cat4cStress' ORDER BY Id DESC LIMIT 3"
    $r=$q2.ExecuteReader()
    while($r.Read()){ Write-HarnessLog "STRESS Id=$($r.GetInt64(0)) $($r.GetString(1))" }
    $r.Close()
    $c2.Close()
    $integrityOk= ($res -eq "ok")
} catch {
    Write-HarnessLog "INTEGRITY_FAIL $_"
    $integrityOk=$false
}

# Cleanup stress rows
$c3=[Microsoft.Data.Sqlite.SqliteConnection]::new("Data Source=$global:HistoryDb")
$c3.Open(); $q3=$c3.CreateCommand(); $q3.CommandText="DELETE FROM RunHistory WHERE ScriptId='Cat4cStress'"; $q3.ExecuteNonQuery() | Out-Null; $c3.Close()
Write-HarnessLog "CLEANUP stress rows"

if($integrityOk){
    Write-HarnessLog "RESULT: Success, DB not corrupted after kill mid-insert, partial commits ok"
} else {
    Write-HarnessLog "RESULT: Failed, DB corrupted"
    exit 1
}
Write-HarnessLog "=== CAT4C END ==="

