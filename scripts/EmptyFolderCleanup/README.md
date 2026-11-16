# EmptyFolderCleanup

Recursively removes all empty directories under chosen root folders (`TargetFolders`).

## Features

- **Multi-Root Scanning:** Configure multiple root folders (`TargetFolders`) to clean in one pass, with automatic duplicate and nested root elimination.
- **Reparse Point & Junction Skip:** NTFS junctions and symlinks are never traversed or deleted, protecting external files and directory structures.
- **Built-in Ignore List:** Protects common project and build artifact directories (`.git`, `.svn`, `.hg`, `node_modules`, `vendor`, `.venv`, `venv`, `__pycache__`, `.cargo`, `target`, `bin`, `obj`, `.vs`, `build`, `dist`, `packages`, `.nuget`) by default.
- **Opt-Out Control:** Set `UseDefaultIgnoreNames: false` in config to allow removing empty folders matching default names.
- **Custom Ignore List:** Add specific folder paths to `IgnoreFolders` to permanently exclude them and their children.

## Usage

```powershell
.\EmptyFolderCleanup.ps1
```
