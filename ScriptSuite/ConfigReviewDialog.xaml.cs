using System.Windows;
using ScriptSuite.Models;
using ScriptSuite.Services;

namespace ScriptSuite;

public partial class ConfigReviewDialog : Window
{
    private readonly ScriptManifest _manifest;
    private readonly ConfigTrustStore _trustStore;

    public ConfigReviewDialog(ScriptManifest manifest, ConfigTrustStore trustStore)
    {
        InitializeComponent();
        _manifest = manifest;
        _trustStore = trustStore;

        Title = $"Review Untrusted Configuration — {manifest.DisplayName}";
        TitleText.Text = $"Review Configuration: {manifest.DisplayName}";

        string configPath = AppPaths.ConfigPathFor(manifest.Id);
        var (summary, details) = ConfigReviewHelper.GetReviewInfo(manifest.Id, configPath);
        ActionSummaryText.Text = summary;
        DetailsText.Text = details.Count > 0 ? string.Join(Environment.NewLine, details) : "(no custom configuration settings)";
    }

    public static bool EnsureTrusted(Window? owner, ScriptManifest manifest, ConfigTrustStore trustStore)
    {
        if (trustStore.IsTrusted(manifest.Id))
            return true;

        var dialog = new ConfigReviewDialog(manifest, trustStore) { Owner = owner };
        var res = dialog.ShowDialog();
        return res == true;
    }

    private void CancelButton_Click(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
        Close();
    }

    private void TrustButton_Click(object sender, RoutedEventArgs e)
    {
        _trustStore.Trust(_manifest.Id);
        DialogResult = true;
        Close();
    }
}
