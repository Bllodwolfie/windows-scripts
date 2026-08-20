using ScriptSuite.Models;

namespace ScriptSuite.ViewModels;

/// <summary>One preview row in the single-script run window (Milestone 8):
/// the dry-run item plus the checkbox that decides whether it is passed to
/// the real run via -IncludeOnly. Checked by default.</summary>
public sealed class RunSelectionItem : ViewModelBase
{
    private bool _isChecked = true;

    public RunSelectionItem(DryRunItem item)
    {
        Item = item;
    }

    public DryRunItem Item { get; }

    public string ActionDisplay => Item.ActionDisplay;
    public string Target => Item.Target;
    public string Detail => Item.Detail;

    public bool IsChecked
    {
        get => _isChecked;
        set => Set(ref _isChecked, value);
    }
}