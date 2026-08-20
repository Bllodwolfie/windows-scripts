# M11 — Phase 1 Integration Pass: findings report

Date: 2026-08-20. Scope: full integration pass over the ScriptSuite app
(build of the milestones M6–M10) plus final clean-state restore. This report
records what was actually found — including the two real bugs the pass surfaced
and the honest evidence-provenance notes — not a sanitized "all pass" summary.

Reference commit: `643013c` ("Add ScriptSuite: WPF dashboard over the
windows-scripts PowerShell suite") — the app's initial commit, which includes
the Escape-key fix below. Harnesses and evidence live under
`%TEMP%\opencode\` (`m11a-*`, `m11b-*`, `m11c-*`, `m11d-*`, `m11h-*`,
`m11-shots\`, `m11-postA-state\`, `m6*`, `m8-run*.log`, `m9-run*.log`).

---

## Part A — clean-slate first-run wizard

Harness `m11a-verify.ps1`: delete `%LocalAppData%\ScriptSuite`, launch, drive
the 8-step wizard. **25 assertions (A1–A25)** — note the earlier count of
"A1–A26" was wrong; the harness has 25 checks. Verified: wizard appears when
the marker is absent; step order begins with Temp File Cleanup; manual path
entry shows the inline "Folder does not exist yet" warning; `.tmp` added to the
DownloadsCleanup stringList; steps 3–5/7 advance via "Use recommended
defaults"; step 8 ends on Finish; `wizard.json` marker is written; each manual
value lands in the live config (`TempCleanup.TargetFolder=scratch`,
`CutoffDays=3`, `DownloadsCleanup.DeleteExts` contains `.tmp`, `CutoffDays=4`,
`RestorePoint.Description='M11 Wizard Test'`,
`SystemHealthReport.OutputFile='M11_Health.html'`); the dashboard shows all 9
Run buttons and the Cleanup/System/Reports headers.

Evidence: screenshots `m11-shots\a2-wizard-step1.png`,
`a2-wizard-path-warning.png`, `a2-wizard-step8.png`,
`a2-dashboard-after-wizard.png`; trace `m11a-trace.txt`.

## Part B — cross-milestone interaction checks

Harness `m11b-verify.ps1`; first-run output captured in `m11b-result.txt`.

### Bug found #1 — the em-dash harness bug
`m11b-result.txt` documents the first full run, which FAILED on B2:
`B2 Run All preview opened` and `B2 Run All preview has Confirm button` both
failed. Root cause: the harness searched for a window title containing
`Run All - Preview` (ASCII hyphen), but the real window title uses an em dash
(U+2014): `Run All — Preview`. `FindWin` now normalizes `U+2014` to `-` before
matching. This was a harness defect, not an app defect — the app's window
title was correct. After the fix, B0/B1/B3-Warning/B2/B3-Failed/B4/B5 pass.

### The four outcome rows
The saved dump in `m11b-result.txt` contains the one-session four-outcome pass
(four consecutive SQLite rows, 48 s apart):

| Id | Script | Outcome | Started | Summary |
|----|--------|---------|---------|---------|
| 1  | TempCleanup | Success | 14:52:07 | `Temp cleanup: 2 deleted, 0 skipped (locked or in use).` |
| 2  | TempCleanup | Warning | 14:52:09 | `Temp cleanup: 1 deleted, 1 skipped (locked or in use).` |
| 3  | SystemHealthReport | Failed | 14:52:34 | `ERROR: …Could not find a part of the path …` |
| 4  | DownloadsCleanup | Success | 14:52:55 | `DownloadsCleanup: 1 deleted, 0 skipped (locked or in use).` |

The formal harness re-covered the first three as Ids 11–14 (B1=11 Success,
B3-W=12 Warning, B3-F=13 Failed, B5=14 Success). **Cancelled could not share
that session**: it requires a human clicking "No" on consent.exe. It was
verified in the dedicated follow-up session as **Id 36, ClearEventLogs /
Cancelled, summary `Cancelled: the UAC prompt was declined (error 1223).`**
(verify script `m11c-cancel-verify.ps1`; screenshot `b3-cancel-declined.png`).
So all four outcomes are real DB rows with real timestamps, but three in one
session + Cancelled in a separate human-declined session.

### Visual proof of the four chips side by side
A targeted run (`m11h-four-history.ps1`) re-populated all four outcomes fresh
in one session (Success, Warning, Failed, then Cancelled via a real UAC
decline), opened the History window, and captured
`m11-shots\history-four-outcomes.png`. The visible rows (most recent first):

1. Clear Event Logs — `Cancelled: the UAC prompt was declined (error 1223).` — **Cancelled**
2. System Health Report — `ERROR: …Could not find a part of the path …` — **Failed**
3. Temp File Cleanup — `Temp cleanup: 1 deleted, 1 skipped (locked or in use).` — **Warning**
4. Temp File Cleanup — `Temp cleanup: 2 deleted, 0 skipped (locked or in use).` — **Success**

Count text read `4 run(s) recorded`; every chip (green/yellow/pink/blue) was
present. State was restored to clean afterwards.

### B3-Cancelled method
To make UAC actually prompt, the app must run at Medium integrity. Launching
from the elevated harness shell inherited High integrity, so the first targeted
attempt elevated silently and ClearEventLogs ran for real — see Incident 1.

## Part C — keyboard-only navigation + screen-reader name audit

Harness `m11d-keyboard.ps1` (C0–C6). Tab traversal: 46 distinct stops across
44 focusables, focus cycles back to the first control, nothing sticks. Enter
opens run/settings windows, Tab alone reaches Confirm/"Confirm and run all",
keyboard-typed values persist, Alt+F4 closes. Every keyboard-focusable
interactive control has an accessible name.

Control enumeration (fresh run, `m11g-a11y-enumerate.ps1`):

| Window | Named interactive controls | Unnamed focusable | Unnamed non-focusable |
|--------|---------------------------|-------------------|------------------------|
| Dashboard | 39 (29 buttons, 10 checkboxes) | 0 | 4 (WPF ScrollBar internals) |
| Settings (TempCleanup) | 6 (`Browse.`, `Decrease`, `Increase`, `Undo last change`, `Delete files older than`, `Folder to clean`) | 0 | 0 |
| Run window | 7 (`Close`, `Confirm`, 5 file checkboxes) | 0 | 0 |
| Run All preview | 1 (`Confirm and run all`) | 0 | 4 (ScrollBar internals) |

The only unnamed controls are WPF ScrollBar internal line/page buttons —
standard WPF, not keyboard-reachable, not a defect. No accessible names were
found broken. `Undo last change` reports `IsKeyboardFocusable=False` while
disabled (nothing to undo); after a real edit it becomes enabled and focusable
(verified, then reverted).

### Bug found #2 — Escape was not bound on modal windows (the fix in this commit)
C6 asserted standard dialog behavior: pressing Escape should close a modal.
The first run **failed** — Escape did nothing on Settings, the Run All preview,
or the Resume prompt (Alt+F4 worked; screen-reader users rely on Escape). This
was a genuine keyboard-accessibility gap, not a crash or data-loss bug.

Fix (user-approved, in the app): `OnKeyDown` overrides added to five windows —
`SettingsWindow` (Escape→Close), `ResumePromptWindow` (Escape→Close = discard),
`FirstRunWizardWindow` (Escape→Close; marker stays absent so the wizard
reappears next launch), `RunAllPreviewWindow`, and `ScriptRunWindow`.

**The mid-run guard.** Both execution windows set a `_running` flag the moment
execution starts (`RunAllPreviewWindow.ConfirmButton_Click`;
`ScriptRunWindow.RunAsync`) and their `OnKeyDown` only honors Escape when
`!_running`. Result: Escape can never abort or discard a run in progress (the
Close button is disabled during a run for the same reason); once the run
reaches a terminal state it closes normally. Verified by
`m11c-esc-probe.ps1`: Escape mid-run leaves the run window open; Escape after
completion closes it; Escape closes the Run All preview pre-run.

## Part D — regression re-verification of M6–M10

- m6/m6b/m6c/m6d (schema-driven settings form, stringList/undo/auto-save):
  harnesses pass after harness-only baseline fixes (DownloadsCleanup SourceDir
  baseline; "Saved" check changed to "absent or offscreen" for collapsed
  elements; m6c pending-check changed to a direct non-polling `FindFirst`).
- m7 (wizard recommended defaults/seeding): pass.
- m8 (run window, elevated runs, live streaming): saved output
  `m8-run12.log` (A1–E6 PASS; history Ids 47–54).
- m9 (crash recovery resume/discard): saved output `m9-run5.log` (A1–C8 PASS,
  genuine mid-run kills 112/1400 and 495/600 remaining). After the intentional
  M10 change — discarding a journal now records a Cancelled history row — m9's
  C7 was updated from "discard added nothing" to assert that Cancelled row and
  re-passed.
- m10 (every run lands in history, incl. Run All legs and Cancelled): pass.

## Incident 1 — silent elevation during the first targeted four-outcome run

The first attempt at the History screenshot run launched the app with plain
`Start-Process`, which **inherited the harness shell's High integrity
(S-1-16-12288)**. ClearEventLogs then elevated silently (no UAC prompt), ran
for real, cleared 62 event logs (with backups written to
`%USERPROFILE%\Documents\Script_Logs\EventLogBackups`), and recorded a Warning
chip — so the screenshot showed no Cancelled row. Relaunching via
`explorer.exe` (hand-off to the Medium desktop shell) restored
S-1-16-8192 and the real prompt appeared; the user declined and Cancelled was
recorded. **Remaining side effect: the 62-log event backlog backups from the
aborted run are still on disk and should be deleted when no longer needed.**

## Evidence-provenance notes (honest limits)

- **Part A** has no saved PASS result file; its outcome is attested by the
  harness source (A1–A25), the screenshots, and `m11a-trace.txt`. The
  `m11-postA-state` snapshot is **not** pure post-A state — the last m11b run
  re-snapshotted over it (it holds later values, e.g. `CutoffDays=30`), so it
  must not be cited as Part A evidence.
- **Part B** `m11b-result.txt` is the *failing* first run (the em-dash bug);
  the corrected ALL-PASS re-runs were not saved to a file. Ids 1–4 and 5–14
  come from the saved dump; Id 36 (Cancelled) and the final re-runs are
  in-session records — `history.db` was wiped by the final restore.
- **Part C** `m11d-keyboard.ps1` final ALL-PASS output is in-session; the
  a11y enumeration and Escape-guard probe outputs were re-generated and saved.
- **Part D** m8/m9 have saved log files; m6/m6b/m6c/m6d and the m9 C7 update
  re-runs are in-session.

## Final state

Restored and verified (`m11f-restore.ps1`, ALL PASS): `%LocalAppData%\ScriptSuite`
recreated via wizard Skip; `wizard.json` present; no `dashboard.json`; no
journal; run history empty; configs at seeded defaults (TempCleanup `%TEMP%`/7,
DownloadsCleanup `DeleteExts` without the wizard-added `.tmp`); test artifact
`%USERPROFILE%\Pictures\Misc\pic.png` removed. The History screenshot from the
targeted run remains at `%TEMP%\opencode\m11-shots\history-four-outcomes.png`.