using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;

namespace ZenTab;

/// <summary>
/// A held modifier set + per-mode trigger keys. Most-specific trigger (most modifiers)
/// wins, and the overlay commits when the modifier set is released.
/// </summary>
public sealed class HotkeyProfile
{
    public sealed record Trigger(string[] Mods, int Key, SwitchMode Mode);

    public required IReadOnlyList<Trigger> Triggers { get; init; }
    public required string[] CommitMods { get; init; }
    public required string Description { get; init; }

    /// <summary>The shipping scheme: Alt+Tab / Alt+` / Ctrl+Alt+Tab. Hard-coded (see VISION.md).</summary>
    public static HotkeyProfile Normal { get; } = new()
    {
        Triggers = new[]
        {
            new Trigger(new[] { "ctrl", "alt" }, Native.VK_TAB, SwitchMode.Everything),
            new Trigger(new[] { "alt" }, Native.VK_TAB, SwitchMode.Apps),
            new Trigger(new[] { "alt" }, Native.VK_OEM_3, SwitchMode.AppWindows),
        },
        CommitMods = new[] { "alt" },
        Description = "Alt+Tab / Alt+` / Ctrl+Alt+Tab",
    };
}

/// <summary>
/// ZenTab configuration. This is a DEVELOPER aid, not user-facing configurability
/// (ZenTab is intentionally not configurable — see VISION.md). It exists only so the
/// switcher can be tested without hijacking the real Alt+Tab while developing.
/// </summary>
public sealed class ZenConfig
{
    public bool DevEnabled { get; set; }
    public string Modifier { get; set; } = "ctrl+alt";
    public string Apps { get; set; } = "F1";
    public string AppWindows { get; set; } = "F2";
    public string Everything { get; set; } = "F3";

    public HotkeyProfile BuildProfile()
    {
        if (!DevEnabled) return HotkeyProfile.Normal;

        var mods = ParseMods(Modifier);
        return new HotkeyProfile
        {
            Triggers = new[]
            {
                new HotkeyProfile.Trigger(mods, ParseKey(Apps), SwitchMode.Apps),
                new HotkeyProfile.Trigger(mods, ParseKey(AppWindows), SwitchMode.AppWindows),
                new HotkeyProfile.Trigger(mods, ParseKey(Everything), SwitchMode.Everything),
            },
            CommitMods = mods,
            Description = $"DEV: {Modifier}+{{ {Apps} / {AppWindows} / {Everything} }}",
        };
    }

    /// <summary>Load zentab.toml from the exe directory or the working dir; defaults if absent.</summary>
    public static ZenConfig Load()
    {
        foreach (var dir in new[] { AppContext.BaseDirectory, Environment.CurrentDirectory })
        {
            var path = Path.Combine(dir, "zentab.toml");
            if (File.Exists(path))
            {
                try { return Parse(File.ReadAllLines(path)); }
                catch { /* malformed config falls back to defaults */ }
            }
        }
        return new ZenConfig();
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

            if (section != "dev") continue;
            switch (key)
            {
                case "enabled": cfg.DevEnabled = value.Equals("true", StringComparison.OrdinalIgnoreCase); break;
                case "modifier": cfg.Modifier = value; break;
                case "apps": cfg.Apps = value; break;
                case "app_windows": cfg.AppWindows = value; break;
                case "everything": cfg.Everything = value; break;
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

    private static string[] ParseMods(string spec)
    {
        var parts = spec.Split('+', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        var mods = new List<string>();
        foreach (var p in parts)
        {
            var m = p.ToLowerInvariant();
            if (m is "alt" or "ctrl" or "control" or "shift" or "win")
                mods.Add(m == "control" ? "ctrl" : m);
        }
        return mods.Count > 0 ? mods.ToArray() : new[] { "ctrl", "alt" };
    }

    /// <summary>Map a key name (F1, Tab, A, `, ...) to a virtual-key code.</summary>
    private static int ParseKey(string name)
    {
        name = name.Trim();
        if (name.Length == 0) return Native.VK_F1;
        switch (name.ToLowerInvariant())
        {
            case "tab": return Native.VK_TAB;
            case "`": case "backtick": case "tilde": return Native.VK_OEM_3;
            case "esc": case "escape": return Native.VK_ESCAPE;
        }

        // Function keys F1..F24
        if ((name[0] == 'F' || name[0] == 'f') && name.Length > 1
            && int.TryParse(name[1..], NumberStyles.Integer, CultureInfo.InvariantCulture, out int fn)
            && fn is >= 1 and <= 24)
            return 0x70 + (fn - 1); // VK_F1 = 0x70

        // Single letter / digit
        char c = char.ToUpperInvariant(name[0]);
        if (c is >= 'A' and <= 'Z' or >= '0' and <= '9') return c;

        return Native.VK_F1; // safe fallback
    }
}
