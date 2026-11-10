param([switch]$SelfTest, [string]$ProbePath)

$ErrorActionPreference = 'Stop'
if (-not $SelfTest) {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        try {
            $launchArgs = '-NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File "{0}"' -f $PSCommandPath
            Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $launchArgs -Verb RunAs -WindowStyle Hidden | Out-Null
        }
        catch {
            Add-Type -AssemblyName System.Windows.Forms
            [void][Windows.Forms.MessageBox]::Show('Pil Modu yönetici izniyle başlatılamadı.', 'Pil Modu', 'OK', 'Warning')
        }
        return
    }
}
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class PilModuVisuals
{
    [DllImport("user32.dll")] private static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] private static extern bool DestroyIcon(IntPtr icon);

    public static void EnableDpiAwareness()
    {
        SetProcessDPIAware();
        SetThreadDpiAwarenessContext(new IntPtr(-2));
    }

    public static Icon CreateBatteryIcon(int size)
    {
        using (var bitmap = new Bitmap(size, size, PixelFormat.Format32bppArgb))
        using (var graphics = Graphics.FromImage(bitmap))
        using (var background = new SolidBrush(Color.FromArgb(25, 61, 109)))
        using (var white = new SolidBrush(Color.White))
        using (var charge = new SolidBrush(Color.FromArgb(107, 235, 183)))
        {
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            graphics.ScaleTransform(size / 32f, size / 32f);
            graphics.FillEllipse(background, 0, 0, 32, 32);
            graphics.FillRectangle(white, 6, 10, 19, 12);
            graphics.FillRectangle(white, 25, 13, 2, 6);
            graphics.FillRectangle(background, 8, 12, 15, 8);
            graphics.FillRectangle(charge, 9, 13, 10, 6);

            IntPtr handle = bitmap.GetHicon();
            try
            {
                using (var borrowed = Icon.FromHandle(handle))
                    return (Icon)borrowed.Clone();
            }
            finally { DestroyIcon(handle); }
        }
    }
}
'@
[PilModuVisuals]::EnableDpiAwareness()
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$workerPath = Join-Path $PSScriptRoot 'Pil-Modu.ps1'
$snapshotPath = Join-Path $env:LOCALAPPDATA 'PilModuProfile\onceki-ayarlar.json'
$script:worker = $null
$script:exiting = $false
$script:openSignal = $null

function Start-ModeWorker([string]$Mode, [string]$Path = $workerPath) {
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = Join-Path $PSHOME 'powershell.exe'
    $start.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -Command "[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); try { & $env:PILMODU_WORKER -Mode $env:PILMODU_ACTION 6>&1 | Out-String -Stream -Width 200 | ForEach-Object { [Console]::WriteLine($_) }; exit 0 } catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }"'
    $start.EnvironmentVariables['PILMODU_WORKER'] = $Path
    $start.EnvironmentVariables['PILMODU_ACTION'] = $Mode
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.Encoding]::UTF8
    $start.StandardErrorEncoding = [Text.Encoding]::UTF8
    $process = [Diagnostics.Process]::Start($start)
    [pscustomobject]@{
        Process = $process
        Output = $process.StandardOutput.ReadToEndAsync()
        Errors = $process.StandardError.ReadToEndAsync()
    }
}

function Show-MainWindow {
    $form.Show()
    $form.WindowState = 'Normal'
    $form.Activate()
}

function Set-ModeControls([bool]$Enabled) {
    foreach ($control in $outside, $normal, $outsideMenu, $normalMenu, $exitMenu) {
        $control.Enabled = $Enabled
    }
}

function Set-ModeButtonColors([string]$Mode) {
    $selected, $unselected = if ($Mode -eq 'Disari') { $outside, $normal } else { $normal, $outside }
    $selected.BackColor = $surface
    $selected.ForeColor = $ink
    $selected.FlatAppearance.BorderColor = $buttonBorder
    $selected.FlatAppearance.BorderSize = 1
    $unselected.BackColor = $accent
    $unselected.ForeColor = [Drawing.Color]::White
    $unselected.FlatAppearance.BorderSize = 0
}

function Show-Result([string]$Message, [string]$Details, [bool]$Failed) {
    $status.Text = $Message
    $status.ForeColor = if ($Failed) { [Drawing.Color]::FromArgb(152, 48, 44) } else { $ink }
    $result.Text = $Details.Trim()
    $result.Select(0, 0)
    $result.ScrollToCaret()
    if (-not $form.Visible -or $form.WindowState -eq 'Minimized') {
        $icon = if ($Failed) { [Windows.Forms.ToolTipIcon]::Error } else { [Windows.Forms.ToolTipIcon]::Info }
        $tray.ShowBalloonTip(4000, 'Pil Modu', $Message, $icon)
    }
}

function Start-Mode([string]$Mode, [string]$Title) {
    if ($null -ne $script:worker) { return }
    if ($Mode -eq 'Normal' -and -not (Test-Path -LiteralPath $snapshotPath -PathType Leaf)) {
        Set-ModeButtonColors 'Normal'
        Show-Result 'Geri yüklenecek bir Dışarı Modu kaydı bulunamadı.' '' $false
        return
    }
    if (-not (Test-Path -LiteralPath $workerPath -PathType Leaf)) {
        Show-Result 'Pil-Modu.ps1 bulunamadı.' 'Uygulama dosyalarını aynı klasörde tut.' $true
        return
    }
    Set-ModeControls $false
    $status.Text = "$Title uygulanıyor…"
    $status.ForeColor = $ink
    $result.Clear()
    try {
        $script:worker = Start-ModeWorker $Mode
        $script:workerMode = $Mode
        $script:workerTitle = $Title
    }
    catch {
        Set-ModeControls $true
        Show-Result "$Title başlatılamadı." $_.Exception.Message $true
    }
}

if (-not $SelfTest) {
    $created = $false
    $script:openSignal = [Threading.EventWaitHandle]::new(
        $false, [Threading.EventResetMode]::AutoReset, 'Local\PilModu.General.Window', [ref]$created)
    if (-not $created) {
        [void]$script:openSignal.Set()
        $script:openSignal.Dispose()
        return
    }
}

[Windows.Forms.Application]::EnableVisualStyles()
[Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)
$ink = [Drawing.Color]::FromArgb(22, 38, 61)
$muted = [Drawing.Color]::FromArgb(74, 90, 110)
$surface = [Drawing.Color]::FromArgb(255, 255, 255)
$accent = [Drawing.Color]::FromArgb(25, 61, 109)
$buttonBorder = [Drawing.Color]::FromArgb(180, 194, 212)
$batteryIcon = [PilModuVisuals]::CreateBatteryIcon(32)
$form = New-Object Windows.Forms.Form -Property @{
    Text = 'Pil Modu'
    StartPosition = 'CenterScreen'
    ClientSize = [Drawing.Size]::new(620, 420)
    MinimumSize = [Drawing.Size]::new(570, 390)
    FormBorderStyle = 'Sizable'
    MaximizeBox = $true
    Font = [Drawing.Font]::new('Segoe UI', 10)
    Icon = $batteryIcon
    BackColor = [Drawing.Color]::FromArgb(242, 246, 252)
    ForeColor = $ink
    AutoScaleDimensions = [Drawing.SizeF]::new(96, 96)
    AutoScaleMode = 'Dpi'
}
$layout = New-Object Windows.Forms.TableLayoutPanel -Property @{
    Dock = 'Fill'
    ColumnCount = 1
    RowCount = 5
    Padding = [Windows.Forms.Padding]::new(22, 18, 22, 18)
}
[void]$layout.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent', 100))
foreach ($style in 'AutoSize', 'AutoSize', 'AutoSize', 'Percent', 'AutoSize') {
    [void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new($style, 100))
}
$form.Controls.Add($layout)

$titleLabel = New-Object Windows.Forms.Label -Property @{
    Text = 'Pil Modu'
    Font = [Drawing.Font]::new('Segoe UI Semibold', 21)
    Margin = [Windows.Forms.Padding]::new(0, 0, 0, 2)
    AutoSize = $true
}
$subtitle = New-Object Windows.Forms.Label -Property @{
    Text = 'Windows için pil, güç ve ekran ayarları'
    ForeColor = $muted
    Margin = [Windows.Forms.Padding]::new(0, 0, 0, 16)
    AutoSize = $true
}
$buttons = New-Object Windows.Forms.TableLayoutPanel -Property @{
    Dock = 'Top'
    AutoSize = $true
    ColumnCount = 2
    RowCount = 1
    Margin = [Windows.Forms.Padding]::new(0, 0, 0, 14)
}
foreach ($column in 1, 2) {
    [void]$buttons.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent', 50))
}
$outside = New-Object Windows.Forms.Button -Property @{
    Text = 'Dışarı Modu'
    Dock = 'Fill'
    MinimumSize = [Drawing.Size]::new(0, 42)
    Margin = [Windows.Forms.Padding]::new(0, 0, 5, 0)
    FlatStyle = 'Flat'
    UseVisualStyleBackColor = $false
}
$normal = New-Object Windows.Forms.Button -Property @{
    Text = 'Normal Mod'
    Dock = 'Fill'
    MinimumSize = [Drawing.Size]::new(0, 42)
    Margin = [Windows.Forms.Padding]::new(5, 0, 0, 0)
    FlatStyle = 'Flat'
    UseVisualStyleBackColor = $false
}
$buttons.Controls.Add($outside, 0, 0)
$buttons.Controls.Add($normal, 1, 0)
$initialMode = if (Test-Path -LiteralPath $snapshotPath -PathType Leaf) { 'Disari' } else { 'Normal' }
Set-ModeButtonColors $initialMode

$card = New-Object Windows.Forms.TableLayoutPanel -Property @{
    Dock = 'Fill'
    ColumnCount = 1
    RowCount = 2
    Margin = [Windows.Forms.Padding]::new(0)
    Padding = [Windows.Forms.Padding]::new(13, 10, 13, 8)
    BackColor = $surface
}
[void]$card.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent', 100))
[void]$card.RowStyles.Add([Windows.Forms.RowStyle]::new('AutoSize'))
[void]$card.RowStyles.Add([Windows.Forms.RowStyle]::new('Percent', 100))
$status = New-Object Windows.Forms.Label -Property @{
    Text = 'Hazır. Bir mod seçebilirsin.'
    Font = [Drawing.Font]::new('Segoe UI Semibold', 10)
    AutoSize = $true
    Margin = [Windows.Forms.Padding]::new(0, 0, 0, 6)
}
$result = New-Object Windows.Forms.TextBox -Property @{
    AccessibleName = 'İşlem sonucu'
    Dock = 'Fill'
    Margin = [Windows.Forms.Padding]::new(0)
    BorderStyle = 'None'
    BackColor = $surface
    ForeColor = $muted
    Multiline = $true
    ReadOnly = $true
    ScrollBars = 'Vertical'
    TabStop = $false
}
$card.Controls.Add($status, 0, 0)
$card.Controls.Add($result, 0, 1)
$hint = New-Object Windows.Forms.Label -Property @{
    Text = 'Kapatınca saatin yanındaki simge alanında kalır.'
    Font = [Drawing.Font]::new('Segoe UI', 9)
    ForeColor = $muted
    Margin = [Windows.Forms.Padding]::new(0, 10, 0, 0)
    AutoSize = $true
}
$layout.Controls.Add($titleLabel, 0, 0)
$layout.Controls.Add($subtitle, 0, 1)
$layout.Controls.Add($buttons, 0, 2)
$layout.Controls.Add($card, 0, 3)
$layout.Controls.Add($hint, 0, 4)

$menu = New-Object Windows.Forms.ContextMenuStrip
$openMenu = $menu.Items.Add('Pencereyi aç')
[void]$menu.Items.Add([Windows.Forms.ToolStripSeparator]::new())
$outsideMenu = $menu.Items.Add($outside.Text)
$normalMenu = $menu.Items.Add($normal.Text)
[void]$menu.Items.Add([Windows.Forms.ToolStripSeparator]::new())
$exitMenu = $menu.Items.Add('Çıkış')
$tray = New-Object Windows.Forms.NotifyIcon -Property @{
    Text = 'Pil Modu'
    Icon = $form.Icon
    ContextMenuStrip = $menu
}

$outside.Add_Click({ Start-Mode 'Disari' 'Dışarı Modu' })
$normal.Add_Click({ Start-Mode 'Normal' 'Normal Mod' })
$outsideMenu.Add_Click({ Start-Mode 'Disari' 'Dışarı Modu' })
$normalMenu.Add_Click({ Start-Mode 'Normal' 'Normal Mod' })
$openMenu.Add_Click({ Show-MainWindow })
$tray.Add_DoubleClick({ Show-MainWindow })
$exitMenu.Add_Click({ $script:exiting = $true; $form.Close() })
$form.Add_FormClosing({
    param($sender, $eventArgs)
    if ($eventArgs.CloseReason -eq 'UserClosing' -and -not $script:exiting) {
        $eventArgs.Cancel = $true
        $form.Hide()
    }
})

$timer = New-Object Windows.Forms.Timer -Property @{ Interval = 200 }
$timer.Add_Tick({
    if ($script:openSignal.WaitOne(0)) { Show-MainWindow }
    if ($null -eq $script:worker -or -not $script:worker.Process.HasExited) { return }
    $run = $script:worker
    try {
        $run.Process.WaitForExit()
        $details = $run.Output.GetAwaiter().GetResult()
        if ($run.Process.ExitCode -eq 0) {
            Set-ModeButtonColors $script:workerMode
            Show-Result "$script:workerTitle işlemi tamamlandı." $details $false
        }
        else {
            $errors = $run.Errors.GetAwaiter().GetResult()
            Show-Result "$script:workerTitle tamamlanamadı. Bazı ayarlar değişmiş olabilir." "$details`r`n$errors" $true
        }
    }
    catch {
        Show-Result "$script:workerTitle sonucu okunamadı." $_.Exception.Message $true
    }
    finally {
        $run.Process.Dispose()
        $script:worker = $null
        Set-ModeControls $true
    }
})

try {
    if ($SelfTest) {
        $form.PerformLayout()
        if ($layout.Controls.Count -ne 5 -or $menu.Items.Count -ne 6 -or $tray.Icon.Width -ne 32) {
            throw 'Pencere, pil simgesi veya simge menüsü eksik.'
        }
        if ($outside.Width -lt 120 -or $normal.Width -lt 120 -or $result.Height -lt 55) {
            throw 'Pencere yerleşiminde yeterli alan kalmadı.'
        }
        if ($outside.Text -cne 'Dışarı Modu' -or $outsideMenu.Text -cne $outside.Text -or $normalMenu.Text -cne $normal.Text) {
            throw 'Pencere ve simge menüsündeki mod etiketleri uyuşmuyor.'
        }
        Set-ModeButtonColors 'Disari'
        if ($outside.BackColor -ne $surface -or $normal.BackColor -ne $accent) { throw 'Dışarı Modu renkleri hatalı.' }
        Set-ModeButtonColors 'Normal'
        if ($normal.BackColor -ne $surface -or $outside.BackColor -ne $accent) { throw 'Normal Mod renkleri hatalı.' }
        $testWorker = if ($ProbePath) { Start-ModeWorker 'Durum' (Resolve-Path -LiteralPath $ProbePath).Path } else { Start-ModeWorker 'Durum' }
        try {
            $testWorker.Process.WaitForExit()
            if ($testWorker.Process.ExitCode -ne 0) { throw $testWorker.Errors.GetAwaiter().GetResult() }
            $testOutput = $testWorker.Output.GetAwaiter().GetResult()
            if ($testOutput -notmatch 'YenilemeHizi|Yenileme hızı') { throw 'Pil betiği durum bilgisi döndürmedi.' }
            if ($ProbePath) {
                if ($testOutput -notmatch "Şarjda değil\r?\nParlaklık %30") {
                    throw 'Türkçe karakterler veya satır sonları korunamadı.'
                }
                $failure = Start-ModeWorker 'Disari' (Resolve-Path -LiteralPath $ProbePath).Path
                try {
                    $failure.Process.WaitForExit()
                    if ($failure.Process.ExitCode -eq 0 -or $failure.Errors.GetAwaiter().GetResult() -notmatch 'Örnek hata') {
                        throw 'Alt işlemin hatası arayüze iletilmedi.'
                    }
                }
                finally { $failure.Process.Dispose() }
            }
            Write-Output 'Pencere, simge menüsü ve alt işlem iletişimi doğrulandı.'
        }
        finally { $testWorker.Process.Dispose() }
        return
    }
    $tray.Visible = $true
    $timer.Start()
    [Windows.Forms.Application]::Run($form)
}
finally {
    $timer.Dispose()
    $tray.Visible = $false
    $tray.Dispose()
    $menu.Dispose()
    $form.Dispose()
    $batteryIcon.Dispose()
    if ($null -ne $script:openSignal) { $script:openSignal.Dispose() }
}
