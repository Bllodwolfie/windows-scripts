using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace ScriptSuite.Models;

/// <summary>
/// Static description of one script: what it is, whether it needs admin, and
/// the shape of its settings fields. Mirrors the JSON manifests shipped under
/// Manifests/ and is the source of truth for how the app presents a script.
/// </summary>
public sealed class ScriptManifest
{
    [JsonPropertyName("id")] public string Id { get; set; } = "";
    [JsonPropertyName("displayName")] public string DisplayName { get; set; } = "";
    [JsonPropertyName("description")] public string Description { get; set; } = "";
    [JsonPropertyName("category")] public string Category { get; set; } = "";
    [JsonPropertyName("requiresAdmin")] public bool RequiresAdmin { get; set; }
    [JsonPropertyName("supportsDryRun")] public bool SupportsDryRun { get; set; }
    [JsonPropertyName("scriptPath")] public string ScriptPath { get; set; } = "";
    [JsonPropertyName("fields")] public List<ScriptField> Fields { get; set; } = new();

    public string AbsoluteScriptPath =>
        Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, ScriptPath));

    /// <summary>Always false for the built-in scripts; Phase 3 custom scripts
    /// set it so the dashboard shows the "Custom" badge.</summary>
    [JsonIgnore] public bool IsCustom { get; set; }

    /// <summary>Loaded from an external manifest (future Phase 3 custom
    /// scripts), rather than one of the shipped built-in files.</summary>
    [JsonIgnore] public bool IsExternal { get; set; }
}