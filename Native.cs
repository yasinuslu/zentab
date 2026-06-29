using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace ZenTab;

/// <summary>
/// Thin Win32/DWM interop layer. Everything platform-specific lives here so the
/// rest of the app stays plain C#. Kept deliberately lean — ZenTab is resident all
/// day, so these calls sit on the hot path of summon and must stay cheap.
/// </summary>
internal static class Native
{
    // ---- Window enumeration ---------------------------------------------------
    public delegate bool EnumWindowsProc(nint hWnd, nint lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, nint lParam);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(nint hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsWindow(nint hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsIconic(nint hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowTextLength(nint hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(nint hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll")]
    public static extern nint GetWindow(nint hWnd, uint uCmd);

    [DllImport("user32.dll")]
    public static extern nint GetWindowLongPtr(nint hWnd, int nIndex);

    [DllImport("user32.dll")]
    public static extern nint SetWindowLongPtr(nint hWnd, int nIndex, nint dwNewLong);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(nint hWnd, out uint lpdwProcessId);

    // ---- Activation -----------------------------------------------------------
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(nint hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(nint hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern nint GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern bool BringWindowToTop(nint hWnd);

    [DllImport("user32.dll")]
    public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);

    [DllImport("kernel32.dll")]
    public static extern uint GetCurrentThreadId();

    // ---- Process image path (fast, robust across bitness/elevation) ------------
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern nint OpenProcess(uint access, bool inherit, uint pid);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(nint handle);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool QueryFullProcessImageName(nint process, uint flags, StringBuilder buffer, ref uint size);

    public const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;

    // ---- Messaging (close window) ---------------------------------------------
    [DllImport("user32.dll")]
    public static extern bool PostMessage(nint hWnd, uint msg, nint wParam, nint lParam);

    // ---- DWM ------------------------------------------------------------------
    [DllImport("dwmapi.dll")]
    public static extern int DwmGetWindowAttribute(nint hWnd, int dwAttribute, out int pvAttribute, int cbAttribute);

    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(nint hWnd, int dwAttribute, ref int pvAttribute, int cbAttribute);

    public const int DWMWA_WINDOW_CORNER_PREFERENCE = 33; // Win11+: round the window corners
    public const int DWMWCP_ROUND = 2;

    /// <summary>Round a window's corners at the GPU/DWM level (Win11; no-op on older Windows).
    /// Also restores the native soft drop shadow on a borderless window.</summary>
    public static void RoundCorners(nint hWnd)
    {
        int pref = DWMWCP_ROUND;
        DwmSetWindowAttribute(hWnd, DWMWA_WINDOW_CORNER_PREFERENCE, ref pref, sizeof(int));
    }

    // ---- Monitors / cursor ----------------------------------------------------
    [DllImport("user32.dll")]
    public static extern nint MonitorFromWindow(nint hWnd, uint dwFlags);

    [DllImport("user32.dll")]
    public static extern nint MonitorFromPoint(POINT pt, uint dwFlags);

    [DllImport("user32.dll")]
    public static extern bool GetCursorPos(out POINT lpPoint);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern bool GetMonitorInfo(nint hMonitor, ref MONITORINFO lpmi);

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X; public int Y; }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    public struct SIZE { public int cx; public int cy; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public struct MONITORINFO
    {
        public int cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
    }

    /// <summary>The monitor handle under the mouse cursor — ZenTab's notion of "current monitor".</summary>
    public static nint CursorMonitor()
    {
        GetCursorPos(out var p);
        return MonitorFromPoint(p, MONITOR_DEFAULTTONEAREST);
    }

    /// <summary>Work area (excludes taskbar) of the monitor under the mouse cursor, in pixels.</summary>
    public static RECT CursorMonitorWorkArea()
    {
        var mi = new MONITORINFO { cbSize = Marshal.SizeOf<MONITORINFO>() };
        GetMonitorInfo(CursorMonitor(), ref mi);
        return mi.rcWork;
    }

    // ---- DWM live thumbnails --------------------------------------------------
    [DllImport("dwmapi.dll")]
    public static extern int DwmRegisterThumbnail(nint dest, nint src, out nint thumbId);

    [DllImport("dwmapi.dll")]
    public static extern int DwmUnregisterThumbnail(nint thumbId);

    [DllImport("dwmapi.dll")]
    public static extern int DwmUpdateThumbnailProperties(nint thumbId, ref DWM_THUMBNAIL_PROPERTIES props);

    [DllImport("dwmapi.dll")]
    public static extern int DwmQueryThumbnailSourceSize(nint thumbId, out SIZE size);

    [StructLayout(LayoutKind.Sequential)]
    public struct DWM_THUMBNAIL_PROPERTIES
    {
        public int dwFlags;
        public RECT rcDestination;
        public RECT rcSource;
        public byte opacity;
        public bool fVisible;
        public bool fSourceClientAreaOnly;
    }

    public const int DWM_TNP_RECTDESTINATION = 0x1;
    public const int DWM_TNP_RECTSOURCE = 0x2;
    public const int DWM_TNP_OPACITY = 0x4;
    public const int DWM_TNP_VISIBLE = 0x8;
    public const int DWM_TNP_SOURCECLIENTAREAONLY = 0x10;

    // ---- Win-event hook (foreground tracking) ---------------------------------
    public delegate void WinEventDelegate(nint hWinEventHook, uint eventType, nint hWnd,
        int idObject, int idChild, uint dwEventThread, uint dwmsEventTime);

    [DllImport("user32.dll")]
    public static extern nint SetWinEventHook(uint eventMin, uint eventMax, nint hmodWinEventProc,
        WinEventDelegate lpfnWinEventProc, uint idProcess, uint idThread, uint dwFlags);

    [DllImport("user32.dll")]
    public static extern bool UnhookWinEvent(nint hWinEventHook);

    public const uint EVENT_SYSTEM_FOREGROUND = 0x0003;
    public const uint WINEVENT_OUTOFCONTEXT = 0x0000;

    // ---- Low-level keyboard hook ----------------------------------------------
    public delegate nint LowLevelKeyboardProc(int nCode, nint wParam, nint lParam);

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern nint SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, nint hMod, uint dwThreadId);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool UnhookWindowsHookEx(nint hhk);

    [DllImport("user32.dll")]
    public static extern nint CallNextHookEx(nint hhk, int nCode, nint wParam, nint lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern nint GetModuleHandle(string? lpModuleName);

    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);

    [StructLayout(LayoutKind.Sequential)]
    public struct KBDLLHOOKSTRUCT
    {
        public uint vkCode;
        public uint scanCode;
        public uint flags;
        public uint time;
        public nuint dwExtraInfo;
    }

    public const int WH_KEYBOARD_LL = 13;
    public const int WM_KEYDOWN = 0x0100;
    public const int WM_KEYUP = 0x0101;
    public const int WM_SYSKEYDOWN = 0x0104;
    public const int WM_SYSKEYUP = 0x0105;

    // Virtual key codes used by the hook.
    public const int VK_SHIFT = 0x10;
    public const int VK_CONTROL = 0x11;
    public const int VK_MENU = 0x12; // Alt (either side)
    public const int VK_LSHIFT = 0xA0;
    public const int VK_RSHIFT = 0xA1;
    public const int VK_LCONTROL = 0xA2;
    public const int VK_RCONTROL = 0xA3;
    public const int VK_LMENU = 0xA4;
    public const int VK_RMENU = 0xA5;
    public const int VK_LWIN = 0x5B;
    public const int VK_RWIN = 0x5C;
    public const int VK_TAB = 0x09;
    public const int VK_ESCAPE = 0x1B;
    public const int VK_DELETE = 0x2E;
    public const int VK_LEFT = 0x25;
    public const int VK_RIGHT = 0x27;
    public const int VK_OEM_3 = 0xC0; // backtick / tilde
    public const int VK_F1 = 0x70;

    public static bool IsKeyDown(int vk) => (GetAsyncKeyState(vk) & 0x8000) != 0;

    // ---- Constants ------------------------------------------------------------
    public const uint GW_OWNER = 4;

    public const int GWL_EXSTYLE = -20;
    public const long WS_EX_TOOLWINDOW = 0x00000080;
    public const long WS_EX_NOACTIVATE = 0x08000000;
    public const long WS_EX_APPWINDOW = 0x00040000;

    public const int DWMWA_CLOAKED = 14;
    public const int DWM_CLOAKED_APP = 0x1;       // app itself hid it (suspended UWP, etc.)
    public const int DWM_CLOAKED_SHELL = 0x2;     // shell hid it — e.g. on another virtual desktop
    public const int DWM_CLOAKED_INHERITED = 0x4;

    public const int SW_RESTORE = 9;

    public const uint MONITOR_DEFAULTTONEAREST = 2;

    public const uint WM_CLOSE = 0x0010;

    // ---- Helpers --------------------------------------------------------------

    /// <summary>
    /// Cheap, mode-independent test for an alt-tab-worthy top-level window: visible,
    /// not owned, not a tool window, has a title, and not minimized. Virtual-desktop
    /// and process scoping are applied by <see cref="WindowService"/> per mode.
    /// Minimized windows are excluded everywhere by design (see VISION.md).
    /// </summary>
    public static bool IsCandidate(nint hWnd)
    {
        if (!IsWindowVisible(hWnd)) return false;
        if (IsIconic(hWnd)) return false;
        if (GetWindow(hWnd, GW_OWNER) != 0) return false;

        long ex = GetWindowLongPtr(hWnd, GWL_EXSTYLE).ToInt64();
        if ((ex & WS_EX_TOOLWINDOW) != 0) return false;

        return GetWindowTextLength(hWnd) > 0;
    }

    public static IEnumerable<nint> EnumerateTopLevel()
    {
        var result = new List<nint>(256);
        EnumWindows((h, _) => { result.Add(h); return true; }, 0);
        return result;
    }

    /// <summary>0 if not cloaked, otherwise the DWM_CLOAKED_* reason bits.</summary>
    public static int CloakReason(nint hWnd) =>
        DwmGetWindowAttribute(hWnd, DWMWA_CLOAKED, out int cloaked, sizeof(int)) == 0 ? cloaked : 0;

    public static uint Pid(nint hWnd)
    {
        GetWindowThreadProcessId(hWnd, out uint pid);
        return pid;
    }

    public static nint Monitor(nint hWnd) => MonitorFromWindow(hWnd, MONITOR_DEFAULTTONEAREST);

    /// <summary>
    /// Full executable path of a process via QueryFullProcessImageName — much cheaper than
    /// Process.MainModule and it doesn't throw across 32/64-bit or elevation boundaries.
    /// </summary>
    public static string? ProcessPath(uint pid)
    {
        nint handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
        if (handle == 0) return null;
        try
        {
            var sb = new StringBuilder(1024);
            uint size = (uint)sb.Capacity;
            return QueryFullProcessImageName(handle, 0, sb, ref size) ? sb.ToString() : null;
        }
        finally
        {
            CloseHandle(handle);
        }
    }

    public static string Title(nint hWnd)
    {
        int len = GetWindowTextLength(hWnd);
        if (len == 0) return string.Empty;
        var sb = new StringBuilder(len + 1);
        GetWindowText(hWnd, sb, sb.Capacity);
        return sb.ToString();
    }

    /// <summary>Bring a window to the foreground, restoring it if minimized.</summary>
    public static void Activate(nint hWnd)
    {
        if (!IsWindow(hWnd)) return;
        if (IsIconic(hWnd)) ShowWindow(hWnd, SW_RESTORE);

        // SetForegroundWindow is rejected unless the calling thread shares input state
        // with the current foreground thread — attach input briefly to work around it.
        nint fg = GetForegroundWindow();
        uint fgThread = GetWindowThreadProcessId(fg, out _);
        uint thisThread = GetCurrentThreadId();
        uint targetThread = GetWindowThreadProcessId(hWnd, out _);

        bool attachedFg = fgThread != thisThread && AttachThreadInput(thisThread, fgThread, true);
        bool attachedTarget = targetThread != thisThread && targetThread != fgThread
            && AttachThreadInput(thisThread, targetThread, true);

        BringWindowToTop(hWnd);
        SetForegroundWindow(hWnd);

        if (attachedTarget) AttachThreadInput(thisThread, targetThread, false);
        if (attachedFg) AttachThreadInput(thisThread, fgThread, false);
    }

    /// <summary>Politely ask a window to close (WM_CLOSE — the app may prompt to save).</summary>
    public static void Close(nint hWnd)
    {
        if (IsWindow(hWnd)) PostMessage(hWnd, WM_CLOSE, 0, 0);
    }
}
