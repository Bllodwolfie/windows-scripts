using System.Collections.ObjectModel;
using ScriptSuite.Models;
using ScriptSuite.Services;

namespace ScriptSuite.ViewModels;

/// <summary>State behind the dashboard: the category-grouped script rows and
/// the "Show hidden" filter. Rebuilds the visible rows whenever hiding or the
/// filter changes so hidden scripts truly leave the view.</summary>
public sealed class MainWindowViewModel : ViewModelBase
{
    private readonly ManifestCatalog _catalog;
    private readonly DashboardStateStore _stateStore;
    private bool _showHidden;

    public MainWindowViewModel(ManifestCatalog catalog, DashboardStateStore stateStore)
    {
        _catalog = catalog;
        _stateStore = stateStore;
    }

    public ObservableCollection<ScriptCategoryViewModel> Categories { get; } = new();

    public bool ShowHidden
    {
        get => _showHidden;
        set
        {
            if (Set(ref _showHidden, value))
                Refresh();
        }
    }

    public void Refresh()
    {
        Categories.Clear();
        foreach (var (category, scripts) in _catalog.GroupByCategory())
        {
            var cat = new ScriptCategoryViewModel(category);
            foreach (var manifest in scripts)
            {
                var row = new ScriptRowViewModel(manifest, _stateStore);
                if (row.IsHidden && !ShowHidden)
                    continue;
                cat.Rows.Add(row);
            }
            if (cat.Rows.Count > 0)
                Categories.Add(cat);
        }
        OnPropertyChanged(nameof(AnyEnabled));
    }

    /// <summary>True when at least one script is enabled (checked and not
    /// hidden) — the Run All button requires at least one to do anything.</summary>
    public bool AnyEnabled =>
        _catalog.All.Any(m => _stateStore.IsRunAllEnabled(m.Id) && !_stateStore.IsHidden(m.Id));
}