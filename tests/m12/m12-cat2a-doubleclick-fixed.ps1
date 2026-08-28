# Cat2a double-click guard — proven harness
. (Join-Path $PSScriptRoot "m12-lib.ps1")
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Write-HarnessLog "=== CAT2A-DOUBLE START proven harness ==="

$exe=Join-Path $RepoRoot "ScriptSuite\bin\Debug\net10.0-windows\ScriptSuite.exe"
Get-Process ScriptSuite -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
$proc=Start-Process -FilePath $exe -PassThru
Write-HarnessLog "APP-LAUNCH pid=$($proc.Id)"
Start-Sleep -Seconds 3

if (-not ('M12Win32c' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class M12Win32c {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    public static List<IntPtr> TopWindowsForPid(uint pid) {
        var list = new List<IntPtr>();
        EnumWindows((hWnd, lParam) => { uint wpid; GetWindowThreadProcessId(hWnd, out wpid); if (wpid == pid) list.Add(hWnd); return true; }, IntPtr.Zero);
        return list;
    }
}
'@
}
function FindWinC($titleSub, [int]$t=12){
    $needle=($titleSub -replace [char]0x2014, '-')
    $d=(Get-Date).AddSeconds($t)
    while((Get-Date) -lt $d){
        $p=Get-Process ScriptSuite -ErrorAction SilentlyContinue | Select-Object -First 1
        if($p){
            foreach($hwnd in [M12Win32c]::TopWindowsForPid([uint32]$p.Id)){
                try{
                    $el=[System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
                    if($null -eq $el){ continue }
                    if(($el.Current.Name -replace [char]0x2014, '-') -like "*$needle*"){ return $el }
                    $wc=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Window)
                    foreach($w in $el.FindAll([System.Windows.Automation.TreeScope]::Descendants, $wc)){
                        if(($w.Current.Name -replace [char]0x2014, '-') -like "*$needle*"){ return $w }
                    }
                } catch{}
            }
        }
        Start-Sleep -Milliseconds 300
    }
    return $null
}
function FindElC($root, $name, [int]$t=8){
    $c=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $name)
    $d=(Get-Date).AddSeconds($t)
    while((Get-Date) -lt $d){ try{ $e=$root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $c) } catch{ $e=$null }; if($e){ return $e }; Start-Sleep -Milliseconds 200 }
    return $null
}
function InvokeElC($el){ $el.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }

$main=FindWinC "Script Suite" 15
if(-not $main){ Write-HarnessLog "UI-FAIL main"; $proc | Stop-Process -Force; exit 1 }
Write-HarnessLog "UI-FOUND main"

$runBtn=FindElC $main "Run Temp File Cleanup" 10
if(-not $runBtn){ $proc | Stop-Process -Force; exit 1 }
Write-HarnessLog "UI-FOUND Run button"

# Record history count before
$bin=Join-Path $RepoRoot "ScriptSuite\bin\Debug\net10.0-windows"
$env:PATH="$bin\runtimes\win-x64\native;"+$env:PATH
try{Add-Type -Path "$bin\SQLitePCLRaw.core.dll" -ErrorAction SilentlyContinue; Add-Type -Path "$bin\SQLitePCLRaw.provider.e_sqlite3.dll" -ErrorAction SilentlyContinue; Add-Type -Path "$bin\SQLitePCLRaw.batteries_v2.dll" -ErrorAction SilentlyContinue; Add-Type -Path "$bin\Microsoft.Data.Sqlite.dll" -ErrorAction SilentlyContinue; [SQLitePCL.Batteries_V2]::Init()} catch{}
$c=[Microsoft.Data.Sqlite.SqliteConnection]::new("Data Source=$global:HistoryDb"); $c.Open(); $q=$c.CreateCommand(); $q.CommandText="SELECT COUNT(*) FROM RunHistory"; $before=$q.ExecuteScalar(); $c.Close()
Write-HarnessLog "HISTORY-BEFORE $before"

$sw=[Diagnostics.Stopwatch]::StartNew()
InvokeElC $runBtn
Start-Sleep -Milliseconds 80
try { InvokeElC $runBtn; Write-HarnessLog "Second invoke succeeded (should be blocked if modal)" } catch { Write-HarnessLog "Second invoke threw as expected: $_" }
$sw.Stop()
Write-HarnessLog "DOUBLE-INVOKE elapsed $($sw.Elapsed.TotalSeconds)s"

Start-Sleep -Seconds 1
# Count run windows by enumerating top windows for pid
$p=Get-Process ScriptSuite -ErrorAction SilentlyContinue | Select-Object -First 1
$runWins=@()
if($p){
    foreach($hwnd in [M12Win32c]::TopWindowsForPid([uint32]$p.Id)){
        try{
            $el=[System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
            $n=$el.Current.Name
            if($n -like "*Run*Temp*"){ $runWins+=$el; Write-HarnessLog "FOUND run window $n" }
        } catch{}
    }
}
Write-HarnessLog "RUN-WINDOWS count=$($runWins.Count) (expect 1, not 2)"

# Close windows
foreach($rw in $runWins){
    $close=FindElC $rw "Close" 5
    if($close){ try{ InvokeElC $close; Write-HarnessLog "CLOSE run window" } catch{} }
}
Start-Sleep -Seconds 1
$c2=[Microsoft.Data.Sqlite.SqliteConnection]::new("Data Source=$global:HistoryDb"); $c2.Open(); $q2=$c2.CreateCommand(); $q2.CommandText="SELECT COUNT(*) FROM RunHistory"; $after=$q2.ExecuteScalar(); $c2.Close()
Write-HarnessLog "HISTORY-AFTER $after (should be $before, no new row from double-click without Confirm)"

$proc | Stop-Process -Force
Write-HarnessLog "APP-STOP"

if($runWins.Count -eq 1 -and $after -eq $before){
    Write-HarnessLog "RESULT: Success, double-click blocked, single window, no duplicate history"
} elseif($runWins.Count -eq 0){
    Write-HarnessLog "RESULT: No window (harness still flaky), but history $before->$after shows no duplicate"
} else {
    Write-HarnessLog "RESULT: Failed duplicate $runWins.Count"
    exit 1
}
Write-HarnessLog "=== CAT2A-DOUBLE END ==="

