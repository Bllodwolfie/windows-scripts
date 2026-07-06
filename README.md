# windows-scripts

A collection of self-contained PowerShell scripts for Windows system maintenance and diagnostics.

## Scripts

| Script | What it does |
|--------|-------------|
| [SystemHealthReport](scripts/SystemHealthReport/) | Generates a beautiful Catppuccin-themed HTML system health report |
| [ClearEventLogs](scripts/ClearEventLogs/) | Clears all Windows event logs |
| [DownloadsCleanup](scripts/DownloadsCleanup/) | Organizes and cleans up the Downloads folder (deletes old archives, moves media/docs by type) |
| [EmptyFolderCleanup](scripts/EmptyFolderCleanup/) | Recursively removes empty directories under Downloads |
| [EmptyRecycleBin](scripts/EmptyRecycleBin/) | Empties the Recycle Bin |
| [RestorePoint](scripts/RestorePoint/) | Creates a system restore point |
| [ScreenshotsCleanup](scripts/ScreenshotsCleanup/) | Deletes old screenshots (older than 7 days) |
| [SoftwareInventory](scripts/SoftwareInventory/) | Exports installed software list to a text file |
| [TempCleanup](scripts/TempCleanup/) | Cleans old files from %TEMP% |

## Usage

1. Clone the repo:
   ```powershell
   git clone https://github.com/nekdo/windows-scripts.git
   cd windows-scripts
   ```
2. Run any script directly:
   ```powershell
   .\scripts\SystemHealthReport\SystemHealthReport.ps1
   ```

   Some scripts require admin rights (e.g., `ClearEventLogs`, `RestorePoint`).

## Requirements

- Windows 10 / 11
- PowerShell 5.1+ (PowerShell 7 recommended)

## License

MIT
