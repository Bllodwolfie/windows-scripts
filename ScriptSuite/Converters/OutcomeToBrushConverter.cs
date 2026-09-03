using System.Globalization;
using System.Windows;
using System.Windows.Data;
using System.Windows.Media;

namespace ScriptSuite.Converters;

/// <summary>
/// Resolves an outcome string/enum to a theme brush via Application resources.
/// Keys: Brush.Status.Success / Warning / Error / Info (+ Success.Foreground etc. not used here).
/// Falls back to Brush.Foreground.Primary for unknown outcomes. Uses TryFindResource so
/// missing keys do not throw — falls back to a hard-coded brush only in that case.
/// Phase 1 keeps Mocha hexes; Phase 2 Latte palette will flow automatically via DynamicResource.
/// </summary>
public sealed class OutcomeToBrushConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        string outcome = value switch
        {
            string s => s,
            ScriptSuite.Models.RunOutcome ro => ro.ToString(),
            ScriptSuite.ViewModels.RunPhaseStatus rps => rps.ToString(),
            _ => value?.ToString() ?? ""
        };

        string key = outcome switch
        {
            "Success" => "Brush.Status.Success",
            "Warning" => "Brush.Status.Warning",
            "Failed" => "Brush.Status.Error",   // Error token is Failed
            "Cancelled" => "Brush.Status.Info",
            "SkippedBusy" => "Brush.Status.Info",
            _ => "Brush.Foreground.Primary"
        };

        if (Application.Current != null)
        {
            var res = Application.Current.TryFindResource(key);
            if (res is Brush b) return b;
            if (res is Color c) return new SolidColorBrush(c);
        }
        // Design-time / fallback: should never hit at runtime after Tokens.xaml merged.
        // No hex literals here — falls back to TryFindResource above or neutral gray.
        return new SolidColorBrush(Color.FromRgb(0xCD, 0xD6, 0xF4));
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => throw new NotSupportedException();
}
