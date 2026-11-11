[CmdletBinding()]
param([switch]$NoPause)

$ErrorActionPreference = 'Stop'

function Get-RecoveryBrightness([string]$Id) {
    $panels = @(Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightness |
        Where-Object { $_.Active -and $_.InstanceName -eq $Id })
    if ($panels.Count -ne 1 -or $null -eq $panels[0].CurrentBrightness) {
        throw 'Kaydedilen dahili ekranın parlaklığı okunamadı. Geri yükleme kaydına dokunulmadı.'
    }
    $value = [int]$panels[0].CurrentBrightness
    if ($value -lt 0 -or $value -gt 100) { throw 'Ekran geçerli bir parlaklık değeri bildirmedi.' }
    return $value
}

function Repair-BrightnessJournal([string]$StatePath, [string]$BackupRoot) {
    if (-not [IO.File]::Exists($StatePath)) {
        if (Test-Path -LiteralPath "$StatePath.new") { throw 'Tamamlanmamış bir kayıt dosyası var. Onarım durduruldu.' }
        return [pscustomobject]@{ BackupPath = $null; Remaining = @() }
    }
    if (([IO.File]::GetAttributes($StatePath) -band [IO.FileAttributes]::ReparsePoint) -or
        ((Get-Item -LiteralPath (Split-Path -Parent $StatePath) -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Geri yükleme kaydı bir dosya veya klasör bağlantısı içeriyor.'
    }
    if (Test-Path -LiteralPath "$StatePath.new") { throw 'Tamamlanmamış bir kayıt dosyası var. Onarım durduruldu.' }
    $originalBytes = [IO.File]::ReadAllBytes($StatePath)
    $saved = [IO.File]::ReadAllText($StatePath) | ConvertFrom-Json
    $property = $saved.PSObject.Properties['Brightness']
    if (-not $property) { throw 'Bekleyen kayıtta parlaklık ayarı yok. Diğer ayarlara dokunulmadı.' }
    $entry = $property.Value
    $target = 0
    if ($entry.Id -isnot [string] -or [string]::IsNullOrWhiteSpace($entry.Id) -or
        -not [int]::TryParse([string]$entry.Value, [ref]$target) -or $target -lt 0 -or $target -gt 100) {
        throw 'Kaydedilen parlaklık bilgisi geçersiz. Kayıt korunuyor.'
    }
    $actual = Get-RecoveryBrightness $entry.Id
    if ($actual -ne $target) {
        throw "Kaydedilen parlaklık %$target, geçerli parlaklık %$actual. Windows ayarlarından parlaklığı %$target yapıp tekrar çalıştır. Kayıt korunuyor."
    }

    [void][IO.Directory]::CreateDirectory($BackupRoot)
    $name = 'Profil-onarim_' + [DateTime]::UtcNow.ToString("yyyy-MM-dd_HH-mm-ss'Z'") + '_' + [guid]::NewGuid().ToString('N') + '.json'
    $backup = Join-Path $BackupRoot $name
    $stream = [IO.File]::Open($backup, 'CreateNew', 'Write', 'None')
    try { $stream.Write($originalBytes, 0, $originalBytes.Length) }
    finally { $stream.Dispose() }
    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($backup)) -cne [Convert]::ToBase64String($originalBytes)) {
        throw 'Yedek doğrulanamadı. Geri yükleme kaydı korunuyor.'
    }
    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($StatePath)) -cne [Convert]::ToBase64String($originalBytes) -or
        (Get-RecoveryBrightness $entry.Id) -ne $target) {
        throw 'Onarım sırasında kayıt veya parlaklık değişti. İşlem durduruldu.'
    }

    # Only clear the setting whose original value was verified. Never discard
    # another pending restoration just to let the uninstaller continue.
    $saved.PSObject.Properties.Remove('Brightness')
    $remaining = @($saved.PSObject.Properties | ForEach-Object Name)
    if ($remaining.Count -eq 0) { [IO.File]::Delete($StatePath) }
    else {
        $pending = "$StatePath.new"
        [IO.File]::WriteAllText($pending, ($saved | ConvertTo-Json -Depth 5), [Text.Encoding]::UTF8)
        [IO.File]::Replace($pending, $StatePath, [NullString]::Value)
    }
    return [pscustomobject]@{ BackupPath = $backup; Remaining = $remaining }
}

$lock = $null
$ownsLock = $false
$failed = $false
try {
    $appEvent = $null
    try { $appEvent = [Threading.EventWaitHandle]::OpenExisting('Local\PilModu.General.Window') }
    catch [Threading.WaitHandleCannotBeOpenedException] { }
    if ($null -ne $appEvent) {
        $appEvent.Dispose()
        throw "Önce saatin yanındaki Pil Modu simgesine sağ tıklayıp Çıkış'ı seç. Pencerenin X düğmesi uygulamayı kapatmaz."
    }
    $lock = [Threading.Mutex]::new($false, 'Local\PilModu.General.Profile')
    try { $ownsLock = $lock.WaitOne(0) }
    catch [Threading.AbandonedMutexException] { $ownsLock = $true }
    if (-not $ownsLock) { throw 'Bir profil işlemi hâlâ çalışıyor. Bitmesini bekleyip tekrar dene.' }

    $statePath = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'PilModuProfile\onceki-ayarlar.json'
    $backupRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'Pil-Modu-Yedekler'
    $result = Repair-BrightnessJournal $statePath $backupRoot
    if ($result.BackupPath) {
        Write-Host 'Parlaklığın eski değerine döndüğü doğrulandı. Hatalı bekleme kaydı temizlendi.' -ForegroundColor Green
        Write-Host "Doğrulanan yedek: $($result.BackupPath)"
    }
    if ($result.Remaining.Count -gt 0) {
        throw "Başka ayarlar hâlâ geri yüklenmeyi bekliyor: $($result.Remaining -join ', '). Bu kayıtlar korundu."
    }

    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Uninstall\PilModu.WindowsProfile')
    if (-not $key) { throw 'Kurulum kaydı bulunamadı. Onarım tamamlandı; kurulum klasöründeki Uninstall.exe dosyasını açabilirsin.' }
    try {
        $folder = [string]$key.GetValue('InstallLocation')
        $installId = [string]$key.GetValue('InstallId')
    }
    finally { $key.Dispose() }
    if ([string]::IsNullOrWhiteSpace($folder) -or [string]::IsNullOrWhiteSpace($installId)) {
        throw 'Kurulum bilgisi eksik. Kurulum klasöründeki Uninstall.exe dosyasını aç.'
    }
    $uninstaller = Join-Path $folder 'Uninstall.exe'
    if (-not [IO.File]::Exists($uninstaller) -or [IO.File]::ReadAllText((Join-Path $folder '.pilmodu-install')) -ne $installId) {
        throw 'Kaldırıcı ile kurulum kaydı eşleşmiyor. Otomatik başlatılmadı.'
    }
    Start-Process -FilePath $uninstaller -WorkingDirectory $folder -Verb RunAs
    Write-Host 'Kaldırıcı açıldı. Windows izin ekranını ve kaldırma sorusunu onayla.'
}
catch {
    $failed = $true
    Write-Host $_.Exception.Message -ForegroundColor Red
}
finally {
    if ($ownsLock) { $lock.ReleaseMutex() }
    if ($null -ne $lock) { $lock.Dispose() }
    if (-not $NoPause -and [Environment]::UserInteractive) { [void](Read-Host 'Pencereyi kapatmak için Enter') }
}
if ($failed) { exit 1 }
