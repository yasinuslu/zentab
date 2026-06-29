using System;
using System.Windows;
using Forms = System.Windows.Forms;

namespace ZenTab;

/// <summary>
/// App entry point. ZenTab is resident all day with no main window — it lives in the
/// tray and is summoned by the keyboard hook. There is nothing to show at startup.
/// </summary>
public partial class App : System.Windows.Application
{
    private SwitcherController? _controller;
    private Forms.NotifyIcon? _tray;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        var config = ZenConfig.Load();
        _controller = new SwitcherController(config, Dispatcher);

        try
        {
            _controller.Start();
        }
        catch (Exception ex)
        {
            System.Windows.MessageBox.Show($"ZenTab couldn't install its keyboard hook:\n\n{ex.Message}",
                "ZenTab", MessageBoxButton.OK, MessageBoxImage.Error);
            Shutdown(1);
            return;
        }

        CreateTray(_controller.Profile);
    }

    private void CreateTray(HotkeyProfile profile)
    {
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add(new Forms.ToolStripMenuItem(profile.Description) { Enabled = false });
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Quit ZenTab", null, (_, _) => Shutdown());

        _tray = new Forms.NotifyIcon
        {
            Icon = System.Drawing.SystemIcons.Application,
            Visible = true,
            Text = "ZenTab — " + profile.Description,
            ContextMenuStrip = menu,
        };
    }

    protected override void OnExit(ExitEventArgs e)
    {
        if (_tray is not null)
        {
            _tray.Visible = false;
            _tray.Dispose();
        }
        _controller?.Dispose();
        base.OnExit(e);
    }
}
