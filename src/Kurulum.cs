using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("Pil Modu")]
[assembly: AssemblyProduct("Pil Modu")]
[assembly: AssemblyVersion("0.3.1.0")]
[assembly: AssemblyFileVersion("0.3.1.0")]

internal static class Program
{
    private const string AppLock = @"Local\PilModu.General.Window";

    [DllImport("user32.dll")]
    private static extern bool SetProcessDPIAware();

    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length == 1 && args[0] == "--verify")
        {
            try
            {
#if UNINSTALL
                if (!File.Exists(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Kaldir.ps1"))) return 2;
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
        if (stream == null) throw new InvalidOperationException("Paket dosyası eksik: " + name);
        return stream;
    }

#if UNINSTALL
    private static void RunUninstaller()
    {
        var answer = MessageBox.Show(
            "Pil Modu'nun kurduğu dosyalar ve kısayollar kalıcı olarak silinecek. Devam edilsin mi?",
            "Pil Modu'nu kaldır", MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2);
        if (answer != DialogResult.Yes) return;

        try
        {
            string script = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Kaldir.ps1");
            if (!File.Exists(script))
                throw new FileNotFoundException("Kaldırma dosyası bulunamadı.", script);
            var start = new ProcessStartInfo
            {
                FileName = InstallFiles.PowerShell,
                Arguments = "-NoProfile -NonInteractive -STA -ExecutionPolicy RemoteSigned -File \"" + script + "\"",
                UseShellExecute = false, CreateNoWindow = true,
                WorkingDirectory = Path.GetTempPath()
            };
            start.EnvironmentVariables["PILMODU_REMOVE_DIR"] = AppDomain.CurrentDomain.BaseDirectory;
            start.EnvironmentVariables["PILMODU_REMOVE_PID"] = Process.GetCurrentProcess().Id.ToString();
            using (Process.Start(start)) { }
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "Kaldırıcı başlatılamadı", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
#else
    internal static void Install(string folder)
    {
        bool ownsEvent;
        using (var appEvent = new EventWaitHandle(false, EventResetMode.AutoReset, AppLock, out ownsEvent))
        {
            if (!ownsEvent) throw new InvalidOperationException("Pil Modu açıksa önce simge menüsünden Çıkış'ı seç.");
            InstallFiles.Install(folder);
        }
    }
#endif
}

internal static class InstallFiles
{
    internal const string AppName = "Pil Modu";
    internal const string Version = "0.3.1";
    internal const string Entry = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\PilModu.WindowsProfile";
    internal const string Marker = ".pilmodu-install";
    internal static readonly string PowerShell = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe");
    internal static readonly string[] Payload = {
        "PilModu.exe", "PilModu.Native.dll", "PilModu.Visuals.dll", "Pil-Modu-Uygulamasi.ps1",
        "Pil-Modu.ps1", "Kaldir.ps1", "Pil-Modu.ico", "README.txt", "Uninstall.exe"
    };

    internal static string DefaultFolder
    {
        get
        {
            string programs = Environment.GetEnvironmentVariable("ProgramW6432") ??
                Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
            return Path.Combine(programs, "PilModu");
        }
    }

    internal static string ValidateFolder(string input)
    {
        if (string.IsNullOrWhiteSpace(input) || !Path.IsPathRooted(input) ||
            input.Length < 3 || input[1] != ':' || (input[2] != '\\' && input[2] != '/'))
            throw new InvalidOperationException("Yerel bir sürücüde tam klasör yolu seç.");

        string path = Path.GetFullPath(input.Trim()).TrimEnd('\\');
        string root = Path.GetPathRoot(path + "\\");
        if (path.Length <= 2 || new DriveInfo(root).DriveType != DriveType.Fixed || path.Length > 205)
            throw new InvalidOperationException("Yerel bir diskte kısa ve uygulamaya ayrılmış bir klasör seç.");

        for (var node = new DirectoryInfo(path); node != null; node = node.Parent)
        {
            if (File.Exists(node.FullName) || (node.Exists && (node.Attributes & FileAttributes.ReparsePoint) != 0))
                throw new InvalidOperationException("Kurulum yolu bir dosya veya klasör bağlantısı içeriyor.");
        }
        if (Directory.Exists(path) && Directory.GetFileSystemEntries(path).Length != 0)
            throw new InvalidOperationException("Yeni veya boş bir kurulum klasörü seç.");
        if (!Directory.Exists(Path.GetDirectoryName(path)) &&
            !string.Equals(path, DefaultFolder, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Üst klasörü önce oluştur veya var olan bir üst klasör seç.");
        return path;
    }

    internal static void Install(string input)
    {
        using (var windows = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion"))
        {
            int build;
            if (windows == null || !int.TryParse(Convert.ToString(windows.GetValue("CurrentBuildNumber")), out build) || build < 19045)
                throw new InvalidOperationException("Windows 10 22H2 veya Windows 11 gerekli.");
        }
        using (var current = Registry.CurrentUser.OpenSubKey(Entry))
            if (current != null) throw new InvalidOperationException("Bu kullanıcıda Pil Modu zaten kurulu. Önce mevcut sürümü kaldır.");

        string path = ValidateFolder(input);
        string menu = ShortcutPath(Environment.SpecialFolder.Programs);
        AssertShortcutFree(menu);
        bool createdFolder = !Directory.Exists(path);
        var createdFiles = new System.Collections.Generic.List<string>();
        bool registered = false;
        bool menuCreated = false;
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
            string marker = Path.Combine(path, Marker);
            using (var writer = new StreamWriter(new FileStream(marker, FileMode.CreateNew, FileAccess.Write)))
            {
                createdFiles.Add(marker);
                writer.Write(id);
            }
            using (var registry = Registry.CurrentUser.CreateSubKey(Entry))
            {
                registered = true;
                registry.SetValue("DisplayName", AppName);
                registry.SetValue("DisplayVersion", Version);
                registry.SetValue("InstallLocation", path);
                registry.SetValue("InstallId", id);
                registry.SetValue("CreatedFolder", createdFolder ? 1 : 0);
                registry.SetValue("DisplayIcon", Path.Combine(path, "Pil-Modu.ico"));
                registry.SetValue("UninstallString", "\"" + Path.Combine(path, "Uninstall.exe") + "\"");
                registry.SetValue("NoModify", 1);
                registry.SetValue("NoRepair", 1);
            }
            CreateShortcut(menu, path);
            menuCreated = true;
        }
        catch
        {
            if (menuCreated) TryRollback(() => File.Delete(menu));
            if (registered) TryRollback(() => Registry.CurrentUser.DeleteSubKey(Entry, false));
            foreach (string file in createdFiles) TryRollback(() => File.Delete(file));
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
            throw new InvalidOperationException("Windows kısayol klasörünü bildirmedi.");
        return Path.Combine(path, AppName + ".lnk");
    }

    private static void AssertShortcutFree(string shortcutPath)
    {
        if (File.Exists(shortcutPath) || Directory.Exists(shortcutPath))
            throw new InvalidOperationException("Aynı adlı bir kısayol zaten var: " + shortcutPath);
    }

    internal static void CreateShortcut(string shortcutPath, string folder)
    {
        AssertShortcutFree(shortcutPath);
        dynamic shell = Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell", true));
        string temporary = Path.Combine(Path.GetDirectoryName(shortcutPath), "PilModu-" + Guid.NewGuid().ToString("N") + ".lnk");
        try
        {
            dynamic shortcut = shell.CreateShortcut(temporary);
            shortcut.TargetPath = Path.Combine(folder, "PilModu.exe");
            shortcut.Arguments = "";
            shortcut.WorkingDirectory = folder;
            shortcut.IconLocation = Path.Combine(folder, "Pil-Modu.ico") + ",0";
            shortcut.Description = AppName;
            shortcut.WindowStyle = 7;
            shortcut.Save();
            File.Move(temporary, shortcutPath);
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
    private readonly CheckBox agreement = new CheckBox();
    private readonly TextBox path = new TextBox();
    private readonly CheckBox readme = new CheckBox();
    private readonly CheckBox desktop = new CheckBox();
    private int step;
    private string installedFolder;

    internal SetupWindow()
    {
        Text = "Pil Modu Kurulumu";
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

        var frame = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(22), RowCount = 4, ColumnCount = 1 };
        frame.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        frame.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        frame.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        frame.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        frame.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        Controls.Add(frame);
        progress.AutoSize = true;
        progress.ForeColor = Color.FromArgb(73, 93, 121);
        frame.Controls.Add(progress, 0, 0);
        heading.AutoSize = true;
        heading.Font = new Font("Segoe UI Semibold", 24);
        heading.Margin = new Padding(0, 4, 0, 12);
        frame.Controls.Add(heading, 0, 1);
        content.Dock = DockStyle.Fill;
        content.Margin = new Padding(0);
        frame.Controls.Add(content, 0, 2);

        var actions = new FlowLayoutPanel
        {
            FlowDirection = FlowDirection.RightToLeft, Dock = DockStyle.Fill, AutoSize = true,
            WrapContents = false, Margin = new Padding(0, 14, 0, 0)
        };
        ConfigureButton(cancel, "İptal");
        ConfigureButton(back, "Geri");
        ConfigureButton(next, "İleri");
        next.BackColor = Color.FromArgb(25, 61, 109);
        next.ForeColor = Color.White;
        next.UseVisualStyleBackColor = false;
        actions.Controls.AddRange(new Control[] { cancel, next, back });
        frame.Controls.Add(actions, 0, 3);
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
        if (next.Enabled) throw new InvalidOperationException("Agreement must be accepted.");
        agreement.Checked = true;
        if (!next.Enabled) throw new InvalidOperationException("Agreement acceptance was not applied.");
        ShowPage(1);
        if (step != 1 || next.Text != "Kur") throw new InvalidOperationException("Location page is incomplete.");
        ShowPage(2);
        if (next.Text != "Bitir" || !readme.Checked || desktop.Checked)
            throw new InvalidOperationException("Finish options are incomplete.");
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
        progress.Text = string.Format("PİL MODU {0}   /   ADIM {1} / 3", InstallFiles.Version, page + 1);
        back.Visible = page == 1;
        cancel.Visible = page != 2;
        next.Enabled = page != 0 || agreement.Checked;

        if (page == 0)
        {
            heading.Text = "Kurulum koşulları";
            next.Text = "İleri";
            var terms = new TextBox
            {
                Dock = DockStyle.Fill, Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical,
                BackColor = Color.White, Margin = new Padding(0, 0, 0, 10),
                Text = "Pil Modu, desteklenen Windows cihazlarında ekran ve güç ayarlarını değiştiren bir masaüstü uygulamasıdır.\r\n\r\n" +
                    "Kurulum, seçtiğin klasöre uygulama dosyalarını ve kaldırıcıyı yazar. Başlat menüsünde kısayol ve Windows Uygulamalar listesinde kaldırma kaydı oluşturur.\r\n\r\n" +
                    "Dışarı Modu, desteklenen ayarları değiştirirken önceki değerleri bu kullanıcı hesabında saklar. Kaldırmadan önce Normal Mod ile ayarlarını geri yükle. \r\n\r\n" + 
                    "Bana destek olmak isterseniz GitHub Hesabımı ziyaraet edebilirsiniz: https://github.com/bnsolaris"
            };
            rows.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            rows.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            rows.Controls.Add(terms, 0, 0);
            agreement.Text = "Kurulum koşullarını okudum ve kabul ediyorum.";
            agreement.AutoSize = true;
            rows.Controls.Add(agreement, 0, 1);
        }
        else if (page == 1)
        {
            heading.Text = "Kurulum konumu";
            next.Text = "Kur";
            rows.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            rows.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            rows.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            rows.Controls.Add(Description("Pil Modu için yeni veya boş bir klasör seç."), 0, 0);
            var picker = new TableLayoutPanel { Dock = DockStyle.Top, AutoSize = true, ColumnCount = 2 };
            picker.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            picker.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            path.Dock = DockStyle.Fill;
            path.AccessibleName = "Kurulum klasörü";
            var browse = new Button();
            ConfigureButton(browse, "Gözat…");
            browse.Click += Browse;
            picker.Controls.Add(path, 0, 0);
            picker.Controls.Add(browse, 1, 0);
            rows.Controls.Add(picker, 0, 1);
            rows.Controls.Add(Description("Varsayılan konum Program Files klasörüdür. Kurulum ve uygulama yönetici izniyle çalışır."), 0, 2);
        }
        else
        {
            heading.Text = "Kurulum tamamlandı";
            next.Text = "Bitir";
            for (int i = 0; i < 3; i++) rows.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            rows.Controls.Add(Description("Pil Modu'nu Başlat menüsünden açabilirsin."), 0, 0);
            readme.Text = "README dosyasını aç";
            readme.AutoSize = true;
            readme.Checked = true;
            desktop.Text = "Masaüstüne kısayol oluştur";
            desktop.AutoSize = true;
            rows.Controls.Add(readme, 0, 1);
            rows.Controls.Add(desktop, 0, 2);
        }
    }

    private void Browse(object sender, EventArgs args)
    {
        using (var picker = new FolderBrowserDialog())
        {
            picker.Description = "Pil Modu klasörünün oluşturulacağı üst klasörü seç.";
            if (picker.ShowDialog(this) == DialogResult.OK)
                path.Text = Path.Combine(picker.SelectedPath, "PilModu");
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
                installedFolder = InstallFiles.ValidateFolder(path.Text);
                Program.Install(installedFolder);
                ShowPage(2);
            }
            else
            {
                if (desktop.Checked)
                {
                    InstallFiles.CreateShortcut(InstallFiles.ShortcutPath(Environment.SpecialFolder.DesktopDirectory), installedFolder);
                    desktop.Checked = false;
                }
                if (readme.Checked)
                    Process.Start(new ProcessStartInfo(Path.Combine(installedFolder, "README.txt")) { UseShellExecute = true });
                Close();
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, step == 2 ? "Son adım tamamlanamadı" : "Kurulum tamamlanamadı",
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }
}
#endif
