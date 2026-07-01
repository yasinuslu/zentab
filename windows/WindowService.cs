using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace ZenTab;

/// <summary>
/// Keeps window state warm so summoning is near-instant (see VISION.md: never enumerate
/// cold or build heavy state on the keypress). It owns two cheap, idle-free signals:
/// a foreground win-event hook that maintains MRU recency, and a stable first-seen
/// sequence so the visible order never shuffles ("Slack is always 4th").
/// Builds the per-mode <see cref="SwitchEntry"/> list on summon.
/// </summary>
public sealed class WindowService : IDisposable
{
    // Stable display order: the order in which we first observed each window.
    private readonly Dictionary<nint, long> _firstSeen = new();
    private long _seenSeq;

    // MRU recency: bumped whenever a window becomes foreground.
    private readonly Dictionary<nint, long> _lastActive = new();
    private long _activeSeq;

    // Per-pid caches — process lookups are comparatively expensive; do them once.
    // Concurrent because a background warm-up fills them off the UI thread.
    private readonly ConcurrentDictionary<uint, string?> _pathByPid = new();
    private readonly ConcurrentDictionary<string, string> _friendlyByPath = new(StringComparer.OrdinalIgnoreCase);
    // App icons extracted from the exe, frozen so they can be built on the warm-up thread
    // and consumed on the UI thread. Null means "tried and couldn't resolve".
    private readonly ConcurrentDictionary<string, ImageSource?> _iconByPath = new(StringComparer.OrdinalIgnoreCase);

    // Static window snapshots (per hwnd), idle-warmed so a tile can paint an image immediately
    // instead of waiting for DWM to composite a live thumbnail. Frozen for cross-thread use.
    // Null means "captured, but blank" (e.g. a GPU window PrintWindow can't grab).
    private readonly ConcurrentDictionary<nint, ImageSource?> _previewByHwnd = new();

    // win-event hook (foreground changes) — near-zero idle cost, only fires on switch.
    private Native.WinEventDelegate? _winEventProc;
    private nint _winEventHook;

    // The window that currently holds the foreground — snapshotted the moment it loses it, so
    // every window is cached in the exact state you last left it (the "intelligent" cadence).
    private nint _foreground;

    // Low-frequency background refresh: keeps the active window's snapshot current, captures
    // windows that appeared since the last sweep, and prunes previews for windows that are gone.
    private System.Threading.Timer? _refreshTimer;
    private int _refreshing; // 0/1 gate so ticks never overlap
    private static readonly TimeSpan RefreshEvery = TimeSpan.FromSeconds(3);

    public void Start()
    {
        _winEventProc = OnForegroundChanged;
        _winEventHook = Native.SetWinEventHook(
            Native.EVENT_SYSTEM_FOREGROUND, Native.EVENT_SYSTEM_FOREGROUND,
            0, _winEventProc, 0, 0, Native.WINEVENT_OUTOFCONTEXT);

        // Seed recency with whatever is focused right now.
        _foreground = Native.GetForegroundWindow();
        Touch(_foreground);

        // Pre-warm the process caches + tile previews off the UI thread so the first summon is
        // already hot, then keep previews fresh on a low-frequency idle refresh.
        Task.Run(Warmup);
        _refreshTimer = new System.Threading.Timer(_ => RefreshPreviews(), null, RefreshEvery, RefreshEvery);
    }

    /// <summary>Resolve process paths/names and snapshot windows now, so summon stays cheap.</summary>
    private void Warmup()
    {
        try
        {
            foreach (var h in Native.EnumerateTopLevel())
            {
                if (!Native.IsCandidate(h)) continue;
                var path = PathOf(Native.Pid(h));
                if (path != null) { FriendlyName(path); IconForPath(path); }
                CapturePreview(h);
            }
        }
        catch
        {
            // Warm-up is best-effort; a failure just means the first summon pays the cost.
        }
    }

    private void OnForegroundChanged(nint hook, uint ev, nint hWnd, int idObject, int idChild, uint thread, uint time)
    {
        if (idObject != 0) return; // OBJID_WINDOW only
        Touch(hWnd);

        // Snapshot the window we just left, off the UI thread — it's now stable and is exactly
        // the state the user will want to recognize when they alt-tab. Capturing on switch (not
        // continuously) is the cheap, intelligent signal: every window gets cached as you leave it.
        nint outgoing = _foreground;
        _foreground = hWnd;
        if (outgoing != 0 && outgoing != hWnd)
            Task.Run(() => { try { if (Native.IsCandidate(outgoing)) CapturePreview(outgoing); } catch { } });
    }

    /// <summary>
    /// Idle refresh: re-snapshot the active window (so its cache stays current for when it
    /// becomes a target), capture any candidate that appeared since the last sweep, and drop
    /// previews for windows that no longer exist. Runs on a timer thread; ticks never overlap.
    /// </summary>
    private void RefreshPreviews()
    {
        if (Interlocked.Exchange(ref _refreshing, 1) == 1) return;
        try
        {
            nint fg = Native.GetForegroundWindow();
            if (fg != 0 && Native.IsCandidate(fg)) CapturePreview(fg);

            foreach (var h in Native.EnumerateTopLevel())
                if (Native.IsCandidate(h) && !_previewByHwnd.ContainsKey(h))
                    CapturePreview(h); // newly appeared since the last sweep

            foreach (var stale in _previewByHwnd.Keys.Where(h => !Native.IsWindow(h)).ToList())
                _previewByHwnd.TryRemove(stale, out _);
        }
        catch
        {
            // Best-effort; a failed refresh just leaves the previous snapshots in place.
        }
        finally
        {
            Interlocked.Exchange(ref _refreshing, 0);
        }
    }

    /// <summary>The cached snapshot for a window, or null if it hasn't been captured yet.</summary>
    private ImageSource? PreviewOf(nint hWnd)
    {
        if (_previewByHwnd.TryGetValue(hWnd, out var img)) return img;
        // Miss (a window not yet swept) — capture in the background for next time, show none now.
        Task.Run(() => { try { if (Native.IsCandidate(hWnd)) CapturePreview(hWnd); } catch { } });
        return null;
    }

    /// <summary>Snapshot a window's client area into a small frozen bitmap and cache it.</summary>
    private void CapturePreview(nint hWnd) => _previewByHwnd[hWnd] = CaptureWindow(hWnd);

    /// <summary>
    /// PrintWindow(PW_RENDERFULLCONTENT) grabs a window even when occluded; we crop to the client
    /// area (to match the live DWM thumbnail, which is client-only) and downscale so the cache
    /// stays light and the tile stays crisp. Frozen for cross-thread use. Null on failure — some
    /// hardware-accelerated windows return blank, and the live thumbnail covers those.
    /// </summary>
    private static ImageSource? CaptureWindow(nint hWnd)
    {
        if (!Native.GetWindowRect(hWnd, out var wr)) return null;
        int ww = wr.Right - wr.Left, wh = wr.Bottom - wr.Top;
        if (ww <= 0 || wh <= 0 || ww > 30000 || wh > 30000) return null;

        try
        {
            using var full = new System.Drawing.Bitmap(ww, wh, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
            using (var g = System.Drawing.Graphics.FromImage(full))
            {
                nint hdc = g.GetHdc();
                bool ok = Native.PrintWindow(hWnd, hdc, Native.PW_RENDERFULLCONTENT);
                g.ReleaseHdc(hdc);
                if (!ok) return null;
            }

            // Crop the window frame away so the preview shows just the client area (like DWM).
            System.Drawing.Bitmap client = full;
            bool cropped = false;
            if (Native.GetClientRect(hWnd, out var cr))
            {
                var origin = new Native.POINT { X = 0, Y = 0 };
                Native.ClientToScreen(hWnd, ref origin);
                int cx = origin.X - wr.Left, cy = origin.Y - wr.Top, cw = cr.Right, ch = cr.Bottom;
                if (cw > 0 && ch > 0 && cx >= 0 && cy >= 0 && cx + cw <= ww && cy + ch <= wh)
                {
                    client = full.Clone(new System.Drawing.Rectangle(cx, cy, cw, ch), full.PixelFormat);
                    cropped = true;
                }
            }

            try
            {
                // Downscale (2x the tile's display size) preserving aspect, to bound cache memory.
                const int maxDim = 400;
                int cw = client.Width, ch = client.Height;
                double scale = Math.Min(1.0, (double)maxDim / Math.Max(cw, ch));
                int tw = Math.Max(1, (int)(cw * scale)), th = Math.Max(1, (int)(ch * scale));

                using var scaled = new System.Drawing.Bitmap(client, new System.Drawing.Size(tw, th));
                nint hbitmap = scaled.GetHbitmap();
                try
                {
                    var src = Imaging.CreateBitmapSourceFromHBitmap(
                        hbitmap, nint.Zero, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
                    src.Freeze();
                    return src;
                }
                finally
                {
                    Native.DeleteObject(hbitmap);
                }
            }
            finally
            {
                if (cropped) client.Dispose();
            }
        }
        catch
        {
            return null; // capture is best-effort; the live DWM thumbnail is the fallback
        }
    }

    private void Touch(nint hWnd)
    {
        if (hWnd == 0) return;
        _lastActive[hWnd] = ++_activeSeq;
        if (!_firstSeen.ContainsKey(hWnd)) _firstSeen[hWnd] = ++_seenSeq;
    }

    /// <summary>Record stable order for any newly-appeared windows, in enumeration order.</summary>
    private void Observe(IReadOnlyList<nint> handles)
    {
        foreach (var h in handles)
            if (!_firstSeen.ContainsKey(h)) _firstSeen[h] = ++_seenSeq;
    }

    private long FirstSeen(nint h) => _firstSeen.TryGetValue(h, out var v) ? v : long.MaxValue;
    private long LastActive(nint h) => _lastActive.TryGetValue(h, out var v) ? v : 0;

    private string? PathOf(uint pid) => _pathByPid.GetOrAdd(pid, Native.ProcessPath);

    private string FriendlyName(string path) => _friendlyByPath.GetOrAdd(path, static p =>
    {
        try
        {
            var desc = FileVersionInfo.GetVersionInfo(p).FileDescription;
            return string.IsNullOrWhiteSpace(desc) ? Path.GetFileNameWithoutExtension(p) : desc;
        }
        catch
        {
            return Path.GetFileNameWithoutExtension(p);
        }
    });

    /// <summary>The app icon for a window's process (cached by exe path); null if unresolved.</summary>
    private ImageSource? IconFor(nint hWnd)
    {
        var path = PathOf(Native.Pid(hWnd));
        return path is null ? null : IconForPath(path);
    }

    private ImageSource? IconForPath(string path) => _iconByPath.GetOrAdd(path, static p =>
    {
        try
        {
            using var icon = System.Drawing.Icon.ExtractAssociatedIcon(p);
            if (icon is null) return null;
            var src = Imaging.CreateBitmapSourceFromHIcon(
                icon.Handle, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
            src.Freeze(); // immutable + cross-thread (built on warm-up thread, used on UI)
            return src;
        }
        catch
        {
            return null; // no extractable icon (e.g. a system path) — UI falls back gracefully
        }
    });

    /// <summary>
    /// Build the entry list for a mode plus the initially-highlighted index. Initial
    /// selection is the MRU-previous entry (the one you'd get from a blind quick tap),
    /// even though the list itself is in stable order.
    /// </summary>
    public (List<SwitchEntry> Entries, int InitialIndex) Build(SwitchMode mode, nint foreground)
    {
        uint fgPid = Native.Pid(foreground);
        string? fgPath = PathOf(fgPid);
        // "Current monitor" is the monitor under the mouse cursor (see VISION.md as refined
        // in testing) — not the foreground window's monitor.
        nint currentMonitor = Native.CursorMonitor();

        // ---- gather candidates with per-mode scoping ----
        var candidates = new List<nint>();
        foreach (var h in Native.EnumerateTopLevel())
        {
            if (!Native.IsCandidate(h)) continue;

            int cloak = Native.CloakReason(h);
            if (mode == SwitchMode.Everything)
            {
                // Escape hatch crosses desktops: keep shell-cloaked (other-desktop) windows,
                // but still drop app-cloaked ghosts (suspended UWP, etc.).
                if ((cloak & Native.DWM_CLOAKED_APP) != 0) continue;
            }
            else if (cloak != 0)
            {
                continue; // everyday modes stay on the current desktop
            }

            if (mode == SwitchMode.Apps && Native.Monitor(h) != currentMonitor) continue;

            if (mode == SwitchMode.AppWindows && !IsSameApp(h, fgPid, fgPath)) continue;

            candidates.Add(h);
        }

        Observe(candidates);

        var entries = mode == SwitchMode.Apps
            ? BuildAppEntries(candidates)
            : BuildWindowEntries(candidates);

        return (entries, InitialSelection(entries, foreground));
    }

    private bool IsSameApp(nint h, uint fgPid, string? fgPath)
    {
        if (fgPath != null)
            return string.Equals(PathOf(Native.Pid(h)), fgPath, StringComparison.OrdinalIgnoreCase);
        return Native.Pid(h) == fgPid; // unknown path — fall back to the exact process
    }

    private List<SwitchEntry> BuildWindowEntries(List<nint> candidates) =>
        candidates
            .OrderBy(FirstSeen)
            .Select(h => new SwitchEntry
            {
                Title = Native.Title(h),
                Primary = h,
                Handles = new[] { h },
                IsApp = false,
                Icon = IconFor(h),
                Preview = PreviewOf(h),
            })
            .ToList();

    private List<SwitchEntry> BuildAppEntries(List<nint> candidates)
    {
        var groups = new Dictionary<string, List<nint>>();
        foreach (var h in candidates)
        {
            uint pid = Native.Pid(h);
            string key = PathOf(pid) ?? $"pid:{pid}";
            if (!groups.TryGetValue(key, out var list)) groups[key] = list = new List<nint>();
            list.Add(h);
        }

        return groups
            // Stable order: by the earliest-seen window in each app.
            .OrderBy(g => g.Value.Min(FirstSeen))
            .Select(g =>
            {
                // Primary = the app's most-recently-active window.
                var windows = g.Value.OrderByDescending(LastActive).ToList();
                nint primary = windows[0];
                string title = g.Key.StartsWith("pid:")
                    ? Native.Title(primary)
                    : FriendlyName(g.Key);
                return new SwitchEntry
                {
                    Title = string.IsNullOrEmpty(title) ? Native.Title(primary) : title,
                    Primary = primary,
                    Handles = windows,
                    IsApp = true,
                    Icon = IconFor(primary),
                    Preview = PreviewOf(primary),
                };
            })
            .ToList();
    }

    private int InitialSelection(List<SwitchEntry> entries, nint foreground)
    {
        int sel = 0;
        long best = -1;
        for (int i = 0; i < entries.Count; i++)
        {
            // Skip the entry that owns the current foreground window — we want the *previous*.
            if (entries[i].Handles.Contains(foreground)) continue;
            long recency = entries[i].Handles.Max(LastActive);
            if (recency > best)
            {
                best = recency;
                sel = i;
            }
        }
        return sel;
    }

    public void Dispose()
    {
        _refreshTimer?.Dispose();
        _refreshTimer = null;

        if (_winEventHook != 0)
        {
            Native.UnhookWinEvent(_winEventHook);
            _winEventHook = 0;
        }
        _winEventProc = null;
    }
}
