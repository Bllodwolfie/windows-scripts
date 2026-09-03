using System.ComponentModel;
using System.Windows;
using System.Windows.Input;
using ScriptSuite.Models;
using ScriptSuite.Services;
using ScriptSuite.ViewModels;

namespace ScriptSuite;

/// <summary>Schema-driven settings screen for one script. Hosts the reusable
/// SettingsForm control; flushes any in-flight text edits when the window
/// closes so nothing typed is ever lost.</summary>
public partial class SettingsWindow : Window
{
    private readonly SettingsFormViewModel _form;
    private readonly DownloadsAdvancedRulesViewModel? _advancedRules;

    public SettingsWindow(ScriptManifest manifest, ScriptConfigService config)
    {
        InitializeComponent();
        Title = "Settings — " + manifest.DisplayName;
        ScriptNameText.Text = manifest.DisplayName;
        ScriptDescriptionText.Text = manifest.Description;

        _form = new SettingsFormViewModel(manifest, config);
        SettingsFormControl.Form = _form;

        if (manifest.Fields.Count == 0)
        {
            SettingsFormControl.Visibility = Visibility.Collapsed;
            NoFieldsText.Visibility = Visibility.Visible;
        }

        // Advanced per-extension rules — DownloadsCleanup only, additive to simple mode.
        if (string.Equals(manifest.Id, "DownloadsCleanup", StringComparison.OrdinalIgnoreCase))
        {
            _advancedRules = new DownloadsAdvancedRulesViewModel(config);
            AdvancedRulesControl.DataContext = _advancedRules;
            AdvancedRulesControl.Visibility = Visibility.Visible;
        }
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        _form.FlushPending();
        base.OnClosing(e);
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (e.Key == Key.Escape)
        {
            Close();
            e.Handled = true;
            return;
        }
        base.OnKeyDown(e);
    }

    private void HelpButton_Click(object sender, RoutedEventArgs e)
    {
        HelpPanel.Visibility = HelpPanel.Visibility == Visibility.Visible ? Visibility.Collapsed : Visibility.Visible;
    }
}