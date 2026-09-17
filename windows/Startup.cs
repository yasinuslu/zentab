using System;
using Microsoft.Win32;

namespace ZenTab;

/// <summary>
/// ZenTab launches at login, always — it is not a setting. An Alt+Tab replacement that
/// isn't already running when you press Alt+Tab is useless, so per VISION.md ("the default
/// answer to 'should this be a setting?' is no") there is no checkbox: every real launch
/// writes the current exe path to the per-user Run key.
///
/// Writing on every startup makes it self-healing — move the portable exe and the next
/// launch re-points the key at the new location. Debug builds (<c>dotnet run</c> / dev.ps1)
/// never register, so day-to-day development doesn't hijack your login.
///
/// The MSIX / Store build is the exception: MSIX virtualizes writes to the Run key, so the
/// shell never sees them. That build declares a <c>windows.startupTask</c> extension in
/// msix/AppxManifest.xml instead, which the OS honors natively — same always-on behavior,
/// different mechanism — so this code stands down when it detects a package identity.
/// </summary>
internal static class Startup
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "ZenTab";

    /// <summary>Ensure the per-user Run key points at this exe. Cheap and idempotent.</summary>
    public static void EnsureLaunchOnLogin()
    {
#if !DEBUG
        // The packaged build's manifest already declares the startup task; writing the Run
        // key from inside the package would only land in the package's virtualized hive.
        if (Native.IsPackaged())
            return;

        try
        {
            // ProcessPath is the real launched exe (the single-file host on a published
            // build), which is exactly what we want the shell to re-run at login.
            var exePath = Environment.ProcessPath;
            if (string.IsNullOrEmpty(exePath))
                return;

            var command = "\"" + exePath + "\"";
            using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: true)
                            ?? Registry.CurrentUser.CreateSubKey(RunKeyPath);
            if (key is null)
                return;

            if (key.GetValue(ValueName) as string != command)
                key.SetValue(ValueName, command, RegistryValueKind.String);
        }
        catch
        {
            // Non-fatal: worst case ZenTab just won't auto-start. Never block launch over it.
        }
#endif
    }
}
