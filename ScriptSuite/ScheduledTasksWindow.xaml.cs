using System;
using System.Collections.ObjectModel;
using System.Windows;
using ScriptSuite.Models;
using ScriptSuite.Services;
using ScriptSuite.ViewModels;

namespace ScriptSuite;

public partial class ScheduledTasksWindow : Window
{
    private readonly ManifestCatalog _catalog;
    private readonly ScheduleStore _schedules;
    private readonly RunHistoryStore _history;
    private readonly RiskConsentStore _riskStore;
    private readonly ObservableCollection<ScheduledTaskRowViewModel> _tasks = new();

    public ScheduledTasksWindow(
        ManifestCatalog catalog,
        ScheduleStore schedules,
        RunHistoryStore history,
        RiskConsentStore riskStore)
    {
        InitializeComponent();
        _catalog = catalog;
        _schedules = schedules;
        _history = history;
        _riskStore = riskStore;
        TasksList.ItemsSource = _tasks;
        Loaded += (_, _) => Refresh();
    }

    public void Refresh()
    {
        _tasks.Clear();
        var latest = _history.GetLatestByScript();
        int activeCount = 0;

        foreach (var m in _catalog.All)
        {
            var entry = _schedules.Get(m.Id);
            bool hasSchedule = entry is not null;
            if (hasSchedule) activeCount++;

            string scheduleSummary = "Not scheduled";
            if (entry is not null)
            {
                scheduleSummary = $"{entry.Interval} {entry.Unit} @ {entry.TimeOfDay}";
                if (entry.Unit == "Weeks" && entry.Weekdays != null && entry.Weekdays.Length > 0)
                {
                    scheduleSummary += $" ({string.Join(", ", entry.Weekdays)})";
                }
            }

            string lastRanText = "Never ran";
            string lastOutcome = "";
            if (latest.TryGetValue(m.Id, out var h) && !string.IsNullOrEmpty(h.StartedAt))
            {
                lastRanText = $"{ScriptRowViewModel.FormatAgo(h.StartedAt)} ({h.Outcome})";
                lastOutcome = h.Outcome;
            }

            _tasks.Add(new ScheduledTaskRowViewModel
            {
                ScriptId = m.Id,
                DisplayName = m.DisplayName,
                Category = m.Category,
                Description = m.Description,
                HasSchedule = hasSchedule,
                ScheduleSummary = scheduleSummary,
                LastRanAt = lastRanText,
                LastOutcome = lastOutcome,
                Manifest = m
            });
        }

        CountText.Text = $"{activeCount} of {_catalog.All.Count} script(s) scheduled";
        EmptyMessage.Visibility = activeCount == 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private void ConfigureButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.Tag is ScheduledTaskRowViewModel row)
        {
            var dlg = new ScheduleWindow(row.Manifest, _schedules, _riskStore, _catalog) { Owner = this };
            if (dlg.ShowDialog() == true)
            {
                Refresh();
            }
        }
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e) => Close();
}
