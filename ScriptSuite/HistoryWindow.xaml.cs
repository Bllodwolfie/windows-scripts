using System.Collections.ObjectModel;
using System.Windows;
using ScriptSuite.Services;
using ScriptSuite.ViewModels;

namespace ScriptSuite;

/// <summary>
/// Milestone 10: basic run history list, most recent first. Shows when each
/// run happened, which script it was, its outcome, and a short summary of what
/// it did. Deliberately read-only with no search/filter yet — Phase 4 builds
/// search/filter on top of this same GetRecent() data.
/// </summary>
public partial class HistoryWindow : Window
{
    private readonly RunHistoryStore _history;
    private readonly ManifestCatalog _catalog;
    private readonly ObservableCollection<HistoryRowViewModel> _rows = new();

    public HistoryWindow(RunHistoryStore history, ManifestCatalog catalog)
    {
        InitializeComponent();
        _history = history;
        _catalog = catalog;
        HistoryList.ItemsSource = _rows;
        Loaded += OnLoaded;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        var entries = _history.GetRecent(200);
        foreach (var entry in entries)
        {
            var manifest = _catalog.Find(entry.ScriptId);
            _rows.Add(new HistoryRowViewModel
            {
                When = entry.StartedAt ?? "",
                DisplayName = manifest?.DisplayName ?? entry.ScriptId,
                Outcome = entry.Outcome,
                OutcomeBrush = entry.Outcome switch
                {
                    "Success" => "#FFA6E3A1",
                    "Warning" => "#FFF9E2AF",
                    "Failed" => "#FFF38BA8",
                    "Cancelled" => "#FF89B4FA",
                    _ => "#FFCDD6F4",
                },
                Summary = entry.Summary,
            });
        }
        CountText.Text = $"{entries.Count} run(s) recorded";
        EmptyMessage.Visibility = entries.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e) => Close();
}