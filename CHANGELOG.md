# Changelog

All notable changes to ScriptSuite are documented in this file.

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
