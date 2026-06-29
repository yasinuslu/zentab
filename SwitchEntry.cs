using System.Collections.Generic;

namespace ZenTab;

/// <summary>The three hard-coded switching modes. See VISION.md — not configurable.</summary>
public enum SwitchMode
{
    /// <summary>Alt+Tab — apps (one entry per app), current monitor + current desktop.</summary>
    Apps,

    /// <summary>Alt+` — windows of the current/foreground app, current desktop, all monitors.</summary>
    AppWindows,

    /// <summary>Ctrl+Alt+Tab — everything, all monitors, all desktops. The escape hatch.</summary>
    Everything,
}

/// <summary>
/// One row in the overlay. For app entries (Apps mode) <see cref="Handles"/> holds every
/// window of that app and <see cref="Primary"/> is the one we activate; for window entries
/// both collapse to a single window.
/// </summary>
public sealed class SwitchEntry
{
    public required string Title { get; init; }
    public required nint Primary { get; init; }
    public required IReadOnlyList<nint> Handles { get; init; }
    public required bool IsApp { get; init; }
}
