using System.IO;
using System.Security.Cryptography;
using System.Text.Json;

[assembly: System.Runtime.CompilerServices.InternalsVisibleTo("TestTrust")]

namespace ScriptSuite.Services;

/// <summary>SEC-04: Configuration Trust System.
/// Stores SHA-256 hashes of approved config files in %LOCALAPPDATA%\ScriptSuite\config-trust.json.
/// If a config is edited outside the app or untrusted, headless runs reject execution and
/// interactive runs require user review and explicit approval.</summary>
public sealed class ConfigTrustStore
{
    private readonly string _path;
    private readonly string _configsDir;
    private readonly object _lock = new();
    private Dictionary<string, string> _map;

    public ConfigTrustStore()
        : this(AppPaths.ConfigTrustPath, AppPaths.ConfigsDir)
    {
    }

    internal ConfigTrustStore(string path, string configsDir)
    {
        _path = path;
        _configsDir = configsDir;
        _map = LoadOrSeed(_path, _configsDir);
    }

    private static Dictionary<string, string> LoadOrSeed(string path, string configsDir)
    {
        if (File.Exists(path))
        {
            try
            {
                return JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(path))
                       ?? new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            }
            catch
            {
                return new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            }
        }

        // On first start with no trust store, seed all existing configs as trusted (migration) and log once.
        var seeded = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (Directory.Exists(configsDir))
        {
            foreach (var file in Directory.GetFiles(configsDir, "*.json"))
            {
                var scriptId = Path.GetFileNameWithoutExtension(file);
                var hash = ComputeHash(file);
                if (!string.IsNullOrEmpty(hash))
                {
                    seeded[scriptId] = hash;
                }
            }
        }

        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            var tmp = path + ".tmp";
            File.WriteAllText(tmp, JsonSerializer.Serialize(seeded, new JsonSerializerOptions { WriteIndented = true }));
            File.Move(tmp, path, overwrite: true);
            Console.WriteLine($"Config trust store initialized; seeded {seeded.Count} existing configs as trusted.");
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Failed to write seeded config trust store: {ex.Message}");
        }

        return seeded;
    }

    public static string ComputeHash(string configPath)
    {
        if (!File.Exists(configPath)) return string.Empty;
        try
        {
            var bytes = File.ReadAllBytes(configPath);
            return Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
        }
        catch
        {
            return string.Empty;
        }
    }

    private string ConfigPathFor(string scriptId) => Path.Combine(_configsDir, scriptId + ".json");

    public bool IsTrusted(string scriptId)
    {
        var configPath = ConfigPathFor(scriptId);
        if (!File.Exists(configPath)) return true; // No config file -> trusted (uses fallback defaults)
        var currentHash = ComputeHash(configPath);
        if (string.IsNullOrEmpty(currentHash)) return false;

        lock (_lock)
        {
            if (_map.TryGetValue(scriptId, out var trustedHash))
            {
                return string.Equals(trustedHash, currentHash, StringComparison.OrdinalIgnoreCase);
            }
            return false;
        }
    }

    public void Trust(string scriptId)
    {
        var configPath = ConfigPathFor(scriptId);
        if (!File.Exists(configPath)) return;
        var hash = ComputeHash(configPath);
        if (string.IsNullOrEmpty(hash)) return;

        lock (_lock)
        {
            _map[scriptId] = hash;
            SaveLocked();
        }
    }

    private void SaveLocked()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
            var tmp = _path + ".tmp";
            File.WriteAllText(tmp, JsonSerializer.Serialize(_map, new JsonSerializerOptions { WriteIndented = true }));
            File.Move(tmp, _path, overwrite: true);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Failed to save config trust store: {ex.Message}");
        }
    }
}
