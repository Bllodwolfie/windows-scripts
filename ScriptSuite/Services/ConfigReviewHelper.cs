using System.IO;
using System.Text.Json.Nodes;

namespace ScriptSuite.Services;

/// <summary>Helper to extract human-readable action summaries and configuration
/// details for the SEC-04 untrusted config review dialog.</summary>
public static class ConfigReviewHelper
{
    public static (string ActionSummary, List<string> Details) GetReviewInfo(string scriptId, string configPath)
    {
        var details = new List<string>();
        if (!File.Exists(configPath))
        {
            return ("Run with default settings (no custom configuration file found).", details);
        }

        JsonObject? root = null;
        try
        {
            root = JsonNode.Parse(File.ReadAllText(configPath)) as JsonObject;
        }
        catch { }

        if (root == null)
        {
            return ("Configuration file is empty or malformed; script will use defaults.", details);
        }

        string actionSummary;
        switch (scriptId)
        {
            case "DownloadsCleanup":
            {
                string source = root["SourceDirectory"]?.ToString() ?? "%USERPROFILE%\\Downloads";
                string cutoff = root["CutoffDays"]?.ToString() ?? "30";
                var exts = root["DeleteExts"] is JsonArray arr
                    ? string.Join(", ", arr.Select(x => x?.ToString() ?? "").Where(s => !string.IsNullOrEmpty(s)))
                    : ".exe, .msi, .zip";
                actionSummary = $"Will delete files matching [{exts}] older than {cutoff} days under '{source}', and organize other files into category folders.";
                break;
            }
            case "EmptyFolderCleanup":
            {
                string target = root["TargetFolder"]?.ToString() ?? "%USERPROFILE%";
                actionSummary = $"Will delete empty folders under '{target}'.";
                break;
            }
            case "EmptyRecycleBin":
            {
                string age = root["MinAgeDays"]?.ToString() ?? "0";
                actionSummary = $"Will permanently delete files in the Recycle Bin older than {age} days.";
                break;
            }
            case "ScreenshotsCleanup":
            {
                string source = root["SourceDirectory"]?.ToString() ?? "%USERPROFILE%\\Pictures\\Screenshots";
                string cutoff = root["CutoffDays"]?.ToString() ?? "30";
                actionSummary = $"Will clean screenshots older than {cutoff} days under '{source}'.";
                break;
            }
            case "TempCleanup":
            {
                string target = root["TargetFolder"]?.ToString() ?? "%TEMP%";
                string cutoff = root["CutoffDays"]?.ToString() ?? "7";
                actionSummary = $"Will delete temporary files older than {cutoff} days under '{target}'.";
                break;
            }
            case "ClearEventLogs":
            {
                string backup = root["BackupDir"]?.ToString() ?? "%USERPROFILE%\\Documents\\Script_Logs\\EventLogBackups";
                actionSummary = $"Will back up event logs to '{backup}' and clear non-empty Windows event logs.";
                break;
            }
            case "RestorePoint":
            {
                string desc = root["Description"]?.ToString() ?? "Monthly Cleanup";
                actionSummary = $"Will create a System Restore point named '{desc}'.";
                break;
            }
            case "SoftwareInventory":
            {
                string outPath = root["OutputFile"]?.ToString() ?? "%USERPROFILE%\\Documents\\Script_Logs\\Software_Inventory.txt";
                actionSummary = $"Will scan installed software and write inventory to '{outPath}'.";
                break;
            }
            case "SystemHealthReport":
            {
                string outDir = root["OutputDir"]?.ToString() ?? "%USERPROFILE%\\Desktop";
                actionSummary = $"Will generate an HTML system health report in '{outDir}'.";
                break;
            }
            default:
                actionSummary = $"Will execute {scriptId} using configured paths and options.";
                break;
        }

        foreach (var kvp in root)
        {
            if (kvp.Value is JsonArray ja)
            {
                var items = ja.Select(x => x?.ToString() ?? "").Where(s => !string.IsNullOrEmpty(s));
                details.Add($"{kvp.Key}: [{string.Join(", ", items)}]");
            }
            else if (kvp.Value is JsonObject jo)
            {
                details.Add($"{kvp.Key}:");
                foreach (var inner in jo)
                {
                    details.Add($"  • {inner.Key} => {inner.Value}");
                }
            }
            else
            {
                details.Add($"{kvp.Key}: {kvp.Value}");
            }
        }

        return (actionSummary, details);
    }
}
