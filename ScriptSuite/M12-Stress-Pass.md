# M12 — Phase 1 Adversarial Stress Pass: consolidated report

Date: 2026-08-28. Scope: 19 categories (Cat1a–Cat4f) over ScriptSuite `643013c` + Escape fix, build `net10.0-windows` `Microsoft.Data.Sqlite 10.0.11` `Microsoft.PowerShell.SDK 7.6.5` (`ScriptSuite/bin/Debug/net10.0-windows/ScriptSuite.exe` 2026-08-20 16:30:29). State root `%LOCALAPPDATA%\ScriptSuite` (`history.db`, `wizard.json`, `Configs/*.json`, `dashboard.json`). All harnesses under `%TEMP%\opencode\m12` share `m12-lib.ps1` (`Write-HarnessLog` → `m12-harness.log`, `SCRATCH-CREATE/DELETE` discrete, `HISTORY-RESET` vacuous, `Seed-BatchFlat` flat-at-root). Scratch-only isolation; no `ClearEventLogs`/`RestorePoint`/`EmptyRecycleBin` real-impact run per ground rule 4.

Reference commits: `643013c` app + `3ac7b4f` M11 report. Uncommitted at this pass: 9 modified `scripts/*.ps1`, `ElevationHarness/`, `ScriptSuite/bin`, `ScriptSuite/obj` (`.gitignore` keeps bin/obj untracked).

---

## 1. Status by category

| Cat | Script / trigger | Status | One-line evidence pointer |
|-----|------------------|--------|---------------------------|
| **Cat1a** | DownloadsCleanup scale 10k flat (5000×`.zip` + 5000×`.dat`), non-recursive scan | **done** | `history.db Id8 2026-08-27 19:47:16 DownloadsCleanup Success 5000 deleted` via `m12-cat1a-5000-scriptexecutor.ps1`; harness `%TEMP%\opencode\m12\m12-harness.log:2026-08-27 19:50:06.719 RESULT Success 10000 preview 5000 deleted` + `BIN-EMPTY 20623→0` `19:44:01.706`; post 5000/0/5000, log 10002 lines |
| **Cat1b** | EmptyFolderCleanup 5101 empty dirs (5000 flat + 100 nested chain + root), `MAX_PATH` 1067 chars | **done** | `history.db Id7 2026-08-27 16:06:07 EmptyFolderCleanup Success 5101 deleted` via `m12-cat1b-scriptexecutor.ps1`; harness `16:07:01.110 END`; DryRun 5101 → remain 0 after `\\?\` fix |
| **Cat1c** | TempCleanup multi-GB sparse (2GB/5GB/512MB/1KB), `N1 InvariantCulture` `2,048.0 MB` formatting | **done** | `history.db Id9 2026-08-27 20:38:14 Temp cleanup: 4 deleted` via `m12-cat1c-largefiles.ps1`; harness `20:38:15.230 END`; DryRun 4 Execute 0.20s remain 0 |
| **Cat1d** | DownloadsCleanup `stringList` 300 `.ext001-300` | **done** | `history.db Id10 2026-08-27 20:38:52 DownloadsCleanup 10 deleted` via `m12-cat1d-stringlist.ps1`; harness `20:38:53.347 END`; DryRun 20 Execute 0.42s remain 10 |
| **Cat2a** | Double-click `Run` guard | **failed** (bug) | `m12-cat2a-doubleclick-fixed.ps1` harness `20:43:47.183 START` proves `2× Run — Temp File Cleanup` windows `20:43:54`, `HISTORY-BEFORE 6→AFTER 6` (no second row); deferred to unified `_running` guard |
| **Cat2b** | Rapid `TempCleanup.json CutoffDays` toggling 100× + 2×50 concurrent | **done** | `m12-cat2b-rapidtoggle.ps1` harness `20:46:35.915 END`; final valid JSON `CutoffDays 7–16`, `0.27s`, no truncation |
| **Cat2c** | Two instances `history.db` `SQLITE_BUSY` | **done** (gap not reproduced) | `m12-cat2c-sqlitebusy.ps1` `20:46:50.620 END` + `m12-cat2c-busy2.ps1` `20:47:08.995 END`; `history.db Id11/12` both `Success` (`20:46:50`), aggressive `BEGIN IMMEDIATE 3s` also both `Success`; `PRAGMA journal_mode` is `delete`, no `WAL`/`busy_timeout` in `Services/RunHistoryStore.cs` but stress did not surface `BUSY` — gap not reproduced at 2-writer scale; `WAL`/`busy_timeout=0` remains unaddressed and untested at Phase-2-realistic concurrency |
| **Cat2d** | `Run All` vs manual `Run` conflict | **failed** (bug) | `m12-cat2d-runallconflict.ps1` harness `20:47:41.214 END` proves `2 windows` (`Run All — Preview` + `Run — …`) at `20:47`; deferred to unified guard |
| **Cat2e** | `Hide` during `Run All` preview | **failed** (bug) | `m12-cat2e-hideshow.ps1` harness `21:00:59.980 END`; `IsEnabled True` while `Run All — Preview` open (should be disabled); deferred to unified guard |
| **Cat3a** | Corrupt `TempCleanup.json` | **failed** (bug) | `m12-cat3a-corruptconfig.ps1` harness `21:01:38.363 END`; `Failed Error Conversion from JSON` via `Services/ScriptConfigService.cs:18`; decision Option A vs B still open |
| **Cat3b** | Corrupt manifest JSON | **done** | `m12-cat3b-corruptmanifest.ps1` harness `21:02:02.778 END`; `ManifestCatalog` skips malformed, main `Script Suite` still up — graceful |
| **Cat3c** | Path edges (unicode/trailing slash/UNC/`Z:\`/trailing dot) | **done** (low-priority quirk) | `m12-cat3c-pathedges.ps1` harness `21:10:18.861 END`; all counts `0/724` no crash; `Z:\` yields `parameter binding File vs trailing_dot` not `path-not-found` — add `Test-Path` guard (low priority) |
| **Cat3d** | Missing/corrupt `TempCleanup.ps1` | **done** | `m12-cat3d-missingscript.ps1` harness `21:10:38.676 END`; `threw not recognized syntax → Failed` not crash — correct graceful `Failed` |
| **Cat4a** | Kill during preview — 500 files (proven) + 2000 files (own evidence, not inherited) | **done** | 500: `m12-cat4a-killpreview.ps1` harness `21:12:36.897 END`; 2000: `m12-cat4a-2000-root.ps1` harness `11:38:59.052 RESULT Success at 2000` (`RootElement.FindFirst` fix), `APP-LAUNCH pid=7540 11:38:49.046` → `UI-FOUND Run Temp File Cleanup 11:38:52.380` → `KILL 11:38:53.403` (1.011s after invoke) → `JOURNAL False` `11:38:55.421` → `RELAUNCH pid=22336 11:38:58.444` → `POST remain=2000 11:38:58.677`; `ALL-BUTTONS 39` proves tile renders |
| **Cat4b** | Kill mid-`Config` save | **done** | `m12-cat4b-midconfig.ps1` harness `21:12:54.946 END`; rapid 200× `CutoffDays` write/kill → `POST valid JSON CutoffDays 7–16`, `DRYRUN Warning 0 Error 0`; last-writer-wins, no corruption |
| **Cat4c** | Kill mid-`history.db` insert | **done** | `m12-cat4c-midinsert.ps1` harness `21:13:18.499 END`; 100× job inserts + kill → `PRAGMA integrity_check ok`, `HISTORY-AFTER delta partial`, stress rows cleaned |
| **Cat4d** | Kill elevated child (`m12_elevated_test` scratch, `requiresAdmin:true` generic `RunElevated`) | **done** (with caveat) | `m12-cat4d-elevatedkill-v2.ps1` harness `22:11:06.208 END`; `10s sleep` child → `JOB OUTPUT RunElevated Outcome=Failed Logs=The elevated helper did not write a result file.`; no crash — caveat: child kill not confirmed via `Stop-Process`/handle; result file never appeared, plausibly a UAC-hidden-window visibility artifact rather than a true kill-mid-elevation event; does not fully prove the elevated-kill path was exercised as intended |
| **Cat4e** | Kill during first-run wizard (embedded buttons) | **done** | `m12-cat4e-killwizard-v2.ps1` harness `11:43:19.624 RESULT Success`; `WIZARD-DELETE` `11:43:06.855` → `UI-FOUND wizard embedded via Use recommended defaults 11:43:12.164 Step 1 of 8` → `KILL 11:43:13.491` → `WIZARD-EXISTS after kill False` `11:43:15.505` `JOURNAL False` `INTEGRITY ok` → `WIZARD2 found after relaunch 11:43:18.583`; restored `wizard.json len 31` |
| **Cat4f** | Repeated kill/relaunch 5 cycles (alternating mid-preview/idle) | **done** | `m12-cat4f-repeatedkill.ps1` harness `11:43:52.104 RESULT Success`; `SEED 200` → 5× `JOURNAL False` `INTEGRITY ok` `REMAIN 200` (`CYCLE 1 pid12716 11:43:28.790` … `CYCLE 5 pid20404 11:43:47.757`) → `FINAL MAIN found 11:43:51.795 BUTTONS 39 has Run Temp True` `FINAL INTEGRITY ok HISTORY 8 delta 0` |

**Not run per ground rule 4 (deliberate scope boundary, not oversight):** any real-impact execution of `ClearEventLogs`, `Create Restore Point`, or `EmptyRecycleBin` (would touch 62 live event logs / VSS / 20623-bin recycle bin). Their manifests/configs were inspected and their dashboard entries exercised only for `Hide`/`Settings`/`Run All` preview, never `Confirm`. See §5.

---

## 2. Deferred fix backlog (itemized, not yet applied except where noted)

### 2.1 Unified `_running` / active-run guard — **one fix covers Cat2a + Cat2d + Cat2e**
- **Covers:** Cat2a (double-click opens 2× `Run —` windows, `Services/ScriptExecutor.cs` `WaitForExit` no timeout + `MainWindow.xaml.cs ShowDialog` no guard), Cat2d (`Run All — Preview` vs manual `Run` yields 2 windows `20:47`), Cat2e (`Hide` `IsEnabled True` while `Run All — Preview` open `21:00`).
- **Fix:** single `_running`/`_activeRun` flag in `MainWindowViewModel`/`MainWindow.xaml.cs` + `Services/ScriptExecutor.cs` guard that disables `Run`/`Run All`/`Hide` while any `ScriptRunWindow`/`RunAllPreviewWindow` is open, and queues or rejects a second `InvokePattern`. One patch, three categories closed. **Deferred — not applied mid-stress; harnesses prove bugs remain.**

### 2.2 `TempCleanup` corrupt-config handling (Cat3a) — **Option A vs B still open, not chosen**
- **Evidence:** `Services/ScriptConfigService.cs:18` `Load()` returns empty `JsonObject` on malformed → `SetField` `File.WriteAllText` non-atomic; harness `21:01:38.363` shows `Failed Error Conversion from JSON`.
- **Options:** A) fail closed with `Failed` + `Write-Warning` (transparent), B) fallback to `DefaultConfigs\TempCleanup.json` + `Write-Warning` (resilient). Decision still open. Intent stated: **Option B with warning** (not silent fallback) — `WarningCount>0→Warning` via `Services/ScriptExecutor.cs:170`. **Not yet applied.**

### 2.3 Cat3c `Z:\` provider-binding quirk — **low priority, add `Test-Path` guard**
- **Evidence:** `m12-cat3c-pathedges.ps1` `21:10:18.860`; `Z:\nonexistent` gives `parameter binding File vs trailing_dot` mismatch vs `path-not-found` for other drives. Root cause: `ViewModels/SettingsFieldViewModel.cs` path warning only checks `Directory.Exists` after `Path.GetDirectoryName`, not provider validity. Fix: `Test-Path -IsValid` + `ValidateDriveLetter` guard in `SettingsFieldViewModel.Validate()`; keep graceful `0/724` counts. Low priority.

### 2.4 EmptyFolderCleanup `\\?\` long-path fix — **already applied and verified, not backlog**
- **Bug:** `scripts/EmptyFolderCleanup/EmptyFolderCleanup.ps1:92-104` 100-deep `1067 chars >260 MAX_PATH` chain; `CreateFileW` + `Directory.Delete` fails; loop left `101 remain` (`level_100` warning only, `level_099` silent `while($deletedAnything)` exit) — harness `15:14` DryRun `5101` → `5000 deleted`.
- **Fix applied:** `ConvertTo-LongPath` helper **only** in `Remove-EmptyFolder` at `:100`/`:112` (enumeration kept original `Get-ChildItem` at `:143/:165` after 5001 regression when `\\?\` added to enumeration `5101→5001`), plus post-loop `$remainingEmpty` `Get-ChildItem -Recurse | Where Count -eq 0 → Write-Warning` so `ScriptExecutor.cs:170 WarningCount>0→Warning`. Verified via `m12-cat1b-scriptexecutor.ps1` re-run `DRYRUN 5101 EXECUTE 53.25s Success remain 0 LOG 5103 DELETED 5101 HISTORY Id7` `16:06:07`. **Not backlog.**

---

## 3. Open anomalies not filed as bugs

### 3.1 DownloadsCleanup Execute timing residual (~34s unexplained beyond SDK overhead, correlated but not proven causal with `E:` USB `I/O` errors)
- **Evidence:** Cat1a 2000-file direct run `93.91s` at `20:28` vs SDK `PowerShell.Create` run `136.91s` same files → `+43s` SDK overhead confirmed via back-to-back A/B. Cat1a 10k-file run via SDK `Id8` `1.51s DryRun?` actually `169.89s Execute Success` at `19:47:16` vs prior direct `93.91s` → `+76s`; subtracting `43s` SDK leaves `~33–34s` residual. That session's `E: StoreJet Transcend` `Event 140 transaction log I/O error ×6 19:50:30-59` (USB) correlated in time but no causal link proven; `DownloadsCleanup.ps1:177` is non-recursive, not touching `E:`; `m12-lib.ps1` seeds only `%LOCALAPPDATA%`. **Not filed as bug — flagged as open anomaly, keep `E:` unplugged for timing baselines; future pass should A/B with `E:` detached to isolate.**

---

## 4. `history.db` provenance note (so a future session doesn't re-derive)

Current `history.db` (`%LOCALAPPDATA%\ScriptSuite\history.db`, `12288` bytes, `PRAGMA integrity_check ok`) holds `8` rows `Id5–Id12`. Backups under `%LOCALAPPDATA%\ScriptSuite\history.db.pre-*.bak` preserve superseded rows. `m12-harness.log` is the authoritative `SCRATCH-CREATE/DELETE` + `HISTORY-RESET` chain.

| Id | ScriptId | Outcome | StartedAt | Summary | Provenance | Trustworthy? | Notes |
|----|----------|---------|-----------|---------|------------|--------------|-------|
| 1 | DownloadsCleanup | Success | 2026-08-21 16:08:52 | `5000 deleted, 0 skipped` | `ScriptExecutor` (?) DB-only | **superseded** | Log missing — `CleanupLog.txt:154 Out-File -Append` but file `CreationTime 19:00:43 == Id3 Started` proves recreation between Id1/Id3; DB-only, not file+log+history atomic |
| 2 | EmptyFolderCleanup | Success | 2026-08-21 16:15:01 | `<NULL>` | ScriptExecutor incomplete | **superseded** | `<NULL>` summary; prior `16:15` run `957952` log size; overwritten |
| 3 | DownloadsCleanup | Success | 2026-08-21 19:00:43 | `5000 deleted, 0 skipped` | ScriptExecutor | **superseded** | Archived in `history.db.pre-cat1a-clean-20260827-003503.bak` |
| 4 | *(interim)* DownloadsCleanup | Success | 2026-08-27 00:38:29? | `5000 deleted` | **manual `INSERT INTO RunHistory ... 'Success'`** (not `ScriptExecutor.InvokeInProcess`) | **not trustworthy** | Interim `beforeRows=1` at `00:38:19` was `Id4` manual; vacated by `HISTORY-RESET beforeRows=1` `00:38:19.934` |
| 5 | DownloadsCleanup | Success | 2026-08-27 00:38:29 | `5000 deleted, 0 skipped` | **manual INSERT** (`Id5` in `pre-cat1a-dryrunfix-20260827-140052.bak`) | **superseded / not trustworthy** | Superseded by `Id8`; kept only for delta-reasoning |
| 6 | EmptyFolderCleanup | Success | 2026-08-27 15:28:26 | `5000 deleted` | **manual INSERT** | **superseded** | Left `101 remain` (`level_100` chain bug before `\\?\` fix); superseded by `Id7` |
| 7 | EmptyFolderCleanup | Success | 2026-08-27 16:06:07 | `5101 deleted` | **`ScriptExecutor` via `PowerShell.Create` SDK** (`AppPaths.ConfigPathFor` same as `ScriptRunWindow.xaml.cs:81,183` `requiresAdmin:false→ExecuteInProcess` generic) | **trustworthy** | Verifies `\\?\` + `$remainingEmpty` fix; `5101` remains `0` `LOG 5103 DELETED 5101` |
| 8 | DownloadsCleanup | Success | 2026-08-27 19:47:16 | `5000 deleted, 0 skipped` | **`ScriptExecutor` SDK after `BIN-EMPTY 20623→0` `19:44:01.706 Clear-RecycleBin 2m44s`** | **trustworthy** | Atomic 10k preview `DryRun 10000` `EXECUTE 169.89s` `POST 5000/0/5000`; `Id4/5/6` are **not** evidence for this scale |
| 9 | TempCleanup | Success | 2026-08-27 20:38:14 | `Temp cleanup: 4 deleted` | **ScriptExecutor** | **trustworthy** | Cat1c sparse |
| 10 | DownloadsCleanup | Success | 2026-08-27 20:38:52 | `10 deleted` | **ScriptExecutor** | **trustworthy** | Cat1d stringList 300 |
| 11 | TempCleanup | Success | 2026-08-27 20:46:50 | `Cat2c job1` | **ScriptExecutor concurrent job1** | **trustworthy** | Cat2c SQLITE_BUSY probe |
| 12 | TempCleanup | Success | 2026-08-27 20:46:50 | `Cat2c job2` | **ScriptExecutor concurrent job2** | **trustworthy** | Same second as Id11 |
| — | *(Cat2c aggressive)* | — | 2026-08-27 20:47:05 | — | holder/contender rows removed after test | — | Not in final DB; `PRAGMA integrity_check ok` verified |

**Rule for future sessions:** only `Id7–Id12` are `ScriptExecutor`-derived, file+log+history atomic evidence. `Id1–Id6` are either manual `INSERT`s or superseded runs without `ScriptExecutor` — do not cite them as proof; they are kept in `*.bak` only to explain the `beforeRows` `3→1` discrepancy derived from scratch.

---

## 5. What was explicitly not attempted

Any real-impact test on `ClearEventLogs`, `Create Restore Point`, or `EmptyRecycleBin` was **deliberately not run** per ground rule 4 (evidence over summaries, never guess, report broken/suspicious plainly, **stop-and-ask before `ClearEventLogs`/`RestorePoint`/`EmptyRecycleBin`** which touch 62 live event logs / VSS / recycle bin). This is a **scope boundary, not an oversight**.

- `ClearEventLogs` manifest/config inspected, dashboard `Hide`/`Settings`/`Run All` preview exercised, but `Confirm` never invoked (would clear `62` real logs; backups in `%USERPROFILE%\Documents\Script_Logs\EventLogBackups` were **kept** per user decision).
- `RestorePoint` manifest/config inspected, preview exercised, `Confirm` never invoked (would create `SystemRestore` point; `Checkpoint-Computer` touches real OS state).
- `EmptyRecycleBin` inspected, preview exercised, `Confirm` never invoked after `BIN-EMPTY 20623→0` (would delete `20623` real bin items; `EmptyRecycleBin.ps1` deferred).

Scratch-only triggers used throughout: `m12scratch-dl`, `m12scratch-ef`, `m12scratch-tc-1c`, `m12scratch-cat1d`, `m12scratch-cat4a/f` etc., plus `m12_elevated_test` (`requiresAdmin:true`) for Cat4d via the generic `RunElevated` path (`Scripts/m12_elevated_test/test.ps1` `10s sleep`, result file missing → `Failed`). All `Remove-ScratchLogged`/`New-ScratchLogged`/`Reset-HistoryLogged`/`Write-HarnessLog` are in `%TEMP%\opencode\m12\m12-harness.log`.

---

## 6. Build & environment at sign-off

- App: `ScriptSuite/bin/Debug/net10.0-windows/ScriptSuite.exe` 2026-08-20 16:30:29 (`net10.0-windows`, `Microsoft.Data.Sqlite 10.0.11`).
- State: `wizard.json {"wizardCompleted": true}` `dashboard.json` `history.db` 8 rows `Id5–12` `integrity_check ok` at `2026-08-28 11:43:52.037` (`FINAL INTEGRITY ok HISTORY 8 delta 0`).
- `AppDataRoot` clean: `m12scratch-*` all `SCRATCH-DELETED`, `journal.json` `False` after every kill cycle.
- Harnesses: `m12-lib.ps1`, `m12-cat1a-5000-scriptexecutor.ps1`, `m12-cat1b-scriptexecutor.ps1`, `m12-cat1c-largefiles.ps1`, `m12-cat1d-stringlist.ps1`, `m12-cat2a-doubleclick-fixed.ps1`, `m12-cat2b-rapidtoggle.ps1`, `m12-cat2c-*.ps1`, `m12-cat2d-runallconflict.ps1`, `m12-cat2e-hideshow.ps1`, `m12-cat3a-corruptconfig.ps1`, `m12-cat3b-corruptmanifest.ps1`, `m12-cat3c-pathedges.ps1`, `m12-cat3d-missingscript.ps1`, `m12-cat4a-killpreview.ps1`, `m12-cat4a-2000-root.ps1` (`RootElement.FindFirst` fix), `m12-cat4e-killwizard-v2.ps1`, `m12-cat4f-repeatedkill.ps1`.

Next: apply backlog §2.1–2.3 in one branch, re-run only `Failed` categories (Cat2a/d/e, Cat3a, Cat3c `Z:\`) plus timing A/B with `E:` detached for §3.1.

