using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;

namespace ZenTab;

/// <summary>
/// A per-mode set of trigger chords (modifiers + key) plus the modifiers whose release
/// commits the overlay. Most-specific trigger (most modifiers) wins when several match a
/// keystroke, and the overlay commits when any held trigger modifier is released.
/// </summary>
public sealed class HotkeyProfile
{
    public sealed record Trigger(string[] Mods, int Key, SwitchMode Mode);

    public required IReadOnlyList<Trigger> Triggers { get; init; }
    public required string[] CommitMods { get; init; }
    public required string Description { get; init; }

    /// <summary>The trigger chord for a mode, formatted for display (e.g. "Ctrl+Alt+Tab").</summary>
    public string KeyDisplay(SwitchMode mode)
    {
        var t = Triggers.FirstOrDefault(x => x.Mode == mode);
        return t is null ? string.Empty : Display(t);
    }

    /// <summary>Canonical Windows-order, plus-joined chord text (e.g. "Ctrl+Alt+Tab").</summary>
    public static string Display(Trigger t)
    {
        var parts = t.Mods.OrderBy(ModOrder).Select(ModName).Append(KeyName(t.Key));
        return string.Join("+", parts);
    }

    private static int ModOrder(string mod) => mod switch
    {
        "ctrl" => 0, "alt" => 1, "shift" => 2, "win" => 3, _ => 9,
    };

    private static string ModName(string mod) => mod switch
    {
        "ctrl" => "Ctrl", "alt" => "Alt", "shift" => "Shift", "win" => "Win", _ => mod,
    };

    private static string KeyName(int vk) => vk switch
    {
        Native.VK_TAB => "Tab",
        Native.VK_OEM_3 => "`",
        Native.VK_ESCAPE => "Esc",
        Native.VK_LEFT => "Left",
        Native.VK_RIGHT => "Right",
        >= 0x70 and <= 0x87 => "F" + (vk - 0x70 + 1), // F1..F24
        >= 0x41 and <= 0x5A => ((char)vk).ToString(), // A..Z
        >= 0x30 and <= 0x39 => ((char)vk).ToString(), // 0..9
        _ => "?",
    };
}

/// <summary>
/// ZenTab configuration — a single TOML file (see VISION.md: "config is a file"). ZenTab is
/// intentionally opinionated and almost nothing is configurable: the only knobs are the three
/// trigger chords and the hold threshold. The switching behavior itself is fixed.
///
/// Read, in priority order, from:
///   1. <c>zentab.toml</c> beside the exe or in the working directory — a portable / dev
///      override (the source tree ships one with safe chords so development never hijacks the
///      real Alt+Tab; it is excluded from the published exe and MSI).
///   2. <c>%APPDATA%\zentab\config.toml</c> — the standard per-user config.
///   3. Built-in defaults (the shipping scheme below) when no file is present.
/// </summary>
public sealed class ZenConfig
{
    // The three trigger chords, exactly as written in [keys]. Defaults are the shipping
    // scheme — Alt+Tab / Alt+` / Ctrl+Alt+Tab (VISION.md). Shift is reserved everywhere for
    // reverse navigation, so it never appears in a trigger.
    public string OtherApps { get; set; } = "alt+tab";
    public string CurrentApp { get; set; } = "alt+`";
    public string Everything { get; set; } = "ctrl+alt+tab";

    // [behavior] hold_threshold_ms — how long the trigger must be held before the overlay
    // appears; a quicker tap-and-release switches invisibly. Default 150 (matches macOS).
    public int HoldThresholdMs { get; set; } = 150;

    public HotkeyProfile BuildProfile()
    {
        var triggers = new List<HotkeyProfile.Trigger>
        {
            ParseChord(OtherApps, SwitchMode.Apps, "alt+tab"),
            ParseChord(CurrentApp, SwitchMode.AppWindows, "alt+`"),
            ParseChord(Everything, SwitchMode.Everything, "ctrl+alt+tab"),
        };

        // Releasing any modifier that took part in a trigger commits the selection.
        var commit = triggers.SelectMany(t => t.Mods).Distinct().ToArray();

        return new HotkeyProfile
        {
            Triggers = triggers,
            CommitMods = commit.Length > 0 ? commit : new[] { "alt" },
            Description = string.Join("  /  ", triggers.Select(HotkeyProfile.Display)),
        };
    }

    public static ZenConfig Load()
    {
        foreach (var path in CandidatePaths())
        {
            if (path is null || !File.Exists(path)) continue;
            try { return Parse(File.ReadAllLines(path)); }
            catch { /* malformed config falls back to the next candidate / defaults */ }
        }
        return new ZenConfig();
    }

    private static IEnumerable<string?> CandidatePaths()
    {
        // 1. Portable / dev override beside the exe or in the working directory.
        yield return Path.Combine(AppContext.BaseDirectory, "zentab.toml");
        yield return Path.Combine(Environment.CurrentDirectory, "zentab.toml");

        // 2. The standard per-user config: %APPDATA%\zentab\config.toml.
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        yield return string.IsNullOrEmpty(appData) ? null : Path.Combine(appData, "zentab", "config.toml");
    }

    private static ZenConfig Parse(string[] lines)
    {
        var cfg = new ZenConfig();
        string section = "";
        foreach (var raw in lines)
        {
            var line = StripComment(raw).Trim();
            if (line.Length == 0) continue;

            if (line.StartsWith('[') && line.EndsWith(']'))
            {
                section = line[1..^1].Trim().ToLowerInvariant();
                continue;
            }

            int eq = line.IndexOf('=');
            if (eq < 0) continue;
            string key = line[..eq].Trim().ToLowerInvariant();
            string value = Unquote(line[(eq + 1)..].Trim());

            switch (section)
            {
                case "keys":
                    switch (key)
                    {
                        case "other_apps": cfg.OtherApps = value; break;
                        case "current_app": cfg.CurrentApp = value; break;
                        case "everything": cfg.Everything = value; break;
                    }
                    break;
                case "behavior":
                    if (key == "hold_threshold_ms"
                        && int.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out int ms))
                        cfg.HoldThresholdMs = Math.Clamp(ms, 0, 2000);
                    break;
            }
        }
        return cfg;
    }

    private static string StripComment(string s)
    {
        bool inString = false;
        for (int i = 0; i < s.Length; i++)
        {
            if (s[i] == '"') inString = !inString;
            else if (s[i] == '#' && !inString) return s[..i];
        }
        return s;
    }

    private static string Unquote(string s) =>
        s.Length >= 2 && s[0] == '"' && s[^1] == '"' ? s[1..^1] : s;

    /// <summary>Parse "ctrl+alt+tab" into a trigger; fall back to the default chord if invalid.</summary>
    private static HotkeyProfile.Trigger ParseChord(string spec, SwitchMode mode, string fallback)
    {
        if (!TryParseChord(spec, out var mods, out int key))
            TryParseChord(fallback, out mods, out key);
        return new HotkeyProfile.Trigger(mods, key, mode);
    }

    private static bool TryParseChord(string spec, out string[] mods, out int key)
    {
        mods = Array.Empty<string>();
        key = 0;

        var parts = spec.Split('+', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (parts.Length == 0) return false;

        var modList = new List<string>();
        string? keyToken = null;
        foreach (var p in parts)
        {
            switch (p.ToLowerInvariant())
            {
                case "alt": case "option": case "opt": AddMod(modList, "alt"); break;
                case "ctrl": case "control": AddMod(modList, "ctrl"); break;
                case "win": case "super": case "cmd": case "meta": AddMod(modList, "win"); break;
                case "shift": break; // reserved for reverse navigation — never part of a trigger
                default: keyToken = p; break; // the last non-modifier token is the key
            }
        }

        if (keyToken is null) return false;
        key = ParseKey(keyToken);
        mods = modList.ToArray();
        return true;
    }

    private static void AddMod(List<string> mods, string mod)
    {
        if (!mods.Contains(mod)) mods.Add(mod);
    }

    /// <summary>Map a key name (Tab, F1, A, `, ...) to a virtual-key code.</summary>
    private static int ParseKey(string name)
    {
        name = name.Trim();
        if (name.Length == 0) return Native.VK_TAB;
        switch (name.ToLowerInvariant())
        {
            case "tab": return Native.VK_TAB;
            case "`": case "backtick": case "tilde": return Native.VK_OEM_3;
            case "esc": case "escape": return Native.VK_ESCAPE;
            case "left": return Native.VK_LEFT;
            case "right": return Native.VK_RIGHT;
        }

        // Function keys F1..F24
        if ((name[0] == 'F' || name[0] == 'f') && name.Length > 1
            && int.TryParse(name[1..], NumberStyles.Integer, CultureInfo.InvariantCulture, out int fn)
            && fn is >= 1 and <= 24)
            return 0x70 + (fn - 1); // VK_F1 = 0x70

        // Single letter / digit
        char c = char.ToUpperInvariant(name[0]);
        if (c is >= 'A' and <= 'Z' or >= '0' and <= '9') return c;

        return Native.VK_TAB; // safe fallback
    }
}
