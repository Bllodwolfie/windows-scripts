# windows-scripts

![License](https://img.shields.io/github/license/Bllodwolfie/windows-scripts)
[![Catppuccin](https://img.shields.io/badge/catppuccin-Mocha%20%26%20Latte-DDB6F2?style=flat)](https://github.com/catppuccin/catppuccin)

A Windows maintenance suite — a WPF dashboard (`ScriptSuite`) over nine self-contained PowerShell scripts for cleanup, system tasks, and diagnostics. For most users it's a normal Windows app (download, unzip, run); for developers the same scripts run directly via PowerShell and the app builds from source.

## Preview

![ScriptSuite dashboard](assets/dashboard.png)

*ScriptSuite dashboard in Mocha dark (966×633) — the Cleanup section shown (5 of 9 script tiles); System and Reports sections continue below. Each tile has run, settings, and hide controls, plus "run all" selection. History and Run All are accessible from the header.*

## Download — for most users (no SDK needed)

**Latest Release:** [`v1.0.1` — `ScriptSuite v1.0.1`](https://github.com/Bllodwolfie/windows-scripts/releases/tag/v1.0.1)

1. Download [`ScriptSuite-win-x64-self-contained.zip`](https://github.com/Bllodwolfie/windows-scripts/releases/download/v1.0.1/ScriptSuite-win-x64-self-contained.zip) (80.3 MB zip, 188.8 MB unzipped, 766 files — self-contained `win-x64`, no .NET runtime to install).
2. Right-click the zip → `Extract All` → open the folder.
3. Double-click `ScriptSuite.exe`. Optionally run `Install.ps1` from the repo to create a Start Menu shortcut (Windows Search → `ScriptSuite`).

> **First-run SmartScreen:** the exe is unsigned, so Windows SmartScreen / Microsoft Defender SmartScreen may show *Windows protected your PC* → click `More info` → `Run anyway`. The zip comes from GitHub via `Mark of the Web`; extracting with Explorer handles it. No admin needed to run the app itself.

*Requires Windows 10 / 11 (x64). No PowerShell version check — the shipped `scripts\` are bundled with the publish output.*

## Build from source — for developers

**Prerequisite:** [.NET 10 SDK](https://dotnet.microsoft.com/download) (`10.0.x`, `dotnet --version` should print `10.0.400+`). The app builds `ScriptSuite/ScriptSuite.csproj:3` (`net10.0-windows`, `UseWPF`).

```powershell
git clone https://github.com/Bllodwolfie/windows-scripts.git
cd windows-scripts

# Per-user install (no admin): publish self-contained to %LOCALAPPDATA%\Programs\ScriptSuite
# and create %APPDATA%\Microsoft\Windows\Start Menu\Programs\ScriptSuite.lnk
.\Install.ps1

# Later
.\Uninstall.ps1   # removes app + shortcut, keeps %LOCALAPPDATA%\ScriptSuite data (history.db, configs)
```

`Install.ps1` runs `dotnet publish -c Release -r win-x64 --self-contained true -o publish` (`publish` is not committed, `**/bin/`, `**/obj/` are gitignored) and copies to the stable per-user path (`AppPaths.cs:26` data stays at `%LOCALAPPDATA%\ScriptSuite`). Use `-NoBuild` to install from an already-downloaded Release zip, or `-InstallDir` / `-ShortcutPath` to override.

**Run scripts directly (no dashboard):**

```powershell
# If your policy already allows local scripts (RemoteSigned)
.\scripts\SystemHealthReport\SystemHealthReport.ps1

# Fresh Windows (Restricted) — one-off bypass, no permanent change
pwsh -ExecutionPolicy Bypass -File .\scripts\SystemHealthReport\SystemHealthReport.ps1

# From a ZIP download, first unblock
Get-ChildItem .\scripts -Recurse -Filter *.ps1 | Unblock-File
```

## The 9 scripts

Descriptions are verbatim from `ScriptSuite/Manifests/*.json:2` (source of truth for what ships; `v1.0.1` excludes `m12_elevated_test` test scaffolding).

| Script | What it does | Requires admin |
|--------|--------------|----------------|
| [SystemHealthReport](scripts/SystemHealthReport/) | Generates a self-contained HTML report of system health (CPU, memory, disks, network, errors). | No |
| [ClearEventLogs](scripts/ClearEventLogs/) | Backs up and clears all Windows event logs. | **Yes** |
| [DownloadsCleanup](scripts/DownloadsCleanup/) | Sorts and cleans the Downloads folder: deletes old installer/archive files and moves others into matching category folders. | No |
| [EmptyFolderCleanup](scripts/EmptyFolderCleanup/) | Recursively removes empty folders under a chosen root folder. | No |
| [EmptyRecycleBin](scripts/EmptyRecycleBin/) | Permanently empties the Recycle Bin. Deleted files cannot be recovered. | No |
| [RestorePoint](scripts/RestorePoint/) | Creates a System Restore point and verifies it actually appeared. | **Yes** |
| [ScreenshotsCleanup](scripts/ScreenshotsCleanup/) | Deletes old screenshots from the Pictures\Screenshots folder. | No |
| [SoftwareInventory](scripts/SoftwareInventory/) | Generates a text report of all installed software. | No |
| [TempCleanup](scripts/TempCleanup/) | Deletes files from the Windows temp folder that are older than the cutoff. | No |

Defaults live in `ScriptSuite/DefaultConfigs/*.json:1` and copy to `%LOCALAPPDATA%\ScriptSuite\Configs\` on first run (`AppPaths.cs:37` `EnsureConfigsSeeded`, never overwrites existing):

- `ClearEventLogs` → `BackupDir: %USERPROFILE%\Documents\Script_Logs\EventLogBackups`
- `DownloadsCleanup` → `SourceDir: %USERPROFILE%\Downloads`, `CutoffDays: 7`, `LogDir: %USERPROFILE%\Documents\Script_Logs` (+ `DeleteExts` / `Categories`)
- `EmptyFolderCleanup` → `TargetFolder: %USERPROFILE%\Downloads`
- `ScreenshotsCleanup` → `TargetFolder: %USERPROFILE%\Pictures\Screenshots`, `CutoffDays: 7`
- `SoftwareInventory` → `OutputFile: %USERPROFILE%\Documents\Script_Logs\Software_Inventory.txt`
- `SystemHealthReport` → `OutputDir: %USERPROFILE%\Documents`, `OutputFile: System_Health_Report.html`
- `TempCleanup` → `TargetFolder: %TEMP%`, `CutoffDays: 7`

Each script supports dry-run preview where `supportsDryRun: true` in its manifest (7 of 9; `SoftwareInventory` and `SystemHealthReport` are reports, not previews).

*Sample `System Health Report` output (fictional data, Catppuccin Mocha/Latte, 1360×1600) — see `assets/preview.png`:*

![Sample System Health Report](assets/preview.png)

## Prerequisites

- **For the Release zip:** Windows 10 / 11 x64 only. No .NET runtime, no PowerShell version needed (self-contained).
- **For `scripts\` directly:** Windows 10 / 11, PowerShell 5.1+ (PowerShell 7 recommended).
- **For building:** Windows 10 / 11, .NET 10 SDK (`10.0.x`).

## Known limitations & notices

- **Unsigned exe:** SmartScreen warning on first launch (see above). No EV cert yet.
- **Scheduled/unattended runs are not yet supported — all runs are manual, via the dashboard:** the dashboard has Run/History/Settings; automatic Task Scheduler wiring is planned and will reuse the stable per-user install path (`%LOCALAPPDATA%\Programs\ScriptSuite\ScriptSuite.exe`). The `Install.ps1` path is already the permanent one.
- **SQLite WAL sidecars:** run history lives at `%LOCALAPPDATA%\ScriptSuite\history.db` (`RunHistoryStore.cs:84` `journal_mode=WAL`, `busy_timeout=5000`). Beside it you will see `history.db-wal` / `history.db-shm` — normal for WAL; don't copy the `.db` alone while the app is running (raw `File.Copy` would miss uncheckpointed wal). Use `wal_checkpoint` or the app’s backup API when it exists.
- **v1.0.1 vs v1.0.0:** `v1.0.0` shipped `Manifests/m12_elevated_test.json` (`Test` category, `10s sleep` harness for Cat4d). `v1.0.1` excludes it via `ScriptSuite.csproj:21` `Exclude="Manifests\m12_elevated_test.json"` / `Exclude="..\scripts\m12_elevated_test\**\*"`. The source files remain in repo for `ElevationHarness` regression tests.

## License

MIT — see [LICENSE](LICENSE) (Copyright (c) 2026 Bllodwolfie).
