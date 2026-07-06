# DownloadsCleanup

Scans the Downloads folder for files older than 7 days:

- **Deletes** archives, installers, and fonts (`.zip`, `.rar`, `.exe`, `.msi`, `.ttf`, etc.)
- **Moves** media, documents, and spreadsheets to organized folders by file extension.

## Usage

```powershell
.\DownloadsCleanup.ps1
```

Activity is logged to `Documents\Script_Logs\CleanupLog.txt`.
