using System.IO;
using System.Text.Json;
using ScriptSuite.Models;

namespace ScriptSuite.Services;

/// <summary>Per-script schedules (Stage 2). Mirrors DashboardStateStore pattern:
/// single JSON file in AppData, atomic write.</summary>
public sealed class ScheduleStore
{
    private readonly string _path;
    private Dictionary<string, ScheduleEntry> _map;

    public ScheduleStore(string path)
    {
        _path = path;
        _map = Load(path);
    }

    private static Dictionary<string, ScheduleEntry> Load(string path)
    {
        if (!File.Exists(path)) return new();
        try
        {
            var json = File.ReadAllText(path);
            return JsonSerializer.Deserialize<Dictionary<string, ScheduleEntry>>(json) ?? new();
        }
        catch { return new(); }
    }

    private void Save()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
        var tmp = _path + ".tmp";
        File.WriteAllText(tmp, JsonSerializer.Serialize(_map, new JsonSerializerOptions { WriteIndented = true }));
        File.Move(tmp, _path, overwrite: true);
    }

    public IReadOnlyDictionary<string, ScheduleEntry> All => _map;
    public bool Has(string scriptId) => _map.ContainsKey(scriptId);
    public ScheduleEntry? Get(string scriptId) => _map.TryGetValue(scriptId, out var v) ? v : null;

    public void Set(ScheduleEntry entry)
    {
        _map[entry.ScriptId] = entry;
        Save();
    }

    public bool Remove(string scriptId)
    {
        if (_map.Remove(scriptId)) { Save(); return true; }
        return false;
    }
}
