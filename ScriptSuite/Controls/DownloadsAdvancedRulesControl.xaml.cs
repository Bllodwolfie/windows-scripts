using System.IO;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;
using ScriptSuite.ViewModels;

namespace ScriptSuite.Controls;

public partial class DownloadsAdvancedRulesControl : UserControl
{
    public DownloadsAdvancedRulesControl()
    {
        InitializeComponent();
    }

    private DownloadsAdvancedRulesViewModel? ViewModel => DataContext as DownloadsAdvancedRulesViewModel;

    private void RemoveRule_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.Tag is AdvancedRuleRowViewModel row)
            ViewModel?.Remove(row);
        else if ((sender as FrameworkElement)?.DataContext is AdvancedRuleRowViewModel row2)
            ViewModel?.Remove(row2);
    }

    private void AddRule_Click(object sender, RoutedEventArgs e) => ViewModel?.AddNew();

    private void RuleAction_Changed(object sender, SelectionChangedEventArgs e)
    {
        if ((sender as FrameworkElement)?.DataContext is AdvancedRuleRowViewModel row)
            ViewModel?.NotifyRowChanged(row);
    }

    private void RuleExtension_LostFocus(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.DataContext is AdvancedRuleRowViewModel row)
            ViewModel?.NotifyRowChanged(row);
    }

    private void RuleDestination_LostFocus(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.DataContext is AdvancedRuleRowViewModel row)
            ViewModel?.NotifyRowChanged(row);
    }

    private void BrowseDestination_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is not AdvancedRuleRowViewModel row) return;
        var dlg = new OpenFolderDialog
        {
            Title = "Choose folder for " + row.Extension,
            InitialDirectory = TryGetInitialDir(row.Destination)
        };
        if (dlg.ShowDialog() == true)
        {
            row.Destination = dlg.FolderName;
            ViewModel?.NotifyRowChanged(row);
        }
    }

    private void BrowseNewDestination_Click(object sender, RoutedEventArgs e)
    {
        var vm = ViewModel;
        if (vm is null) return;
        var dlg = new OpenFolderDialog
        {
            Title = "Choose folder for " + (string.IsNullOrWhiteSpace(vm.NewExtension) ? "new rule" : vm.NewExtension),
            InitialDirectory = TryGetInitialDir(vm.NewDestination)
        };
        if (dlg.ShowDialog() == true)
            vm.SetNewDestination(dlg.FolderName);
    }

    private static string TryGetInitialDir(string path)
    {
        try
        {
            var expanded = Environment.ExpandEnvironmentVariables(path ?? "");
            if (!string.IsNullOrWhiteSpace(expanded) && Path.IsPathRooted(expanded))
            {
                var dir = Directory.Exists(expanded) ? expanded : Path.GetDirectoryName(expanded);
                if (!string.IsNullOrEmpty(dir) && Directory.Exists(dir)) return dir;
            }
        }
        catch { }
        return Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
    }
}
