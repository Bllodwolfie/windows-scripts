param(
    [switch]$DryRun,
    [string]$ConfigPath = "$env:LOCALAPPDATA\ScriptSuite\Configs\m12_elevated_test.json",
    [string[]]$IncludeOnly = @()
)

if ($DryRun) {
    [PSCustomObject]@{
        Action = 'Test'
        Target = 'm12_elevated_test'
        Detail = 'would run elevated test'
    }
    exit
}

Write-Host "m12_elevated_test: elevated ok - starting 10s sleep"
Start-Sleep -Seconds 10
Write-Host "m12_elevated_test: completed"
