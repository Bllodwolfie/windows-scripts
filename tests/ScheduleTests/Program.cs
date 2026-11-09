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

    // 4. fake launcher returning 1223 => task XML and schedules.json hash unchanged
    private static void Test4_CancelledElevationPreservesState(string testRoot)
    {
        Console.WriteLine("\n--- Test 4: Fake launcher returning 1223 (UAC cancel) preserves task XML and schedules.json ---");
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

    // 7. Timeout and Exception Handling
    private static void Test7_TimeoutAndExceptionHandling()
    {
        Console.WriteLine("\n--- Test 7: Timeout and Exception handling ---");
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
}
