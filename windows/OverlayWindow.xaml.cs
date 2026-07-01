using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using MouseEventArgs = System.Windows.Input.MouseEventArgs;

namespace ZenTab;

/// <summary>
/// The switcher panel: a borderless, top-most, non-activating, content-sized window that
/// floats on the monitor under the cursor, over a translucent <see cref="DimWindow"/>. Each
/// card shows a cached static window snapshot (warmed on idle by <see cref="WindowService"/>)
/// so previews paint instantly. It never takes focus, so the real foreground app stays put
/// until the user commits (release-to-switch, hover-to-select, click-to-switch).
/// </summary>
public partial class OverlayWindow : Window
{
    private static readonly Duration FadeIn = new(TimeSpan.FromMilliseconds(60));
    private static readonly Duration FadeOut = new(TimeSpan.FromMilliseconds(45));

    private readonly DimWindow _dim = new();
    private readonly WindowInteropHelper _interop;
    private List<SwitchEntry> _entries = new();
    private bool _closing;
    private bool _everShown;
    private bool _prepared;  // content is built + rendered off-screen, waiting to reveal
    private bool _revealed;  // currently on-screen

    /// <summary>Mouse-click commit on a card.</summary>
    public event Action<SwitchEntry>? Committed;

    public OverlayWindow()
    {
        InitializeComponent();
        _interop = new WindowInteropHelper(this);

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

    /// <summary>
    /// Build the panel's content and render it fully off-screen — while the trigger is still being
    /// held, before the reveal. This is the expensive half (regenerating the card containers, the
    /// layout pass, uploading the preview image textures to the GPU); doing it here, during the
    /// hold's dead time, means <see cref="Reveal"/> is just a move-on-screen with no first-frame
    /// hitch. (Web analogy: keep the component mounted and rendered, then swap it into view.)
    /// </summary>
    public void Prepare(IReadOnlyList<SwitchEntry> entries, int selectedIndex, SwitchMode mode, string keyGlyphs)
    {
        if (!_everShown) Prewarm();

        _entries = new List<SwitchEntry>(entries);
        Cards.ItemsSource = _entries;
        Cards.SelectedIndex = _entries.Count == 0 ? -1 : Math.Clamp(selectedIndex, 0, _entries.Count - 1);
        EmptyLabel.Visibility = _entries.Count == 0 ? Visibility.Visible : Visibility.Collapsed;

        // Header chrome: the trigger pill, the mode label, and the count.
        KeyPillText.Text = keyGlyphs;
        ModeLabel.Text = ModeLabelText(mode);
        CountText.Text = CountLabelText(mode, _entries.Count);

        // Render off-screen at full opacity so the visual tree + preview textures are realized on
        // the GPU now, not at reveal. Parked far off any monitor, so nothing shows.
        Left = Top = -32000;
        Visibility = Visibility.Visible;
        Scene.BeginAnimation(OpacityProperty, null);
        Scene.Opacity = 1;
        UpdateLayout(); // force measure/arrange (finalizes SizeToContent) during the hold
        _prepared = true;
        _revealed = false;
    }

    /// <summary>
    /// Swap the pre-rendered panel into view: fade the dim in, position on the cursor's monitor,
    /// and fade the (already-rendered) content up. No content build, layout, or texture upload
    /// happens here — that was all done in <see cref="Prepare"/>.
    /// </summary>
    public void Reveal()
    {
        if (!_prepared) return;
        _closing = false;
        _revealed = true;

        _dim.ShowDim();

        Scene.BeginAnimation(OpacityProperty, null);
        Scene.Opacity = 0;
        Topmost = true;
        CenterOnCursorMonitor(); // move on-screen; size was already finalized in Prepare
        Scene.BeginAnimation(OpacityProperty, new DoubleAnimation(1, FadeIn));
        ScrollSelectionIntoView();
    }

    /// <summary>Drop a prepared-but-never-revealed panel (a quick tap that switched invisibly)
    /// back to the idle hidden state, so a topmost window isn't left parked off-screen.</summary>
    public void Discard()
    {
        if (_revealed || !_prepared) return;
        _prepared = false;
        Visibility = Visibility.Hidden;
        Left = Top = -32000;
    }

    /// <summary>
    /// Warm both windows offscreen at startup — realize the HWNDs, enable acrylic, and run a
    /// full layout pass so the visual tree and card template are JIT-compiled ahead of time.
    /// Without this the *first* summon pays all of that on the keypress and overshoots the show
    /// budget; after it, every summon takes the fast visibility-toggle path. Runs at Background
    /// priority (see <see cref="SwitcherController"/>) so it never delays app launch.
    /// </summary>
    public void Prewarm()
    {
        if (_everShown) return;

        _dim.Prewarm();  // the owner must be realized before the panel can adopt it
        Owner = _dim;

        _entries = new List<SwitchEntry>();
        Cards.ItemsSource = _entries;

        Left = Top = -32000; // fully offscreen; never visible
        Opacity = 0;
        Scene.Opacity = 0;
        base.Show();
        UpdateLayout(); // force the visual tree + template to realize now, not on first summon
        Visibility = Visibility.Hidden;
        Opacity = 1;    // restore for the real (visibility-toggled) shows
        _everShown = true;
    }

    public void Dismiss()
    {
        if (_closing || !_revealed) return;
        _closing = true;
        _revealed = false;
        _prepared = false;
        _dim.HideDim();

        var fade = new DoubleAnimation(0, FadeOut);
        fade.Completed += (_, _) =>
        {
            // Hidden keeps the HWND warm for next time; park off-screen so it never flashes.
            if (_closing) { Visibility = Visibility.Hidden; Left = Top = -32000; }
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

        _entries.RemoveAt(i);
        Cards.ItemsSource = null;
        Cards.ItemsSource = _entries;
        if (_entries.Count == 0) return false;

        Cards.SelectedIndex = Math.Min(i, _entries.Count - 1);
        UpdateLayout();
        CenterOnCursorMonitor();
        ScrollSelectionIntoView();
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
}
