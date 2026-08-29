using System.Collections.ObjectModel;
using System.Windows;
using ScriptSuite.Services;
using ScriptSuite.ViewModels;

namespace ScriptSuite;

public partial class ScheduledHistoryWindow : Window
{
    private readonly RunHistoryStore _history;
    private readonly ManifestCatalog _catalog;
    private readonly ObservableCollection<HistoryRowViewModel> _rows = new();

    public ScheduledHistoryWindow(RunHistoryStore history, ManifestCatalog catalog)
    {
        InitializeComponent();
        _history = history;
        _catalog = catalog;
        HistoryList.ItemsSource = _rows;
        Loaded += OnLoaded;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        var entries = _history.GetRecentScheduled(200);
        foreach (var entry in entries)
        {
            var manifest = _catalog.Find(entry.ScriptId);
            string outcome = entry.Outcome;
            string brush = outcome switch
            {
                "Success" => "#FFA6E3A1",
                "Warning" => "#FFF9E2AF",
                "Failed" => "#FFF38BA8",
                "SkippedBusy" => "#FF89B4FA",
                "Cancelled" => "#FF89B4FA",
                _ => "#FFCDD6F4",
            };
            _rows.Add(new HistoryRowViewModel
            {
                When = entry.StartedAt,
                DisplayName = (manifest?.DisplayName ?? entry.ScriptId) + $" ({entry.Trigger})",
                Outcome = outcome,
                OutcomeBrush = brush,
                Summary = entry.Summary ?? $"Scheduled for {entry.ScheduledFor}",
            });
        }
        CountText.Text = $"{entries.Count} scheduled run(s) recorded";
        EmptyMessage.Visibility = entries.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
    }
}
