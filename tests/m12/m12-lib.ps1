# m12-lib.ps1 — shared helpers for M12 adversarial pass
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
# FIX: scratch recreation is now explicitly logged; seeder writes flat at SourceDir root

$global:M12Root = Join-Path $env:TEMP "opencode\m12"
$global:M12HarnessLog = Join-Path $global:M12Root "m12-harness.log"
$global:AppDataRoot = "$env:LOCALAPPDATA\ScriptSuite"
$global:HistoryDb = "$env:LOCALAPPDATA\ScriptSuite\history.db"

function Write-HarnessLog([string]$msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    "[$ts] $msg" | Out-File -FilePath $global:M12HarnessLog -Append -Encoding utf8
    Write-Output "[$ts] $msg"
}

function Remove-ScratchLogged([string]$path, [string]$reason) {
    if (Test-Path $path) {
        $countBefore = (Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object).Count
        Write-HarnessLog "SCRATCH-DELETE path=$path files=$countBefore reason=$reason"
        Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
        Write-HarnessLog "SCRATCH-DELETED path=$path"
    } else {
        Write-HarnessLog "SCRATCH-DELETE-SKIP path=$path not present reason=$reason"
    }
}

function New-ScratchLogged([string]$path, [string]$reason) {
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        Write-HarnessLog "SCRATCH-CREATE path=$path reason=$reason"
    }
}

function Reset-HistoryLogged([string]$reason) {
    # Log and truncate RunHistory; keep DB file but clear rows
    $bin=Join-Path $RepoRoot "ScriptSuite\bin\Debug\net10.0-windows"
    $env:PATH="$bin\runtimes\win-x64\native;"+$env:PATH
    try {
        Add-Type -Path "$bin\SQLitePCLRaw.core.dll" -ErrorAction SilentlyContinue
        Add-Type -Path "$bin\SQLitePCLRaw.provider.e_sqlite3.dll" -ErrorAction SilentlyContinue
        Add-Type -Path "$bin\SQLitePCLRaw.batteries_v2.dll" -ErrorAction SilentlyContinue
        Add-Type -Path "$bin\Microsoft.Data.Sqlite.dll" -ErrorAction SilentlyContinue
        [SQLitePCL.Batteries_V2]::Init()
    } catch {}
    $conn=[Microsoft.Data.Sqlite.SqliteConnection]::new("Data Source=$global:HistoryDb")
    $conn.Open()
    $cmd=$conn.CreateCommand()
    $cmd.CommandText="SELECT COUNT(*) FROM RunHistory"
    $before=$cmd.ExecuteScalar()
    $cmd.CommandText="DELETE FROM RunHistory; VACUUM;"
    $cmd.ExecuteNonQuery() | Out-Null
    $conn.Close()
    Write-HarnessLog "HISTORY-RESET beforeRows=$before reason=$reason"
}

# FIXED seeder: flat at SourceDir root, not Join-Path $scratch $ext
function Seed-BatchFlat([string]$scratch, [int]$count, [string]$prefix, [string]$ext, [int]$daysOld) {
    # Writes flat at $scratch root, e.g. $scratch/z_1.zip — matches DownloadsCleanup non-recursive scan
    New-ScratchLogged $scratch "seed target"
    $created = 0
    for ($i=1; $i -le $count; $i++) {
        $name = "{0}_{1}{2}" -f $prefix, $i, $ext
        $full = Join-Path $scratch $name
        # 1-byte file, LastWrite old enough to pass CutoffDays
        [System.IO.File]::WriteAllBytes($full, [byte[]]@(0x78))
        (Get-Item $full).LastWriteTime = (Get-Date).AddDays(-$daysOld)
        $created++
    }
    Write-HarnessLog "SEED-FLAT scratch=$scratch prefix=$prefix ext=$ext count=$created daysOld=$daysOld (flat at root, non-recursive compatible)"
    return $created
}

function Get-HistoryRows {
    $bin=Join-Path $RepoRoot "ScriptSuite\bin\Debug\net10.0-windows"
    $env:PATH="$bin\runtimes\win-x64\native;"+$env:PATH
    try {
        Add-Type -Path "$bin\SQLitePCLRaw.core.dll" -ErrorAction SilentlyContinue
        Add-Type -Path "$bin\SQLitePCLRaw.provider.e_sqlite3.dll" -ErrorAction SilentlyContinue
        Add-Type -Path "$bin\SQLitePCLRaw.batteries_v2.dll" -ErrorAction SilentlyContinue
        Add-Type -Path "$bin\Microsoft.Data.Sqlite.dll" -ErrorAction SilentlyContinue
        [SQLitePCL.Batteries_V2]::Init()
    } catch {}
    $conn=[Microsoft.Data.Sqlite.SqliteConnection]::new("Data Source=$global:HistoryDb")
    $conn.Open()
    $cmd=$conn.CreateCommand()
    $cmd.CommandText="SELECT Id, ScriptId, Outcome, Summary, StartedAt, FinishedAt FROM RunHistory ORDER BY Id"
    $r=$cmd.ExecuteReader()
    $rows=@()
    while($r.Read()){
        $rows+= [PSCustomObject]@{
            Id=$r.GetInt64(0); ScriptId=$r.GetString(1); Outcome=$r.GetString(2)
            Summary= if($r.IsDBNull(3)){"<NULL>"} else {$r.GetString(3)}
            Started=$r.GetString(4); Finished= if($r.IsDBNull(5)){"<NULL>"} else {$r.GetString(5)}
        }
    }
    $conn.Close()
    return $rows
}

