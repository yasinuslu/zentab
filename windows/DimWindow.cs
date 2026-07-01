using System;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Animation;
// WinForms is enabled (tray icon), so System.Drawing is implicitly imported and collides
// with WPF on these names — pin them to the WPF types.
using Brush = System.Windows.Media.Brush;
using Color = System.Windows.Media.Color;
using Point = System.Windows.Point;

namespace ZenTab;

/// <summary>
/// The spotlight backdrop behind the switcher — a layered window spanning every monitor so
/// the world recedes (still visible, dimmed + blurred) while you choose. It carries no content
/// and no thumbnails; the floating <see cref="OverlayWindow"/> panel sits on top. (Thumbnails
/// can't render on a layered window, which is exactly why these are two windows.)
///
/// The blur is a GPU acrylic via <see cref="Native.EnableAcrylicBlur"/> (VISION.md: "GPU, not
/// CPU, for visuals"); the dark scrim is the acrylic tint, and a radial gradient on top lifts
/// the top-left and sinks the corners so it reads like the website's directional spotlight.
/// On a build without acrylic support the gradient alone still dims (just without blur).
/// </summary>
public sealed class DimWindow : Window
{
    private static readonly Duration FadeIn = new(TimeSpan.FromMilliseconds(60));
    private static readonly Duration FadeOut = new(TimeSpan.FromMilliseconds(45));

    // Acrylic tint = the website scrim rgba(6,7,10,0.55), as 0xAABBGGRR.
    private const uint ScrimTint = 0x8C0A0706;

    private bool _everShown;
    private bool _visible;

    public DimWindow()
    {
        Title = "ZenTab Dim";
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = BuildDim();
        ShowInTaskbar = false;
        ShowActivated = false;
        Topmost = true;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.Manual;
        Opacity = 0;
    }

    /// <summary>The directional dim painted over the acrylic: a faint blue lift at the top-left
    /// origin, transparent through the middle (so the blurred world shows), darkening into the
    /// corners — the website's radial spotlight (Overlay.tsx) adapted to ride on real blur.</summary>
    private static Brush BuildDim()
    {
        var brush = new RadialGradientBrush
        {
            GradientOrigin = new Point(0.32, 0.15),
            Center = new Point(0.32, 0.15),
            RadiusX = 1.25,
            RadiusY = 1.25,
        };
        brush.GradientStops.Add(new GradientStop(Color.FromArgb(0x1F, 0x1F, 0x35, 0x50), 0.0)); // (31,53,80) @ .12 lift
        brush.GradientStops.Add(new GradientStop(Color.FromArgb(0x00, 0x06, 0x07, 0x0A), 0.55)); // transparent
        brush.GradientStops.Add(new GradientStop(Color.FromArgb(0x73, 0x06, 0x07, 0x0A), 1.0));  // (6,7,10) @ .45 corners
        brush.Freeze();
        return brush;
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        var hwnd = new System.Windows.Interop.WindowInteropHelper(this).Handle;
        long ex = Native.GetWindowLongPtr(hwnd, Native.GWL_EXSTYLE).ToInt64();
        ex |= Native.WS_EX_TOOLWINDOW | Native.WS_EX_NOACTIVATE;
        ex &= ~Native.WS_EX_APPWINDOW;
        Native.SetWindowLongPtr(hwnd, Native.GWL_EXSTYLE, (nint)ex);

        // The GPU blur behind the dim — the spotlight effect (VISION.md performance pillar).
        // Aero blur-behind, NOT acrylic: acrylic re-composites the whole virtual screen on every
        // reveal, a measured ~100–185ms GPU stall that made the overlay feel laggy; blur-behind is
        // the same idea at ~a third of the cost (see the timing work behind this choice).
        Native.EnableBlur(hwnd, ScrimTint, acrylic: false);
    }

    /// <summary>
    /// Realize the HWND and enable acrylic (both happen in <see cref="OnSourceInitialized"/>)
    /// offscreen at startup, so the first real summon skips window-creation cost and lands
    /// within the show budget. Opacity is 0 throughout, so nothing ever flashes on screen.
    /// </summary>
    public void Prewarm()
    {
        if (_everShown) return;
        Left = Top = -32000; // fully offscreen; belt-and-braces with Opacity 0
        Width = Height = 1;
        Show(); // Opacity is 0 (set in the ctor), so this is invisible
        _everShown = true;
        Visibility = Visibility.Hidden;
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
