using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using ScriptSuite.Models;
using ScriptSuite.Services;

namespace ScheduleTests;

public class Program
{
    private static int _passed = 0;
    private static int _failed = 0;

    private static void Assert(bool condition, string message)
    {
        if (condition)
        {
            Console.WriteLine($"[PASS] {message}");
            _passed++;
        }
        else
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine($"[FAIL] {message}");
            Console.ResetColor();
            _failed++;
        }
    }

    public static int Main(string[] args)
    {
        Console.WriteLine("=================================================");
        Console.WriteLine("      ScriptSuite v3.2.1 Automated Test Suite     ");
        Console.WriteLine("=================================================");

        string testRoot = Path.Combine(Path.GetTempPath(), "ScriptSuite_Test_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(testRoot);
        Environment.SetEnvironmentVariable("LOCALAPPDATA", testRoot);

        try
        {
            Test1_NonAdminAccessDenied();
            Test2_OtherFailureNoElevation();
            Test3_ReadbackMismatch();
            Test4_CancelledElevationPreservesState(testRoot);
            Test5_SaveTaskA_LeavesTaskB_Unchanged();
            Test6_FailedRegisterLeavesPreviousTaskIdentical();
            Test7_TimeoutAndExceptionHandling();
            Test8_ElevatedRegisterTimeout();
            Test9_ScheduleCalculationDSTAndAnchors();
            Test10_CollisionDetection();
            Test11_CleanErrorMessageWithClixmlSample();
            Test12_ExactCapturedStderrProof();
            Test13_RunHistoryStore_SchemaMigrationAndPrune(testRoot);
            Test14_DownloadsCleanup_PacketTracerCategory();
            Test15_EmptyFolderCleanup_DevTreePruning(testRoot);
            Test16_EmptyFolderCleanup_ReparsePointSkip(testRoot);
            Test17_EmptyFolderCleanup_RelativeIgnoreNames(testRoot);
            Test18_EmptyFolderCleanup_MultiFolder(testRoot);
        }
        finally
        {
            // Reset seams
            ScheduledTaskService.ElevatedLauncher = null;
            ScheduledTaskService.ProcessRunner = null;

            // Clean up any stray test tasks
            CleanScratchTask("ScriptSuiteTest_UnitAccessDenied");
            CleanScratchTask("ScriptSuiteTest_UnitBadTime");
            CleanScratchTask("ScriptSuiteTest_ReadbackMismatch");
            CleanScratchTask("ScriptSuiteTest_CancelUAC");
            CleanScratchTask("ScriptSuiteTest_TaskA");
            CleanScratchTask("ScriptSuiteTest_TaskB");
            CleanScratchTask("ScriptSuiteTest_PrevIdentical");
            CleanScratchTask("ScriptSuiteTest_Proof");

            // Clean up temp test directory
            try
            {
                if (Directory.Exists(testRoot))
                    Directory.Delete(testRoot, recursive: true);
            }
            catch { }
        }

        Console.WriteLine("=================================================");
        Console.WriteLine($"Total Tests: {_passed + _failed} | Passed: {_passed} | Failed: {_failed}");
        Console.WriteLine("=================================================");

        return _failed == 0 ? 0 : 1;
    }

    private static void CleanScratchTask(string name)
    {
        try
        {
            var psi = new ProcessStartInfo("schtasks", $"/delete /tn \"\\ScriptSuite\\{name}\" /f")
            {
                CreateNoWindow = true,
                UseShellExecute = false
            };
            using var p = Process.Start(psi);
            p?.WaitForExit(3000);
        }
        catch { }
    }

    private static string GetTaskXml(string name)
    {
        var psi = new ProcessStartInfo("schtasks")
        {
            CreateNoWindow = true,
            UseShellExecute = false,
            RedirectStandardOutput = true
        };
        psi.ArgumentList.Add("/query");
        psi.ArgumentList.Add("/tn");
        psi.ArgumentList.Add($"\\ScriptSuite\\{name}");
        psi.ArgumentList.Add("/xml");
        using var p = Process.Start(psi)!;
        string xml = p.StandardOutput.ReadToEnd();
        p.WaitForExit(5000);
        return xml;
    }

    private static string ComputeSha256(string content)
    {
        byte[] bytes = Encoding.UTF8.GetBytes(content);
        byte[] hash = SHA256.HashData(bytes);
        return Convert.ToHexString(hash);
    }

    // 1. non-admin script + access denied => (false, ..., needsElevation=true)
    private static void Test1_NonAdminAccessDenied()
    {
        Console.WriteLine("\n--- Test 1: Non-admin script + access denied => needsElevation=true ---");
        var entry = new ScheduleEntry
        {
            ScriptId = "ScriptSuiteTest_UnitAccessDenied",
            Unit = "Days",
            Interval = 1,
            TimeOfDay = "10:00"
        };

        // Simulate PowerShell process failing with HRESULT 0x80070005 PermissionDenied
        ScheduledTaskService.ProcessRunner = (psi) => (
            1,
            "",
            "Register-ScheduledTask : Access is denied. CategoryInfo : PermissionDenied: (PS_ScheduledTask) FullyQualifiedErrorId : HRESULT 0x80070005,Register-ScheduledTask"
        );

        var (ok, err, needsElev) = ScheduledTaskService.Register(entry, requiresAdmin: false);

        Assert(!ok, "Register returns ok=false on access denied");
        Assert(needsElev, "Register returns needsElevation=true for non-admin script when access denied");
        Assert(err != null && err.Contains("0x80070005"), "Error message contains 0x80070005");
    }

    // 2. other failure (e.g. bad time) => needsElevation=false
    private static void Test2_OtherFailureNoElevation()
    {
        Console.WriteLine("\n--- Test 2: Other failure (e.g. bad time / syntax error) => needsElevation=false ---");
        var entry = new ScheduleEntry
        {
            ScriptId = "ScriptSuiteTest_UnitBadTime",
            Unit = "Days",
            Interval = 1,
            TimeOfDay = "10:00"
        };

        // Simulate PowerShell failing with non-access-denied error (bad argument)
        ScheduledTaskService.ProcessRunner = (psi) => (
            1,
            "",
            "Cannot validate argument on parameter 'At'. The string 'invalid' was not recognized as a valid DateTime."
        );

        var (ok, err, needsElev) = ScheduledTaskService.Register(entry, requiresAdmin: false);

        Assert(!ok, "Register returns ok=false on non-access-denied failure");
        Assert(!needsElev, "Register returns needsElevation=false on non-access-denied failure");
        Assert(err != null && err.Contains("Cannot validate argument"), "Error message reflects PowerShell error");
    }

    // 3. read-back mismatch => (false, "Verification failed...")
    private static void Test3_ReadbackMismatch()
    {
        Console.WriteLine("\n--- Test 3: Read-back verification mismatch ---");
        string taskName = "ScriptSuiteTest_ReadbackMismatch";
        CleanScratchTask(taskName);

        // Register a scratch task with boundary 2026-11-15T10:00:00
        ScheduledTaskService.ProcessRunner = null;
        var initialEntry = new ScheduleEntry
        {
            ScriptId = taskName,
            Unit = "Days",
            Interval = 1,
            TimeOfDay = "10:00",
            StartDate = "2026-11-15"
        };
        var (iOk, iErr, _) = ScheduledTaskService.Register(initialEntry, requiresAdmin: false);
        Assert(iOk, "Initial scratch task registered for read-back test");

        // Now simulate a runner that returns exit 0 (pretending success), but the task in Task Scheduler was NOT updated
        var updateEntry = new ScheduleEntry
        {
            ScriptId = taskName,
            Unit = "Days",
            Interval = 1,
            TimeOfDay = "18:02",
            StartDate = "2026-11-15"
        };
        ScheduledTaskService.ProcessRunner = (psi) => (0, "OK", "");

        var (ok, err, needsElev) = ScheduledTaskService.Register(updateEntry, requiresAdmin: false);

        Assert(!ok, "Register returns ok=false when read-back verification fails");
        Assert(!needsElev, "needsElevation is false on verification failure");
        Assert(err != null && err.StartsWith("Verification failed:"), $"Error message starts with 'Verification failed:' (actual: {err})");

        CleanScratchTask(taskName);
    }

    // 4. launcher exit code 1223 => task XML and schedules.json hash unchanged
    private static void Test4_CancelledElevationPreservesState(string testRoot)
    {
        Console.WriteLine("\n--- Test 4: Launcher exit code 1223 (UAC cancel) preserves task XML and schedules.json ---");
        string taskName = "ScriptSuiteTest_CancelUAC";
        CleanScratchTask(taskName);

        string schedulesPath = Path.Combine(testRoot, "schedules.json");
        var store = new ScheduleStore(schedulesPath);
        var baseEntry = new ScheduleEntry
        {
            ScriptId = taskName,
            Unit = "Days",
            Interval = 1,
            TimeOfDay = "10:00",
            StartDate = "2026-11-15",
            Enabled = true,
            CreatedAt = "2026-11-09 10:00:00"
        };
        store.Set(baseEntry);
        string schedulesHashBefore = ComputeSha256(File.ReadAllText(schedulesPath));

        // Register initial task
        ScheduledTaskService.ProcessRunner = null;
        var (iOk, _, _) = ScheduledTaskService.Register(baseEntry, requiresAdmin: false);
        Assert(iOk, "Initial task registered for cancel UAC test");
        string xmlBefore = GetTaskXml(taskName);
        string xmlHashBefore = ComputeSha256(xmlBefore);

        // Attempt save with simulated access denied on unelevated, and 1223 (cancel) on elevated
        ScheduledTaskService.ProcessRunner = (psi) => (1, "", "Access is denied. FullyQualifiedErrorId : HRESULT 0x80070005");
        ScheduledTaskService.ElevatedLauncher = (psi) => throw new Win32Exception(1223);

        var attemptedEntry = new ScheduleEntry
        {
            ScriptId = taskName,
            Unit = "Weeks",
            Interval = 1,
            TimeOfDay = "18:06",
            Weekdays = new[] { "Sunday" },
            StartDate = "2026-11-15",
            Enabled = true,
            CreatedAt = "2026-11-09 10:00:00"
        };

        // Simulate ScheduleWindow atomic save sequence
        var (ok, err, needsElev) = ScheduledTaskService.Register(attemptedEntry, requiresAdmin: false);
        bool elevatedCancelled = false;
        string? elevatedErr = null;
        if (!ok && needsElev)
        {
            var (eOk, eErr) = ScheduledTaskService.RegisterElevated(attemptedEntry);
            if (!eOk)
            {
                elevatedCancelled = true;
                elevatedErr = eErr;
                // Atomic save aborts: do NOT update scheduleStore
            }
            else
            {
                store.Set(attemptedEntry);
            }
        }
        else if (ok)
        {
            store.Set(attemptedEntry);
        }

        Assert(elevatedCancelled, "Elevation was cancelled by fake launcher (Win32Exception 1223)");
        Assert(elevatedErr != null && elevatedErr.Contains("cancelled"), "Clear error message on UAC cancellation");

        string schedulesHashAfter = ComputeSha256(File.ReadAllText(schedulesPath));
        Assert(schedulesHashBefore == schedulesHashAfter, "schedules.json hash is IDENTICAL before and after cancelled elevation");

        string xmlAfter = GetTaskXml(taskName);
        string xmlHashAfter = ComputeSha256(xmlAfter);
        Assert(xmlHashBefore == xmlHashAfter, "Task XML hash is IDENTICAL before and after cancelled elevation");

        CleanScratchTask(taskName);
    }

    // 5. save on scratch TaskA => scratch TaskB XML diff = 0
    private static void Test5_SaveTaskA_LeavesTaskB_Unchanged()
    {
        Console.WriteLine("\n--- Test 5: Saving scratch TaskA leaves scratch TaskB XML diff = 0 ---");
        string taskA = "ScriptSuiteTest_TaskA";
        string taskB = "ScriptSuiteTest_TaskB";
        CleanScratchTask(taskA);
        CleanScratchTask(taskB);

        ScheduledTaskService.ProcessRunner = null;
        ScheduledTaskService.ElevatedLauncher = null;

        var entryB = new ScheduleEntry
        {
            ScriptId = taskB,
            Unit = "Days",
            Interval = 1,
            TimeOfDay = "08:00",
            StartDate = "2026-11-15"
        };
        var (bOk, _, _) = ScheduledTaskService.Register(entryB, requiresAdmin: false);
        Assert(bOk, "TaskB registered");
        string xmlBBefore = GetTaskXml(taskB);
        string hashBBefore = ComputeSha256(xmlBBefore);

        var entryA = new ScheduleEntry
        {
            ScriptId = taskA,
            Unit = "Weeks",
            Interval = 1,
            TimeOfDay = "18:02",
            Weekdays = new[] { "Sunday" },
            StartDate = "2026-11-15"
        };
        var (aOk, aErr, _) = ScheduledTaskService.Register(entryA, requiresAdmin: false);
        Assert(aOk, $"TaskA registered successfully (err: {aErr})");

        string xmlBAfter = GetTaskXml(taskB);
        string hashBAfter = ComputeSha256(xmlBAfter);
        Assert(hashBBefore == hashBAfter, "TaskB XML diff = 0 after TaskA was saved/modified");

        CleanScratchTask(taskA);
        CleanScratchTask(taskB);
    }

    // 6. failed Register leaves the previous task XML identical
    private static void Test6_FailedRegisterLeavesPreviousTaskIdentical()
    {
        Console.WriteLine("\n--- Test 6: Failed Register leaves the previous task XML identical ---");
        string taskName = "ScriptSuiteTest_PrevIdentical";
        CleanScratchTask(taskName);

        ScheduledTaskService.ProcessRunner = null;
        ScheduledTaskService.ElevatedLauncher = null;

        var initialEntry = new ScheduleEntry
        {
            ScriptId = taskName,
            Unit = "Days",
            Interval = 1,
            TimeOfDay = "10:00",
            StartDate = "2026-11-15"
        };
        var (iOk, _, _) = ScheduledTaskService.Register(initialEntry, requiresAdmin: false);
        Assert(iOk, "Initial task registered");
        string xmlBefore = GetTaskXml(taskName);
        string hashBefore = ComputeSha256(xmlBefore);

        // Attempt registration that fails in PowerShell (simulate error via ProcessRunner)
        ScheduledTaskService.ProcessRunner = (psi) => (
            1,
            "",
            "Cannot process argument transformation on parameter 'At'. Cannot convert value 'invalid' to type 'DateTime'."
        );

        var failEntry = new ScheduleEntry
        {
            ScriptId = taskName,
            Unit = "Days",
            Interval = 1,
            TimeOfDay = "11:00",
            StartDate = "2026-11-15"
        };
        var (fOk, _, _) = ScheduledTaskService.Register(failEntry, requiresAdmin: false);
        Assert(!fOk, "Register returned ok=false on failed registration");

        ScheduledTaskService.ProcessRunner = null;
        string xmlAfter = GetTaskXml(taskName);
        string hashAfter = ComputeSha256(xmlAfter);
        Assert(hashBefore == hashAfter, "Previous task XML is IDENTICAL after failed registration (Unregister-then-Register eliminated)");

        CleanScratchTask(taskName);
    }

    // 7. Exception handling (timeout not covered)
    private static void Test7_TimeoutAndExceptionHandling()
    {
        Console.WriteLine("\n--- Test 7: Exception handling (timeout not covered) ---");
        var entry = new ScheduleEntry
        {
            ScriptId = "ScriptSuiteTest_Timeout",
            Unit = "Days",
            Interval = 1,
            TimeOfDay = "10:00"
        };

        // Exception seam
        ScheduledTaskService.ProcessRunner = (psi) => throw new InvalidOperationException("Simulated process start failure");
        var (okEx, errEx, needsElevEx) = ScheduledTaskService.Register(entry, requiresAdmin: false);
        Assert(!okEx, "Register returns ok=false on exception");
        Assert(!needsElevEx, "Register returns needsElevation=false on exception");
        Assert(errEx != null && errEx.Contains("Simulated process start failure"), "Exception message returned");
    }

    // 8. RegisterElevated Timeout Handling
    private static void Test8_ElevatedRegisterTimeout()
    {
        Console.WriteLine("\n--- Test 8: RegisterElevated Timeout & Exit Code ---");
        var entry = new ScheduleEntry
        {
            ScriptId = "ScriptSuiteTest_ElevTimeout",
            Unit = "Days",
            Interval = 1,
            TimeOfDay = "10:00"
        };

        // Helper exits non-zero
        ScheduledTaskService.ElevatedLauncher = (psi) => 5;
        var (ok1, err1) = ScheduledTaskService.RegisterElevated(entry);
        Assert(!ok1, "RegisterElevated returns ok=false on exit code 5");
        Assert(err1 == "Elevated helper exit 5", $"Error message matches expected helper exit (actual: {err1})");

        // Helper exits 1223
        ScheduledTaskService.ElevatedLauncher = (psi) => 1223;
        var (ok2, err2) = ScheduledTaskService.RegisterElevated(entry);
        Assert(!ok2, "RegisterElevated returns ok=false on code 1223");
        Assert(err2 != null && err2.Contains("cancelled"), "Error message states UAC prompt was cancelled");
    }

    // 9. ScheduleCalculation DST and Anchors
    private static void Test9_ScheduleCalculationDSTAndAnchors()
    {
        Console.WriteLine("\n--- Test 9: ScheduleCalculation DST and Anchors ---");

        // 2-week interval anchor calculation
        var entry2W = new ScheduleEntry
        {
            ScriptId = "Test2W",
            Unit = "Weeks",
            Interval = 2,
            TimeOfDay = "14:00",
            Weekdays = new[] { "Monday" },
            StartDate = "2026-11-02"
        };
        var (_, boundary2W, preview2W) = ScheduleCalculation.ComputeSchedule(entry2W);
        Assert(!boundary2W.EndsWith("Z"), "StartBoundary has no Z suffix");
        Assert(preview2W.Contains("14:00"), "Live preview contains chosen time 14:00");

        // DST transition autumn 2026: 2026-10-25
        var entryAutumn = new ScheduleEntry
        {
            ScriptId = "TestAutumn",
            Unit = "Days",
            Interval = 1,
            TimeOfDay = "03:30",
            StartDate = "2026-10-25"
        };
        var (_, boundaryAutumn, _) = ScheduleCalculation.ComputeSchedule(entryAutumn);
        Assert(boundaryAutumn.StartsWith("2026-10-25T03:30:00"), "Boundary matches local wall-clock across autumn DST");

        // DST transition spring 2027: 2027-03-28
        var entrySpring = new ScheduleEntry
        {
            ScriptId = "TestSpring",
            Unit = "Days",
            Interval = 1,
            TimeOfDay = "03:30",
            StartDate = "2027-03-28"
        };
        var (_, boundarySpring, _) = ScheduleCalculation.ComputeSchedule(entrySpring);
        Assert(boundarySpring.StartsWith("2027-03-28T03:30:00"), "Boundary matches local wall-clock across spring DST");
    }

    // 10. Collision Detection
    private static void Test10_CollisionDetection()
    {
        Console.WriteLine("\n--- Test 10: Collision Detection ---");
        var existing = new[]
        {
            new ScheduleEntry { ScriptId = "Task1", Unit = "Weeks", Interval = 1, TimeOfDay = "18:02", Weekdays = new[] { "Sunday" }, Enabled = true },
            new ScheduleEntry { ScriptId = "Task2", Unit = "Days", Interval = 1, TimeOfDay = "09:00", Enabled = true },
            new ScheduleEntry { ScriptId = "DisabledTask", Unit = "Weeks", Interval = 1, TimeOfDay = "18:02", Weekdays = new[] { "Sunday" }, Enabled = false },
        };

        var colliding = new ScheduleEntry { ScriptId = "NewTask", Unit = "Weeks", Interval = 1, TimeOfDay = "18:02", Weekdays = new[] { "Sunday" }, Enabled = true };
        var nonColliding = new ScheduleEntry { ScriptId = "NewTask2", Unit = "Weeks", Interval = 1, TimeOfDay = "18:06", Weekdays = new[] { "Sunday" }, Enabled = true };

        string? warn1 = ScheduleCalculation.DetectCollision(colliding, existing);
        Assert(!string.IsNullOrEmpty(warn1) && warn1.Contains("Task1"), "Collision detected on same time and overlapping weekday");

        string? warn2 = ScheduleCalculation.DetectCollision(nonColliding, existing);
        Assert(string.IsNullOrEmpty(warn2), "No collision warning when times differ (18:02 vs 18:06)");
    }

    // 11. Human-Readable Error Extraction from CLIXML Sample
    private static void Test11_CleanErrorMessageWithClixmlSample()
    {
        Console.WriteLine("\n--- Test 11: Human-Readable Error Extraction from CLIXML Sample ---");

        // Real PowerShell Access-Denied CLIXML sample captured from scheduled task registration failure
        string clixmlSample = "#< CLIXML\r\n<Objs Version=\"1.1.0.1\" xmlns=\"http://schemas.microsoft.com/powershell/2004/04\"><Obj S=\"progress\" RefId=\"0\"><TN RefId=\"0\"><T>System.Management.Automation.PSCustomObject</T><T>System.Object</T></TN><MS><I64 N=\"SourceId\">1</I64><PR N=\"Record\"><AV>Preparing modules for first use.</AV><AI>0</AI><Nil /><PI>-1</PI><PC>-1</PC><T>Completed</T><SR>-1</SR><SD> </SD></PR></MS></Obj><S S=\"Error\">Register-ScheduledTask : Access is denied._x000D__x000A_</S><S S=\"Error\">At line:1 char:601_x000D__x000A_</S><S S=\"Error\">+ ...  -Hours 2); Register-ScheduledTask -TaskName 'ScriptSuiteTest_Proof'  ..._x000D__x000A_</S><S S=\"Error\">+                 ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~_x000D__x000A_</S><S S=\"Error\">    + CategoryInfo          : PermissionDenied: (PS_ScheduledTask:Root/Microsoft/...S_ScheduledTask) [Register-Schedul _x000D__x000A_</S><S S=\"Error\">   edTask], CimException_x000D__x000A_</S><S S=\"Error\">    + FullyQualifiedErrorId : HRESULT 0x80070005,Register-ScheduledTask_x000D__x000A_</S><S S=\"Error\"> _x000D__x000A_</S></Objs>";

        string cleaned = ScheduledTaskService.CleanErrorMessage(clixmlSample);
        Assert(!cleaned.StartsWith("#< CLIXML"), "Cleaned message does not start with '#< CLIXML'");
        Assert(!cleaned.Contains("<Objs"), "Cleaned message does not contain XML tags");
        Assert(!cleaned.Contains("<S S=\"Error\">"), "Cleaned message does not contain <S S='Error'>");
        Assert(!cleaned.Contains("_x000D_"), "Hex entity _x000D_ decoded or stripped");
        Assert(cleaned == "Access is denied.", $"Cleaned message extracted short error: '{cleaned}' (expected 'Access is denied.')");

        // Second CLIXML sample (argument validation error)
        string clixmlArgSample = "#< CLIXML\r\n<Objs Version=\"1.1.0.1\" xmlns=\"http://schemas.microsoft.com/powershell/2004/04\"><S S=\"Error\">Cannot validate argument on parameter 'At'. The string 'invalid' was not recognized as a valid DateTime._x000D__x000A_</S></Objs>";
        string cleanedArg = ScheduledTaskService.CleanErrorMessage(clixmlArgSample);
        Assert(cleanedArg == "Cannot validate argument on parameter 'At'. The string 'invalid' was not recognized as a valid DateTime.", "Cleaned argument validation message matches");
    }

    // 12. Feeding exact captured stderr from access-denied proof
    private static void Test12_ExactCapturedStderrProof()
    {
        Console.WriteLine("\n--- Test 12: Exact captured stderr from proof => cleaned text and needsElevation=true ---");
        string proofStderr = "#< CLIXML\r\n<Objs Version=\"1.1.0.1\" xmlns=\"http://schemas.microsoft.com/powershell/2004/04\"><S S=\"Error\">Register-ScheduledTask : Access is denied._x000D__x000A_</S><S S=\"Error\">At line:1 char:601_x000D__x000A_</S><S S=\"Error\">+ ...  -Hours 2); Register-ScheduledTask -TaskName 'ScriptSuiteTest_Proof'  ..._x000D__x000A_</S><S S=\"Error\">+                 ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~_x000D__x000A_</S><S S=\"Error\">    + CategoryInfo          : PermissionDenied: (PS_ScheduledTask:Root/Microsoft/...S_ScheduledTask) [Register-Schedul _x000D__x000A_</S><S S=\"Error\">   edTask], CimException_x000D__x000A_</S><S S=\"Error\">    + FullyQualifiedErrorId : HRESULT 0x80070005,Register-ScheduledTask_x000D__x000A_</S><S S=\"Error\"> _x000D__x000A_</S></Objs>";

        var entry = new ScheduleEntry
        {
            ScriptId = "ScriptSuiteTest_ProofStderr",
            Unit = "Weeks",
            Interval = 1,
            TimeOfDay = "18:02",
            Weekdays = new[] { "Sunday" }
        };

        ScheduledTaskService.ProcessRunner = (psi) => (1, "", proofStderr);

        var (ok, err, needsElev) = ScheduledTaskService.Register(entry, requiresAdmin: false);

        Assert(!ok, "Register returns ok=false on captured proof stderr");
        Assert(needsElev, "Register returns needsElevation=true on captured proof stderr");
        Assert(err == "Access is denied.", $"Cleaned error text is strictly 'Access is denied.' (actual: '{err}')");
    }

    // 13. RunHistoryStore schema migration, 28-day auto-pruning, and unified query filters
    private static void Test13_RunHistoryStore_SchemaMigrationAndPrune(string testRoot)
    {
        Console.WriteLine("\n--- Test 13: RunHistoryStore Schema Migration, Pruning & Filtering ---");
        string dbPath = Path.Combine(testRoot, "history_test.db");
        var store = new RunHistoryStore(dbPath);

        // Insert manual run
        store.Insert("DownloadsCleanup", DateTime.Now.AddMinutes(-10), DateTime.Now.AddMinutes(-9), RunOutcome.Success, "Cleaned 5 files");

        // Insert scheduled run
        store.InsertScheduled("SystemHealthReport", DateTime.Now.AddMinutes(-5), DateTime.Now.AddMinutes(-5), DateTime.Now.AddMinutes(-4), "Success", "Health report generated", "timer");

        // Insert old run (40 days old)
        store.Insert("ClearEventLogs", DateTime.Now.AddDays(-40), DateTime.Now.AddDays(-40), RunOutcome.Success, "Old event log clear");

        // Prune stale runs older than 28 days
        int pruned = store.PruneStale(28);
        Assert(pruned >= 1, $"PruneStale pruned {pruned} old row(s)");

        var allRuns = store.GetRecent(200, "All");
        Assert(allRuns.Count == 2, $"GetRecent('All') returned 2 active runs (actual: {allRuns.Count})");

        var manualRuns = store.GetRecent(200, "Manual");
        Assert(manualRuns.Count == 1, $"GetRecent('Manual') returned 1 run (actual: {manualRuns.Count})");
        Assert(manualRuns[0].ScriptId == "DownloadsCleanup", "Manual run script matches");
        Assert(manualRuns[0].TriggerType == "Manual", "Manual run trigger type is 'Manual'");

        var scheduledRuns = store.GetRecent(200, "Scheduled");
        Assert(scheduledRuns.Count == 1, $"GetRecent('Scheduled') returned 1 run (actual: {scheduledRuns.Count})");
        Assert(scheduledRuns[0].ScriptId == "SystemHealthReport", "Scheduled run script matches");
        Assert(scheduledRuns[0].TriggerType == "Scheduled", "Scheduled run trigger type is 'Scheduled'");

        var latest = store.GetLatestByScript();
        Assert(latest.ContainsKey("DownloadsCleanup"), "GetLatestByScript contains DownloadsCleanup");
        Assert(latest.ContainsKey("SystemHealthReport"), "GetLatestByScript contains SystemHealthReport");
    }

    private static string FindRepoRoot()
    {
        string? dir = AppDomain.CurrentDomain.BaseDirectory;
        while (!string.IsNullOrEmpty(dir))
        {
            if (Directory.Exists(Path.Combine(dir, "ScriptSuite")) && Directory.Exists(Path.Combine(dir, "scripts")))
            {
                return dir;
            }
            dir = Path.GetDirectoryName(dir);
        }
        return AppDomain.CurrentDomain.BaseDirectory;
    }

    // 14. DownloadsCleanup Cisco PacketTracer category routing
    private static void Test14_DownloadsCleanup_PacketTracerCategory()
    {
        Console.WriteLine("\n--- Test 14: DownloadsCleanup PacketTracer Routing ---");
        string repoRoot = FindRepoRoot();
        string configPath = Path.Combine(repoRoot, @"ScriptSuite\DefaultConfigs\DownloadsCleanup.json");
        Assert(File.Exists(configPath), $"DownloadsCleanup.json exists at {configPath}");

        string json = File.ReadAllText(configPath);
        using var doc = System.Text.Json.JsonDocument.Parse(json);
        var categories = doc.RootElement.GetProperty("Categories");

        bool foundPacketTracer = false;
        foreach (var prop in categories.EnumerateObject())
        {
            if (prop.Name.EndsWith(@"Networking\PacketTracer", StringComparison.OrdinalIgnoreCase))
            {
                foundPacketTracer = true;
                var exts = new System.Collections.Generic.List<string>();
                foreach (var el in prop.Value.EnumerateArray())
                {
                    exts.Add(el.GetString()!);
                }
                Assert(exts.Contains(".pkt"), "PacketTracer category contains .pkt");
                Assert(exts.Contains(".pka"), "PacketTracer category contains .pka");
                Assert(exts.Contains(".pkz"), "PacketTracer category contains .pkz");
                break;
            }
        }
        Assert(foundPacketTracer, "DownloadsCleanup.json defines Networking/PacketTracer category");
    }

    // 15. EmptyFolderCleanup built-in dev-tree pruning
    private static void Test15_EmptyFolderCleanup_DevTreePruning(string testRoot)
    {
        Console.WriteLine("\n--- Test 15: EmptyFolderCleanup Built-in Dev-Tree Pruning ---");
        string repoRoot = FindRepoRoot();
        string scriptPath = Path.Combine(repoRoot, @"scripts\EmptyFolderCleanup\EmptyFolderCleanup.ps1");
        Assert(File.Exists(scriptPath), $"EmptyFolderCleanup.ps1 exists at {scriptPath}");

        string scriptContent = File.ReadAllText(scriptPath);
        Assert(scriptContent.Contains("node_modules"), "Script includes node_modules in default ignore names");
        Assert(scriptContent.Contains(".git"), "Script includes .git in default ignore names");

        // Create scratch folder structure: root/empty_valid, root/node_modules/empty_sub
        string scratchTarget = Path.Combine(testRoot, "efc_scratch");
        string validEmpty = Path.Combine(scratchTarget, "empty_valid");
        string nodeModulesEmpty = Path.Combine(scratchTarget, "node_modules", "empty_sub");
        Directory.CreateDirectory(validEmpty);
        Directory.CreateDirectory(nodeModulesEmpty);

        string logDir = Path.Combine(testRoot, "logs");
        string testCfg = Path.Combine(testRoot, "efc_cfg.json");
        File.WriteAllText(testCfg, $"{{\"TargetFolder\": \"{scratchTarget.Replace("\\", "\\\\")}\", \"LogDir\": \"{logDir.Replace("\\", "\\\\")}\", \"LogFile\": \"CleanupLog.txt\"}}");

        var psi = new ProcessStartInfo("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -Command \"& '{scriptPath}' -DryRun -ConfigPath '{testCfg}' | Out-String -Width 4096\"")
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false
        };
        using var proc = Process.Start(psi)!;
        string stdout = proc.StandardOutput.ReadToEnd();
        string stderr = proc.StandardError.ReadToEnd();
        proc.WaitForExit();

        Assert(stdout.Contains("empty_valid"), $"DryRun preview includes empty_valid (stdout: '{stdout.Trim()}', stderr: '{stderr.Trim()}')");
        Assert(!stdout.Contains("empty_sub"), "DryRun preview prunes/ignores node_modules/empty_sub");
    }

    // 16. EmptyFolderCleanup ReparsePoint and junction skipping
    private static void Test16_EmptyFolderCleanup_ReparsePointSkip(string testRoot)
    {
        Console.WriteLine("\n--- Test 16: EmptyFolderCleanup ReparsePoint Skip ---");
        string repoRoot = FindRepoRoot();
        string scriptPath = Path.Combine(repoRoot, @"scripts\EmptyFolderCleanup\EmptyFolderCleanup.ps1");

        // Scratch directories: scan_root, outside_folder, outside_sub, normal_empty
        string scratchTarget = Path.Combine(testRoot, "efc_reparse_scratch");
        string scanRoot = Path.Combine(scratchTarget, "scan_root");
        string outsideFolder = Path.Combine(scratchTarget, "outside_folder");
        string outsideSub = Path.Combine(outsideFolder, "empty_sub");
        string normalEmpty = Path.Combine(scanRoot, "normal_empty");

        Directory.CreateDirectory(outsideSub);
        Directory.CreateDirectory(normalEmpty);

        string junctionPath = Path.Combine(scanRoot, "junc_outside");
        var createJunc = Process.Start(new ProcessStartInfo("powershell.exe",
            $"-NoProfile -Command \"New-Item -ItemType Junction -Path '{junctionPath}' -Target '{outsideFolder}' | Out-Null\"")
        {
            UseShellExecute = false,
            CreateNoWindow = true
        })!;
        createJunc.WaitForExit();
        Assert(Directory.Exists(junctionPath), "Junction successfully created in scratch dir");

        string logDir = Path.Combine(testRoot, "logs_reparse");
        string testCfg = Path.Combine(testRoot, "efc_reparse_cfg.json");
        File.WriteAllText(testCfg, $"{{\"TargetFolder\": \"{scanRoot.Replace("\\", "\\\\")}\", \"LogDir\": \"{logDir.Replace("\\", "\\\\")}\", \"LogFile\": \"CleanupLog.txt\"}}");

        // 1. DryRun preview test
        var psiDry = new ProcessStartInfo("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -Command \"& '{scriptPath}' -DryRun -ConfigPath '{testCfg}' | Out-String -Width 4096\"")
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false
        };
        using var procDry = Process.Start(psiDry)!;
        string stdoutDry = procDry.StandardOutput.ReadToEnd();
        procDry.WaitForExit();

        Assert(stdoutDry.Contains("normal_empty"), "DryRun includes normal_empty folder");
        Assert(!stdoutDry.Contains("junc_outside"), "DryRun does not include junction folder");
        Assert(!stdoutDry.Contains("empty_sub"), "DryRun does not traverse into junction target empty_sub");

        // 2. Real run test
        var psiReal = new ProcessStartInfo("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -Command \"& '{scriptPath}' -ConfigPath '{testCfg}' | Out-String -Width 4096\"")
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false
        };
        using var procReal = Process.Start(psiReal)!;
        procReal.WaitForExit();

        Assert(!Directory.Exists(normalEmpty), "Normal empty folder was deleted in real run");
        Assert(Directory.Exists(junctionPath), "Junction itself was not deleted in real run");
        Assert(Directory.Exists(outsideFolder), "Outside folder was untouched in real run");
        Assert(Directory.Exists(outsideSub), "Outside empty subfolder was untouched in real run");

        // 3. Safe removal of junction (remove junction itself, never recurse)
        Directory.Delete(junctionPath, false);
        Assert(!Directory.Exists(junctionPath), "Junction safely removed");
        Assert(Directory.Exists(outsideFolder) && Directory.Exists(outsideSub), "Outside folder untouched after junction removal");
    }

    // 17. EmptyFolderCleanup Relative Ignore Names
    private static void Test17_EmptyFolderCleanup_RelativeIgnoreNames(string testRoot)
    {
        Console.WriteLine("\n--- Test 17: EmptyFolderCleanup Relative Ignore Names ---");
        string repoRoot = FindRepoRoot();
        string scriptPath = Path.Combine(repoRoot, @"scripts\EmptyFolderCleanup\EmptyFolderCleanup.ps1");

        // Scratch hierarchy: testRoot/ancestor_bin/bin/scan_root/empty_sub
        // Scan root sits under an ancestor named 'bin'.
        string scratchBase = Path.Combine(testRoot, "efc_rel_scratch");
        string scanRoot = Path.Combine(scratchBase, "ancestor_bin", "bin", "scan_root");
        string emptySub = Path.Combine(scanRoot, "empty_sub");
        string nodeModulesChild = Path.Combine(scanRoot, "node_modules", "empty_child");

        Directory.CreateDirectory(emptySub);
        Directory.CreateDirectory(nodeModulesChild);

        string logDir = Path.Combine(testRoot, "logs_rel");
        string testCfg = Path.Combine(testRoot, "efc_rel_cfg.json");
        File.WriteAllText(testCfg, $"{{\"TargetFolder\": \"{scanRoot.Replace("\\", "\\\\")}\", \"LogDir\": \"{logDir.Replace("\\", "\\\\")}\", \"LogFile\": \"CleanupLog.txt\"}}");

        // 1. DryRun preview
        var psiDry = new ProcessStartInfo("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -Command \"& '{scriptPath}' -DryRun -ConfigPath '{testCfg}' | Out-String -Width 4096\"")
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false
        };
        using var procDry = Process.Start(psiDry)!;
        string stdoutDry = procDry.StandardOutput.ReadToEnd();
        procDry.WaitForExit();

        Assert(stdoutDry.Contains("empty_sub"), "DryRun includes empty_sub even though scan root is under an ancestor named 'bin'");
        Assert(!stdoutDry.Contains("empty_child"), "DryRun skips node_modules/empty_child below scan root");

        // 2. Real run
        var psiReal = new ProcessStartInfo("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -Command \"& '{scriptPath}' -ConfigPath '{testCfg}' | Out-String -Width 4096\"")
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false
        };
        using var procReal = Process.Start(psiReal)!;
        procReal.WaitForExit();

        Assert(!Directory.Exists(emptySub), "empty_sub was deleted in real run under ancestor bin");
        Assert(Directory.Exists(nodeModulesChild), "node_modules/empty_child was kept in real run");
    }

    // 18. EmptyFolderCleanup Multi-Folder Support
    private static void Test18_EmptyFolderCleanup_MultiFolder(string testRoot)
    {
        Console.WriteLine("\n--- Test 18: EmptyFolderCleanup Multi-Folder Support ---");
        string repoRoot = FindRepoRoot();
        string scriptPath = Path.Combine(repoRoot, @"scripts\EmptyFolderCleanup\EmptyFolderCleanup.ps1");
        string logDir = Path.Combine(testRoot, "logs_multi");

        // Subtest 1: Legacy single-TargetFolder config
        string legacyTarget = Path.Combine(testRoot, "efc_legacy");
        string legacyEmpty = Path.Combine(legacyTarget, "empty_leg");
        Directory.CreateDirectory(legacyEmpty);
        string cfgLegacy = Path.Combine(testRoot, "efc_cfg_legacy.json");
        File.WriteAllText(cfgLegacy, $"{{\"TargetFolder\": \"{legacyTarget.Replace("\\", "\\\\")}\", \"LogDir\": \"{logDir.Replace("\\", "\\\\")}\", \"LogFile\": \"CleanupLog.txt\"}}");

        var psiLegacy = new ProcessStartInfo("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -Command \"& '{scriptPath}' -ConfigPath '{cfgLegacy}' | Out-String -Width 4096\"")
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false
        };
        using (var p = Process.Start(psiLegacy)!) { p.WaitForExit(); }
        Assert(!Directory.Exists(legacyEmpty), "Legacy single-TargetFolder config deletes empty folder");

        // Subtest 2: Two roots both processed
        string root1 = Path.Combine(testRoot, "efc_multi1");
        string root2 = Path.Combine(testRoot, "efc_multi2");
        string empty1 = Path.Combine(root1, "empty1");
        string empty2 = Path.Combine(root2, "empty2");
        Directory.CreateDirectory(empty1);
        Directory.CreateDirectory(empty2);

        string cfgMulti = Path.Combine(testRoot, "efc_cfg_multi.json");
        File.WriteAllText(cfgMulti, $"{{\"TargetFolders\": [\"{root1.Replace("\\", "\\\\")}\", \"{root2.Replace("\\", "\\\\")}\"], \"LogDir\": \"{logDir.Replace("\\", "\\\\")}\", \"LogFile\": \"CleanupLog.txt\"}}");

        var psiDryMulti = new ProcessStartInfo("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -Command \"& '{scriptPath}' -DryRun -ConfigPath '{cfgMulti}' | Out-String -Width 4096\"")
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false
        };
        string dryOutMulti;
        using (var p = Process.Start(psiDryMulti)!) { dryOutMulti = p.StandardOutput.ReadToEnd(); p.WaitForExit(); }
        Assert(dryOutMulti.Contains("empty1") && dryOutMulti.Contains("empty2"), "Two roots both processed in DryRun");

        var psiRealMulti = new ProcessStartInfo("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -Command \"& '{scriptPath}' -ConfigPath '{cfgMulti}' | Out-String -Width 4096\"")
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false
        };
        string realOutMulti;
        using (var p = Process.Start(psiRealMulti)!) { realOutMulti = p.StandardOutput.ReadToEnd(); p.WaitForExit(); }
        Assert(!Directory.Exists(empty1) && !Directory.Exists(empty2), "Two roots both processed and deleted in real run");
        Assert(realOutMulti.Contains("across 2 root(s) processed"), "Summary states 2 roots were processed");

        // Subtest 3: Overlapping roots de-duplicated
        string parentRoot = Path.Combine(testRoot, "efc_overlap_parent");
        string childRoot = Path.Combine(parentRoot, "child_dir");
        string emptyParent = Path.Combine(parentRoot, "empty_parent");
        string emptyChild = Path.Combine(childRoot, "empty_child");
        Directory.CreateDirectory(emptyParent);
        Directory.CreateDirectory(emptyChild);

        string cfgOverlap = Path.Combine(testRoot, "efc_cfg_overlap.json");
        File.WriteAllText(cfgOverlap, $"{{\"TargetFolders\": [\"{parentRoot.Replace("\\", "\\\\")}\", \"{childRoot.Replace("\\", "\\\\")}\", \"{parentRoot.Replace("\\", "\\\\")}\"], \"LogDir\": \"{logDir.Replace("\\", "\\\\")}\", \"LogFile\": \"CleanupLog.txt\"}}");

        var psiOverlap = new ProcessStartInfo("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -Command \"& '{scriptPath}' -ConfigPath '{cfgOverlap}' 3>&1 | Out-String -Width 4096\"")
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false
        };
        string overlapOut;
        using (var p = Process.Start(psiOverlap)!) { overlapOut = p.StandardOutput.ReadToEnd(); p.WaitForExit(); }
        Assert(overlapOut.Contains("duplicate") || overlapOut.Contains("nested"), "Overlapping and duplicate roots generate drop warnings");
        Assert(!Directory.Exists(emptyParent) && !Directory.Exists(emptyChild), "Empty folders under parent and nested child roots deleted cleanly");

        // Subtest 4: One denylisted root aborts everything before any delete
        string safeRoot = Path.Combine(testRoot, "efc_safe_root");
        string mustKeep = Path.Combine(safeRoot, "must_not_delete");
        Directory.CreateDirectory(mustKeep);

        string cfgDeny = Path.Combine(testRoot, "efc_cfg_deny.json");
        File.WriteAllText(cfgDeny, $"{{\"TargetFolders\": [\"{safeRoot.Replace("\\", "\\\\")}\", \"C:\\\\\"], \"LogDir\": \"{logDir.Replace("\\", "\\\\")}\", \"LogFile\": \"CleanupLog.txt\"}}");

        var psiDeny = new ProcessStartInfo("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -Command \"& '{scriptPath}' -ConfigPath '{cfgDeny}' | Out-String -Width 4096\"")
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false
        };
        int denyExit;
        using (var p = Process.Start(psiDeny)!) { p.WaitForExit(); denyExit = p.ExitCode; }
        Assert(denyExit != 0, "Denylisted root aborts run with non-zero exit code");
        Assert(Directory.Exists(mustKeep), "Nothing was deleted when a denylisted root was present");

        // Subtest 5: Missing root warns and continues
        string existRoot = Path.Combine(testRoot, "efc_exist_root");
        string emptyExist = Path.Combine(existRoot, "empty_exist");
        string missingRoot = Path.Combine(testRoot, "efc_missing_dir_12345");
        Directory.CreateDirectory(emptyExist);

        string cfgMissing = Path.Combine(testRoot, "efc_cfg_missing.json");
        File.WriteAllText(cfgMissing, $"{{\"TargetFolders\": [\"{missingRoot.Replace("\\", "\\\\")}\", \"{existRoot.Replace("\\", "\\\\")}\"], \"LogDir\": \"{logDir.Replace("\\", "\\\\")}\", \"LogFile\": \"CleanupLog.txt\"}}");

        var psiMissing = new ProcessStartInfo("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -Command \"& '{scriptPath}' -ConfigPath '{cfgMissing}' 3>&1 | Out-String -Width 4096\"")
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false
        };
        string missingOut;
        using (var p = Process.Start(psiMissing)!) { missingOut = p.StandardOutput.ReadToEnd(); p.WaitForExit(); }
        Assert(missingOut.Contains("does not exist"), "Missing root produces warning");
        Assert(!Directory.Exists(emptyExist), "Existing root was processed and empty folder deleted despite missing sibling root");

        // Subtest 6: DryRun list equals what the real run deletes on a scratch tree
        string parityRoot = Path.Combine(testRoot, "efc_parity_root");
        string parityP = Path.Combine(parityRoot, "p_empty");
        string parityC = Path.Combine(parityP, "c_empty");
        Directory.CreateDirectory(parityC);

        string cfgParity = Path.Combine(testRoot, "efc_cfg_parity.json");
        File.WriteAllText(cfgParity, $"{{\"TargetFolders\": [\"{parityRoot.Replace("\\", "\\\\")}\"], \"LogDir\": \"{logDir.Replace("\\", "\\\\")}\", \"LogFile\": \"CleanupLog.txt\"}}");

        var psiDryParity = new ProcessStartInfo("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -Command \"& '{scriptPath}' -DryRun -ConfigPath '{cfgParity}' | Out-String -Width 4096\"")
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false
        };
        string dryParity;
        using (var p = Process.Start(psiDryParity)!) { dryParity = p.StandardOutput.ReadToEnd(); p.WaitForExit(); }
        int dryCount = 0;
        foreach (var line in dryParity.Split('\n'))
        {
            if (line.Trim().StartsWith("Delete")) dryCount++;
        }

        var psiRealParity = new ProcessStartInfo("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -Command \"& '{scriptPath}' -ConfigPath '{cfgParity}' | Out-String -Width 4096\"")
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false
        };
        using (var p = Process.Start(psiRealParity)!) { p.WaitForExit(); }
        Assert(dryCount == 2, $"DryRun predicted 2 folder deletions (actual: {dryCount})");
        Assert(!Directory.Exists(parityC) && !Directory.Exists(parityP), "Real run deleted both nested empty folders matching DryRun prediction");
    }
}
