using System;
using System.Collections.Generic;
using System.Windows.Threading;

namespace ZenTab;

/// <summary>
/// Glues the keyboard hook, the warm window state, and the overlay together:
/// summon → cycle → commit / cancel / close / quit.
///
/// Like native Alt+Tab, a quick tap (press and release within <see cref="ShowDelayMs"/>)
/// switches straight to the MRU-previous window without ever flashing the overlay; the
/// overlay only appears if you keep holding, or tap again to start cycling.
/// </summary>
public sealed class SwitcherController : IDisposable
{
    private const int ShowDelayMs = 200;

    private readonly KeyboardHook _hook;
    private readonly WindowService _windows;
    private readonly OverlayWindow _overlay;
    private readonly DispatcherTimer _armTimer;

    // "Armed" = a summon is pending: entries are built but the overlay is held back until
    // the threshold elapses (or a second gesture arrives), so a quick tap stays invisible.
    private bool _armed;
    private bool _visible;
    private List<SwitchEntry> _armedEntries = new();
    private int _armedIndex;

    public HotkeyProfile Profile { get; }

    public SwitcherController(ZenConfig config, Dispatcher dispatcher)
    {
        Profile = config.BuildProfile();
        _windows = new WindowService();
        _overlay = new OverlayWindow();
        _hook = new KeyboardHook(Profile, dispatcher);

        _armTimer = new DispatcherTimer(DispatcherPriority.Normal, dispatcher)
        {
            Interval = TimeSpan.FromMilliseconds(ShowDelayMs),
        };
        _armTimer.Tick += (_, _) => Reveal();

        _hook.Navigate += OnNavigate;
        _hook.Commit += Commit;
        _hook.Cancel += Cancel;
        _hook.CloseWindow += () => CloseOrQuit(quitApp: false);
        _hook.QuitApp += () => CloseOrQuit(quitApp: true);
        _overlay.Committed += CommitTo;
    }

    public void Start()
    {
        _windows.Start();
        _hook.Start();
    }

    private void OnNavigate(SwitchMode mode, bool reverse)
    {
        if (_visible)
        {
            if (reverse) _overlay.MovePrev(); else _overlay.MoveNext();
            return;
        }

        if (_armed)
        {
            // A second gesture before the threshold — the user is cycling, so reveal now.
            Reveal();
            if (reverse) _overlay.MovePrev(); else _overlay.MoveNext();
            return;
        }

        Arm(mode);
    }

    private void Arm(SwitchMode mode)
    {
        var foreground = Native.GetForegroundWindow();
        var (entries, initial) = _windows.Build(mode, foreground);
        if (entries.Count == 0)
        {
            _hook.Capturing = false; // nothing to switch to — drop the gesture
            return;
        }

        _armedEntries = entries;
        _armedIndex = initial;
        _armed = true;
        _armTimer.Start();
    }

    private void Reveal()
    {
        if (!_armed) return;
        _armTimer.Stop();
        _armed = false;
        _overlay.Show(_armedEntries, _armedIndex);
        _visible = true;
    }

    private void Commit()
    {
        if (_armed)
        {
            // Quick tap — released before the threshold: switch without ever showing.
            _armTimer.Stop();
            _armed = false;
            _hook.Capturing = false;
            var entry = _armedIndex >= 0 && _armedIndex < _armedEntries.Count ? _armedEntries[_armedIndex] : null;
            if (entry is not null) Native.Activate(entry.Primary);
            return;
        }

        if (!_visible) return;
        CommitTo(_overlay.Selected);
    }

    private void CommitTo(SwitchEntry? entry)
    {
        if (!_visible) return;
        Hide();
        if (entry is not null) Native.Activate(entry.Primary);
    }

    private void Cancel()
    {
        if (_armed)
        {
            _armTimer.Stop();
            _armed = false;
            _hook.Capturing = false;
            return;
        }
        if (!_visible) return;
        Hide();
    }

    private void CloseOrQuit(bool quitApp)
    {
        if (!_visible) return; // only meaningful once the overlay is shown
        if (_overlay.Selected is not { } entry) return;

        if (quitApp)
            foreach (var h in entry.Handles) Native.Close(h);
        else
            Native.Close(entry.Primary);

        // Keep the overlay up; drop the entry so the list stays responsive.
        if (!_overlay.RemoveSelected())
            Hide();
    }

    private void Hide()
    {
        _visible = false;
        _hook.Capturing = false; // safety: in case we hid without a key release (e.g. mouse click)
        _overlay.Dismiss();
    }

    public void Dispose()
    {
        _hook.Dispose();
        _windows.Dispose();
    }
}
