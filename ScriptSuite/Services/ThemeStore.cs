using System.IO;
using System.Text.Json;

namespace ScriptSuite.Services;

/// <summary>Mirrors DashboardStateStore pattern — persists theme preference in %LOCALAPPDATA%\ScriptSuite\theme.json
/// as {"Theme":"Dark"} or {"Theme":"Latte"}. Default Dark if absent preserves existing installs.</summary>
public sealed class ThemeStore
{
    private readonly string _path;
    private ThemeState _state;

    public ThemeStore(string path)
    {
        _path = path;
        _state = Load(path);
    }

    private static ThemeState Load(string path)
    {
        if (!File.Exists(path))
            return new ThemeState();
        try
        {
            var json = File.ReadAllText(path);
            var state = JsonSerializer.Deserialize<ThemeState>(json);
            if (state == null || string.IsNullOrWhiteSpace(state.Theme))
                return new ThemeState();
            // Normalize
            state.Theme = state.Theme.Equals("Latte", StringComparison.OrdinalIgnoreCase) ? "Latte" : "Dark";
            return state;
        }
        catch (JsonException)
        {
            return new ThemeState();
        }
        catch (IOException)
        {
            return new ThemeState();
        }
    }

    public string Theme => _state.Theme;

    public void SetTheme(string theme)
    {
        theme = theme.Equals("Latte", StringComparison.OrdinalIgnoreCase) ? "Latte" : "Dark";
        if (_state.Theme == theme) return;
        _state.Theme = theme;
        Save();
    }

    private void Save()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
        File.WriteAllText(_path, JsonSerializer.Serialize(_state, new JsonSerializerOptions { WriteIndented = true }));
    }

    private sealed class ThemeState
    {
        public string Theme { get; set; } = "Dark";
    }
}
