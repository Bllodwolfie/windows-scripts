using System.IO;

namespace ScriptSuite.Services;

/// <summary>Resolves the app's on-disk locations. Everything user-visible
/// lives under %LocalAppData%\ScriptSuite; shipped assets (manifests, default
/// configs, scripts) live next to the exe.</summary>
public static class AppPaths
{
    public static string AppDataRoot => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ScriptSuite");

    public static string ConfigsDir => Path.Combine(AppDataRoot, "Configs");

    public static string DashboardStatePath => Path.Combine(AppDataRoot, "dashboard.json");

    /// <summary>First-run marker (Milestone 7). Config presence can't signal
    /// "first run" because configs are seeded unconditionally on every launch,
    /// so completion of the first-run wizard is tracked by this separate file.
    /// It is written only when the wizard is actually finished or skipped.</summary>
    public static string WizardStatePath => Path.Combine(AppDataRoot, "wizard.json");

    /// <summary>Run history database (Milestone 8 write path, Milestone 10
    /// schema). SQLite so Phase 4's search/filter can build on it without a
    /// storage migration.</summary>
    public static string HistoryDbPath => Path.Combine(AppDataRoot, "history.db");

    public static string ManifestsDir => Path.Combine(AppContext.BaseDirectory, "Manifests");

    public static string DefaultConfigsDir => Path.Combine(AppContext.BaseDirectory, "DefaultConfigs");

    public static string ConfigPathFor(string scriptId) => Path.Combine(ConfigsDir, scriptId + ".json");

    /// <summary>Copies the shipped default config JSON for each script into
    /// AppData on first run, so every script has a config the app and a bare
    /// terminal can both read. Existing files are never overwritten.</summary>
    public static void EnsureConfigsSeeded()
    {
        Directory.CreateDirectory(ConfigsDir);
        if (!Directory.Exists(DefaultConfigsDir))
            return;
        foreach (var file in Directory.GetFiles(DefaultConfigsDir, "*.json"))
        {
            var dest = Path.Combine(ConfigsDir, Path.GetFileName(file));
            if (!File.Exists(dest))
                File.Copy(file, dest);
        }
    }
}