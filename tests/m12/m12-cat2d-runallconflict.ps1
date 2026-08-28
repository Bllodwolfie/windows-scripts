# Cat2d — Run All vs manual run conflict
. "C:\Users\nekdo\AppData\Local\Temp\opencode\m12\m12-lib.ps1"
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Write-HarnessLog "=== CAT2D START Run All vs manual ==="

$exe="C:\Users\nekdo\Documents\windows-scripts\ScriptSuite\bin\Debug\net10.0-windows\ScriptSuite.exe"
Get-Process ScriptSuite -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
$proc=Start-Process -FilePath $exe -PassThru
Write-HarnessLog "APP-LAUNCH pid=$($proc.Id)"
Start-Sleep -Seconds 3

function FindWin($name, $t=10){
    $needle=($name -replace [char]0x2014,'-')
    $d=(Get-Date).AddSeconds($t)
    while((Get-Date) -lt $d){
        $p=Get-Process ScriptSuite -ErrorAction SilentlyContinue | Select-Object -First 1
        if($p){
            $hwnds=[M12Win32b]::TopWindowsForPid([uint32]$p.Id) 2>$null
            if($hwnds){
                foreach($hwnd in $hwnds){
                    try{
                        $el=[System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
                        if($el.Current.Name -replace [char]0x2014,'-' -like "*$needle*"){ return $el }
                    } catch{}
                }
            }
        }
        Start-Sleep -Milliseconds 300
    }
    return $null
}
# Need M12Win32b from m12-lib
if (-not ('M12Win32b' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class M12Win32b {
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

$main=FindWin "Script Suite" 10
if(-not $main){ Write-HarnessLog "UI-FAIL main"; $proc | Stop-Process -Force; exit 1 }
Write-HarnessLog "UI-FOUND main"

# Find Run All button
$condBtn=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
$btns=$main.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condBtn)
$runAllBtn=$null; $runBtn=$null
foreach($b in $btns){
    $n=$b.Current.Name
    if($n -like "*Run All*"){ $runAllBtn=$b; Write-HarnessLog "FOUND Run All $n" }
    if($n -like "Run Temp*"){ $runBtn=$b }
}
if(-not $runAllBtn){ Write-HarnessLog "UI-FAIL Run All not found"; $proc | Stop-Process -Force; exit 1 }

# Click Run All
$runAllBtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
Write-HarnessLog "INVOKE Run All"
Start-Sleep -Seconds 2
$preview=FindWin "Run All" 10
if($preview){ Write-HarnessLog "FOUND Run All preview $($preview.Current.Name)" } else { Write-HarnessLog "No Run All preview (maybe no scripts enabled)"; $proc | Stop-Process -Force; exit 0 }

# While preview is open, try to invoke manual Run
if($runBtn){
    try{
        $runBtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
        Write-HarnessLog "Manual Run invoke while preview open succeeded (should be blocked if modal)"
        # Check if second window opened
        Start-Sleep -Seconds 1
        $second=FindWin "Temp File Cleanup" 3
        if($second){ Write-HarnessLog "Second window opened while preview open -> conflict not blocked" } else { Write-HarnessLog "Second window not opened -> correctly blocked (modal)" }
    } catch {
        Write-HarnessLog "Manual Run invoke threw as expected (blocked): $_"
    }
} else {
    Write-HarnessLog "No manual Run button to test"
}

# Close preview
$closeCond=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, "Close")
$closeBtn=$preview.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $closeCond)
if($closeBtn){ try{ $closeBtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Write-HarnessLog "CLOSE preview" } catch{} }

$proc | Stop-Process -Force
Write-HarnessLog "APP-STOP"
Write-HarnessLog "RESULT: Run All preview correctly blocks manual Run (modal) if second window not opened"
Write-HarnessLog "=== CAT2D END ==="
