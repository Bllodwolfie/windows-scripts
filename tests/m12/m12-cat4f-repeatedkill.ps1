# Cat4f — repeated kill/relaunch cycles (5x) — scratch isolation, no real-impact scripts
. "C:\Users\nekdo\AppData\Local\Temp\opencode\m12\m12-lib.ps1"
Write-HarnessLog "=== CAT4F START repeated kill/relaunch 5 cycles ==="

$scratch="$env:LOCALAPPDATA\ScriptSuite\m12scratch-cat4f"
$scratchLogs="$env:LOCALAPPDATA\ScriptSuite\m12scratch-cat4f-logs"
$cfgPath="$env:LOCALAPPDATA\ScriptSuite\Configs\TempCleanup.json"
$journalPath="$env:LOCALAPPDATA\ScriptSuite\journal.json"
$historyDb="$env:LOCALAPPDATA\ScriptSuite\history.db"
$exe="C:\Users\nekdo\Documents\windows-scripts\ScriptSuite\bin\Debug\net10.0-windows\ScriptSuite.exe"

Remove-ScratchLogged $scratch "CAT4F clean"
Remove-ScratchLogged $scratchLogs "CAT4F clean log"
New-ScratchLogged $scratch "CAT4F seed"
New-ScratchLogged $scratchLogs "CAT4F log"
$cfg=Get-Content $cfgPath -Raw | ConvertFrom-Json
$origTarget=$cfg.TargetFolder; $origCutoff=$cfg.CutoffDays
$cfg.TargetFolder=$scratch; $cfg.CutoffDays=7; $cfg | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cfgPath -Encoding utf8
for($i=1;$i -le 200;$i++){ $p=Join-Path $scratch ("f{0:D4}.dat" -f $i); Set-Content -LiteralPath $p -Value "x"; (Get-Item $p).LastWriteTime=(Get-Date).AddDays(-10) }
Write-HarnessLog "SEED 200 files target=$scratch"
$initialCount=(Get-ChildItem $scratch -File | Measure-Object).Count
Write-HarnessLog "INITIAL count=$initialCount expected 200"

$bin="C:\Users\nekdo\Documents\windows-scripts\ScriptSuite\bin\Debug\net10.0-windows"
$env:PATH="$bin\runtimes\win-x64\native;"+$env:PATH
try{ Add-Type -Path "$bin\SQLitePCLRaw.core.dll" -ErrorAction SilentlyContinue; Add-Type -Path "$bin\SQLitePCLRaw.provider.e_sqlite3.dll" -ErrorAction SilentlyContinue; Add-Type -Path "$bin\SQLitePCLRaw.batteries_v2.dll" -ErrorAction SilentlyContinue; Add-Type -Path "$bin\Microsoft.Data.Sqlite.dll" -ErrorAction SilentlyContinue; [SQLitePCL.Batteries_V2]::Init()} catch{}
$c=[Microsoft.Data.Sqlite.SqliteConnection]::new("Data Source=$historyDb")
$c.Open(); $q=$c.CreateCommand(); $q.CommandText="SELECT COUNT(*) FROM RunHistory"; $before=$q.ExecuteScalar(); $c.Close()
Write-HarnessLog "HISTORY-BEFORE $before"

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
function FindMain-Root([int]$t=10){
    $d=(Get-Date).AddSeconds($t)
    $root=[System.Windows.Automation.AutomationElement]::RootElement
    $cond=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, "Script Suite")
    while((Get-Date) -lt $d){
        try{ $el=$root.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond) } catch{ $el=$null }
        if($el){ return $el }
        Start-Sleep -Milliseconds 300
    }
    return $null
}
function FindEl-Root($root, $name, [int]$t=5){
    $c2=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $name)
    $d=(Get-Date).AddSeconds($t)
    while((Get-Date) -lt $d){
        try{ $e=$root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $c2) } catch{ $e=$null }
        if($e){ return $e }
        Start-Sleep -Milliseconds 200
    }
    return $null
}

$ok=$true
for($cycle=1;$cycle -le 5;$cycle++){
    Write-HarnessLog "--- CYCLE $cycle START ---"
    Get-Process ScriptSuite -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    $proc=Start-Process -FilePath $exe -PassThru
    Write-HarnessLog "CYCLE $cycle APP-LAUNCH pid=$($proc.Id) at $(Get-Date -Format 'HH:mm:ss.fff')"
    Start-Sleep -Seconds 2
    $main=FindMain-Root 10
    if(-not $main){ Write-HarnessLog "CYCLE $cycle UI-FAIL main not found"; $ok=$false; $proc | Stop-Process -Force; break }
    Write-HarnessLog "CYCLE $cycle UI-FOUND main $($main.Current.Name)"
    # Alternate: odd cycles kill during preview, even cycles kill idle (no Run)
    if($cycle % 2 -eq 1){
        $runBtn=FindEl-Root $main "Run Temp File Cleanup" 8
        if(-not $runBtn){ Write-HarnessLog "CYCLE $cycle UI-FAIL Run button"; $ok=$false; $proc | Stop-Process -Force; break }
        $runBtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
        Write-HarnessLog "CYCLE $cycle INVOKE Run (preview)"
        Start-Sleep -Milliseconds 800
        Write-HarnessLog "CYCLE $cycle KILL mid-preview pid=$($proc.Id) at $(Get-Date -Format 'HH:mm:ss.fff')"
    } else {
        Start-Sleep -Milliseconds 500
        Write-HarnessLog "CYCLE $cycle KILL idle pid=$($proc.Id) at $(Get-Date -Format 'HH:mm:ss.fff')"
    }
    $proc | Stop-Process -Force
    Start-Sleep -Seconds 1
    $journalExists=Test-Path $journalPath
    Write-HarnessLog "CYCLE $cycle JOURNAL exists=$journalExists (expect False)"
    if($journalExists){ $ok=$false; Write-HarnessLog "CYCLE $cycle FAIL journal should be False after preview-kill" }
    $c2=[Microsoft.Data.Sqlite.SqliteConnection]::new("Data Source=$historyDb")
    $c2.Open(); $q2=$c2.CreateCommand(); $q2.CommandText="PRAGMA integrity_check;"; $res=$q2.ExecuteScalar(); $q2.CommandText="SELECT COUNT(*) FROM RunHistory"; $cnt=$q2.ExecuteScalar(); $c2.Close()
    Write-HarnessLog "CYCLE $cycle INTEGRITY $res HISTORY $cnt (delta $($cnt-$before))"
    if($res -ne "ok"){ $ok=$false; Write-HarnessLog "CYCLE $cycle FAIL integrity $res" }
    $remain=(Get-ChildItem $scratch -File -ErrorAction SilentlyContinue | Measure-Object).Count
    Write-HarnessLog "CYCLE $cycle REMAIN $remain expected 200 (no delete yet)"
    if($remain -ne 200){ $ok=$false; Write-HarnessLog "CYCLE $cycle FAIL remain $remain" }
    Write-HarnessLog "--- CYCLE $cycle END ---"
}

# Final relaunch should show dashboard clean
$procF=Start-Process -FilePath $exe -PassThru
Write-HarnessLog "FINAL RELAUNCH pid=$($procF.Id) at $(Get-Date -Format 'HH:mm:ss.fff')"
Start-Sleep -Seconds 3
$mainF=FindMain-Root 10
if($mainF){ Write-HarnessLog "FINAL MAIN found $($mainF.Current.Name) — dashboard functional after 5 kills" } else { Write-HarnessLog "FINAL MAIN NOT found — FAIL" ; $ok=$false }
$condBtn=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
$btns=$mainF.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condBtn)
$names=@(); foreach($b in $btns){ try{ $names+=$b.Current.Name } catch{} }
Write-HarnessLog "FINAL BUTTONS count=$($btns.Count) has Run Temp=$($names -contains 'Run Temp File Cleanup')"
if(-not ($names -contains 'Run Temp File Cleanup')){ $ok=$false; Write-HarnessLog "FINAL FAIL Run Temp missing" }
$procF | Stop-Process -Force
Write-HarnessLog "APP-STOP pid=$($procF.Id)"

$finalRemain=(Get-ChildItem $scratch -File | Measure-Object).Count
Write-HarnessLog "FINAL REMAIN $finalRemain expected 200"
$c3=[Microsoft.Data.Sqlite.SqliteConnection]::new("Data Source=$historyDb")
$c3.Open(); $q3=$c3.CreateCommand(); $q3.CommandText="PRAGMA integrity_check;"; $r3=$q3.ExecuteScalar(); $q3.CommandText="SELECT COUNT(*) FROM RunHistory"; $finalHist=$q3.ExecuteScalar(); $c3.Close()
Write-HarnessLog "FINAL INTEGRITY $r3 HISTORY $finalHist (before $before delta $($finalHist-$before) expect 0)"

# Restore config and cleanup
$cfg2=Get-Content $cfgPath -Raw | ConvertFrom-Json
$cfg2.TargetFolder=$origTarget; $cfg2.CutoffDays=$origCutoff; $cfg2 | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cfgPath -Encoding utf8
Write-HarnessLog "RESTORED config TargetFolder to original"
Remove-ScratchLogged $scratch "CAT4F cleanup"
Remove-ScratchLogged $scratchLogs "CAT4F cleanup log"

if($ok -and $r3 -eq "ok" -and $finalRemain -eq 200 -and $finalHist -eq $before){
    Write-HarnessLog "RESULT: Success — 5 kill/relaunch cycles left no journal, DB ok, dashboard functional, 0 files deleted"
} else {
    Write-HarnessLog "RESULT: FAIL — ok=$ok integrity=$r3 remain=$finalRemain histDelta=$($finalHist-$before)"
}
Write-HarnessLog "=== CAT4F END ==="
