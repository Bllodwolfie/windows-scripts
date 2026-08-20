using System.IO;
using System.Text.Json;

namespace ScriptSuite.Services;

/// <summary>
/// Crash/interrupted-run recovery (Milestone 9). Before a real item-based run
/// starts, ScriptRunWindow writes the confirmed target list (IncludeOnly) to
/// %LocalAppData%\ScriptSuite\journal.json. If that file still exists on the
/// next launch, the app was killed before the run completed normally: the
/// startup flow offers to resume, and the resume preview re-runs the script's
/// dry-run and shows only the items that are still outstanding — the
/// interrupted run's already-processed items no longer appear in a fresh
/// dry-run (deleted files are gone, cleared logs dropped to 0 records), so the
/// journal never double-processes anything.
///
/// The journal is deleted the moment a run finishes (any outcome) or the user
/// discards the resume offer, so a completed run never resurrects a prompt.
/// </summary>
public sealed class RunJournal
{
    public const string FileName = "journal.json";

    public string ScriptId { get; set; } = "";
    public string ConfigPath { get; set; } = "";
    public List<string> IncludeOnly { get; set; } = new();
    public DateTime StartedAt { get; set; }

    public static string Path => System.IO.Path.Combine(AppPaths.AppDataRoot, FileName);

    public static RunJournal? Load()
    {
        try
        {
            if (!File.Exists(Path)) return null;
            return JsonSerializer.Deserialize<RunJournal>(File.ReadAllText(Path));
        }
        catch (JsonException) { return null; }
        catch (IOException) { return null; }
    }

    public void Write()
    {
        Directory.CreateDirectory(AppPaths.AppDataRoot);
        File.WriteAllText(Path, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
    }

    public static void Delete()
    {
        try { if (File.Exists(Path)) File.Delete(Path); } catch (IOException) { }
    }
}