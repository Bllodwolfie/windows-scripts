# DownloadsCleanup

Scans configured downloads folders (`SourceDirs`, defaults to `Downloads`) for files older than 7 days:

- **Deletes** archives, installers, and fonts (`.zip`, `.rar`, `.exe`, `.msi`, `.ttf`, etc.)
- **Moves** media, documents, and spreadsheets to organized folders by file extension.

## Features

- **Multi-Root Scanning:** Configure multiple root folders (`SourceDirs`) to clean in one pass, with automatic duplicate and nested root elimination.
- **Advanced Rules:** Define per-extension custom actions (`Delete`, `MoveTo`, `Ignore`).
- **Ignore Patterns:** Define glob patterns (`IgnorePatterns`) to exclude specific filenames from sorting or deletion.
- **Safe Recycling:** Deleted files are sent to the Recycle Bin rather than permanently deleted.

## Usage

```powershell
.\DownloadsCleanup.ps1
```

Activity is logged to `Documents\Script_Logs\CleanupLog.txt`.
