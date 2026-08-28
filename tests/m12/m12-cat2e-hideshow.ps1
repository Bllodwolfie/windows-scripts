# Cat2e — Hide/Show during Run All preview
. (Join-Path $PSScriptRoot "m12-lib.ps1")
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Write-HarnessLog "=== CAT2E START Hide/Show during Run All preview ==="

$exe=Join-Path $RepoRoot "ScriptSuite\bin\Debug\net10.0-windows\ScriptSuite.exe"
Get-Process ScriptSuite -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
$proc=Start-Process -FilePath $exe -PassThru
Write-HarnessLog "APP-LAUNCH pid=$($proc.Id)"
Start-Sleep -Seconds 3

if (-not ('M12Win32d' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class M12Win32d {
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
function FindWinE($titleSub, [int]$t=10){
    $needle=($titleSub -replace [char]0x2014,'-')
    $d=(Get-Date).AddSeconds($t)
    while((Get-Date) -lt $d){
        $p=Get-Process ScriptSuite -ErrorAction SilentlyContinue | Select-Object -First 1
        if($p){
            foreach($hwnd in [M12Win32d]::TopWindowsForPid([uint32]$p.Id)){
                try{
                    $el=[System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
                    if(($el.Current.Name -replace [char]0x2014,'-') -like "*$needle*"){ return $el }
                } catch{}
            }
        }
        Start-Sleep -Milliseconds 300
    }
    return $null
}

$main=FindWinE "Script Suite" 10
if(-not $main){ Write-HarnessLog "UI-FAIL main"; $proc | Stop-Process -Force; exit 1 }
Write-HarnessLog "UI-FOUND main"

# Find Run All and open preview
$condBtn=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
$btns=$main.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condBtn)
$runAllBtn=$null; $hideBtn=$null
foreach($b in $btns){
    $n=$b.Current.Name
    if($n -like "*Run All*"){ $runAllBtn=$b }
    if($n -like "Hide*"){ if(-not $hideBtn){ $hideBtn=$b } }
}
if(-not $runAllBtn){ Write-HarnessLog "UI-FAIL Run All not found"; $proc | Stop-Process -Force; exit 1 }
Write-HarnessLog "FOUND Run All"

$runAllBtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
Write-HarnessLog "INVOKE Run All"
Start-Sleep -Seconds 2
$preview=FindWinE "Run All" 10
if($preview){ Write-HarnessLog "FOUND preview $($preview.Current.Name)" } else { Write-HarnessLog "No preview"; $proc | Stop-Process -Force; exit 0 }

# While preview open, try Hide
if($hideBtn){
    $isEnabled=$hideBtn.Current.IsEnabled
    Write-HarnessLog "Hide button IsEnabled=$isEnabled while preview open (expect False if modal blocks)"
    try{
        $hideBtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
        Write-HarnessLog "Hide invoke succeeded while preview open (not blocked)"
        Start-Sleep -Seconds 1
        # Check if Hide actually toggled (check if button still exists or changed)
        $hideBtn2=$main.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condBtn) | Where-Object { $_.Current.Name -like "Hide*" } | Select-Object -First 1
        if($hideBtn2){ Write-HarnessLog "Hide button still exists after invoke" } else { Write-HarnessLog "Hide button gone after invoke (toggled)" }
    } catch {
        Write-HarnessLog "Hide invoke threw (blocked): $_"
    }
} else {
    Write-HarnessLog "No Hide button found to test"
}

# Close preview
$closeCond=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, "Close")
$closeBtn=$preview.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $closeCond)
if($closeBtn){ try{ $closeBtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Write-HarnessLog "CLOSE preview" } catch{} }

$proc | Stop-Process -Force
Write-HarnessLog "APP-STOP"
# Since preview is modal, Hide should be blocked (IsEnabled False) — if not, it's same gap as Cat2a/2d (no cross-window guard)
if($hideBtn -and $hideBtn.Current.IsEnabled -eq $false){
    Write-HarnessLog "RESULT: Success, Hide blocked while preview open (modal)"
} elseif($hideBtn -and $hideBtn.Current.IsEnabled -eq $true){
    Write-HarnessLog "RESULT: Failed/bug-found, Hide not blocked while preview open (same gap as Cat2a/2d)"
} else {
    Write-HarnessLog "RESULT: Inconclusive, no Hide button"
}
Write-HarnessLog "=== CAT2E END ==="

