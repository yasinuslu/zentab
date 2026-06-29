using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;

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

    // win-event hook (foreground changes) — near-zero idle cost, only fires on switch.
    private Native.WinEventDelegate? _winEventProc;
    private nint _winEventHook;

    public void Start()
    {
        _winEventProc = OnForegroundChanged;
        _winEventHook = Native.SetWinEventHook(
            Native.EVENT_SYSTEM_FOREGROUND, Native.EVENT_SYSTEM_FOREGROUND,
            0, _winEventProc, 0, 0, Native.WINEVENT_OUTOFCONTEXT);

        // Seed recency with whatever is focused right now.
        Touch(Native.GetForegroundWindow());

        // Pre-warm the process caches off the UI thread so the first summon is already hot.
        Task.Run(Warmup);
    }

    /// <summary>Resolve process paths/names for the current windows now, so summon stays cheap.</summary>
    private void Warmup()
    {
        try
        {
            foreach (var h in Native.EnumerateTopLevel())
            {
                if (!Native.IsCandidate(h)) continue;
                var path = PathOf(Native.Pid(h));
                if (path != null) FriendlyName(path);
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
        if (_winEventHook != 0)
        {
            Native.UnhookWinEvent(_winEventHook);
            _winEventHook = 0;
        }
        _winEventProc = null;
    }
}
