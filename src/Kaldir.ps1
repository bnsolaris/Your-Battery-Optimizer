$ErrorActionPreference = 'Stop'
$entry = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\PilModu.WindowsProfile'
$markerName = '.pilmodu-install'
$payload = 'PilModu.exe', 'PilModu.Native.dll', 'PilModu.Visuals.dll', 'Pil-Modu-Uygulamasi.ps1', 'Pil-Modu.ps1', 'Kaldir.ps1', 'Pil-Modu.ico', 'README.txt', 'Uninstall.exe'

function Assert-InstallFolder([string]$Folder) {
    $fullPath = [IO.Path]::GetFullPath($Folder).TrimEnd('\')
    if ($fullPath.Length -le 3 -or -not [IO.Directory]::Exists($fullPath)) {
        throw 'Kurulum klasörü bulunamadı.'
    }
    for ($node = [IO.DirectoryInfo]::new($fullPath); $null -ne $node; $node = $node.Parent) {
        if ($node.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'Kurulum yolu bir klasör bağlantısı içeriyor.'
        }
    }
    foreach ($name in $payload + $markerName) {
        $file = Join-Path $fullPath $name
        if (Test-Path -LiteralPath $file) {
            $item = Get-Item -LiteralPath $file -Force
            if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw "Kurulan dosyanın yerinde bir klasör veya bağlantı var. $name"
            }
        }
    }
    return $fullPath
}

function Remove-OwnedShortcut([string]$Folder, [string]$AppFolder) {
    if (-not $Folder) { return }
    $file = Join-Path $Folder 'Pil Modu.lnk'
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return }
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($file)
    $expected = '-WindowStyle Hidden -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File "' +
        (Join-Path $AppFolder 'Pil-Modu-Uygulamasi.ps1') + '"'
    $powershell = Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
    $nativeLink = $link.TargetPath -eq (Join-Path $AppFolder 'PilModu.exe') -and -not $link.Arguments
    if ($nativeLink -or ($link.Arguments -eq $expected -and $link.TargetPath -eq $powershell)) {
        Remove-Item -LiteralPath $file -Force
    }
}

function Remove-Payload([string]$AppFolder, [string[]]$Names) {
    foreach ($name in $Names) {
        $file = Join-Path $AppFolder $name
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
        for ($attempt = 0; ; $attempt++) {
            try {
                Remove-Item -LiteralPath $file -Force
                break
            }
            catch {
                if ($attempt -ge 19) { throw }
                Start-Sleep -Milliseconds 250
            }
        }
    }
}

try {
    $parentId = [int]$env:PILMODU_REMOVE_PID
    $parent = Get-Process -Id $parentId -ErrorAction SilentlyContinue
    if ($parent -and -not $parent.WaitForExit(15000)) {
        throw 'Kaldırıcı kapanmadı. Tekrar dene.'
    }
    $appFolder = Assert-InstallFolder $env:PILMODU_REMOVE_DIR
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($entry)
    if (-not $key) { throw 'Bu kullanıcı için kurulum kaydı bulunamadı.' }
    try {
        $registered = [string]$key.GetValue('InstallLocation')
        $installId = [string]$key.GetValue('InstallId')
        $createdFolder = [int]$key.GetValue('CreatedFolder', 0)
    }
    finally { $key.Dispose() }
    if (-not $installId -or
        [IO.Path]::GetFullPath($registered).TrimEnd('\') -ne $appFolder -or
        [IO.File]::ReadAllText((Join-Path $appFolder $markerName)) -ne $installId) {
        throw 'Kurulum klasörü ile kaldırma kaydı uyuşmuyor.'
    }
    $profileFolder = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'PilModuProfile'
    $snapshot = Join-Path $profileFolder 'onceki-ayarlar.json'
    if ((Test-Path -LiteralPath $snapshot) -or (Test-Path -LiteralPath "$snapshot.new")) {
        throw "Önce Pil Modu'nu açıp Normal Mod ile kaydedilen ayarlarını geri yükle."
    }
    $created = $false
    $appLock = [Threading.EventWaitHandle]::new($false, 'AutoReset', 'Local\PilModu.General.Window', [ref]$created)
    try {
        if (-not $created) { throw "Pil Modu açık. Saatin yanındaki simgeye sağ tıklayıp Çıkış'ı seç." }
        Remove-Payload $appFolder ($payload | Where-Object { $_ -notin @('Uninstall.exe', 'Kaldir.ps1') })
        Remove-OwnedShortcut ([Environment]::GetFolderPath('Programs')) $appFolder
        Remove-OwnedShortcut ([Environment]::GetFolderPath('DesktopDirectory')) $appFolder
        Remove-Payload $appFolder @('Uninstall.exe')
        Remove-Payload $appFolder @('Kaldir.ps1')
        Remove-Item -LiteralPath (Join-Path $appFolder $markerName) -Force
        [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKey($entry, $false)
        if ($createdFolder -eq 1 -and -not (Get-ChildItem -LiteralPath $appFolder -Force)) {
            [IO.Directory]::Delete($appFolder)
        }
        if ([IO.Directory]::Exists($profileFolder) -and
            -not ((Get-Item -LiteralPath $profileFolder -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -and
            -not (Get-ChildItem -LiteralPath $profileFolder -Force)) {
            [IO.Directory]::Delete($profileFolder)
        }
    }
    finally { $appLock.Dispose() }
    Add-Type -AssemblyName System.Windows.Forms
    [void][Windows.Forms.MessageBox]::Show('Pil Modu kaldırıldı.', 'Pil Modu', 'OK', 'Information')
}
catch {
    Add-Type -AssemblyName System.Windows.Forms
    [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Kaldırma tamamlanamadı', 'OK', 'Warning')
    exit 1
}
