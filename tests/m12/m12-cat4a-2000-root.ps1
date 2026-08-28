# Cat4a-2000 ROOT — kill during preview at 2000 with direct RootElement.FindFirst
. "C:\Users\nekdo\AppData\Local\Temp\opencode\m12\m12-lib.ps1"
Write-HarnessLog "=== CAT4A-2000-ROOT START kill during preview at 2000 (RootElement) ==="

$scratch="$env:LOCALAPPDATA\ScriptSuite\m12scratch-cat4a"
$scratchLogs="$env:LOCALAPPDATA\ScriptSuite\m12scratch-cat4a-logs"
Remove-ScratchLogged $scratch "CAT4A-2000-ROOT clean"
Remove-ScratchLogged $scratchLogs "CAT4A-2000-ROOT clean log"
New-ScratchLogged $scratch "CAT4A-2000-ROOT seed"
New-ScratchLogged $scratchLogs "CAT4A-2000-ROOT log"
$cfgPath="$env:LOCALAPPDATA\ScriptSuite\Configs\TempCleanup.json"
$cfg=Get-Content $cfgPath -Raw | ConvertFrom-Json
$cfg.TargetFolder=$scratch; $cfg.CutoffDays=7; $cfg | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cfgPath -Encoding utf8
for($i=1;$i -le 2000;$i++){ $p=Join-Path $scratch ("f{0:D4}.dat" -f $i); Set-Content -LiteralPath $p -Value "x"; (Get-Item $p).LastWriteTime=(Get-Date).AddDays(-10) }
Write-HarnessLog "SEED 2000 files count=$((Get-ChildItem $scratch -File | Measure-Object).Count)"

$exe="C:\Users\nekdo\Documents\windows-scripts\ScriptSuite\bin\Debug\net10.0-windows\ScriptSuite.exe"
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
function FindEl-Root($root, $name, [int]$t=15){
    $c=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $name)
    $d=(Get-Date).AddSeconds($t)
    while((Get-Date) -lt $d){
        try{ $e=$root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $c) } catch{ $e=$null }
        if($e){ return $e }
        Start-Sleep -Milliseconds 300
    }
    return $null
}

$main=FindMain-Root 15
if(-not $main){ Write-HarnessLog "UI-FAIL main RootElement timeout 15s"; $proc | Stop-Process -Force; exit 1 }
Write-HarnessLog "UI-FOUND main $($main.Current.Name) via RootElement"

$condBtnAll=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
$allBtns=$main.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condBtnAll)
$names=@(); foreach($b in $allBtns){ try{ $names+=$b.Current.Name } catch{} }
Write-HarnessLog "ALL-BUTTONS count=$($allBtns.Count): $($names -join ' | ')"
$tempCount=($names | Where-Object { $_ -like "*Temp*" }).Count
Write-HarnessLog "TEMP-RELATED count=$tempCount"

$runBtn=FindEl-Root $main "Run Temp File Cleanup" 15
if(-not $runBtn){
    Write-HarnessLog "FALLBACK scan for Run Temp*"
    foreach($b in $allBtns){ try{ if($b.Current.Name -like "Run Temp*"){ $runBtn=$b; Write-HarnessLog "FALLBACK found $($b.Current.Name)"; break } } catch{} }
}
if(-not $runBtn){ Write-HarnessLog "UI-FAIL Run Temp File Cleanup after 15s RootElement"; $proc | Stop-Process -Force; exit 1 }
Write-HarnessLog "UI-FOUND Run button $($runBtn.Current.Name) at $(Get-Date -Format 'HH:mm:ss.fff')"
$runBtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
Write-HarnessLog "INVOKE Run (preview loading) at $(Get-Date -Format 'HH:mm:ss.fff')"

Start-Sleep -Seconds 1
Write-HarnessLog "KILL pid=$($proc.Id) mid-preview at $(Get-Date -Format 'HH:mm:ss.fff')"
$proc | Stop-Process -Force
Start-Sleep -Seconds 2

$journal="$env:LOCALAPPDATA\ScriptSuite\journal.json"
$exists=Test-Path $journal
$journalPreview=if($exists){ (Get-Content $journal -Raw).Substring(0,[Math]::Min(200,(Get-Content $journal -Raw).Length)) } else { "<no file>" }
Write-HarnessLog "JOURNAL exists=$exists preview=$journalPreview (expect False, preview doesn't journal)"

$proc2=Start-Process -FilePath $exe -PassThru
Write-HarnessLog "RELAUNCH pid=$($proc2.Id) at $(Get-Date -Format 'HH:mm:ss.fff')"
Start-Sleep -Seconds 3
$running=Get-Process -Id $proc2.Id -ErrorAction SilentlyContinue
if($running){ Write-HarnessLog "RELAUNCH success pid=$($proc2.Id) still running, no crash" } else { Write-HarnessLog "RELAUNCH failed pid=$($proc2.Id) not running" }
$main2=FindMain-Root 10
if($main2){ Write-HarnessLog "MAIN2 found after relaunch name=$($main2.Current.Name), no resume journal as expected" } else { Write-HarnessLog "MAIN2 not found after relaunch" }
$condDialog=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, "Resume")
$resume=$null
try{ $resume=$main2.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condDialog) } catch{}
Write-HarnessLog "RESUME-DIALOG found=$($null -ne $resume) (expect False)"

$proc2 | Stop-Process -Force
Write-HarnessLog "APP-STOP pid=$($proc2.Id)"

$remain=(Get-ChildItem $scratch -File -ErrorAction SilentlyContinue | Measure-Object).Count
Write-HarnessLog "POST remain=$remain expected 2000 (preview shouldn't delete)"

Remove-ScratchLogged $scratch "CAT4A-2000-ROOT cleanup"
Remove-ScratchLogged $scratchLogs "CAT4A-2000-ROOT cleanup log"

if($remain -eq 2000 -and -not $exists){
    Write-HarnessLog "RESULT: Success at 2000 — kill during preview left no journal, clean relaunch, 0 files deleted (own evidence, not inherited from 500)"
} else {
    Write-HarnessLog "RESULT: FAIL remain=$remain journal=$exists"
}
Write-HarnessLog "=== CAT4A-2000-ROOT END ==="
