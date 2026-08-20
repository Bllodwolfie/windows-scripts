namespace ScriptSuite.Models;

/// <summary>One row of a dry-run preview, mirroring the PSCustomObject shape
/// the scripts emit: Action (Delete|Move|Clear|Create|Skip), Target, Detail.</summary>
public sealed class DryRunItem
{
    public string Action { get; set; } = "";
    public string Target { get; set; } = "";
    public string Detail { get; set; } = "";

    public string ActionDisplay =>
        Action switch
        {
            "Delete" => "Delete",
            "Move" => "Move",
            "Clear" => "Clear",
            "Create" => "Create",
            "Skip" => "Skip",
            _ => Action,
        };
}