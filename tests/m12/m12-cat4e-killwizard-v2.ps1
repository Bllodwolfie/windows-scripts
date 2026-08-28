# Cat4e V2 — kill during first-run wizard (wizard embedded in main; detect via inner buttons)
. "C:\Users\nekdo\AppData\Local\Temp\opencode\m12\m12-lib.ps1"
Write-HarnessLog "=== CAT4E-V2 START kill during wizard (embedded) ==="

$wizardPath="$env:LOCALAPPDATA\ScriptSuite\wizard.json"
$journalPath="$env:LOCALAPPDATA\ScriptSuite\journal.json"
$historyDb="$env:LOCALAPPDATA\ScriptSuite\history.db"
$exe="C:\Users\nekdo\Documents\windows-scripts\ScriptSuite\bin\Debug\net10.0-windows\ScriptSuite.exe"

$wizardBackup=if(Test-Path $wizardPath){ Get-Content $wizardPath -Raw } else { $null }
$wizardExisted=Test-Path $wizardPath
Write-HarnessLog "BACKUP wizard existed=$wizardExisted len=$(if($wizardBackup){$wizardBackup.Length}else{0})"

$bin="C:\Users\nekdo\Documents\windows-scripts\ScriptSuite\bin\Debug\net10.0-windows"
$env:PATH="$bin\runtimes\win-x64\native;"+$env:PATH
try{ Add-Type -Path "$bin\SQLitePCLRaw.core.dll" -ErrorAction SilentlyContinue; Add-Type -Path "$bin\SQLitePCLRaw.provider.e_sqlite3.dll" -ErrorAction SilentlyContinue; Add-Type -Path "$bin\SQLitePCLRaw.batteries_v2.dll" -ErrorAction SilentlyContinue; Add-Type -Path "$bin\Microsoft.Data.Sqlite.dll" -ErrorAction SilentlyContinue; [SQLitePCL.Batteries_V2]::Init()} catch{}
$c=[Microsoft.Data.Sqlite.SqliteConnection]::new("Data Source=$historyDb")
$c.Open(); $q=$c.CreateCommand(); $q.CommandText="SELECT COUNT(*) FROM RunHistory"; $before=$q.ExecuteScalar(); $c.Close()
Write-HarnessLog "HISTORY-BEFORE $before"

if(Test-Path $wizardPath){ Remove-Item $wizardPath -Force; Write-HarnessLog "WIZARD-DELETE deleted $wizardPath to force first-run" }
Write-HarnessLog "WIZARD-EXISTS after delete=$(Test-Path $wizardPath) expect False"

Get-Process ScriptSuite -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
$proc=Start-Process -FilePath $exe -PassThru
Write-HarnessLog "APP-LAUNCH pid=$($proc.Id) at $(Get-Date -Format 'HH:mm:ss.fff')"
Start-Sleep -Seconds 3

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
function FindMain-Root([int]$t=15){
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
function FindEl-Root($root, $name, [int]$t=10){
    $c2=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $name)
    $d=(Get-Date).AddSeconds($t)
    while((Get-Date) -lt $d){
        try{ $e=$root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $c2) } catch{ $e=$null }
        if($e){ return $e }
        Start-Sleep -Milliseconds 300
    }
    return $null
}

$main=FindMain-Root 10
if(-not $main){ Write-HarnessLog "UI-FAIL main Script Suite not found"; $proc | Stop-Process -Force; if($wizardExisted){ Set-Content -LiteralPath $wizardPath -Value $wizardBackup -Encoding utf8 }; exit 1 }
Write-HarnessLog "UI-FOUND main $($main.Current.Name) pid=$($proc.Id)"

# Wizard is embedded: detect via distinctive wizard buttons inside main
$useRec=FindEl-Root $main "Use recommended defaults" 8
$skipBtn=FindEl-Root $main "Skip" 5
$nextBtn=FindEl-Root $main "Next" 5
if(-not $useRec){
    # Log all buttons for debug
    $condBtn=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
    $allBtns=$main.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condBtn)
    $names=@(); foreach($b in $allBtns){ try{ $names+=$b.Current.Name } catch{} }
    Write-HarnessLog "WIZARD-FAIL Use recommended defaults not found within 8s, buttons: $($names -join ' | ')"
    $proc | Stop-Process -Force
    if($wizardExisted){ Set-Content -LiteralPath $wizardPath -Value $wizardBackup -Encoding utf8; Write-HarnessLog "RESTORED wizard after fail" }
    exit 1
}
Write-HarnessLog "UI-FOUND wizard embedded via Use recommended defaults=$($useRec.Current.Name) Skip=$($null -ne $skipBtn) Next=$($null -ne $nextBtn) at $(Get-Date -Format 'HH:mm:ss.fff')"
# Also log step header text
$condText=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Text)
$texts=$main.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condText)
$stepTexts=@(); foreach($t in $texts){ try{ $n=$t.Current.Name; if($n -like "Step *"){ $stepTexts+=$n } } catch{} }
Write-HarnessLog "WIZARD-STEP $($stepTexts -join ' | ') (expect Step 1 of *)"

Start-Sleep -Seconds 1
Write-HarnessLog "KILL pid=$($proc.Id) mid-wizard at $(Get-Date -Format 'HH:mm:ss.fff')"
$proc | Stop-Process -Force
Start-Sleep -Seconds 2

$wizardExistsAfter=Test-Path $wizardPath
$wizardContentAfter=if($wizardExistsAfter){ (Get-Content $wizardPath -Raw).Trim() } else { "<absent>" }
Write-HarnessLog "WIZARD-EXISTS after kill=$wizardExistsAfter content=$wizardContentAfter (expect False/<absent>)"
$journalExists=Test-Path $journalPath
Write-HarnessLog "JOURNAL exists=$journalExists (expect False, wizard doesn't journal)"

$c2=[Microsoft.Data.Sqlite.SqliteConnection]::new("Data Source=$historyDb")
$c2.Open(); $q2=$c2.CreateCommand(); $q2.CommandText="PRAGMA integrity_check;"; $res=$q2.ExecuteScalar(); $q2.CommandText="SELECT COUNT(*) FROM RunHistory"; $afterKill=$q2.ExecuteScalar(); $c2.Close()
Write-HarnessLog "INTEGRITY_CHECK $res after kill (expect ok) HISTORY after kill $afterKill (before $before delta $($afterKill-$before) expect 0)"

# Relaunch — wizard should reappear because marker absent
$proc2=Start-Process -FilePath $exe -PassThru
Write-HarnessLog "RELAUNCH pid=$($proc2.Id) at $(Get-Date -Format 'HH:mm:ss.fff')"
Start-Sleep -Seconds 3
$main2=FindMain-Root 10
if(-not $main2){ Write-HarnessLog "RELAUNCH FAIL main2 not found"; $proc2 | Stop-Process -Force; if($wizardExisted){ Set-Content -LiteralPath $wizardPath -Value $wizardBackup -Encoding utf8 }; exit 1 }
$useRec2=FindEl-Root $main2 "Use recommended defaults" 8
if($useRec2){ Write-HarnessLog "WIZARD2 found after relaunch via Use recommended defaults — reappears as expected (marker absent)" } else { Write-HarnessLog "WIZARD2 NOT found after relaunch — UNEXPECTED" }
Write-HarnessLog "MAIN2 found $($main2.Current.Name)"

$proc2 | Stop-Process -Force
Start-Sleep -Seconds 1
Write-HarnessLog "APP-STOP pid=$($proc2.Id)"
$wizardExistsFinal=Test-Path $wizardPath
Write-HarnessLog "WIZARD-EXISTS final before restore=$wizardExistsFinal (expect False)"

if($wizardExisted){
    Set-Content -LiteralPath $wizardPath -Value $wizardBackup -Encoding utf8
    Write-HarnessLog "RESTORED wizard.json len=$($wizardBackup.Length)"
}
Write-HarnessLog "WIZARD-EXISTS after restore=$(Test-Path $wizardPath) (expect True)"

$c3=[Microsoft.Data.Sqlite.SqliteConnection]::new("Data Source=$historyDb")
$c3.Open(); $q3=$c3.CreateCommand(); $q3.CommandText="PRAGMA integrity_check;"; $r3=$q3.ExecuteScalar(); $q3.CommandText="SELECT COUNT(*) FROM RunHistory"; $finalCount=$q3.ExecuteScalar(); $c3.Close()
Write-HarnessLog "FINAL INTEGRITY $r3 HISTORY $finalCount (delta $($finalCount-$before))"

if(-not $wizardExistsAfter -and -not $journalExists -and $res -eq "ok" -and $useRec2 -and $r3 -eq "ok"){
    Write-HarnessLog "RESULT: Success — kill mid-wizard left no marker, no journal, DB ok, wizard reappeared on relaunch"
} else {
    Write-HarnessLog "RESULT: FAIL — wizardAfter=$wizardExistsAfter journal=$journalExists integrity=$res wizard2=$($null -ne $useRec2) finalIntegrity=$r3"
}
Write-HarnessLog "=== CAT4E-V2 END ==="
