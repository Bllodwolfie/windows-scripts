using System.Globalization;
using System.Windows;
using System.Windows.Data;

namespace ScriptSuite.Converters;

public sealed class InverseBooleanToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        => value is true ? Visibility.Collapsed : Visibility.Visible;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => throw new NotSupportedException();
}

/// <summary>ConverterParameter is the left margin thickness used when the
/// boolean is true; otherwise a zero margin. Used to keep a shield icon's
/// spacing correct when no icon is shown.</summary>
public sealed class BoolToMarginConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        double left = 0;
        if (parameter is string s && double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out var d))
            left = d;
        return value is true ? new Thickness(left, 0, 0, 0) : new Thickness(0);
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => throw new NotSupportedException();
}