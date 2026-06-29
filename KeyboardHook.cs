using System;
using System.Windows.Threading;

namespace ZenTab;

/// <summary>
/// Low-level keyboard hook that replaces the native switching gestures. The hook
/// callback runs on the UI thread and is kept on a strict diet: it decides whether to
/// swallow a key synchronously (cheap modifier checks via GetAsyncKeyState) and pushes
/// the actual work onto the dispatcher queue, so it never adds input lag (see VISION.md).
/// </summary>
public sealed class KeyboardHook : IDisposable
{
    private readonly HotkeyProfile _profile;
    private readonly Dispatcher _dispatcher;
    private Native.LowLevelKeyboardProc? _proc;
    private nint _hook;

    /// <summary>Raised for a summon/cycle gesture: the requested mode and whether to go in reverse.</summary>
    public event Action<SwitchMode, bool>? Navigate;

    /// <summary>Modifier released — commit to the current selection.</summary>
    public event Action? Commit;

    /// <summary>Escape — dismiss without switching.</summary>
    public event Action? Cancel;

    /// <summary>Delete — close the selected window.</summary>
    public event Action? CloseWindow;

    /// <summary>Shift+Delete — quit the selected app (close all its windows).</summary>
    public event Action? QuitApp;

    /// <summary>True while the overlay is up — enables capture of Esc/Del/arrows and commit-on-release.</summary>
    public bool Capturing { get; set; }

    public KeyboardHook(HotkeyProfile profile, Dispatcher dispatcher)
    {
        _profile = profile;
        _dispatcher = dispatcher;
    }

    public void Start()
    {
        _proc = HookProc;
        _hook = Native.SetWindowsHookEx(Native.WH_KEYBOARD_LL, _proc, Native.GetModuleHandle(null), 0);
        if (_hook == 0)
            throw new InvalidOperationException("Failed to install the low-level keyboard hook.");
    }

    private nint HookProc(int nCode, nint wParam, nint lParam)
    {
        if (nCode >= 0 && TryHandle((int)wParam, lParam))
            return 1; // swallow

        return Native.CallNextHookEx(_hook, nCode, wParam, lParam);
    }

    /// <summary>Returns true if the key should be swallowed. Must stay fast.</summary>
    private bool TryHandle(int msg, nint lParam)
    {
        bool down = msg is Native.WM_KEYDOWN or Native.WM_SYSKEYDOWN;
        bool up = msg is Native.WM_KEYUP or Native.WM_SYSKEYUP;
        if (!down && !up) return false;

        var data = System.Runtime.InteropServices.Marshal.PtrToStructure<Native.KBDLLHOOKSTRUCT>(lParam);
        int vk = (int)data.vkCode;

        if (down)
        {
            // Summon / cycle gesture — pick the most specific matching trigger.
            HotkeyProfile.Trigger? best = null;
            foreach (var t in _profile.Triggers)
                if (t.Key == vk && AllHeld(t.Mods) && (best is null || t.Mods.Length > best.Mods.Length))
                    best = t;

            if (best is not null)
            {
                // Own Capturing synchronously so a quick tap (release before the async
                // summon runs) still commits — the commit is queued after the summon.
                Capturing = true;
                bool reverse = Native.IsKeyDown(Native.VK_SHIFT);
                Post(() => Navigate?.Invoke(best.Mode, reverse));
                return true;
            }

            if (Capturing)
            {
                switch (vk)
                {
                    case Native.VK_ESCAPE:
                        Capturing = false;
                        Post(() => Cancel?.Invoke());
                        return true;
                    case Native.VK_DELETE:
                        if (Native.IsKeyDown(Native.VK_SHIFT)) Post(() => QuitApp?.Invoke());
                        else Post(() => CloseWindow?.Invoke());
                        return true;
                    case Native.VK_TAB:
                    case Native.VK_LEFT:
                    case Native.VK_RIGHT:
                        // Tab/→ advance, Shift+Tab/← reverse — works in every mode (incl. dev).
                        bool reverse = vk == Native.VK_LEFT
                            || (vk == Native.VK_TAB && Native.IsKeyDown(Native.VK_SHIFT));
                        Post(() => Navigate?.Invoke(SwitchMode.Apps, reverse));
                        return true;
                }
            }

            return false;
        }

        // key up — commit when one of the held commit-modifiers is released.
        // NB: we test the released key's own vkCode, NOT GetAsyncKeyState — inside a
        // low-level hook the async state for the key being released still reads "down"
        // (the hook runs before the system applies the event), so polling it would never
        // detect the release. This was why releasing Alt didn't switch.
        if (Capturing && IsCommitModifier(vk))
        {
            Capturing = false;
            Post(() => Commit?.Invoke());
        }

        return false; // never swallow the modifier release — the app must see it
    }

    private bool IsCommitModifier(int vk)
    {
        string? token = TokenForVk(vk);
        return token != null && Array.IndexOf(_profile.CommitMods, token) >= 0;
    }

    private static string? TokenForVk(int vk) => vk switch
    {
        Native.VK_LMENU or Native.VK_RMENU or Native.VK_MENU => "alt",
        Native.VK_LCONTROL or Native.VK_RCONTROL or Native.VK_CONTROL => "ctrl",
        Native.VK_LSHIFT or Native.VK_RSHIFT or Native.VK_SHIFT => "shift",
        Native.VK_LWIN or Native.VK_RWIN => "win",
        _ => null,
    };

    private static bool AllHeld(string[] mods)
    {
        foreach (var m in mods)
            if (!IsModDown(m)) return false;
        return true;
    }

    private static bool IsModDown(string mod) => mod switch
    {
        "alt" => Native.IsKeyDown(Native.VK_MENU),
        "ctrl" => Native.IsKeyDown(Native.VK_CONTROL),
        "shift" => Native.IsKeyDown(Native.VK_SHIFT),
        "win" => Native.IsKeyDown(Native.VK_LWIN) || Native.IsKeyDown(Native.VK_RWIN),
        _ => false,
    };

    // Off the hot path: run the actual handling after the hook returns.
    private void Post(Action action) => _dispatcher.BeginInvoke(action, DispatcherPriority.Send);

    public void Dispose()
    {
        if (_hook != 0)
        {
            Native.UnhookWindowsHookEx(_hook);
            _hook = 0;
        }
        _proc = null;
    }
}
