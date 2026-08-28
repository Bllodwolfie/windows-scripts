# Cat2c aggressive — hold transaction
. "C:\Users\nekdo\AppData\Local\Temp\opencode\m12\m12-lib.ps1"
Write-HarnessLog "=== CAT2C-AGGRESSIVE START ==="

$bin="C:\Users\nekdo\Documents\windows-scripts\ScriptSuite\bin\Debug\net10.0-windows"
$env:PATH="$bin\runtimes\win-x64\native;"+$env:PATH

$jobHolder=Start-Job -ScriptBlock {
    $bin="C:\Users\nekdo\Documents\windows-scripts\ScriptSuite\bin\Debug\net10.0-windows"
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
    $cmd.CommandText="BEGIN IMMEDIATE; INSERT INTO RunHistory (ScriptId, StartedAt, FinishedAt, Outcome, Summary) VALUES ('Cat2cHolder', datetime('now'), datetime('now'), 'Success', 'holder');"
    $cmd.ExecuteNonQuery() | Out-Null
    Write-Output "holder: transaction started, holding 3s"
    Start-Sleep -Seconds 3
    $cmd2=$c.CreateCommand()
    $cmd2.CommandText="COMMIT;"
    $cmd2.ExecuteNonQuery() | Out-Null
    Write-Output "holder: committed"
    $c.Close()
}

Start-Sleep -Seconds 1  # let holder acquire lock

$jobContender=Start-Job -ScriptBlock {
    $bin="C:\Users\nekdo\Documents\windows-scripts\ScriptSuite\bin\Debug\net10.0-windows"
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
    $cmd.CommandText="INSERT INTO RunHistory (ScriptId, StartedAt, FinishedAt, Outcome, Summary) VALUES ('Cat2cContender', datetime('now'), datetime('now'), 'Success', 'contender');"
    try{
        $cmd.ExecuteNonQuery() | Out-Null
        Write-Output "contender: Success"
    } catch {
        Write-Output "contender: Failed $($_.Exception.Message)"
        if($_.Exception.Message -like "*busy*" -or $_.Exception.Message -like "*BUSY*" -or $_.Exception.Message -like "*locked*"){
            Write-Output "contender: BUSY detected"
        }
    }
    $c.Close()
}

Wait-Job $jobHolder,$jobContender | Out-Null
$r1=Receive-Job $jobHolder
$r2=Receive-Job $jobContender
Remove-Job $jobHolder,$jobContender
Write-HarnessLog "HOLDER $r1"
Write-HarnessLog "CONTENDER $r2"

if($r2 -like "*BUSY*" -or $r2 -like "*busy*" -or $r2 -like "*locked*"){
    Write-HarnessLog "RESULT: BUSY confirmed with held transaction — WAL/busy_timeout gap proven"
} elseif($r2 -like "*Success*"){
    Write-HarnessLog "RESULT: Contender succeeded even with holder — no BUSY, gap not triggered (maybe lock not held as expected)"
} else {
    Write-HarnessLog "RESULT: Contender failed non-BUSY: $r2"
}

# Cleanup holder row
$bin2="C:\Users\nekdo\Documents\windows-scripts\ScriptSuite\bin\Debug\net10.0-windows"
$env:PATH="$bin2\runtimes\win-x64\native;"+$env:PATH
try{Add-Type -Path "$bin2\SQLitePCLRaw.core.dll" -ErrorAction SilentlyContinue; Add-Type -Path "$bin2\SQLitePCLRaw.provider.e_sqlite3.dll" -ErrorAction SilentlyContinue; Add-Type -Path "$bin2\SQLitePCLRaw.batteries_v2.dll" -ErrorAction SilentlyContinue; Add-Type -Path "$bin2\Microsoft.Data.Sqlite.dll" -ErrorAction SilentlyContinue; [SQLitePCL.Batteries_V2]::Init()} catch{}
$c2=[Microsoft.Data.Sqlite.SqliteConnection]::new("Data Source=$global:HistoryDb")
$c2.Open(); $q=$c2.CreateCommand(); $q.CommandText="DELETE FROM RunHistory WHERE ScriptId LIKE 'Cat2c%'"; $q.ExecuteNonQuery() | Out-Null; $c2.Close()
Write-HarnessLog "CLEANUP Cat2c holder/contender rows removed"

Write-HarnessLog "=== CAT2C-AGGRESSIVE END ==="
