using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using MouseEventArgs = System.Windows.Input.MouseEventArgs;
using Point = System.Windows.Point;

namespace ZenTab;

/// <summary>
/// The switcher panel: a borderless, top-most, non-activating, content-sized window that
/// floats on the monitor under the cursor, over a translucent <see cref="DimWindow"/>. It
/// shows the cards with DWM live thumbnails. It never takes focus, so the real foreground
/// app stays put until the user commits (release-to-switch, hover-to-select, click-to-switch).
/// </summary>
public partial class OverlayWindow : Window
{
    private static readonly Duration FadeIn = new(TimeSpan.FromMilliseconds(110));
    private static readonly Duration FadeOut = new(TimeSpan.FromMilliseconds(90));

    private sealed record Thumb(nint Id, FrameworkElement Element, Native.SIZE Source);

    private readonly DimWindow _dim = new();
    private readonly WindowInteropHelper _interop;
    private readonly List<Thumb> _thumbs = new();
    private List<SwitchEntry> _entries = new();
    private bool _closing;
    private bool _everShown;

    /// <summary>Mouse-click commit on a card.</summary>
    public event Action<SwitchEntry>? Committed;

    public OverlayWindow()
    {
        InitializeComponent();
        _interop = new WindowInteropHelper(this);
        Cards.AddHandler(ScrollViewer.ScrollChangedEvent, new ScrollChangedEventHandler(OnScroll));

        // Cap the panel so a crowded list wraps + scrolls instead of overflowing the screen.
        Cards.MaxWidth = SystemParameters.PrimaryScreenWidth * 0.85;
        Cards.MaxHeight = SystemParameters.PrimaryScreenHeight * 0.8;
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        // Hide from our own enumeration and never steal activation.
        var hwnd = _interop.Handle;
        long ex = Native.GetWindowLongPtr(hwnd, Native.GWL_EXSTYLE).ToInt64();
        ex |= Native.WS_EX_TOOLWINDOW | Native.WS_EX_NOACTIVATE;
        ex &= ~Native.WS_EX_APPWINDOW;
        Native.SetWindowLongPtr(hwnd, Native.GWL_EXSTYLE, (nint)ex);

        // Rounded corners + native soft shadow so the panel reads as a floating card, not a
        // hard-edged rectangle pasted over the dim (Win11; harmless on older Windows).
        Native.RoundCorners(hwnd);
    }

    public SwitchEntry? Selected => Cards.SelectedItem as SwitchEntry;

    public void Show(IReadOnlyList<SwitchEntry> entries, int selectedIndex, SwitchMode mode, string keyGlyphs)
    {
        ClearThumbs();
        _entries = new List<SwitchEntry>(entries);
        Cards.ItemsSource = _entries;
        Cards.SelectedIndex = _entries.Count == 0 ? -1 : Math.Clamp(selectedIndex, 0, _entries.Count - 1);
        EmptyLabel.Visibility = _entries.Count == 0 ? Visibility.Visible : Visibility.Collapsed;

        // Header chrome: the trigger pill, the mode label, and the count.
        KeyPillText.Text = keyGlyphs;
        ModeLabel.Text = ModeLabelText(mode);
        CountText.Text = CountLabelText(mode, _entries.Count);

        _dim.ShowDim();

        _closing = false;
        Scene.BeginAnimation(OpacityProperty, null);
        Scene.Opacity = 0;

        // First display must go through Show() so the HWND / PresentationSource exists
        // before we measure & position. After that we just toggle visibility.
        if (!_everShown)
        {
            Owner = _dim; // keep the panel above the dim
            base.Show();
            _everShown = true;
        }
        else
        {
            Visibility = Visibility.Visible;
        }
        Topmost = true;

        UpdateLayout(); // finalize SizeToContent so ActualWidth/Height are correct
        CenterOnCursorMonitor();

        Scene.BeginAnimation(OpacityProperty, new DoubleAnimation(1, FadeIn));
        ScrollSelectionIntoView();
        Dispatcher.BeginInvoke(PlaceThumbnails, System.Windows.Threading.DispatcherPriority.Loaded);
    }

    public void Dismiss()
    {
        if (_closing || Visibility != Visibility.Visible) return;
        _closing = true;
        ClearThumbs(); // live thumbnails would otherwise linger over the fade
        _dim.HideDim();

        var fade = new DoubleAnimation(0, FadeOut);
        fade.Completed += (_, _) =>
        {
            if (_closing) Visibility = Visibility.Hidden; // Hidden keeps the HWND for next time
        };
        Scene.BeginAnimation(OpacityProperty, fade);
    }

    public void MoveNext() => Step(+1);
    public void MovePrev() => Step(-1);

    private void Step(int delta)
    {
        int n = _entries.Count;
        if (n == 0) return;
        int i = Cards.SelectedIndex < 0 ? 0 : Cards.SelectedIndex;
        Cards.SelectedIndex = ((i + delta) % n + n) % n;
        ScrollSelectionIntoView();
    }

    /// <summary>Select a tile by its 0-based index (the 1…9 keyboard jump). False if out of range.</summary>
    public bool SelectIndex(int i)
    {
        if (i < 0 || i >= _entries.Count) return false;
        Cards.SelectedIndex = i;
        ScrollSelectionIntoView();
        return true;
    }

    private static string ModeLabelText(SwitchMode mode) => mode switch
    {
        SwitchMode.Apps => "Other apps",
        SwitchMode.AppWindows => "Current app",
        SwitchMode.Everything => "Everything",
        _ => string.Empty,
    };

    private static string CountLabelText(SwitchMode mode, int n)
    {
        // Apps mode lists apps (one entry per app); the other modes list windows.
        string noun = mode == SwitchMode.Apps ? "app" : "window";
        return $"{n} {noun}{(n == 1 ? string.Empty : "s")}";
    }

    /// <summary>Drop the current selection in place (after closing a window); keep the panel up.</summary>
    public bool RemoveSelected()
    {
        int i = Cards.SelectedIndex;
        if (i < 0 || i >= _entries.Count) return false;

        ClearThumbs();
        _entries.RemoveAt(i);
        Cards.ItemsSource = null;
        Cards.ItemsSource = _entries;
        if (_entries.Count == 0) return false;

        Cards.SelectedIndex = Math.Min(i, _entries.Count - 1);
        UpdateLayout();
        CenterOnCursorMonitor();
        ScrollSelectionIntoView();
        Dispatcher.BeginInvoke(PlaceThumbnails, System.Windows.Threading.DispatcherPriority.Loaded);
        return true;
    }

    private void ScrollSelectionIntoView()
    {
        if (Cards.SelectedItem != null) Cards.ScrollIntoView(Cards.SelectedItem);
    }

    // ---- Mouse: hover follows selection, click commits (last input wins) ----

    private void OnItemMouseEnter(object sender, MouseEventArgs e)
    {
        if (sender is ListBoxItem item) item.IsSelected = true;
    }

    private void OnItemMouseUp(object sender, MouseButtonEventArgs e)
    {
        if (Selected is { } entry) Committed?.Invoke(entry);
    }

    private void OnScroll(object sender, ScrollChangedEventArgs e) => UpdateThumbnailRects();

    // ---- Geometry ----

    private void CenterOnCursorMonitor()
    {
        // Center the panel on the monitor under the cursor. (Uniform-DPI assumption; mixed-DPI
        // multi-monitor is a known refinement.)
        var dpi = VisualTreeHelper.GetDpi(this);
        var work = Native.CursorMonitorWorkArea();
        double cx = (work.Left + work.Right) / 2.0;
        double cy = (work.Top + work.Bottom) / 2.0;
        Left = cx / dpi.DpiScaleX - ActualWidth / 2;
        Top = cy / dpi.DpiScaleY - ActualHeight / 2;
    }

    // ---- DWM live thumbnails ----

    private void PlaceThumbnails()
    {
        ClearThumbs();
        var hwnd = _interop.Handle;
        if (hwnd == 0 || Visibility != Visibility.Visible) return;

        Cards.UpdateLayout();
        var winOrigin = PointToScreen(new Point(0, 0));

        for (int i = 0; i < _entries.Count; i++)
        {
            if (Cards.ItemContainerGenerator.ContainerFromIndex(i) is not ListBoxItem container) continue;
            if (FindThumb(container) is not { ActualWidth: > 0 } element) continue;

            if (Native.DwmRegisterThumbnail(hwnd, _entries[i].Primary, out nint id) != 0) continue;
            Native.DwmQueryThumbnailSourceSize(id, out var size);

            var thumb = new Thumb(id, element, size);
            _thumbs.Add(thumb);
            Apply(thumb, winOrigin);
        }
    }

    private void UpdateThumbnailRects()
    {
        if (_thumbs.Count == 0 || Visibility != Visibility.Visible) return;
        var winOrigin = PointToScreen(new Point(0, 0));
        foreach (var thumb in _thumbs) Apply(thumb, winOrigin);
    }

    private void Apply(Thumb thumb, Point winOrigin)
    {
        Point tl = thumb.Element.PointToScreen(new Point(0, 0));
        Point br = thumb.Element.PointToScreen(new Point(thumb.Element.ActualWidth, thumb.Element.ActualHeight));

        var place = new Native.RECT
        {
            Left = (int)Math.Round(tl.X - winOrigin.X),
            Top = (int)Math.Round(tl.Y - winOrigin.Y),
            Right = (int)Math.Round(br.X - winOrigin.X),
            Bottom = (int)Math.Round(br.Y - winOrigin.Y),
        };

        var props = new Native.DWM_THUMBNAIL_PROPERTIES
        {
            dwFlags = Native.DWM_TNP_RECTDESTINATION | Native.DWM_TNP_VISIBLE
                      | Native.DWM_TNP_OPACITY | Native.DWM_TNP_SOURCECLIENTAREAONLY,
            opacity = 255,
            fVisible = true,
            fSourceClientAreaOnly = true,
            rcDestination = FitPreservingAspect(place, thumb.Source),
        };
        Native.DwmUpdateThumbnailProperties(thumb.Id, ref props);
    }

    /// <summary>Letterbox the source into the placeholder rect so thumbnails aren't stretched.</summary>
    private static Native.RECT FitPreservingAspect(Native.RECT box, Native.SIZE src)
    {
        int boxW = box.Right - box.Left, boxH = box.Bottom - box.Top;
        if (src.cx <= 0 || src.cy <= 0 || boxW <= 0 || boxH <= 0) return box;

        double scale = Math.Min((double)boxW / src.cx, (double)boxH / src.cy);
        int w = (int)Math.Round(src.cx * scale);
        int h = (int)Math.Round(src.cy * scale);
        int x = box.Left + (boxW - w) / 2;
        int y = box.Top + (boxH - h) / 2;
        return new Native.RECT { Left = x, Top = y, Right = x + w, Bottom = y + h };
    }

    private void ClearThumbs()
    {
        foreach (var thumb in _thumbs) Native.DwmUnregisterThumbnail(thumb.Id);
        _thumbs.Clear();
    }

    private static FrameworkElement? FindThumb(DependencyObject root)
    {
        int count = VisualTreeHelper.GetChildrenCount(root);
        for (int i = 0; i < count; i++)
        {
            var child = VisualTreeHelper.GetChild(root, i);
            if (child is FrameworkElement { Name: "Thumb" } found) return found;
            if (FindThumb(child) is { } nested) return nested;
        }
        return null;
    }
}
