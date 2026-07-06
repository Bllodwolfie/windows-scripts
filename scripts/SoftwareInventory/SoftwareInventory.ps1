# Generates a text report of all installed software by reading the standard
# Windows "Uninstall" registry keys (covers 64-bit, 32-bit-on-64-bit, and
# per-user installs), then writes it to OutputFile.

$Config = @{
    OutputFile = "$env:USERPROFILE\Documents\Software_Inventory.txt"
}

$outputFile = $Config.OutputFile

# The three registry paths together cover machine-wide 64-bit apps,
# machine-wide 32-bit apps (WOW6432Node), and apps installed for the current user only
Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*,
                HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*,
                HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* |
    Where-Object { $_.DisplayName } |          # Skip registry entries with no display name (not real apps)
    Sort-Object DisplayName |
    Select-Object DisplayName, DisplayVersion, Publisher, InstallDate |
    Format-Table -AutoSize -Wrap |
    Out-String -Width 4096 |                    # Wide width avoids truncating long app names/columns
    Out-File -FilePath $outputFile -Encoding UTF8
