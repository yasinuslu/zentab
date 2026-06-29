using System;
using System.Windows.Threading;

namespace ZenTab;

/// <summary>
/// Glues the keyboard hook, the warm window state, and the overlay together:
/// summon → cycle → commit / cancel / close / quit. Holds no real state beyond
/// "is the overlay up" and the mode it was summoned in.
/// </summary>
public sealed class SwitcherController : IDisposable
{
    private readonly KeyboardHook _hook;
    private readonly WindowService _windows;
    private readonly OverlayWindow _overlay;

    private bool _visible;

    public HotkeyProfile Profile { get; }

    public SwitcherController(ZenConfig config, Dispatcher dispatcher)
    {
        Profile = config.BuildProfile();
        _windows = new WindowService();
        _overlay = new OverlayWindow();
        _hook = new KeyboardHook(Profile, dispatcher);

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
        if (!_visible)
            Summon(mode);
        else if (reverse)
            _overlay.MovePrev();
        else
            _overlay.MoveNext();
    }

    private void Summon(SwitchMode mode)
    {
        var foreground = Native.GetForegroundWindow();
        var (entries, initial) = _windows.Build(mode, foreground);
        if (entries.Count == 0) return; // nothing to switch to — stay invisible

        _overlay.Show(entries, initial);
        _visible = true;
    }

    private void Commit()
    {
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
        if (!_visible) return;
        Hide();
    }

    private void CloseOrQuit(bool quitApp)
    {
        if (!_visible) return;
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
