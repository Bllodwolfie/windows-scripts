using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using Microsoft.Win32;
using ScriptSuite.ViewModels;

namespace ScriptSuite.Controls;

/// <summary>Selects the per-type control template for a settings field. Keeps
/// the field rendering schema-driven: adding a field type means adding a
/// template and a case here, nothing else.</summary>
public sealed class FieldTemplateSelector : DataTemplateSelector
{
    public DataTemplate? IntTemplate { get; set; }
    public DataTemplate? StringTemplate { get; set; }
    public DataTemplate? PathTemplate { get; set; }
    public DataTemplate? BoolTemplate { get; set; }
    public DataTemplate? ListTemplate { get; set; }

    public override DataTemplate? SelectTemplate(object item, DependencyObject container) =>
        item is SettingsFieldViewModel vm ? vm.Field.Type switch
        {
            "int" => IntTemplate,
            "bool" => BoolTemplate,
            "path" => PathTemplate,
            "stringList" => ListTemplate,
            _ => StringTemplate,
        }
        : null;
}

/// <summary>Reusable schema-driven settings form: renders one control per
/// manifest field (int stepper, string textbox, path + browse, bool checkbox,
/// stringList chips), auto-saves every change, and provides a session Undo.
/// Hosted by SettingsWindow now and by the first-run wizard in Milestone 7.</summary>
public partial class SettingsForm : UserControl
{
    public SettingsForm()
    {
        InitializeComponent();
    }

    public SettingsFormViewModel? Form
    {
        get => DataContext as SettingsFormViewModel;
        set => DataContext = value;
    }

    // ------------------------------------------------------------- events

    private void Text_LostFocus(object sender, RoutedEventArgs e) => CommitPending(sender);

    private void Text_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter)
            CommitPending(sender);
    }

    private void AddItem_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter && (sender as FrameworkElement)?.DataContext is SettingsFieldViewModel vm)
            vm.AddNewItem();
    }

    private void AddItem_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.DataContext is SettingsFieldViewModel vm)
            vm.AddNewItem();
    }

    private void ChipRemove_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.Tag is SettingsFieldViewModel vm && fe.DataContext is string item)
            vm.RemoveItem(item);
    }

    private void StepUp_Click(object sender, RoutedEventArgs e) => Step(sender, 1);

    private void StepDown_Click(object sender, RoutedEventArgs e) => Step(sender, -1);

    private static void Step(object sender, int delta)
    {
        if ((sender as FrameworkElement)?.DataContext is SettingsFieldViewModel vm)
            vm.Step(delta);
    }

    private void Browse_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.DataContext is not SettingsFieldViewModel vm)
            return;

        string expanded = Environment.ExpandEnvironmentVariables(vm.TextValue);
        string? initialDir = Path.IsPathRooted(expanded) ? Path.GetDirectoryName(expanded) : null;
        if (initialDir is null || !Directory.Exists(initialDir))
            initialDir = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);

        if (vm.IsFilePath)
        {
            var dlg = new OpenFileDialog
            {
                Title = "Choose file for " + vm.Label,
                CheckFileExists = false,
                InitialDirectory = initialDir,
                FileName = Path.IsPathRooted(expanded) ? Path.GetFileName(expanded) : "",
            };
            if (dlg.ShowDialog() == true)
                vm.SetPath(dlg.FileName);
        }
        else
        {
            var dlg = new OpenFolderDialog
            {
                Title = "Choose folder for " + vm.Label,
                InitialDirectory = initialDir,
            };
            if (dlg.ShowDialog() == true)
                vm.SetPath(dlg.FolderName);
        }
    }

    private void Undo_Click(object sender, RoutedEventArgs e)
    {
        if (DataContext is SettingsFormViewModel form)
            form.Undo();
    }

    private static void CommitPending(object sender)
    {
        if ((sender as FrameworkElement)?.DataContext is SettingsFieldViewModel vm)
            vm.CommitPending();
    }

    private void HelpToggle_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is SettingsFieldViewModel vm)
            vm.ToggleHelp();
        else if ((sender as FrameworkElement)?.DataContext is SettingsFieldViewModel vm2)
            vm2.ToggleHelp();
    }
}