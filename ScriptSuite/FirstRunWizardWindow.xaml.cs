using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Input;
using ScriptSuite.Models;
using ScriptSuite.Services;
using ScriptSuite.ViewModels;

namespace ScriptSuite;

/// <summary>First-run setup wizard (Milestone 7). Shows one step per script
/// that has configurable fields, reusing the Milestone 6 schema-driven form.
/// The wizard's completion is tracked by a dedicated marker file (config
/// presence can't signal first run because configs are seeded on every
/// launch). The marker is written only when the wizard is finished or
/// explicitly skipped — closing it early leaves the marker absent so it
/// reappears on the next launch.
///
/// ACCEPTED TRADE-OFF (known, intentional): because each step reuses the
/// shared SettingsForm, which auto-saves on every edit, wizard steps write
/// live values into the real config files immediately. Only the completion
/// MARKER is deferred. Closing the wizard before finishing does NOT roll
/// those edits back — a partially-configured script keeps whatever the user
/// typed (or the defaults they accepted), and the wizard simply shows again
/// next launch with the current live config pre-filled. The resumable-close
/// guarantee is therefore about completion state (marker), not about discarding
/// partial edits. "Use recommended defaults" additionally overwrites all of a
/// step's fields with that script's manifest defaults before advancing.</summary>
public partial class FirstRunWizardWindow : Window
{
    private readonly List<ScriptManifest> _steps;
    private readonly ScriptConfigService _config;
    private int _index;
    private SettingsFormViewModel? _form;

    public FirstRunWizardWindow(IEnumerable<ScriptManifest> catalog, ScriptConfigService config)
    {
        InitializeComponent();
        _config = config;
        // Skip scripts with no configurable fields (EmptyRecycleBin has none)
        // so every step shows at least one editable setting.
        _steps = catalog.Where(m => m.Fields.Count > 0).ToList();
        ShowStep(0);
    }

    private void ShowStep(int index)
    {
        _index = index;
        var manifest = _steps[index];
        StepHeaderText.Text = $"Step {index + 1} of {_steps.Count} — {manifest.DisplayName}";
        StepDescriptionText.Text = manifest.Description;
        _form = new SettingsFormViewModel(manifest, _config);
        WizardFormControl.Form = _form;
        BackButton.IsEnabled = index > 0;
        bool last = index == _steps.Count - 1;
        NextButton.Content = last ? "Finish" : "Next";
        AutomationProperties.SetName(NextButton, last ? "Finish" : "Next");
    }

    private void Advance()
    {
        _form?.FlushPending();
        if (_index == _steps.Count - 1)
            CompleteAndClose();
        else
            ShowStep(_index + 1);
    }

    private void CompleteAndClose()
    {
        WizardStateStore.MarkCompleted();
        Close();
    }

    private void Recommended_Click(object sender, RoutedEventArgs e)
    {
        _form?.FlushPending();
        _form?.ApplyRecommendedDefaults();
        if (_index == _steps.Count - 1)
            CompleteAndClose();
        else
            ShowStep(_index + 1);
    }

    private void Back_Click(object sender, RoutedEventArgs e)
    {
        if (_index > 0)
        {
            _form?.FlushPending();
            ShowStep(_index - 1);
        }
    }

    private void Next_Click(object sender, RoutedEventArgs e) => Advance();

    private void Skip_Click(object sender, RoutedEventArgs e) => CompleteAndClose();

    protected override void OnClosing(CancelEventArgs e)
    {
        // Save any in-flight text edit, but do NOT write the marker: closing
        // the wizard before finishing/skipping means it shows again next launch.
        _form?.FlushPending();
        base.OnClosing(e);
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (e.Key == Key.Escape)
        {
            // Closing early keeps the marker absent, so the wizard reappears
            // next launch (same as the title-bar close).
            Close();
            e.Handled = true;
            return;
        }
        base.OnKeyDown(e);
    }
}