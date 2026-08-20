using System.IO;
using System.Text.Json;

namespace ScriptSuite.Services;

/// <summary>First-run wizard marker (Milestone 7). The spec's original trigger
/// ("no config exists yet") can never fire because configs are seeded on every
/// launch, so the wizard's completion is tracked by a dedicated flag file that
/// is written only when the user finishes or explicitly skips the wizard.
/// Closing the wizard before that point leaves the flag absent, so it
/// reappears on the next launch.
///
/// ACCEPTED TRADE-OFF: this flag tracks COMPLETION only. The wizard's steps
/// share the auto-saving SettingsForm, so edits write live config values the
/// moment they're made; closing the wizard early does not roll them back.
/// Absent flag = "wizard not finished", not "no config changes were made".</summary>
public static class WizardStateStore
{
    public static string WizardStatePath => AppPaths.WizardStatePath;

    public static bool IsCompleted()
    {
        if (!File.Exists(WizardStatePath))
            return false;
        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(WizardStatePath));
            return doc.RootElement.TryGetProperty("wizardCompleted", out var v)
                && v.ValueKind == JsonValueKind.True;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    public static void MarkCompleted()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(WizardStatePath)!);
        File.WriteAllText(WizardStatePath, "{ \"wizardCompleted\": true }");
    }
}