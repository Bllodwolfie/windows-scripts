# windows-scripts

![License](https://img.shields.io/github/license/Bllodwolfie/windows-scripts)
[![Catppuccin](https://img.shields.io/badge/catppuccin-Mocha%20%26%20Latte-DDB6F2?style=flat)](https://github.com/catppuccin/catppuccin)

A collection of self-contained PowerShell scripts for Windows system maintenance and diagnostics.

## Preview

![System Health Report](assets/preview.png)

*A sample report showing system information, summary cards, and themed tables.*

## Scripts

| Script | What it does |
|--------|-------------|
| [SystemHealthReport](scripts/SystemHealthReport/) | Generates an HTML system health report. |
| [ClearEventLogs](scripts/ClearEventLogs/) | Clears Windows event logs. |
| [DownloadsCleanup](scripts/DownloadsCleanup/) | Sorts Downloads by file type and removes old archives. |
| [EmptyFolderCleanup](scripts/EmptyFolderCleanup/) | Removes empty folders within the Downloads directory. |
| [EmptyRecycleBin](scripts/EmptyRecycleBin/) | Empties the Recycle Bin. |
| [RestorePoint](scripts/RestorePoint/) | Creates a Windows system restore point. |
| [ScreenshotsCleanup](scripts/ScreenshotsCleanup/) | Deletes screenshots older than 7 days. |
| [SoftwareInventory](scripts/SoftwareInventory/) | Exports a list of installed software to a text file. |
| [TempCleanup](scripts/TempCleanup/) | Deletes temporary files from the %TEMP% folder. |

## Usage

### Get the files

Clone the repo (no Mark of the Web, so no unblocking needed):
```powershell
git clone https://github.com/Bllodwolfie/windows-scripts.git
cd windows-scripts
```

Or download the ZIP and extract it. Windows then marks every `.ps1` as coming from the Internet, which blocks them — remove the mark once:
```powershell
Get-ChildItem .\scripts -Recurse -Filter *.ps1 | Unblock-File
```

### Run a script

If your PowerShell policy already allows local scripts (`Get-ExecutionPolicy` returns `RemoteSigned`):
```powershell
.\scripts\SystemHealthReport\SystemHealthReport.ps1
```

On a fresh Windows machine the policy is `Restricted`, which blocks **all** scripts. Either allow them for your user once:
```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```
or skip the policy for a single run — works on every machine, no permanent change:
```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\SystemHealthReport\SystemHealthReport.ps1
```

**Requires Administrator:** `ClearEventLogs`, `RestorePoint`

## Requirements

- Windows 10 / 11
- PowerShell 5.1+ (PowerShell 7 recommended)

## License

MIT
