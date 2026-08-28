# Cat4d v2 — kill elevated child with 10s sleep window, aggressive polling
. "C:\Users\nekdo\AppData\Local\Temp\opencode\m12\m12-lib.ps1"
Write-HarnessLog "=== CAT4D-V2 START kill elevated child (10s window) ==="

$bin="C:\Users\nekdo\Documents\windows-scripts\ScriptSuite\bin\Debug\net10.0-windows"
$manifestId="m12_elevated_test"
$cfgPath=[System.IO.Path]::Combine([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData), "ScriptSuite", "Configs", "m12_elevated_test.json")
if(-not (Test-Path $cfgPath)){ "{}" | Set-Content -LiteralPath $cfgPath -Encoding utf8 }

try{
    Add-Type -Path "$bin\ScriptSuite.dll" -ErrorAction Stop
    $catalog=New-Object ScriptSuite.Services.ManifestCatalog -ArgumentList "$bin\Manifests"
    $executor=New-Object ScriptSuite.Services.ScriptExecutor -ArgumentList $catalog
    Write-HarnessLog "Loaded catalog+executor, manifest exists=$($null -ne $catalog.Find($manifestId))"

    $job=Start-Job -ScriptBlock {
        param($bin, $manifestId, $cfgPath)
        Add-Type -Path "$bin\ScriptSuite.dll"
        $catalog=New-Object ScriptSuite.Services.ManifestCatalog -ArgumentList "$bin\Manifests"
        $executor=New-Object ScriptSuite.Services.ScriptExecutor -ArgumentList $catalog
        $res=$executor.RunElevated($manifestId, $cfgPath)
        Write-Output "RunElevated Outcome=$($res.Outcome) Logs=$($res.Logs -join '|')"
    } -ArgumentList $bin, $manifestId, $cfgPath

    # Aggressive poll for child for up to 8s (child sleeps 10s, so we have window)
    $found=$false
    for($i=0;$i -lt 16;$i++){
        Start-Sleep -Milliseconds 500
        $childs=Get-CimInstance Win32_Process -Filter "Name='ScriptSuite.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*--elevated-run*m12_elevated_test*" }
        if($childs){
            foreach($cp in $childs){
                Write-HarnessLog "FOUND child pid=$($cp.ProcessId) cmd=$($cp.CommandLine)"
                try{ Stop-Process -Id $cp.ProcessId -Force -ErrorAction SilentlyContinue; Write-HarnessLog "KILLED child pid=$($cp.ProcessId)"; $found=$true } catch{ Write-HarnessLog "KILL failed $_" }
            }
            break
        }
    }
    if(-not $found){
        Write-HarnessLog "No child found after 8s poll — checking all ScriptSuite"
        Get-Process ScriptSuite -ErrorAction SilentlyContinue | ForEach-Object { Write-HarnessLog "ScriptSuite pid=$($_.Id)" }
        # Try to find any elevated child via parent pid
        $all=Get-CimInstance Win32_Process -Filter "Name='ScriptSuite.exe'" -ErrorAction SilentlyContinue
        $all | ForEach-Object { Write-HarnessLog "All candidate pid=$($_.ProcessId) ppid=$($_.ParentProcessId) cmd=$($_.CommandLine)" }
    }

    Wait-Job $job -Timeout 30 | Out-Null
    $out=Receive-Job $job
    Remove-Job $job -Force
    Write-HarnessLog "JOB OUTPUT $out"

    if($out -like "*Failed*missing result*"){
        Write-HarnessLog "RESULT: Success, killed elevated child => Failed (missing result file) via generic path"
    } elseif($out -like "*Failed*"){
        Write-HarnessLog "RESULT: Success, killed => Failed (generic)"
    } elseif($out -like "*Success*"){
        Write-HarnessLog "RESULT: Unexpected Success after kill — should be Failed"
    } else {
        Write-HarnessLog "RESULT: Inconclusive $out"
    }
} catch {
    Write-HarnessLog "Failed to run via DLL: $_"
}
Write-HarnessLog "=== CAT4D-V2 END ==="
