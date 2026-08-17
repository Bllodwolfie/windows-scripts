# Creates a System Restore point and verifies it actually appeared.
# Checkpoint-Computer exits silently when System Protection is off or the
# volume has no restore configuration, so the script verifies via
# Get-ComputerRestorePoint before/after and reports failure clearly instead
# of a false success.

$Config = @{
    Description = "Monthly Cleanup"
}

# Best-effort pre-check: is System Protection even enabled for any volume?
$shadow = Get-CimInstance -ClassName Win32_ShadowStorage -ErrorAction SilentlyContinue
if (-not $shadow) {
    Write-Warning "No System Protection / shadow storage found. Restore points may not be enabled on this system."
}

$before = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Where-Object { $_.Description -eq $Config.Description } | Select-Object -ExpandProperty SequenceNumber)

try {
    Checkpoint-Computer -Description $Config.Description -ErrorAction Stop
} catch {
    Write-Error "Failed to create restore point: $_"
    exit 1
}

$after = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Where-Object { $_.Description -eq $Config.Description } | Select-Object -ExpandProperty SequenceNumber)

if (($after | Where-Object { $_ -notin $before }).Count -gt 0) {
    Write-Host "Restore point created: $($Config.Description)"
} else {
    Write-Warning "No new restore point detected for '$($Config.Description)'. System Protection may be disabled for this volume, or a recent point already exists."
}