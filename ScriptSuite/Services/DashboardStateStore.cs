using System.IO;
using System.Text.Json;

namespace ScriptSuite.Services;

/// <summary>Persistent per-script dashboard flags. Hiding is purely visual
/// (Milestone 5) and "included in Run All" is a separate checkbox; both live
/// here in AppData, never in the script's config.</summary>
public sealed class DashboardState
{
    public Dictionary<string, ScriptDashboardState> Scripts { get; set; } = new();
}

public sealed class ScriptDashboardState
{
    public bool RunAll { get; set; } = true;
    public bool Hidden { get; set; }
}

public sealed class DashboardStateStore
{
    private readonly string _path;
    private DashboardState _state;

    public DashboardStateStore(string path)
    {
        _path = path;
        _state = Load(path);
    }

    private static DashboardState Load(string path)
    {
        if (!File.Exists(path))
            return new DashboardState();
        try
        {
            return JsonSerializer.Deserialize<DashboardState>(File.ReadAllText(path)) ?? new DashboardState();
        }
        catch (JsonException)
        {
            return new DashboardState();
        }
    }

    public bool IsRunAllEnabled(string scriptId) =>
        _state.Scripts.TryGetValue(scriptId, out var s) ? s.RunAll : true;

    public bool IsHidden(string scriptId) =>
        _state.Scripts.TryGetValue(scriptId, out var s) ? s.Hidden : false;

    public void SetRunAll(string scriptId, bool value) => Set(scriptId, s => s.RunAll = value);

    public void SetHidden(string scriptId, bool value) => Set(scriptId, s => s.Hidden = value);

    private void Set(string scriptId, Action<ScriptDashboardState> mutate)
    {
        if (!_state.Scripts.TryGetValue(scriptId, out var s))
            _state.Scripts[scriptId] = s = new ScriptDashboardState();
        mutate(s);
        Save();
    }

    private void Save()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
        File.WriteAllText(_path, JsonSerializer.Serialize(_state, new JsonSerializerOptions { WriteIndented = true }));
    }
}