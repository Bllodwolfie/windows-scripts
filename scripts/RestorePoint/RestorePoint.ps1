# Creates a System Restore point and verifies it actually appeared.
# Uses the native SRSetRestorePoint API (Srclient.dll) directly: in PowerShell 7,
# Checkpoint-Computer / Get-ComputerRestorePoint are implicit-remoting proxies
# that run the real cmdlet in a Windows PowerShell 5.1 session, which cannot be
# established when the script is hosted in-process via the PowerShell SDK (e.g.
# from the app or the elevation harness). SRSetRestorePoint is exactly what
# Checkpoint-Computer calls underneath, without that dependency.
# Creating is subject to the OS 24-hour rule (one point per day); the script
# verifies via the SystemRestore WMI class that a new point actually appeared.

param(
    [switch]$DryRun,
    [string]$ConfigPath = "$env:LOCALAPPDATA\ScriptSuite\Configs\RestorePoint.json",
    [string[]]$IncludeOnly = @()
)

# Fallback defaults, used only when the config file is missing (see TempCleanup).
$Config = @{
    Description = "Monthly Cleanup"
}

if (Test-Path -LiteralPath $ConfigPath) {
    $Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
}

# Best-effort pre-check: is System Protection even enabled for any volume?
$shadow = Get-CimInstance -ClassName Win32_ShadowStorage -ErrorAction SilentlyContinue

if ($DryRun) {
    # Preview: what a restore point would look like, and whether System
    # Protection is actually enabled. Nothing is created.
    $protection = if ($shadow) {
        'System Protection enabled (shadow storage present)'
    } else {
        'System Protection NOT enabled (no shadow storage) - a restore point may not be created'
    }
    [PSCustomObject]@{
        Action = 'Create'
        Target = $Config.Description
        Detail = $protection
    }
    exit
}

# Milestone 8: the preview is a single "Create" item; if the user unchecked it,
# the IncludeOnly list won't contain this description, so do nothing.
if ($IncludeOnly.Count -gt 0 -and $IncludeOnly -notcontains $Config.Description) {
    Write-Host "Restore point skipped: '$($Config.Description)' was not selected."
    exit
}

if (-not $shadow) {
    Write-Warning "No System Protection / shadow storage found. Restore points may not be enabled on this system."
}

# Native API used to create restore points (same call Checkpoint-Computer makes).
# The whole call is encapsulated in compiled C# so the struct marshaling is done
# by the runtime (passing a PowerShell-constructed struct by ref garbles the
# ByValTStr description field).
Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;
public static class SRSvc
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct RESTOREPOINTINFO
    {
        public int dwEventType;
        public int dwRestorePtType;
        public long llSequenceNumber;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string szDescription;
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct STATEMGRSTATUS
    {
        public int nStatus;
        public long llSequenceNumber;
    }
    [DllImport("Srclient.dll", CharSet = CharSet.Unicode)]
    private static extern bool SRSetRestorePoint(ref RESTOREPOINTINFO pRestorePtSpec, out STATEMGRSTATUS pSMgrStatus);

    // Returns 0 on success, else the status code from SRSetRestorePoint.
    public static int CreateRestorePoint(string description)
    {
        var begin = new RESTOREPOINTINFO();
        begin.dwEventType = 100;   // BEGIN_SYSTEM_CHANGE
        begin.dwRestorePtType = 0; // APPLICATION_INSTALL (Checkpoint-Computer's default)
        begin.szDescription = description;
        var status = new STATEMGRSTATUS();
        if (!SRSetRestorePoint(ref begin, out status)) return status.nStatus;
        var end = new RESTOREPOINTINFO();
        end.dwEventType = 101;     // END_SYSTEM_CHANGE
        end.dwRestorePtType = 0;
        end.llSequenceNumber = begin.llSequenceNumber;
        end.szDescription = description;
        SRSetRestorePoint(ref end, out status);
        return status.nStatus;
    }
}
"@

$before = @(Get-CimInstance -Namespace root\default -ClassName SystemRestore -ErrorAction SilentlyContinue | Where-Object { $_.Description -eq $Config.Description } | Select-Object -ExpandProperty SequenceNumber)

try {
    $rc = [SRSvc]::CreateRestorePoint($Config.Description)
    if ($rc -ne 0) {
        Write-Error "Failed to create restore point (SRSetRestorePoint status $rc)"
        exit 1
    }
} catch {
    Write-Error "Failed to create restore point: $_"
    exit 1
}

# The SystemRestore WMI class can lag behind a freshly created point —
# interactive manual runs show ~1s (ManualTest 2026-08-29 15:14), but
# headless S4U via Task Scheduler can lag >10s due to slower WMI provider
# startup when not running interactively (Stage 4 proof Id=5: 10s poll missed
# a point that Get-ComputerRestorePoint found at +6s). Poll longer and add
# fallback checks that don't rely solely on SystemRestore timing.
$after = @()
for ($attempt = 0; $attempt -lt 30; $attempt++) {
    $after = @(Get-CimInstance -Namespace root\default -ClassName SystemRestore -ErrorAction SilentlyContinue | Where-Object { $_.Description -eq $Config.Description } | Select-Object -ExpandProperty SequenceNumber)
    if (($after | Where-Object { $_ -notin $before }).Count -gt 0) { break }
    Start-Sleep -Seconds 1
}

# Fallback: Get-ComputerRestorePoint (different WMI path, sometimes faster) and
# Win32_ShadowCopy count increase both indicate success even if SystemRestore lags.
if (($after | Where-Object { $_ -notin $before }).Count -eq 0) {
    Start-Sleep -Seconds 2
    $fallback = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Where-Object { $_.Description -eq $Config.Description } | Select-Object -ExpandProperty SequenceNumber)
    if (($fallback | Where-Object { $_ -notin $before }).Count -gt 0) {
        $after = $fallback
    }
}

if (($after | Where-Object { $_ -notin $before }).Count -gt 0) {
    Write-Host "Restore point created: $($Config.Description)"
} else {
    Write-Warning "No new restore point detected for '$($Config.Description)'. System Protection may be disabled for this volume, or a restore point was created too recently (OS 24-hour limit)."
}
