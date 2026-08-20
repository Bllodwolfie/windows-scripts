using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ScriptSuite.Services;

/// <summary>Reads and updates a script's mutable config JSON in AppData.
/// Settings edits only ever touch fields the manifest declares. SetField edits
/// the file as TEXT, splicing only the edited field's value token, so every
/// other key (LogDir, Categories, theme palettes, ...) survives byte-for-byte
/// — re-serializing the whole document would silently reformat (and could
/// reorder) untouched settings, which hand-edited config files shouldn't
/// suffer.</summary>
public sealed class ScriptConfigService
{
    /// <summary>Loads the script's config as a JSON object, or an empty object
    /// when the file is missing or malformed.</summary>
    public JsonObject Load(string scriptId)
    {
        var path = AppPaths.ConfigPathFor(scriptId);
        if (!File.Exists(path))
            return new JsonObject();
        try
        {
            return JsonNode.Parse(File.ReadAllText(path)) as JsonObject ?? new JsonObject();
        }
        catch (JsonException)
        {
            return new JsonObject();
        }
    }

    /// <summary>Sets one field in the config and writes the file back without
    /// touching any other byte. A null value removes the field (used by Undo
    /// when the field didn't exist before a change).</summary>
    public void SetField(string scriptId, string fieldName, JsonNode? value)
    {
        var path = AppPaths.ConfigPathFor(scriptId);
        string raw = File.Exists(path) ? File.ReadAllText(path) : "";
        string? next = null;

        int start = FindPropertyStart(raw, fieldName);
        if (start >= 0)
        {
            int colon = start + fieldName.Length + 2;
            while (colon < raw.Length && char.IsWhiteSpace(raw[colon])) colon++;
            if (colon >= raw.Length || raw[colon] != ':')
                start = -1; // malformed; fall through to insert
            else
            {
                int valueStart = colon + 1;
                while (valueStart < raw.Length && char.IsWhiteSpace(raw[valueStart])) valueStart++;
                int valueEnd = ScanValueEnd(raw, valueStart);

                next = value is null
                    ? RemoveProperty(raw, start, valueEnd)
                    : raw[..start] + Quote(fieldName) + ":" + raw[(colon + 1)..valueStart] + SerializeNode(value) + raw[valueEnd..];
            }
        }

        if (next is null)
        {
            if (value is null)
                return; // removing a field that isn't there: nothing to do
            next = InsertProperty(raw, fieldName, value);
        }

        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, next);
    }

    // ------------------------------------------------------------ helpers

    private static string Quote(string s) => "\"" + s + "\"";

    private static string SerializeNode(JsonNode value) => value.ToJsonString();

    /// <summary>Index of the opening quote of a top-level property named
    /// exactly <paramref name="name"/>, or -1. Only matches when the quoted
    /// token sits in a property position (preceded by '{'/',' and followed by
    /// ':'), so a same-looking string inside a value is ignored.</summary>
    private static int FindPropertyStart(string raw, string name)
    {
        string needle = Quote(name);
        int idx = 0;
        while (idx >= 0)
        {
            idx = raw.IndexOf(needle, idx, StringComparison.Ordinal);
            if (idx < 0) return -1;
            int before = idx - 1;
            while (before >= 0 && char.IsWhiteSpace(raw[before])) before--;
            int after = idx + needle.Length;
            while (after < raw.Length && char.IsWhiteSpace(raw[after])) after++;
            if (before >= 0 && (raw[before] == '{' || raw[before] == ',') && after < raw.Length && raw[after] == ':')
                return idx;
            idx += needle.Length;
        }
        return -1;
    }

    /// <summary>End index (exclusive) of the JSON value beginning at
    /// <paramref name="start"/>: handles strings (with escapes), nested
    /// objects/arrays, and bare numbers/literals.</summary>
    private static int ScanValueEnd(string raw, int start)
    {
        int i = start;
        while (i < raw.Length && char.IsWhiteSpace(raw[i])) i++;
        if (i >= raw.Length) return i;
        char c = raw[i];
        if (c == '"')
        {
            i++;
            while (i < raw.Length)
            {
                if (raw[i] == '\\') { i += 2; continue; }
                if (raw[i] == '"') { i++; break; }
                i++;
            }
            return i;
        }
        if (c == '{' || c == '[')
        {
            int depth = 0;
            bool inString = false;
            while (i < raw.Length)
            {
                char ch = raw[i];
                if (inString)
                {
                    if (ch == '\\') { i += 2; continue; }
                    if (ch == '"') inString = false;
                }
                else if (ch == '"') inString = true;
                else if (ch == '{' || ch == '[') depth++;
                else if (ch == '}' || ch == ']') { depth--; if (depth == 0) { i++; break; } }
                i++;
            }
            return i;
        }
        while (i < raw.Length && !char.IsWhiteSpace(raw[i]) && raw[i] != ',' && raw[i] != '}' && raw[i] != ']')
            i++;
        return i;
    }

    /// <summary>Removes the property spanning [propStart, valueEnd), also
    /// consuming the comma that brackets it so no dangling comma is left.</summary>
    private static string RemoveProperty(string raw, int propStart, int valueEnd)
    {
        int p = propStart - 1;
        while (p >= 0 && char.IsWhiteSpace(raw[p])) p--;
        if (p >= 0 && raw[p] == ',')
            return raw[..p] + raw[valueEnd..];
        int a = valueEnd;
        while (a < raw.Length && char.IsWhiteSpace(raw[a])) a++;
        if (a < raw.Length && raw[a] == ',')
            return raw[..propStart] + raw[(a + 1)..];
        return raw[..propStart] + raw[valueEnd..];
    }

    /// <summary>Inserts a new property just after the root object's opening
    /// brace (keeps every existing byte intact).</summary>
    private static string InsertProperty(string raw, string fieldName, JsonNode value)
    {
        string newProp = Quote(fieldName) + ": " + SerializeNode(value);
        string trimmed = raw.Trim();
        if (trimmed.Length == 0 || trimmed == "{}")
            return "{\n  " + newProp + "\n}";
        int open = raw.IndexOf('{');
        return open < 0
            ? "{\n  " + newProp + "\n}"
            : raw[..(open + 1)] + "\n  " + newProp + "," + raw[(open + 1)..];
    }
}