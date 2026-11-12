# Changelog

All notable changes to ScriptSuite are documented in this file.

## [3.2.3] - 2026-11-13

### Fixed
- TextBox, ComboBox and ComboBoxItem now use full custom templates bound to theme tokens, so they render correctly when third-party theming tools (e.g. Windhawk) are active; History search box text no longer clips.

## [3.2.2] - 2026-11-10

### Reliable Installation & Packaging
- **Install.cmd Launcher:** Added `Install.cmd` to the release zip and repository root to serve as the zero-setup primary installation method. Double-clicking automatically removes Mark of the Web (`Unblock-File`), applies `-ExecutionPolicy Bypass`, and initiates `Install.ps1` under Windows PowerShell 5.1 with no extra setup.
- **PowerShell 5.1 Compatibility:** Eliminated `$PSScriptRoot` evaluation from parameter defaults in `Install.ps1` and `Uninstall.ps1`, resolving a runtime crash (`Cannot bind argument to parameter 'Path' because it is an empty string`). Script directory and path resolution now occur dynamically inside the script body with `$MyInvocation.MyCommand.Path` fallback.
- **Prebuilt Layout Decoupling:** Prebuilt-exe mode (extracted zip) operates completely independently of `ProjectPath` and the .NET SDK, deploying packaged assets directly.
- **UAC Waiting & Output Synchronization:** Unelevated launchers now block until the elevated installer finishes via `Start-Process ... -Verb RunAs -PassThru -Wait`, catching user cancellation (Win32Exception 1223) without throwing unhandled exceptions and reporting consistent PASS/FAIL exit status.
- **Persistent Logging:** Elevated operations write step-by-step audit logs to `%ProgramData%\ScriptSuite\install.log` and `uninstall.log`, and interactive execution pauses at completion so summaries remain readable.
- **Strict Read-Back Verification:** The installer validates that the target executable exists, reads back its `ProductVersion` against expected project/staging manifests, and confirms the shortcut `TargetPath` before concluding.
- **Automated Regression Suite:** Added `tests/install-tests.ps1` testing isolated installations under Windows PowerShell 5.1, PowerShell 7, `Install.cmd`, 3.1.2 task upgrade migration, running exe termination, locked-file error handling, UAC decline handling, version mismatch detection, and clean uninstallation.

## [3.2.1] - 2026-11-09

### Scheduler Hardening & Fixes
- **Access-Denied Only Elevation:** Restricted elevation escalation in `ScheduledTaskService.Register` strictly to proven access denied signals (`0x80070005`, `PermissionDenied`, `Access is denied`). Removed fallback checks on `requiresAdmin` so argument/syntax errors, timeouts, and exceptions report their own errors without triggering UAC.
- **Eliminated Unregister-Before-Register:** Replaced the unregister-then-register sequence with atomic `Register-ScheduledTask -Force` alone. If registration fails or is rejected, the existing task and its schedule remain intact.
- **Elevated Helper Timeout & Read-Back Verification:** Extended `RegisterElevated` timeout from 20 seconds to 120 seconds to accommodate slower UAC prompt interactions. Elevated registrations are now verified by read-back against Task Scheduler before reporting success.
- **CLIXML Error Sanitization:** Added `CleanErrorMessage` to strip PowerShell `#< CLIXML` formatting, decode hex entities, and remove cmdlet and stack traces so the UI only displays clean, human-readable error messages.
- **Automated Regression Suite:** Added a dedicated test harness (`tests/ScheduleTests`) covering access-denied detection, non-access-denied failures, read-back trigger mismatches, UAC cancellation atomicity, independent task XML preservation, and CLIXML parsing.

## [3.2.0] - 2026-11-09

### Features & Scheduling Control
- **Multi-Weekday Selection:** Weekly schedules now support selecting any combination of weekdays (Monday through Sunday) via checkboxes, with validation ensuring at least one day is selected.
- **Anchor & Start Date Picker:** Users can specify a `startDate` for Days, Hours, and Weeks (with intervals > 1 week). In multi-week schedules, `startDate` anchors the recurrence week cycle in Windows Task Scheduler.
- **Live Next Run Preview:** The schedule dialog calculates and displays an exact, deterministic `"Next run: Ddd dd.MM.yyyy HH:mm"` preview synchronized with Task Scheduler's `StartBoundary` calculation without guessing or UTC drift.
- **Collision Warning:** Added non-blocking collision warnings when an enabled schedule conflicts with another task at the same time and overlapping days to prevent `Skipped — app was busy` mutex conflicts.
- **Strict Registration Verification:** `ScheduledTaskService` now inspects the registered task XML (`StartBoundary`, `DaysOfWeek`, `WeeksInterval`) after registration to guarantee exact trigger matching, eliminating the false-positive fallback.
- **Self-Elevating Save Over Admin-Owned Tasks:** If a standard-user save over an existing admin-owned task fails with Access Denied (`0x80070005`), the app seamlessly prompts for elevation via UAC to update the task while preserving user-mode execution credentials for non-admin scripts. Canceling UAC leaves the task and `schedules.json` untouched.
- **In-Memory Legacy Migration:** Legacy schedule entries lacking `weekdays` or `startDate` are automatically populated in memory from Task Scheduler XML on load and persisted on explicit save without rewriting untouched configs on startup.

## [3.1.2] - 2026-11-03

### Security & Hardening
- **CLI Argument Containment:** Removed the `--config-path` CLI parameter completely from `App.xaml.cs` and `ScriptExecutor.RunElevated`. Elevated execution now unconditionally resolves configuration files through the canonical `%LOCALAPPDATA%\ScriptSuite\Configs\<scriptId>.json` path via `AppPaths.ConfigPathFor(scriptId)`, ensuring no CLI argument can supply or override the configuration path during elevated runs.

## [3.1.1] - 2026-11-03

### Security & Hardening
- **Trust Store Parameter Removal:** Removed the `configPath` parameter from `ConfigTrustStore.IsTrusted` and `Trust` so trust verification always checks against the canonical `%LOCALAPPDATA%\ScriptSuite\Configs` location rather than caller-supplied CLI paths. Test harnesses use an internal constructor for isolated testing.
- **AppData Redirection:** `AppPaths.AppDataRoot` now checks `%LOCALAPPDATA%` environment variable before querying the shell known folder, allowing test harnesses to redirect the runtime environment without polluting user data.
- **Fresh Install Auto-Trust:** `AppPaths.EnsureConfigsSeeded()` automatically seeds `config-trust.json` whenever default configurations are copied on a fresh install.

## [3.1.0] - 2026-11-03

### Security (SEC-04)
- **Configuration Trust System:** Config files in `%LOCALAPPDATA%\ScriptSuite\Configs` are protected by SHA-256 hashes stored in `%LOCALAPPDATA%\ScriptSuite\config-trust.json`. On upgrade/initial install, existing configs are automatically seeded into the trust store.
- **Auto-Approval on Save:** Saving configuration changes through the application UI immediately updates the trusted hash.
- **Untrusted Review Dialog:** If a configuration is modified outside the application (hand-edited or imported), interactive runs and schedule creation/edits display a modal review dialog summarizing planned actions, targeted directories, and file patterns. Users must explicitly choose "Trust and continue" (or Cancel, which is default) before the script can run or schedule. Dry-run previews remain exempt.
- **Headless Enforcement:** Headless executions (`--scheduled-run` and `--elevated-run`) strictly reject untrusted configs without prompting, record a `Failed` entry in `ScheduledRuns` with summary `"Config not trusted; open ScriptSuite and review it"`, and exit with code 1.
- **Independent Child Verification:** Elevated child processes independently verify configuration trust before executing any administrator action.
- **Non-Dry-Run Explicit Execution:** Reporting scripts without dry-run support (`SoftwareInventory`, `SystemHealthReport`) no longer run automatically on window load; users must explicitly click "Run" after viewing the resolved destination path.

### Fixed & Hardened
- **Audit Hardening:** Removed production-reachable test elevation override (`$env:SCRIPTSUITE_FORCE_NONELEVATED`) from all shipped scripts.
- **Encoding Integrity:** Restored original UTF-8 without BOM encoding on `ScriptSuite/Services/ScriptExecutor.cs` and `scripts/ClearEventLogs/ClearEventLogs.ps1`.
- **Destination Validation:** Validated all declared category destination keys in `DownloadsCleanup.ps1` regardless of extension mapping.
- **Dynamic Extension:** Derived expected output extension in `SoftwareInventory.ps1` dynamically from default configuration.

## [3.0.3] - 2026-11-03

### Security
- **Path Scope Denylist:** `Test-PathScope` across cleanup and report scripts (`DownloadsCleanup`, `EmptyFolderCleanup`, `ScreenshotsCleanup`, `TempCleanup`, `SystemHealthReport`, `SoftwareInventory`) hard-aborts with exit 1 regardless of elevation if any target path equals or is an ancestor of: a drive root, `%SystemRoot%`, `%ProgramFiles%`, `%ProgramFiles(x86)%`, `%ProgramData%`, `%USERPROFILE%`, `%APPDATA%`, `%LOCALAPPDATA%`, `%LOCALAPPDATA%\ScriptSuite`, or the application installation directory. Drive-root targets are now blocked.
- **Trailing Separator Scope Boundary:** All path containment checks enforce trailing directory separators to prevent sibling-prefix directory escapes (e.g., `Downloads-evil` is strictly recognized as outside `Downloads`).
- **ClearEventLogs BackupDir Scope Validation:** Added scope validation preventing `BackupDir` from equaling or being an ancestor of any denylisted target, and prohibiting backup directories inside `%SystemRoot%` or `%ProgramFiles%`.
- **SoftwareInventory Output Validation:** Validates `OutputFile` parent directory against the path denylist, and refuses to overwrite existing files whose extension differs from the script's own output extension (`.txt`).
- **Manifest ScriptPath Containment:** `ScriptManifest.AbsoluteScriptPath` enforces strict directory containment under `<BaseDirectory>\scripts\`; attempts to traverse outside throw `SecurityException`, which the UI and runner surface as a clear error without crashing the application.
- **SEC-04 Notice:** Documented limitations regarding unauthenticated shared configuration files and the Authenticode signature design rationale in `README.md`.

## [3.0.2] - 2026-11-03

### Fixed
- **Uninstaller Schedule Cleanup:** `Uninstall.ps1` removes only the unregistered script entries from `%LOCALAPPDATA%\ScriptSuite\schedules.json` upon unregistering tasks, leaving any non-ScriptSuite keys intact and backing up `schedules.json.bak` beforehand. Respects `-WhatIf` and gracefully handles missing/malformed schedule files (`3cd5e53`).
- **Comprehensive Z-Strip Verification:** Added multi-scenario test coverage verifying `Install.ps1` Z-strip migration across Daily triggers, Hourly repetition triggers, S4U/Highest tasks, schedule mismatch skip/warning, and idempotency on already-local boundaries.

## [3.0.1] - 2026-11-03

### Fixed
- **Installer Upgrade Z-Strip:** `Install.ps1` automatically detects existing `\ScriptSuite\*` triggers with legacy `Z` or UTC offset `StartBoundary` and converts them to local no-Z timestamps via `[DateTimeOffset]::Parse($sb).LocalDateTime`, cross-checking against `schedules.json` `timeOfDay` to prevent DST drift for upgrading users (`df35c3e`).
- **Elevated Child Exit Code:** `ScriptExecutor` and `App.xaml.cs` return exit code 1 instead of -1 on elevated child exception paths (`71e89a5`).
- **End-to-End Lifecycle Verification:** Full installation, uninstallation, task backup/restoration, and AppData integrity verified end-to-end.

## [3.0.0] - 2026-11-03

### Security
- **SEC-01: Elevated run script ID validation**
  - `--elevated-run <id>` validates the script ID against the catalog and strictly rejects non-admin scripts with an explicit error and non-zero exit code (`63f9112`).
- **SEC-02: Secure installation directory in Program Files**
  - `Install.ps1` installs the application and shipped scripts to `%ProgramFiles%\ScriptSuite\` (`5bd4a5f`).
  - Directory inherits admin-only write ACLs (`BUILTIN\Users:(RX)`, `Administrators:(F)`, `SYSTEM:(F)`), preventing standard users from modifying binaries or scripts executed by elevated scheduled tasks or admin runs.
  - Requires one UAC prompt at installation. Start Menu shortcut created in `%ProgramData%\Microsoft\Windows\Start Menu\Programs\ScriptSuite.lnk`.
  - Per-user data (`history.db`, configs, schedules, theme) remains safely in `%LOCALAPPDATA%\ScriptSuite\`.
  - Existing `\ScriptSuite\*` scheduled tasks automatically have their `Command` path migrated on installation.
- **SEC-03 Notice: User config & temp interchange scope**
  - Elevated runs read user-writable configs from `%LOCALAPPDATA%\ScriptSuite\Configs\` and exchange IPC files via `%TEMP%`. Mitigated by `Test-PathScope` and strict JSON deserialization; not architecturally isolated.

### Fixed
- **DST Drift Fix: Local StartBoundary on Task Scheduler Triggers**
  - Register triggers with local `StartBoundary` (`yyyy-MM-ddTHH:mm:ss`, no `Z` UTC suffix) for Daily, Weekly, and Hourly tasks (`14659c6`). Eliminates 1-hour wall-clock schedule drift on Daylight Saving Time transitions.
  - Note: Upgrading users can re-save schedules in the UI to update existing triggers to the local boundary format.
- **BUG-01: Scheduler Hourly Repetition**
  - Omit repetition duration for indefinite hourly tasks and validate repetition interval range 1–24 hours (`757f254`).
- **BUG-02: Retention Days Validation**
  - Block negative days in settings UI and clamp negative inputs to 0 with warning in scripts (`7d81cf0`).
- **BUG-04: Extension Leading Dot Normalization**
  - Normalize leading dot on `DeleteExts` items in settings UI and cleanup script (`f2953c4`).
- **BUG-05: Wildcard Bracket Escaping in Pattern Matching**
  - Escape wildcard bracket characters (`[` and `]`) in filename ignore matching (`ef74600`).
- **BUG-06: Path Enclosing Quote Stripping**
  - Strip enclosing double and single quotes in settings UI validators and script path scopes (`05b0801`).
- **BUG-07: Path Scope Warning Decoupling**
  - Decouple informational path scope warnings from `RunOutcome` classification so benign skips do not mark runs as Warning/Failed (`726de9a`).
- **BUG-08: Health Report Update Metric Clarification**
  - Relabel update metric to "Last Installed Update" with KB title (`bf2c896`).
- **BUG-09: RestorePoint Protection Fast-Fail**
  - Fast-fail with an informative warning when Windows System Protection is disabled (`0278f35`).

---

## [2.1.1] - 2026-10-14
- feat(cleareventlogs): add CutoffDays to only clear inactive logs (`80038a7`)
- chore: remove OBS script, clean up test files, bump version to 2.1.1 (`99d3606`)

## [2.0.0] - 2026-09-08
- UI fixes: Scheduled History rendering, collapsible Run All preview, log-routed history detail
- DownloadsCleanup Advanced Rules (Ignore, Delete, MoveTo) and destination validation
- EmptyRecycleBin MinAgeDays filtering via DateDeleted
- Light Mode (Catppuccin Mocha / Latte) runtime switch and contextual help guide

## [1.1.0] - 2026-08-30
- Task scheduling engine with S4U / Interactive split and ScheduledRuns history
- Busy detection mutex and Scheduled History UI
