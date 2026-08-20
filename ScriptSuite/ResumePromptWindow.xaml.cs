using System.Windows;
using System.Windows.Input;

namespace ScriptSuite;

/// <summary>
/// Startup dialog for Milestone 9: an interrupted run's journal was found on
/// launch, so ask whether to resume it (re-showing a preview of only the items
/// still left to process) or discard it. Closing the dialog counts as discard.
/// </summary>
public partial class ResumePromptWindow : Window
{
    public bool ResumeRequested { get; private set; }

    public ResumePromptWindow(string scriptDisplayName, string startedAt)
    {
        InitializeComponent();
        TitleText.Text = $"An interrupted run was detected: {scriptDisplayName}";
        MessageText.Text = $"The app was closed while this run was still in progress (started {startedAt}).\n\n" +
                           "Resume continues the run with only the items that are still left to process — " +
                           "items that were already completed are not redone.\n\n" +
                           "Discard removes the unfinished run and its journal without doing anything.";
    }

    private void ResumeButton_Click(object sender, RoutedEventArgs e)
    {
        ResumeRequested = true;
        DialogResult = true;
    }

    private void DiscardButton_Click(object sender, RoutedEventArgs e) => DialogResult = true;

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
}