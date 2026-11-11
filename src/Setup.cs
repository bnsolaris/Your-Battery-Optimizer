using System;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;
using BatteryOptimizer;

internal static class Program
{
    [DllImport("user32.dll")]
    private static extern bool SetProcessDPIAware();

    [STAThread]
    private static int Main(string[] args)
    {
        bool verify = args.Length == 1 && args[0] == "--verify";
        try
        {
#if UNINSTALL
            UiText.Load(verify ? "en" : UiText.InstalledLanguage());
#else
            UiText.Load(CultureInfo.CurrentUICulture.Name);
#endif
        }
        catch (Exception ex)
        {
            if (!verify) MessageBox.Show(ex.Message, Product.Name, MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        if (verify)
        {
            try
            {
#if UNINSTALL
                if (!File.Exists(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, Product.UninstallScript))) return 2;
#else
                foreach (string name in InstallFiles.Payload)
                    using (var stream = Resource(name))
                        if (stream.Length == 0) return 2;
                Application.EnableVisualStyles();
                using (var wizard = new SetupWindow()) wizard.VerifyPages();
#endif
                return 0;
            }
            catch { return 1; }
        }
        SetProcessDPIAware();
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
#if UNINSTALL
        RunUninstaller();
#else
        using (var wizard = new SetupWindow())
            Application.Run(wizard);
#endif
        return 0;
    }

    internal static Stream Resource(string name)
    {
        var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(name);
        if (stream == null) throw new InvalidOperationException(UiText.Get("PackageMissing", name));
        return stream;
    }

#if UNINSTALL
    private static void RunUninstaller()
    {
        var answer = MessageBox.Show(
            UiText.Get("UninstallConfirm"), UiText.Get("UninstallTitle"),
            MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2);
        if (answer != DialogResult.Yes) return;

        try
        {
            string script = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, Product.UninstallScript);
            if (!File.Exists(script))
                throw new FileNotFoundException(UiText.Get("UninstallScriptMissing"), script);
            var start = new ProcessStartInfo
            {
                FileName = InstallFiles.PowerShell,
                Arguments = "-NoProfile -NonInteractive -STA -ExecutionPolicy RemoteSigned -File \"" + script + "\"",
                UseShellExecute = false, CreateNoWindow = true,
                WorkingDirectory = Path.GetTempPath()
            };
            start.EnvironmentVariables["PILMODU_REMOVE_DIR"] = AppDomain.CurrentDomain.BaseDirectory;
            start.EnvironmentVariables["PILMODU_REMOVE_PID"] = Process.GetCurrentProcess().Id.ToString();
            start.EnvironmentVariables["YBO_LANGUAGE"] = UiText.Language;
            using (Process.Start(start)) { }
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, UiText.Get("UninstallStartFailed"), MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
#else
    internal static string Install(string folder)
    {
        bool ownsEvent;
        using (var appEvent = new EventWaitHandle(false, EventResetMode.AutoReset, Product.WindowEvent, out ownsEvent))
        {
            if (!ownsEvent) throw new InvalidOperationException(UiText.Get("AppOpen"));
            return InstallFiles.Install(folder);
        }
    }
#endif
}

internal static class InstallFiles
{
    internal const string Entry = Product.Registration;
    internal const string Marker = ".pilmodu-install";
    internal static string RecoveredFolder { get; private set; }
    internal static readonly string PowerShell = Product.PowerShell;
    internal static readonly string[] Payload = {
        Product.Executable, "BatteryOptimizer.Native.dll", Product.WorkerScript, Product.UninstallScript,
        "Localization.ps1", Product.TranslationsFile, Product.IconFile, "README.txt", "Uninstall.exe"
    };
    internal static readonly string[] LegacyPayload = {
        "PilModu.exe", "PilModu.Native.dll", "PilModu.Visuals.dll", "Pil-Modu-Uygulamasi.ps1",
        "Pil-Modu.ps1", "Kaldir.ps1", "Pil-Modu.ico", "README.txt", "Uninstall.exe"
    };

    internal static string DefaultFolder
    {
        get
        {
            string programs = Environment.GetEnvironmentVariable("ProgramW6432") ??
                Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
            return Path.Combine(programs, Product.Name);
        }
    }

    private static string NormalizeFolder(string input)
    {
        if (string.IsNullOrWhiteSpace(input) || !Path.IsPathRooted(input) ||
            input.Length < 3 || input[1] != ':' || (input[2] != '\\' && input[2] != '/'))
            throw new InvalidOperationException(UiText.Get("InvalidFolder"));

        string path = Path.GetFullPath(input.Trim()).TrimEnd('\\');
        string root = Path.GetPathRoot(path + "\\");
        if (path.Length <= 2 || new DriveInfo(root).DriveType != DriveType.Fixed || path.Length > 205)
            throw new InvalidOperationException(UiText.Get("LocalFolder"));

        for (var node = new DirectoryInfo(path); node != null; node = node.Parent)
        {
            if (File.Exists(node.FullName) || (node.Exists && (node.Attributes & FileAttributes.ReparsePoint) != 0))
                throw new InvalidOperationException(UiText.Get("LinkedFolder"));
        }
        return path;
    }

    internal static string ValidateFolder(string input, string recoveredFolder = null, string recoveredId = null)
    {
        string path = NormalizeFolder(input);
        if (Directory.Exists(path))
        {
            string[] contents = Directory.GetFileSystemEntries(path);
            bool onlyOldMarker = contents.Length == 1 &&
                string.Equals(path, recoveredFolder, StringComparison.OrdinalIgnoreCase) &&
                string.Equals(Path.GetFileName(contents[0]), Marker, StringComparison.OrdinalIgnoreCase) &&
                !string.IsNullOrEmpty(recoveredId) && File.ReadAllText(contents[0]) == recoveredId;
            if (contents.Length != 0 && !onlyOldMarker)
                throw new InvalidOperationException(UiText.Get("EmptyFolder"));
        }
        if (!Directory.Exists(Path.GetDirectoryName(path)) &&
            !string.Equals(path, DefaultFolder, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException(UiText.Get("ParentMissing"));
        return path;
    }

    internal static string ValidateOrphanedRegistration(string folder, string installId)
    {
        string path = NormalizeFolder(folder);
        // Enumerating also surfaces access errors instead of treating them as
        // evidence that an installation has been deleted.
        bool directoryExists;
        try
        {
            var attributes = File.GetAttributes(path);
            if ((attributes & FileAttributes.Directory) == 0)
                throw new InvalidOperationException(UiText.Get("OldFolderFile"));
            directoryExists = true;
        }
        catch (FileNotFoundException) { directoryExists = false; }
        catch (DirectoryNotFoundException) { directoryExists = false; }
        if (directoryExists)
        {
            string[] contents = Directory.GetFileSystemEntries(path);
            foreach (string item in contents)
            {
                string fileName = Path.GetFileName(item);
                if (Array.Exists(Payload, name => string.Equals(fileName, name, StringComparison.OrdinalIgnoreCase)) ||
                    Array.Exists(LegacyPayload, name => string.Equals(fileName, name, StringComparison.OrdinalIgnoreCase)))
                    throw new InvalidOperationException(UiText.Get("ExistingInstall"));
            }
        }
        string marker = Path.Combine(path, Marker);
        if (Directory.Exists(marker) || (File.Exists(marker) &&
            (((File.GetAttributes(marker) & FileAttributes.ReparsePoint) != 0) ||
             string.IsNullOrEmpty(installId) || File.ReadAllText(marker) != installId)))
            throw new InvalidOperationException(UiText.Get("MarkerMismatch"));
        return path;
    }

    private sealed class SavedRegistration
    {
        internal readonly System.Collections.Generic.Dictionary<string, object> Values =
            new System.Collections.Generic.Dictionary<string, object>();
        internal readonly System.Collections.Generic.Dictionary<string, RegistryValueKind> Kinds =
            new System.Collections.Generic.Dictionary<string, RegistryValueKind>();
        internal string Folder;
        internal string Id;

        internal static SavedRegistration Read()
        {
            using (var key = Registry.CurrentUser.OpenSubKey(Entry))
            {
                if (key == null) return null;
                var result = new SavedRegistration();
                foreach (string name in key.GetValueNames())
                {
                    result.Values[name] = key.GetValue(name, null, RegistryValueOptions.DoNotExpandEnvironmentNames);
                    result.Kinds[name] = key.GetValueKind(name);
                }
                result.Folder = Convert.ToString(key.GetValue("InstallLocation"));
                result.Id = Convert.ToString(key.GetValue("InstallId"));
                return result;
            }
        }

        internal void Restore()
        {
            using (var key = Registry.CurrentUser.CreateSubKey(Entry))
            {
                foreach (string name in key.GetValueNames())
                    if (!Values.ContainsKey(name)) key.DeleteValue(name, false);
                foreach (var item in Values) key.SetValue(item.Key, item.Value, Kinds[item.Key]);
            }
        }
    }

    internal static string Install(string input)
    {
        using (var windows = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion"))
        {
            int build;
            if (windows == null || !int.TryParse(Convert.ToString(windows.GetValue("CurrentBuildNumber")), out build) || build < 19045)
                throw new InvalidOperationException(UiText.Get("WindowsRequired"));
        }
        RecoveredFolder = null;
        var previous = SavedRegistration.Read();
        string oldFolder = previous == null ? null : ValidateOrphanedRegistration(previous.Folder, previous.Id);
        string path = ValidateFolder(input, oldFolder, previous == null ? null : previous.Id);
        string menu = ShortcutPath(Environment.SpecialFolder.Programs);
        AssertShortcutFree(menu, oldFolder ?? path);
        byte[] previousMenu = File.Exists(menu) ? File.ReadAllBytes(menu) : null;
        string marker = Path.Combine(path, Marker);
        byte[] previousMarker = File.Exists(marker) ? File.ReadAllBytes(marker) : null;
        bool createdFolder = !Directory.Exists(path);
        object previousOwnership;
        bool ownedFolder = createdFolder || (previous != null &&
            string.Equals(path, oldFolder, StringComparison.OrdinalIgnoreCase) &&
            previous.Values.TryGetValue("CreatedFolder", out previousOwnership) &&
            previousOwnership is int && (int)previousOwnership == 1);
        var createdFiles = new System.Collections.Generic.List<string>();
        bool registered = false;
        bool menuCreated = false;
        bool markerWritten = false;
        try
        {
            Directory.CreateDirectory(path);
            string id = Guid.NewGuid().ToString("D");
            foreach (string name in Payload)
            {
                string destination = Path.Combine(path, name);
                using (var inputStream = Program.Resource(name))
                using (var output = new FileStream(destination, FileMode.CreateNew, FileAccess.Write))
                {
                    createdFiles.Add(destination);
                    inputStream.CopyTo(output);
                }
            }
            using (var markerStream = new FileStream(marker, previousMarker == null ? FileMode.CreateNew : FileMode.Open, FileAccess.Write))
            {
                if (previousMarker == null) createdFiles.Add(marker);
                markerWritten = true;
                markerStream.SetLength(0);
                using (var writer = new StreamWriter(markerStream)) writer.Write(id);
            }
            using (var registry = Registry.CurrentUser.CreateSubKey(Entry))
            {
                registered = true;
                registry.SetValue("DisplayName", Product.Name);
                registry.SetValue("DisplayVersion", Product.Version);
                registry.SetValue("Language", UiText.Language);
                registry.SetValue("InstallLocation", path);
                registry.SetValue("InstallId", id);
                registry.SetValue("CreatedFolder", ownedFolder ? 1 : 0);
                registry.SetValue("DisplayIcon", DisplayIcon(path));
                registry.SetValue("UninstallString", "\"" + Path.Combine(path, "Uninstall.exe") + "\"");
                registry.SetValue("NoModify", 1);
                registry.SetValue("NoRepair", 1);
            }
            CreateShortcut(menu, path, oldFolder);
            menuCreated = true;
            RecoveredFolder = oldFolder;
            return path;
        }
        catch
        {
            if (menuCreated) TryRollback(() => {
                if (previousMenu == null) File.Delete(menu);
                else File.WriteAllBytes(menu, previousMenu);
            });
            if (registered) TryRollback(() => {
                if (previous == null) Registry.CurrentUser.DeleteSubKey(Entry, false);
                else previous.Restore();
            });
            foreach (string file in createdFiles) TryRollback(() => File.Delete(file));
            if (markerWritten && previousMarker != null) TryRollback(() => File.WriteAllBytes(marker, previousMarker));
            if (createdFolder) TryRollback(() => Directory.Delete(path, false));
            throw;
        }
    }

    private static void TryRollback(Action action)
    {
        try { action(); }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    internal static string ShortcutPath(Environment.SpecialFolder folder)
    {
        string path = Environment.GetFolderPath(folder);
        if (string.IsNullOrWhiteSpace(path))
            throw new InvalidOperationException(UiText.Get("ShortcutFolderMissing"));
        return Path.Combine(path, Product.Name + ".lnk");
    }

    internal static string DisplayIcon(string folder)
    {
        return "\"" + Path.Combine(folder, Product.Executable) + "\",0";
    }

    internal static bool IsOwnedShortcutTarget(string target, string arguments, string folder)
    {
        if (string.IsNullOrEmpty(folder)) return false;
        bool native = string.IsNullOrEmpty(arguments) &&
            (string.Equals(target, Path.Combine(folder, Product.Executable), StringComparison.OrdinalIgnoreCase) ||
             string.Equals(target, Path.Combine(folder, "PilModu.exe"), StringComparison.OrdinalIgnoreCase));
        string legacyArguments = "-WindowStyle Hidden -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File \"" +
            Path.Combine(folder, "Pil-Modu-Uygulamasi.ps1") + "\"";
        return native || (string.Equals(target, PowerShell, StringComparison.OrdinalIgnoreCase) && arguments == legacyArguments);
    }

    private static void AssertShortcutFree(string shortcutPath, string replaceFromFolder)
    {
        if (!File.Exists(shortcutPath) && !Directory.Exists(shortcutPath)) return;
        if (!Directory.Exists(shortcutPath) &&
            (File.GetAttributes(shortcutPath) & FileAttributes.ReparsePoint) == 0)
        {
            dynamic shell = Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell", true));
            dynamic shortcut = null;
            try
            {
                shortcut = shell.CreateShortcut(shortcutPath);
                if (IsOwnedShortcutTarget((string)shortcut.TargetPath, (string)shortcut.Arguments, replaceFromFolder)) return;
            }
            finally
            {
                if (shortcut != null) Marshal.ReleaseComObject(shortcut);
                Marshal.ReleaseComObject(shell);
            }
        }
        throw new InvalidOperationException(UiText.Get("ShortcutCollision", shortcutPath));
    }

    internal static void CreateShortcut(string shortcutPath, string folder, string replaceFromFolder = null)
    {
        AssertShortcutFree(shortcutPath, replaceFromFolder ?? folder);
        dynamic shell = Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell", true));
        string temporary = Path.Combine(Path.GetDirectoryName(shortcutPath), "BatteryOptimizer-" + Guid.NewGuid().ToString("N") + ".lnk");
        try
        {
            dynamic shortcut = shell.CreateShortcut(temporary);
            shortcut.TargetPath = Path.Combine(folder, Product.Executable);
            shortcut.Arguments = "";
            shortcut.WorkingDirectory = folder;
            shortcut.IconLocation = Path.Combine(folder, Product.Executable) + ",0";
            shortcut.Description = Product.Name;
            shortcut.WindowStyle = 7;
            shortcut.Save();
            AssertShortcutFree(shortcutPath, replaceFromFolder ?? folder);
            if (File.Exists(shortcutPath)) File.Replace(temporary, shortcutPath, null);
            else File.Move(temporary, shortcutPath);
        }
        finally
        {
            if (File.Exists(temporary)) File.Delete(temporary);
        }
    }
}

#if !UNINSTALL
internal sealed class SetupWindow : Form
{
    private readonly Label heading = new Label();
    private readonly Panel content = new Panel();
    private readonly Button back = new Button();
    private readonly Button next = new Button();
    private readonly Button cancel = new Button();
    private readonly Label progress = new Label();
    private readonly Label languageLabel = new Label();
    private readonly FlowLayoutPanel languageRow = new FlowLayoutPanel();
    private readonly ComboBox languages = new ComboBox();
    private readonly CheckBox agreement = new CheckBox();
    private readonly TextBox path = new TextBox();
    private readonly CheckBox readme = new CheckBox();
    private readonly CheckBox desktop = new CheckBox();
    private int step;
    private string installedFolder;

    internal SetupWindow()
    {
        Text = UiText.Get("SetupTitle");
        Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
        StartPosition = FormStartPosition.CenterScreen;
        Font = new Font("Segoe UI", 11);
        AutoScaleDimensions = new SizeF(96, 96);
        AutoScaleMode = AutoScaleMode.Dpi;
        ClientSize = new Size(900, 640);
        MinimumSize = new Size(760, 540);
        BackColor = Color.FromArgb(244, 247, 252);
        ForeColor = Color.FromArgb(24, 40, 65);
        MaximizeBox = true;

        var frame = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(22), RowCount = 5, ColumnCount = 1 };
        frame.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        frame.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        frame.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        frame.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        frame.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        frame.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        Controls.Add(frame);
        progress.AutoSize = true;
        progress.ForeColor = Color.FromArgb(73, 93, 121);
        frame.Controls.Add(progress, 0, 0);
        languageRow.Dock = DockStyle.Top;
        languageRow.AutoSize = true;
        languageRow.WrapContents = false;
        languageRow.Margin = new Padding(0, 6, 0, 4);
        languageLabel.AutoSize = true;
        languageLabel.Margin = new Padding(0, 7, 10, 0);
        languages.DropDownStyle = ComboBoxStyle.DropDownList;
        languages.Width = 185;
        languages.Items.AddRange(UiText.Names);
        languages.SelectedIndex = Array.IndexOf(UiText.Codes, UiText.Language);
        languages.SelectedIndexChanged += delegate
        {
            if (languages.SelectedIndex < 0) return;
            UiText.Select(UiText.Codes[languages.SelectedIndex]);
            agreement.Checked = false;
            ShowPage(0);
        };
        languageRow.Controls.AddRange(new Control[] { languageLabel, languages });
        frame.Controls.Add(languageRow, 0, 1);
        heading.AutoSize = true;
        heading.Font = new Font("Segoe UI Semibold", 24);
        heading.Margin = new Padding(0, 4, 0, 12);
        frame.Controls.Add(heading, 0, 2);
        content.Dock = DockStyle.Fill;
        content.Margin = new Padding(0);
        frame.Controls.Add(content, 0, 3);

        var actions = new FlowLayoutPanel
        {
            FlowDirection = FlowDirection.RightToLeft, Dock = DockStyle.Fill, AutoSize = true,
            WrapContents = false, Margin = new Padding(0, 14, 0, 0)
        };
        ConfigureButton(cancel, UiText.Get("Cancel"));
        ConfigureButton(back, UiText.Get("Back"));
        ConfigureButton(next, UiText.Get("Next"));
        next.BackColor = Color.FromArgb(25, 61, 109);
        next.ForeColor = Color.White;
        next.UseVisualStyleBackColor = false;
        actions.Controls.AddRange(new Control[] { cancel, next, back });
        frame.Controls.Add(actions, 0, 4);
        AcceptButton = next;
        CancelButton = cancel;
        next.Click += Advance;
        back.Click += delegate { ShowPage(0); };
        cancel.Click += delegate { Close(); };
        agreement.CheckedChanged += delegate { if (step == 0) next.Enabled = agreement.Checked; };
        path.Text = InstallFiles.DefaultFolder;
        ShowPage(0);
    }

    internal void VerifyPages()
    {
        for (int i = 0; i < UiText.Codes.Length; i++)
        {
            languages.SelectedIndex = i;
            agreement.Checked = false;
            ShowPage(0);
            if (UiText.Language != UiText.Codes[i] || next.Enabled ||
                Text != UiText.Get("SetupTitle") || heading.Text != UiText.Get("Terms"))
                throw new InvalidOperationException("The language or agreement was not applied.");
            agreement.Checked = true;
            if (!next.Enabled) throw new InvalidOperationException("Agreement acceptance was not applied.");
            ShowPage(1);
            if (step != 1 || next.Text != UiText.Get("Install"))
                throw new InvalidOperationException("Location page is incomplete.");
            ShowPage(2);
            if (next.Text != UiText.Get("Finish") || !readme.Checked || desktop.Checked)
                throw new InvalidOperationException("Finish options are incomplete.");
        }
    }

    protected override void OnLoad(EventArgs args)
    {
        base.OnLoad(args);
        Rectangle desktopArea = Screen.FromControl(this).WorkingArea;
        int availableWidth = Math.Max(1, desktopArea.Width - 32);
        int availableHeight = Math.Max(1, desktopArea.Height - 32);
        MinimumSize = new Size(Math.Min(MinimumSize.Width, availableWidth),
            Math.Min(MinimumSize.Height, availableHeight));
        Size = new Size(Math.Min(Width, availableWidth), Math.Min(Height, availableHeight));
        Location = new Point(desktopArea.Left + (desktopArea.Width - Width) / 2,
            desktopArea.Top + (desktopArea.Height - Height) / 2);
    }

    private static void ConfigureButton(Button button, string label)
    {
        button.Text = label;
        button.AutoSize = true;
        button.MinimumSize = new Size(100, 40);
        button.FlatStyle = FlatStyle.Flat;
    }

    private static Label Description(string text)
    {
        return new Label { Text = text, Dock = DockStyle.Top, AutoSize = true, Margin = new Padding(0, 0, 0, 12) };
    }

    private void ShowPage(int page)
    {
        step = page;
        foreach (Control reusable in new Control[] { agreement, path, readme, desktop })
            if (reusable.Parent != null) reusable.Parent.Controls.Remove(reusable);
        while (content.Controls.Count != 0) content.Controls[0].Dispose();
        var rows = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1 };
        rows.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        content.Controls.Add(rows);
        Text = UiText.Get("SetupTitle");
        progress.Text = UiText.Get("Step", Product.Version, page + 1);
        languageLabel.Text = UiText.Get("Language");
        languages.AccessibleName = languageLabel.Text;
        languageRow.Visible = page == 0;
        back.Text = UiText.Get("Back");
        cancel.Text = UiText.Get("Cancel");
        back.Visible = page == 1;
        cancel.Visible = page != 2;
        next.Enabled = page != 0 || agreement.Checked;

        if (page == 0)
        {
            heading.Text = UiText.Get("Terms");
            next.Text = UiText.Get("Next");
            var terms = new TextBox
            {
                Dock = DockStyle.Fill, Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical,
                BackColor = Color.White, Margin = new Padding(0, 0, 0, 10),
                Text = UiText.Get("TermsBody")
            };
            rows.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            rows.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            rows.Controls.Add(terms, 0, 0);
            agreement.Text = UiText.Get("Agree");
            agreement.AutoSize = true;
            rows.Controls.Add(agreement, 0, 1);
        }
        else if (page == 1)
        {
            heading.Text = UiText.Get("Location");
            next.Text = UiText.Get("Install");
            rows.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            rows.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            rows.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            rows.Controls.Add(Description(UiText.Get("ChooseFolder")), 0, 0);
            var picker = new TableLayoutPanel { Dock = DockStyle.Top, AutoSize = true, ColumnCount = 2 };
            picker.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            picker.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            path.Dock = DockStyle.Fill;
            path.AccessibleName = UiText.Get("FolderLabel");
            var browse = new Button();
            ConfigureButton(browse, UiText.Get("Browse"));
            browse.Click += Browse;
            picker.Controls.Add(path, 0, 0);
            picker.Controls.Add(browse, 1, 0);
            rows.Controls.Add(picker, 0, 1);
            rows.Controls.Add(Description(UiText.Get("DefaultLocation")), 0, 2);
        }
        else
        {
            heading.Text = UiText.Get("Installed");
            next.Text = UiText.Get("Finish");
            for (int i = 0; i < 3; i++) rows.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            rows.Controls.Add(Description(UiText.Get(InstallFiles.RecoveredFolder == null ? "StartMenu" : "Recovered")), 0, 0);
            readme.Text = UiText.Get("Readme");
            readme.AutoSize = true;
            readme.Checked = true;
            desktop.Text = UiText.Get("DesktopShortcut");
            desktop.AutoSize = true;
            rows.Controls.Add(readme, 0, 1);
            rows.Controls.Add(desktop, 0, 2);
        }
    }

    private void Browse(object sender, EventArgs args)
    {
        using (var picker = new FolderBrowserDialog())
        {
            picker.Description = UiText.Get("SelectParent");
            if (picker.ShowDialog(this) == DialogResult.OK)
                path.Text = Path.Combine(picker.SelectedPath, Product.Name);
        }
    }

    private void Advance(object sender, EventArgs args)
    {
        try
        {
            if (step == 0)
            {
                if (agreement.Checked) ShowPage(1);
            }
            else if (step == 1)
            {
                installedFolder = Program.Install(path.Text);
                ShowPage(2);
            }
            else
            {
                if (desktop.Checked)
                {
                    InstallFiles.CreateShortcut(InstallFiles.ShortcutPath(Environment.SpecialFolder.DesktopDirectory), installedFolder, InstallFiles.RecoveredFolder);
                    desktop.Checked = false;
                }
                if (readme.Checked)
                    Process.Start(new ProcessStartInfo(Path.Combine(installedFolder, "README.txt")) { UseShellExecute = true });
                Close();
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, UiText.Get(step == 2 ? "FinishFailed" : "SetupFailed"),
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }
}
#endif
