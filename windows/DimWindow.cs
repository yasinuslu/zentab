using System;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Animation;
using Color = System.Windows.Media.Color;

namespace ZenTab;

/// <summary>
/// The translucent dim behind the switcher — a layered, see-through window spanning every
/// monitor so the world recedes (you can still see it, dimmed) while you choose. It carries
/// no content and no thumbnails; the floating <see cref="OverlayWindow"/> panel sits on top.
/// (Thumbnails can't render on a layered window, which is exactly why these are two windows.)
/// </summary>
public sealed class DimWindow : Window
{
    private static readonly Duration FadeIn = new(TimeSpan.FromMilliseconds(120));
    private static readonly Duration FadeOut = new(TimeSpan.FromMilliseconds(90));

    private bool _everShown;
    private bool _visible;

    public DimWindow()
    {
        Title = "ZenTab Dim";
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = new SolidColorBrush(Color.FromArgb(0x9E, 0x07, 0x07, 0x0C));
        ShowInTaskbar = false;
        ShowActivated = false;
        Topmost = true;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.Manual;
        Opacity = 0;
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        var hwnd = new System.Windows.Interop.WindowInteropHelper(this).Handle;
        long ex = Native.GetWindowLongPtr(hwnd, Native.GWL_EXSTYLE).ToInt64();
        ex |= Native.WS_EX_TOOLWINDOW | Native.WS_EX_NOACTIVATE;
        ex &= ~Native.WS_EX_APPWINDOW;
        Native.SetWindowLongPtr(hwnd, Native.GWL_EXSTYLE, (nint)ex);
    }

    public void ShowDim()
    {
        Left = SystemParameters.VirtualScreenLeft;
        Top = SystemParameters.VirtualScreenTop;
        Width = SystemParameters.VirtualScreenWidth;
        Height = SystemParameters.VirtualScreenHeight;

        _visible = true;
        BeginAnimation(OpacityProperty, null);
        Opacity = 0;
        if (!_everShown) { Show(); _everShown = true; }
        else Visibility = Visibility.Visible;
        Topmost = true;
        BeginAnimation(OpacityProperty, new DoubleAnimation(1, FadeIn));
    }

    public void HideDim()
    {
        if (!_visible) return;
        _visible = false;
        var fade = new DoubleAnimation(0, FadeOut);
        fade.Completed += (_, _) => { if (!_visible) Visibility = Visibility.Hidden; };
        BeginAnimation(OpacityProperty, fade);
    }
}
