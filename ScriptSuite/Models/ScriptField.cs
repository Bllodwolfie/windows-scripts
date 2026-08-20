using System.Text.Json;
using System.Text.Json.Serialization;

namespace ScriptSuite.Models;

/// <summary>
/// One configurable setting of a script, declared in its manifest. The
/// settings panel (Milestone 6) renders one control per field based on Type.
/// </summary>
public sealed class ScriptField
{
    [JsonPropertyName("name")] public string Name { get; set; } = "";
    [JsonPropertyName("label")] public string Label { get; set; } = "";
    [JsonPropertyName("type")] public string Type { get; set; } = "";
    [JsonPropertyName("unit")] public string? Unit { get; set; }
    [JsonPropertyName("default")] public JsonElement Default { get; set; }
    [JsonPropertyName("helpText")] public string? HelpText { get; set; }

    /// <summary>For "path" fields, whether the path is a file or a folder
    /// (the Browse button needs to know which dialog to open). Absent means
    /// folder — all shipped folder fields rely on that default; only
    /// SoftwareInventory.OutputFile sets "file".</summary>
    [JsonPropertyName("pathKind")] public string? PathKind { get; set; }

    public bool IsFilePath => string.Equals(PathKind, "file", StringComparison.OrdinalIgnoreCase);

    public bool HasDefault => Default.ValueKind is not JsonValueKind.Undefined and not JsonValueKind.Null;
}