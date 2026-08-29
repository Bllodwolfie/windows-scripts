using System.Windows;
using System.Windows.Controls;
using ScriptSuite.Services;
using ScriptSuite.ViewModels;

namespace ScriptSuite;

public partial class MainWindow : Window
{
    private readonly ManifestCatalog _catalog;
    private readonly DashboardStateStore _stateStore;
    private readonly ScheduleStore _scheduleStore;
    private readonly RiskConsentStore _riskStore;
    private readonly ScriptExecutor _executor;
    private readonly ScriptConfigService _configService;
    private readonly RunHistoryStore _historyStore;
    private readonly MainWindowViewModel _vm;

    public MainWindow(ManifestCatalog catalog, DashboardStateStore stateStore, ScheduleStore scheduleStore, RiskConsentStore riskStore, ScriptExecutor executor, ScriptConfigService configService, RunHistoryStore historyStore)
    {
        InitializeComponent();
        _catalog = catalog;
        _stateStore = stateStore;
        _scheduleStore = scheduleStore;
        _riskStore = riskStore;
        _executor = executor;
        _configService = configService;
        _historyStore = historyStore;

        _vm = new MainWindowViewModel(catalog, stateStore, scheduleStore);
        DataContext = _vm;
        RefreshView();
    }

    private void RefreshView()
    {
        _vm.Refresh();
    }

    private void HideButton_Click(object sender, RoutedEventArgs e)
    {
        if (_vm.IsRunning)
            return;
        if ((sender as FrameworkElement)?.DataContext is ScriptRowViewModel row)
        {
            row.IsHidden = true;
            RefreshView();
        }
    }

    private void ShowButton_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.DataContext is ScriptRowViewModel row)
        {
            row.IsHidden = false;
            RefreshView();
        }
    }

    private void RunAllButton_Click(object sender, RoutedEventArgs e)
    {
        if (_vm.IsRunning)
            return;
        var order = _catalog.BatchOrder(id => _stateStore.IsRunAllEnabled(id) && !_stateStore.IsHidden(id));
        if (order.Count == 0)
            return;

        _vm.IsRunning = true;
        try
        {
            var preview = new RunAllPreviewWindow(_executor, order, _historyStore);
            preview.Owner = this;
            preview.ShowDialog();
        }
        finally
        {
            _vm.IsRunning = false;
        }
    }

    private void HistoryButton_Click(object sender, RoutedEventArgs e)
    {
        var window = new HistoryWindow(_historyStore, _catalog) { Owner = this };
        window.ShowDialog();
    }

    private void ScheduledHistoryButton_Click(object sender, RoutedEventArgs e)
    {
        var window = new ScheduledHistoryWindow(_historyStore, _catalog) { Owner = this };
        window.ShowDialog();
    }

    private void ScheduleButton_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.DataContext is ScriptRowViewModel row)
        {
            var dlg = new ScheduleWindow(row.Manifest, _scheduleStore, _riskStore, _catalog) { Owner = this };
            if (dlg.ShowDialog() == true) RefreshView();
        }
    }

    private void RunButton_Click(object sender, RoutedEventArgs e)
    {
        if (_vm.IsRunning)
            return;
        if ((sender as FrameworkElement)?.DataContext is ScriptRowViewModel row)
        {
            _vm.IsRunning = true;
            try
            {
                var window = new ScriptRunWindow(row.Manifest, _executor, _historyStore) { Owner = this };
                window.ShowDialog();
            }
            finally
            {
                _vm.IsRunning = false;
            }
        }
    }

    private void SettingsButton_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.DataContext is ScriptRowViewModel row)
        {
            var window = new SettingsWindow(row.Manifest, _configService) { Owner = this };
            window.ShowDialog();
        }
    }
}