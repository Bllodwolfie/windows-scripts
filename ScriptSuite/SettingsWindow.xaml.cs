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

        // Script-level help (window header ?)
        var overview = GetScriptOverviewHelp(manifest.Id);
        if (!string.IsNullOrWhiteSpace(overview))
        {
            HelpTextBlock.Text = overview;
            HelpButton.Visibility = Visibility.Visible;
        }
    }

    private static string GetScriptOverviewHelp(string id) => id switch
    {
        "ClearEventLogs" => "This clears every Windows event log after saving a backup. Event logs are Windows' own diagnostic history, not this app's logs. Each log with events is exported as a .evtx file in the backup folder, then cleared. If a backup fails, that log is left untouched. You can re-import a .evtx file in Event Viewer, but the app will not restore it for you.",
        "EmptyRecycleBin" => "This permanently empties the Recycle Bin on all drives. Files are not moved to another folder — they are deleted and cannot be recovered. The preview shows what would be deleted. Use the age filter to keep recently deleted items, or 0 to empty everything.",
        "DownloadsCleanup" => "This sorts old files in your Downloads folder. Files older than the cutoff and matching the delete list go to the Recycle Bin; other old files are moved into category folders (Music, Videos, Pictures, etc.). Advanced Rules below always win over the simple lists for the same extension. Ignore means never touch, even if old. Delete goes to the Recycle Bin. MoveTo needs a valid folder — if empty or missing, that rule is skipped and logged.",
        _ => ""
    };

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