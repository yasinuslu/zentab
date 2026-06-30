using System;
using System.Globalization;
using System.Windows;
using System.Windows.Data;

namespace ZenTab;

/// <summary>
/// Maps a tile's 0-based <c>ItemsControl.AlternationIndex</c> to its 1-based label
/// ("1".."9"). Tiles past the ninth get no number (the keyboard jump shortcuts only run
/// 1-9), so this returns an empty string and the chip is hidden via
/// <see cref="IndexVisibilityConverter"/>.
/// </summary>
public sealed class OneBasedIndexConverter : IValueConverter
{
    public object? Convert(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        value is int i && i is >= 0 and < 9 ? (i + 1).ToString(CultureInfo.InvariantCulture) : string.Empty;

    public object? ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        System.Windows.Data.Binding.DoNothing; // qualified: WinForms also has a Binding type
}

/// <summary>Show the index chip only for the first nine tiles.</summary>
public sealed class IndexVisibilityConverter : IValueConverter
{
    public object? Convert(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        value is int i && i is >= 0 and < 9 ? Visibility.Visible : Visibility.Collapsed;

    public object? ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        System.Windows.Data.Binding.DoNothing; // qualified: WinForms also has a Binding type
}
