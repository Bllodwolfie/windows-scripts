using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using ScriptSuite.Models;
using ScriptSuite.Services;

namespace ScriptSuite;

public partial class ScheduleWindow : Window
{
    private readonly ScriptManifest _manifest;
    private readonly ScheduleStore _scheduleStore;
    private readonly RiskConsentStore _riskStore;
    private readonly ManifestCatalog _catalog;
    private bool _initializing = true;

    public ScheduleWindow(ScriptManifest manifest, ScheduleStore scheduleStore, RiskConsentStore riskStore, ManifestCatalog catalog)
    {
        InitializeComponent();
        _manifest = manifest;
        _scheduleStore = scheduleStore;
        _riskStore = riskStore;
        _catalog = catalog;

        TitleText.Text = $"Schedule — {manifest.DisplayName}";
        DescText.Text = manifest.Description;
        ScheduleHelpText.Text = "Every N Days/Hours/Weeks at HH:mm. For multi-day or custom weekday schedules, select Weeks and check the desired days. For multi-week schedules, the anchor week defines the recurrence cycle. Admin scripts require a one-time UAC prompt to register, then run silently in the background.";

        UnitBox.SelectedIndex = 0;
        TimeBox.Text = "09:00";
        IntervalBox.Text = "1";
        StartDatePicker.SelectedDate = DateTime.Today;

        // Default weekdays: check today's day of week
        SetCheckboxForDay(DateTime.Today.DayOfWeek, true);

        if (_scheduleStore.Get(manifest.Id) is { } existing)
        {
            IntervalBox.Text = existing.Interval.ToString(CultureInfo.InvariantCulture);
            TimeBox.Text = existing.TimeOfDay;
            for (int i = 0; i < UnitBox.Items.Count; i++)
            {
                if ((UnitBox.Items[i] as ComboBoxItem)?.Content as string == existing.Unit)
                    UnitBox.SelectedIndex = i;
            }

            if (!string.IsNullOrWhiteSpace(existing.StartDate) &&
                DateTime.TryParseExact(existing.StartDate, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var sDate))
            {
                StartDatePicker.SelectedDate = sDate;
            }

            if (existing.Unit == "Weeks")
            {
                if (existing.Weekdays != null && existing.Weekdays.Length > 0)
                {
                    ClearAllWeekdayCheckboxes();
                    foreach (var w in existing.Weekdays)
                    {
                        if (ScheduleCalculation.IsValidDayOfWeekName(w))
                            SetCheckboxForDay(ScheduleCalculation.ParseDayOfWeek(w), true);
                    }
                }
                else
                {
                    // Legacy entry without stored weekdays: derive in-memory from registered task
                    var taskInfo = ScheduledTaskService.GetTaskScheduleInfo(manifest.Id);
                    if (taskInfo.Exists && taskInfo.Weekdays != null && taskInfo.Weekdays.Length > 0)
                    {
                        ClearAllWeekdayCheckboxes();
                        foreach (var w in taskInfo.Weekdays)
                        {
                            if (ScheduleCalculation.IsValidDayOfWeekName(w))
                                SetCheckboxForDay(ScheduleCalculation.ParseDayOfWeek(w), true);
                        }
                    }
                    if (taskInfo.Exists && !string.IsNullOrWhiteSpace(taskInfo.StartDate) &&
                        DateTime.TryParseExact(taskInfo.StartDate, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var tDate))
                    {
                        StartDatePicker.SelectedDate = tDate;
                    }
                }
            }
        }

        bool needsRisk = manifest.RequiresAdmin;
        if (needsRisk)
        {
            RiskCheck.Visibility = Visibility.Visible;
            AdminNote.Visibility = Visibility.Visible;
            RiskCheck.IsChecked = _riskStore.HasConsent(manifest.Id);
        }

        RemoveBtn.Visibility = _scheduleStore.Has(manifest.Id) ? Visibility.Visible : Visibility.Collapsed;
        _initializing = false;

        UpdateUiLayout();
        UpdatePreviewAndCollisions();
    }

    private void ScheduleHelpButton_Click(object sender, RoutedEventArgs e)
    {
        ScheduleHelpPanel.Visibility = ScheduleHelpPanel.Visibility == Visibility.Visible ? Visibility.Collapsed : Visibility.Visible;
    }

    private void Cancel_Click(object sender, RoutedEventArgs e) => Close();

    private void Remove_Click(object sender, RoutedEventArgs e)
    {
        var (ok, err) = ScheduledTaskService.Unregister(_manifest.Id);
        if (!ok) { ErrorText.Text = err ?? "Failed to remove task"; return; }
        _scheduleStore.Remove(_manifest.Id);
        DialogResult = true;
        Close();
    }

    private void UnitBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_initializing) return;
        UpdateUiLayout();
        UpdatePreviewAndCollisions();
    }

    private void Control_Changed(object sender, RoutedEventArgs e)
    {
        if (_initializing) return;
        UpdateUiLayout();
        UpdatePreviewAndCollisions();
    }

    private void UpdateUiLayout()
    {
        string unit = (UnitBox.SelectedItem as ComboBoxItem)?.Content as string ?? "Days";
        int.TryParse(IntervalBox.Text.Trim(), out int interval);

        if (unit == "Weeks")
        {
            WeekdaysPanel.Visibility = Visibility.Visible;
            if (interval > 1)
            {
                StartDatePanel.Visibility = Visibility.Visible;
                StartDateLabel.Text = "Anchor week:";
            }
            else
            {
                StartDatePanel.Visibility = Visibility.Collapsed;
            }
        }
        else
        {
            WeekdaysPanel.Visibility = Visibility.Collapsed;
            StartDatePanel.Visibility = Visibility.Visible;
            StartDateLabel.Text = "Start date:";
        }
    }

    private List<string> GetSelectedWeekdays()
    {
        var list = new List<string>();
        if (ChkMon.IsChecked == true) list.Add("Monday");
        if (ChkTue.IsChecked == true) list.Add("Tuesday");
        if (ChkWed.IsChecked == true) list.Add("Wednesday");
        if (ChkThu.IsChecked == true) list.Add("Thursday");
        if (ChkFri.IsChecked == true) list.Add("Friday");
        if (ChkSat.IsChecked == true) list.Add("Saturday");
        if (ChkSun.IsChecked == true) list.Add("Sunday");
        return list;
    }

    private void ClearAllWeekdayCheckboxes()
    {
        ChkMon.IsChecked = false;
        ChkTue.IsChecked = false;
        ChkWed.IsChecked = false;
        ChkThu.IsChecked = false;
        ChkFri.IsChecked = false;
        ChkSat.IsChecked = false;
        ChkSun.IsChecked = false;
    }

    private void SetCheckboxForDay(DayOfWeek d, bool isChecked)
    {
        switch (d)
        {
            case DayOfWeek.Monday: ChkMon.IsChecked = isChecked; break;
            case DayOfWeek.Tuesday: ChkTue.IsChecked = isChecked; break;
            case DayOfWeek.Wednesday: ChkWed.IsChecked = isChecked; break;
            case DayOfWeek.Thursday: ChkThu.IsChecked = isChecked; break;
            case DayOfWeek.Friday: ChkFri.IsChecked = isChecked; break;
            case DayOfWeek.Saturday: ChkSat.IsChecked = isChecked; break;
            case DayOfWeek.Sunday: ChkSun.IsChecked = isChecked; break;
        }
    }

    private ScheduleEntry BuildCandidateEntry()
    {
        string unit = (UnitBox.SelectedItem as ComboBoxItem)?.Content as string ?? "Days";
        int.TryParse(IntervalBox.Text.Trim(), out int interval);
        if (interval <= 0) interval = 1;
        string time = TimeBox.Text.Trim();

        var entry = new ScheduleEntry
        {
            ScriptId = _manifest.Id,
            Unit = unit,
            Interval = interval,
            TimeOfDay = time,
            Enabled = true,
        };

        if (unit == "Weeks")
        {
            entry.Weekdays = GetSelectedWeekdays().ToArray();
            if (interval > 1 && StartDatePicker.SelectedDate.HasValue)
            {
                entry.StartDate = StartDatePicker.SelectedDate.Value.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
            }
        }
        else
        {
            if (StartDatePicker.SelectedDate.HasValue)
            {
                entry.StartDate = StartDatePicker.SelectedDate.Value.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
            }
        }

        return entry;
    }

    private void UpdatePreviewAndCollisions()
    {
        try
        {
            var entry = BuildCandidateEntry();
            var (_, _, preview) = ScheduleCalculation.ComputeSchedule(entry);
            LivePreviewText.Text = preview;

            string? collision = ScheduleCalculation.DetectCollision(entry, _scheduleStore.All.Values);
            if (!string.IsNullOrEmpty(collision))
            {
                CollisionWarningText.Text = collision;
                CollisionWarningPanel.Visibility = Visibility.Visible;
            }
            else
            {
                CollisionWarningPanel.Visibility = Visibility.Collapsed;
            }
        }
        catch
        {
            LivePreviewText.Text = "Next run: --";
            CollisionWarningPanel.Visibility = Visibility.Collapsed;
        }
    }

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        ErrorText.Text = string.Empty;
        string unit = (UnitBox.SelectedItem as ComboBoxItem)?.Content as string ?? "Days";
        int maxInterval = unit == "Hours" ? 24 : 365;

        if (!int.TryParse(IntervalBox.Text.Trim(), out int interval) || interval < 1 || interval > maxInterval)
        {
            ErrorText.Text = unit == "Hours" ? "Hourly interval must be 1-24" : "Interval must be 1-365";
            return;
        }

        string time = TimeBox.Text.Trim();
        if (!TimeSpan.TryParseExact(time, @"h\:mm", CultureInfo.InvariantCulture, out _) &&
            !TimeSpan.TryParse(time, out _))
        {
            ErrorText.Text = "Time must be HH:mm e.g. 09:00";
            return;
        }

        var weekdays = GetSelectedWeekdays();
        if (unit == "Weeks" && weekdays.Count == 0)
        {
            ErrorText.Text = "Please select at least one day of the week.";
            return;
        }

        if (_manifest.RequiresAdmin && RiskCheck.IsChecked != true)
        {
            ErrorText.Text = "You must check 'I understand the risks' to schedule this admin script (per-script opt-in).";
            return;
        }
        if (_manifest.RequiresAdmin && RiskCheck.IsChecked == true)
        {
            _riskStore.SetConsent(_manifest.Id, true);
        }

        var trustStore = new ConfigTrustStore();
        if (!ConfigReviewDialog.EnsureTrusted(this, _manifest, trustStore))
            return;

        var existing = _scheduleStore.Get(_manifest.Id);
        string createdAt = existing?.CreatedAt ?? DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");

        string? startDateStr = null;
        if (StartDatePicker.SelectedDate.HasValue)
        {
            startDateStr = StartDatePicker.SelectedDate.Value.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        }

        var entry = new ScheduleEntry
        {
            ScriptId = _manifest.Id,
            Unit = unit,
            Interval = interval,
            TimeOfDay = time,
            Weekdays = unit == "Weeks" ? weekdays.ToArray() : null,
            StartDate = (unit == "Weeks" && interval <= 1) ? null : startDateStr,
            Enabled = true,
            CreatedAt = createdAt,
        };

        // 1. Try registering task unelevated
        var (ok, err, needsElev) = ScheduledTaskService.Register(entry, _manifest.RequiresAdmin);

        // 2. If access denied or admin required, route through UAC elevation helper
        if (!ok && needsElev)
        {
            var (eok, eerr) = ScheduledTaskService.RegisterElevated(entry);
            if (!eok)
            {
                ErrorText.Text = ScheduledTaskService.CleanErrorMessage(eerr ?? "UAC registration failed (declined?)");
                return; // Do NOT update scheduleStore
            }
            ok = true;
        }

        if (!ok)
        {
            ErrorText.Text = ScheduledTaskService.CleanErrorMessage(err ?? "Failed to register task");
            return;
        }

        // 3. Task Scheduler registered and verified; update schedules.json atomically
        _scheduleStore.Set(entry);
        DialogResult = true;
        Close();
    }
}
