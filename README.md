# windows-scripts

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

1. Clone the repo:
   ```powershell
   git clone https://github.com/Bllodwolfie/windows-scripts.git
   cd windows-scripts
   ```
2. PowerShell blocks script execution by default. Allow it for the current user:
   ```powershell
   Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```
   Or run a script without changing the policy:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\SystemHealthReport\SystemHealthReport.ps1
   ```
3. Run any script:
   ```powershell
   .\scripts\SystemHealthReport\SystemHealthReport.ps1
   ```

   **Requires Administrator:**
   - `ClearEventLogs`
   - `RestorePoint`

## Requirements

- Windows 10 / 11
- PowerShell 5.1+ (PowerShell 7 recommended)

## License

MIT
