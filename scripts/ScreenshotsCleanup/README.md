# ScreenshotsCleanup

Deletes screenshots in configured screenshots folders (`TargetFolders`, defaults to `Pictures\Screenshots`) older than 7 days.

## Features

- **Multi-Root Scanning:** Configure multiple root folders (`TargetFolders`) to clean in one pass, with automatic duplicate and nested root elimination.
- **Ignore Patterns:** Define glob patterns (`IgnorePatterns`) to exclude specific screenshot filenames from deletion.
- **Safe Recycling:** Files are sent to the Recycle Bin rather than permanently deleted.

## Usage

```powershell
.\ScreenshotsCleanup.ps1
```
