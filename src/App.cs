using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using BatteryOptimizer;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        bool verify = args.Length == 1 && args[0] == "--verify";
        try
        {
            UiText.Load(verify ? "en" : UiText.InstalledLanguage());
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            using (var icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath))
            {
                if (icon == null) throw new InvalidOperationException("The executable icon is missing.");
                if (verify)
                {
                    foreach (string language in UiText.Codes)
                    {
                        UiText.Select(language);
                        using (var window = new MainWindow(icon, null)) window.VerifyControls();
                    }
                    return 0;
                }

                bool created;
                using (var openSignal = new EventWaitHandle(false, EventResetMode.AutoReset, Product.WindowEvent, out created))
                {
                    if (!created)
                    {
                        openSignal.Set();
                        return 0;
                    }
                    using (var window = new MainWindow(icon, openSignal)) Application.Run(window);
                }
            }
            return 0;
        }
        catch (Exception ex)
        {
            if (!verify) MessageBox.Show(ex.Message, UiText.Get("AppStartFailed"), MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}

internal sealed class MainWindow : Form
{
    private static readonly Color Ink = Color.FromArgb(22, 38, 61);
    private static readonly Color Muted = Color.FromArgb(74, 90, 110);
    private static readonly Color Accent = Color.FromArgb(25, 61, 109);
    private static readonly Color ButtonBorder = Color.FromArgb(180, 194, 212);
    private readonly Container components = new Container();
    private readonly EventWaitHandle openSignal;
    private readonly Button away;
    private readonly Button normal;
    private readonly Label status;
    private readonly TextBox result;
    private readonly TabControl tabs;
    private readonly TabPage overview;
    private readonly TabPage settingsTab;
    private readonly SettingsPage settings;
    private readonly TextBox currentValues;
    private readonly Button refreshValues;
    private readonly NotifyIcon tray;
    private readonly ToolStripMenuItem awayMenu;
    private readonly ToolStripMenuItem normalMenu;
    private readonly ToolStripMenuItem exitMenu;
    private readonly System.Windows.Forms.Timer timer;
    private readonly string folder = AppDomain.CurrentDomain.BaseDirectory;
    private readonly string journal = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        Product.ProfileJournal);
    private ProfileWorker worker;
    private bool exiting;

    internal MainWindow(Icon icon, EventWaitHandle openSignal, string settingsPath = null)
    {
        this.openSignal = openSignal;
        Text = Product.Name;
        Icon = icon;
        StartPosition = FormStartPosition.CenterScreen;
        AutoScaleDimensions = new SizeF(96, 96);
        AutoScaleMode = AutoScaleMode.Dpi;
        ClientSize = new Size(760, 600);
        MinimumSize = new Size(640, 550);
        Font = new Font("Segoe UI", 10);
        BackColor = Color.FromArgb(242, 246, 252);
        ForeColor = Ink;

        var shell = new TableLayoutPanel
        {
            Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 3, Padding = new Padding(18, 14, 18, 14)
        };
        shell.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        shell.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        shell.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        shell.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        Controls.Add(shell);
        shell.Controls.Add(new Label
        {
            Text = Product.Name, Font = new Font("Segoe UI Semibold", 21), Margin = new Padding(0, 0, 0, 2), AutoSize = true
        }, 0, 0);
        shell.Controls.Add(new Label
        {
            Text = UiText.Get("AppSubtitle"), ForeColor = Muted, Margin = new Padding(0, 0, 0, 12), AutoSize = true
        }, 0, 1);

        tabs = new TabControl { Dock = DockStyle.Fill, Margin = Padding.Empty };
        overview = new TabPage(UiText.Get("OverviewTab")) { BackColor = BackColor };
        settingsTab = new TabPage(UiText.Get("SettingsTab"));
        settings = new SettingsPage(settingsPath ?? Path.Combine(Path.GetDirectoryName(journal), Product.ProfileSettingsFile));
        settingsTab.Controls.Add(settings);
        tabs.TabPages.Add(overview);
        tabs.TabPages.Add(settingsTab);
        shell.Controls.Add(tabs, 0, 2);

        var layout = new TableLayoutPanel
        {
            Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 4, Padding = new Padding(12, 12, 12, 8)
        };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        foreach (SizeType style in new[] { SizeType.AutoSize, SizeType.AutoSize, SizeType.Percent, SizeType.AutoSize })
            layout.RowStyles.Add(new RowStyle(style, 100));
        overview.Controls.Add(layout);

        var buttons = new TableLayoutPanel
        {
            Dock = DockStyle.Top, AutoSize = true, ColumnCount = 2, RowCount = 1, Margin = new Padding(0, 0, 0, 10)
        };
        buttons.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        buttons.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        away = ModeButton(UiText.Get("ModeAway"), new Padding(0, 0, 5, 0));
        normal = ModeButton(UiText.Get("ModeNormal"), new Padding(5, 0, 0, 0));
        buttons.Controls.Add(away, 0, 0);
        buttons.Controls.Add(normal, 1, 0);
        layout.Controls.Add(buttons, 0, 0);
        SelectMode(File.Exists(journal) ? "Away" : "Normal");

        var currentCard = new TableLayoutPanel
        {
            Dock = DockStyle.Top, AutoSize = true, ColumnCount = 2, RowCount = 2,
            Padding = new Padding(13, 8, 13, 8), Margin = new Padding(0, 0, 0, 10), BackColor = Color.White
        };
        currentCard.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        currentCard.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        currentCard.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        currentCard.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        currentCard.Controls.Add(new Label
        {
            Text = UiText.Get("CurrentValues"), Font = new Font("Segoe UI Semibold", 11),
            AutoSize = true, Anchor = AnchorStyles.Left, Margin = new Padding(0, 0, 0, 5)
        }, 0, 0);
        refreshValues = new Button { Text = UiText.Get("RefreshValues"), AutoSize = true, Margin = new Padding(0, 0, 0, 5) };
        refreshValues.Click += delegate { RefreshCurrentValues(); };
        currentCard.Controls.Add(refreshValues, 1, 0);
        currentValues = ReadOnlyText(UiText.Get("CurrentValues"));
        currentValues.MinimumSize = new Size(0, Font.Height * 6 + 6);
        currentValues.Text = UiText.Get("ReadingValues");
        currentCard.Controls.Add(currentValues, 0, 1);
        currentCard.SetColumnSpan(currentValues, 2);
        layout.Controls.Add(currentCard, 0, 1);

        var card = new TableLayoutPanel
        {
            Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 2, Margin = Padding.Empty,
            Padding = new Padding(13, 10, 13, 8), BackColor = Color.White
        };
        card.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        card.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        card.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        status = new Label
        {
            Text = UiText.Get("AppReady"), Font = new Font("Segoe UI Semibold", 10),
            AutoSize = true, Margin = new Padding(0, 0, 0, 6)
        };
        result = ReadOnlyText(UiText.Get("Result"));
        card.Controls.Add(status, 0, 0);
        card.Controls.Add(result, 0, 1);
        layout.Controls.Add(card, 0, 2);
        layout.Controls.Add(new Label
        {
            Text = UiText.Get("AppHint"), Font = new Font("Segoe UI", 9), ForeColor = Muted,
            Margin = new Padding(0, 10, 0, 0), AutoSize = true
        }, 0, 3);

        var menu = new ContextMenuStrip(components);
        menu.Items.Add(UiText.Get("OpenWindow"), null, delegate { ShowWindow(); });
        menu.Items.Add(new ToolStripSeparator());
        awayMenu = new ToolStripMenuItem(away.Text, null, delegate { StartMode("Away", away.Text); });
        normalMenu = new ToolStripMenuItem(normal.Text, null, delegate { StartMode("Normal", normal.Text); });
        menu.Items.Add(awayMenu);
        menu.Items.Add(normalMenu);
        menu.Items.Add(new ToolStripSeparator());
        exitMenu = new ToolStripMenuItem(UiText.Get("Exit"), null, delegate { exiting = true; Close(); });
        menu.Items.Add(exitMenu);
        tray = new NotifyIcon(components) { Text = Product.Name, Icon = icon, ContextMenuStrip = menu };
        tray.DoubleClick += delegate { ShowWindow(); };
        away.Click += delegate { StartMode("Away", away.Text); };
        normal.Click += delegate { StartMode("Normal", normal.Text); };

        timer = new System.Windows.Forms.Timer(components) { Interval = 200 };
        timer.Tick += CheckWorker;
        Shown += delegate { RefreshCurrentValues(); };
        tabs.SelectedIndexChanged += delegate
        {
            if (Visible && tabs.SelectedTab == overview) RefreshCurrentValues();
        };
        if (openSignal != null)
        {
            tray.Visible = true;
            timer.Start();
        }
    }

    protected override void OnLoad(EventArgs args)
    {
        base.OnLoad(args);
        Rectangle area = Screen.FromControl(this).WorkingArea;
        MinimumSize = new Size(Math.Min(MinimumSize.Width, area.Width), Math.Min(MinimumSize.Height, area.Height));
        Size = new Size(Math.Min(Width, area.Width), Math.Min(Height, area.Height));
        Location = new Point(area.Left + (area.Width - Width) / 2, area.Top + (area.Height - Height) / 2);
    }

    private static TextBox ReadOnlyText(string name)
    {
        return new TextBox
        {
            AccessibleName = name, Dock = DockStyle.Fill, Margin = Padding.Empty,
            BorderStyle = BorderStyle.None, BackColor = Color.White, ForeColor = Muted,
            Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, TabStop = false
        };
    }

    private static Button ModeButton(string text, Padding margin)
    {
        return new Button
        {
            Text = text, Dock = DockStyle.Fill, MinimumSize = new Size(0, 42), Margin = margin,
            FlatStyle = FlatStyle.Flat, UseVisualStyleBackColor = false
        };
    }

    private void ShowWindow()
    {
        Show();
        WindowState = FormWindowState.Normal;
        Activate();
        if (tabs.SelectedTab == overview) RefreshCurrentValues();
    }

    protected override void OnFormClosing(FormClosingEventArgs args)
    {
        if (args.CloseReason == CloseReason.UserClosing && !exiting)
        {
            args.Cancel = true;
            Hide();
        }
        base.OnFormClosing(args);
    }

    private void SelectMode(string mode)
    {
        Button selected = mode == "Away" ? away : normal;
        Button other = mode == "Away" ? normal : away;
        selected.BackColor = Color.White;
        selected.ForeColor = Ink;
        selected.FlatAppearance.BorderColor = ButtonBorder;
        selected.FlatAppearance.BorderSize = 1;
        other.BackColor = Accent;
        other.ForeColor = Color.White;
        other.FlatAppearance.BorderSize = 0;
    }

    private void EnableModes(bool enabled)
    {
        away.Enabled = normal.Enabled = enabled;
        awayMenu.Enabled = normalMenu.Enabled = exitMenu.Enabled = enabled;
        refreshValues.Enabled = enabled;
    }

    private void ShowResult(string message, string details, bool failed)
    {
        status.Text = message;
        status.ForeColor = failed ? Color.FromArgb(152, 48, 44) : Ink;
        result.Text = details.Trim();
        result.Select(0, 0);
        result.ScrollToCaret();
        if (!Visible || WindowState == FormWindowState.Minimized)
            tray.ShowBalloonTip(4000, Product.Name, message, failed ? ToolTipIcon.Error : ToolTipIcon.Info);
    }

    private void StartMode(string mode, string title)
    {
        if (worker != null) return;
        ProfileSettings preferences = settings.SavedSettings;
        if (mode == "Away")
        {
            if (preferences == null || settings.HasUnsavedChanges)
            {
                ShowResult(UiText.Get("SaveBeforeAway"), "", true);
                return;
            }
            if (!preferences.HasEnabledSettings)
            {
                ShowResult(UiText.Get("NoEnabledSettings"), "", true);
                return;
            }
        }
        if (mode == "Normal" && !File.Exists(journal))
        {
            SelectMode(mode);
            ShowResult(UiText.Get("NothingToRestore"), "", false);
            if (Visible && tabs.SelectedTab == overview) RefreshCurrentValues();
            return;
        }
        string script = Path.Combine(folder, Product.WorkerScript);
        if (!File.Exists(script))
        {
            ShowResult(UiText.Get("WorkerMissing"), UiText.Get("WorkerMissingHelp"), true);
            return;
        }
        EnableModes(false);
        status.Text = UiText.Get("Working", title);
        status.ForeColor = Ink;
        result.Clear();
        try { worker = ProfileWorker.Start(folder, script, mode, title, preferences); }
        catch (Exception ex)
        {
            EnableModes(true);
            ShowResult(UiText.Get("ModeStartFailed", title), ex.Message, true);
        }
    }

    private void RefreshCurrentValues()
    {
        if (worker != null) return;
        string script = Path.Combine(folder, Product.WorkerScript);
        if (!File.Exists(script))
        {
            currentValues.Text = UiText.Get("WorkerMissing");
            return;
        }
        EnableModes(false);
        currentValues.Text = UiText.Get("ReadingValues");
        try { worker = ProfileWorker.Start(folder, script, "Status", UiText.Get("CurrentValues")); }
        catch
        {
            currentValues.Text = UiText.Get("CurrentReadFailed");
            EnableModes(true);
        }
    }

    private void CheckWorker(object sender, EventArgs args)
    {
        if (openSignal != null && openSignal.WaitOne(0)) ShowWindow();
        ProfileWorker run = worker;
        if (run == null) return;
        bool reading = run.Mode == "Status";
        if (!run.Process.HasExited || !run.Output.IsCompleted || !run.Errors.IsCompleted)
        {
            if (!reading || !run.StatusTimedOut) return;
            try { if (!run.Process.HasExited) run.Process.Kill(); }
            catch (InvalidOperationException) { }
            catch (Win32Exception) { }
            worker = null;
            run.Dispose();
            currentValues.Text = UiText.Get("CurrentReadFailed");
            EnableModes(true);
            return;
        }
        try
        {
            bool success = run.Process.ExitCode == 0;
            string details = run.Output.GetAwaiter().GetResult();
            if (reading)
            {
                currentValues.Text = success && !string.IsNullOrWhiteSpace(details)
                    ? details.Trim() : UiText.Get("CurrentReadFailed");
            }
            else if (success)
            {
                SelectMode(File.Exists(journal) ? "Away" : "Normal");
                ShowResult(UiText.Get("ModeDone", run.Title), details, false);
            }
            else
                ShowResult(UiText.Get("ModeFailed", run.Title),
                    details + Environment.NewLine + run.Errors.GetAwaiter().GetResult(), true);
        }
        catch (Exception ex)
        {
            if (reading) currentValues.Text = UiText.Get("CurrentReadFailed");
            else ShowResult(UiText.Get("ResultFailed", run.Title), ex.Message, true);
        }
        worker = null;
        run.Dispose();
        EnableModes(true);
        if (!reading && Visible && WindowState != FormWindowState.Minimized && tabs.SelectedTab == overview)
            RefreshCurrentValues();
    }

    internal void VerifyControls()
    {
        // The native tab control sizes its pages when its window is created.
        if (tabs.Handle == IntPtr.Zero) throw new InvalidOperationException("The tabs could not be created.");
        PerformLayout();
        if (Text != Product.Name || Icon == null || tray.Icon != Icon ||
            tray.ContextMenuStrip.Items.Count != 6 || awayMenu.Text != away.Text || normalMenu.Text != normal.Text ||
            tabs.TabPages.Count != 2 || settingsTab.Text != UiText.Get("SettingsTab") || !currentValues.ReadOnly ||
            away.Width < 120 || normal.Width < 120 || result.Height < 55)
            throw new InvalidOperationException("The window, icon or mode controls are incomplete.");
        SelectMode("Away");
        if (away.BackColor != Color.White || normal.BackColor != Accent)
            throw new InvalidOperationException("Invalid Away mode colours.");
        SelectMode("Normal");
        if (normal.BackColor != Color.White || away.BackColor != Accent)
            throw new InvalidOperationException("Invalid Normal mode colours.");
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            timer.Stop();
            tray.Visible = false;
            if (worker != null) worker.Dispose();
            components.Dispose();
        }
        base.Dispose(disposing);
    }
}

internal sealed class ProfileWorker : IDisposable
{
    private readonly Stopwatch elapsed = Stopwatch.StartNew();
    internal Process Process { get; private set; }
    internal Task<string> Output { get; private set; }
    internal Task<string> Errors { get; private set; }
    internal string Mode { get; private set; }
    internal string Title { get; private set; }
    internal bool StatusTimedOut { get { return Mode == "Status" && elapsed.ElapsedMilliseconds >= 15000; } }

    internal static ProfileWorker Start(string folder, string script, string mode, string title, ProfileSettings settings = null)
    {
        settings = settings ?? new ProfileSettings();
        var start = new ProcessStartInfo
        {
            FileName = Product.PowerShell,
            Arguments = "-NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -Command \"" +
                "[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); " +
                "try { $disabled = @($env:YBO_DISABLED -split ',' | Where-Object { $_ }); " +
                "& $env:YBO_WORKER -Mode $env:YBO_MODE -Language $env:YBO_LANGUAGE " +
                "-AwayRefreshRate $env:YBO_RATE -AwayBrightness $env:YBO_BRIGHTNESS -AwayVolume $env:YBO_VOLUME " +
                "-AwaySaverThreshold $env:YBO_SAVER -AwayPowerMode $env:YBO_POWER -DisabledSettings $disabled 6>&1 | " +
                "Out-String -Stream -Width 200 | ForEach-Object { [Console]::WriteLine($_) }; exit 0 } " +
                "catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }\"",
            WorkingDirectory = folder,
            UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardOutput = true, RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8
        };
        start.EnvironmentVariables["YBO_WORKER"] = script;
        start.EnvironmentVariables["YBO_MODE"] = mode;
        start.EnvironmentVariables["YBO_LANGUAGE"] = UiText.Language;
        start.EnvironmentVariables["YBO_DISABLED"] = settings.DisabledSettings();
        start.EnvironmentVariables["YBO_RATE"] = settings.RefreshRate.ToString(CultureInfo.InvariantCulture);
        start.EnvironmentVariables["YBO_BRIGHTNESS"] = settings.BrightnessPercent.ToString(CultureInfo.InvariantCulture);
        start.EnvironmentVariables["YBO_VOLUME"] = settings.VolumePercent.ToString(CultureInfo.InvariantCulture);
        start.EnvironmentVariables["YBO_SAVER"] = settings.SaverPercent.ToString(CultureInfo.InvariantCulture);
        start.EnvironmentVariables["YBO_POWER"] = settings.PowerMode;
        var process = Process.Start(start);
        try
        {
            return new ProfileWorker
            {
                Process = process, Mode = mode, Title = title,
                Output = process.StandardOutput.ReadToEndAsync(), Errors = process.StandardError.ReadToEndAsync()
            };
        }
        catch { process.Dispose(); throw; }
    }

    public void Dispose() { Process.Dispose(); }
}
