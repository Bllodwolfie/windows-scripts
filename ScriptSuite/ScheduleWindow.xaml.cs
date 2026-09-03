using System.Windows;
using ScriptSuite.Models;
using ScriptSuite.Services;

namespace ScriptSuite;

public partial class ScheduleWindow : Window
{
    private readonly ScriptManifest _manifest;
    private readonly ScheduleStore _scheduleStore;
    private readonly RiskConsentStore _riskStore;
    private readonly ManifestCatalog _catalog;

    public ScheduleWindow(ScriptManifest manifest, ScheduleStore scheduleStore, RiskConsentStore riskStore, ManifestCatalog catalog)
    {
        InitializeComponent();
        _manifest = manifest;
        _scheduleStore = scheduleStore;
        _riskStore = riskStore;
        _catalog = catalog;
        TitleText.Text = $"Schedule — {manifest.DisplayName}";
        DescText.Text = manifest.Description;
        UnitBox.SelectedIndex = 0;
        TimeBox.Text = "09:00";
        IntervalBox.Text = "1";
        if (_scheduleStore.Get(manifest.Id) is { } existing)
        {
            IntervalBox.Text = existing.Interval.ToString();
            TimeBox.Text = existing.TimeOfDay;
            for (int i = 0; i < UnitBox.Items.Count; i++) if ((UnitBox.Items[i] as System.Windows.Controls.ComboBoxItem)?.Content as string == existing.Unit) UnitBox.SelectedIndex = i;
        }
        bool needsRisk = manifest.RequiresAdmin;
        if (needsRisk)
        {
            RiskCheck.Visibility = Visibility.Visible;
            AdminNote.Visibility = Visibility.Visible;
            RiskCheck.IsChecked = _riskStore.HasConsent(manifest.Id);
        }
        RemoveBtn.Visibility = _scheduleStore.Has(manifest.Id) ? Visibility.Visible : Visibility.Collapsed;
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

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        if (!int.TryParse(IntervalBox.Text.Trim(), out int interval) || interval < 1 || interval > 365)
        { ErrorText.Text = "Interval must be 1-365"; return; }
        string unit = (UnitBox.SelectedItem as System.Windows.Controls.ComboBoxItem)?.Content as string ?? "Days";
        string time = TimeBox.Text.Trim();
        if (!TimeSpan.TryParse(time, out _))
        { ErrorText.Text = "Time must be HH:mm e.g. 09:00"; return; }
        if (_manifest.RequiresAdmin && RiskCheck.IsChecked != true)
        { ErrorText.Text = "You must check 'I understand the risks' to schedule this admin script (per-script opt-in)."; return; }
        if (_manifest.RequiresAdmin && RiskCheck.IsChecked == true) _riskStore.SetConsent(_manifest.Id, true);

        var entry = new ScheduleEntry { ScriptId = _manifest.Id, Unit = unit, Interval = interval, TimeOfDay = time, Enabled = true, CreatedAt = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") };
        var (ok, err, needsElev) = ScheduledTaskService.Register(entry, _manifest.RequiresAdmin);
        if (!ok && needsElev && _manifest.RequiresAdmin)
        {
            // One-time UAC to register HighestAvailable (B: separate from risk checkbox)
            var (eok, eerr) = ScheduledTaskService.RegisterElevated(entry);
            if (!eok) { ErrorText.Text = eerr ?? "UAC registration failed (declined?)"; return; }
            ok = true;
        }
        if (!ok) { ErrorText.Text = err ?? "Failed to register task"; return; }
        _scheduleStore.Set(entry);
        DialogResult = true;
        Close();
    }
}
