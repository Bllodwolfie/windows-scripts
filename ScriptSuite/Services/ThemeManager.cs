using System.Windows;

namespace ScriptSuite.Services;

/// <summary>Swaps the token dictionary in App.Resources.MergedDictionaries.
/// Buttons.xaml stays; only the Tokens.* dictionary is swapped.
/// DynamicResource bindings re-resolve live — no restart required (Phase 1 confirmed 0 StaticResource brush bindings).</summary>
public static class ThemeManager
{
    private const string DarkUri = "Themes/Tokens.xaml";
    private const string LatteUri = "Themes/Tokens.Latte.xaml";

    public static string CurrentTheme { get; private set; } = "Dark";

    /// <summary>Call on startup before first window renders to avoid flash of wrong theme.</summary>
    public static void Initialize()
    {
        var store = new ThemeStore(AppPaths.ThemePath);
        Apply(store.Theme, save: false);
    }

    public static void Apply(string theme, bool save = true)
    {
        theme = theme.Equals("Latte", StringComparison.OrdinalIgnoreCase) ? "Latte" : "Dark";
        CurrentTheme = theme;

        if (Application.Current == null) return;

        var merged = Application.Current.Resources.MergedDictionaries;

        // Find existing token dict (Dark or Latte)
        ResourceDictionary? existing = null;
        foreach (var d in merged)
        {
            if (d.Source != null && (d.Source.OriginalString.Contains("Tokens.xaml") || d.Source.OriginalString.Contains("Tokens.Latte.xaml")))
            {
                existing = d;
                break;
            }
        }

        string targetUri = theme == "Latte" ? LatteUri : DarkUri;

        // If already correct, no-op
        if (existing != null && existing.Source != null && existing.Source.OriginalString.EndsWith(targetUri, StringComparison.OrdinalIgnoreCase))
        {
            if (save) new ThemeStore(AppPaths.ThemePath).SetTheme(theme);
            return;
        }

        var newDict = new ResourceDictionary { Source = new Uri(targetUri, UriKind.Relative) };

        if (existing != null)
        {
            int idx = merged.IndexOf(existing);
            merged.RemoveAt(idx);
            merged.Insert(idx, newDict);
        }
        else
        {
            // Fallback: insert at 0 (before Buttons.xaml)
            merged.Insert(0, newDict);
        }

        if (save)
        {
            new ThemeStore(AppPaths.ThemePath).SetTheme(theme);
        }
    }
}
