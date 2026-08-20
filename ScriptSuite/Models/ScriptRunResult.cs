namespace ScriptSuite.Models;

/// <summary>Structured result of one script run (in-process or elevated),
/// matching the JSON contract the elevated child writes back to its parent.</summary>
public sealed class ScriptRunResult
{
    public RunOutcome Outcome { get; set; }
    public string ScriptId { get; set; } = "";
    public List<string> Logs { get; set; } = new();
    public Dictionary<string, int> ItemCounts { get; set; } = new();
    public string? ErrorMessage { get; set; }
}