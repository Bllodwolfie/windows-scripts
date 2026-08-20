using System.Collections.ObjectModel;

namespace ScriptSuite.ViewModels;

public sealed class ScriptCategoryViewModel : ViewModelBase
{
    public ScriptCategoryViewModel(string category)
    {
        Name = category;
    }

    public string Name { get; }

    public ObservableCollection<ScriptRowViewModel> Rows { get; } = new();
}