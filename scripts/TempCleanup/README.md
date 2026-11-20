# TempCleanup

Deletes files in temporary folders (`TargetFolders`, defaults to `%TEMP%`) older than 7 days.

## Features

- **Multi-Root Scanning:** Configure multiple root folders (`TargetFolders`) to clean in one pass, with automatic duplicate and nested root elimination.
- **Custom Ignore List:** Add specific folder paths to `IgnoreFolders` to permanently exclude them and their children.
- **Safe Recycling:** Files are sent to the Recycle Bin rather than permanently deleted.

## Usage

```powershell
.\TempCleanup.ps1
```
