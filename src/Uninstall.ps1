$ErrorActionPreference = 'Stop'
$entry = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\PilModu.WindowsProfile'
$markerName = '.pilmodu-install'
$payload = 'YourBatteryOptimizer.exe', 'BatteryOptimizer.Native.dll', 'Apply-PowerProfile.ps1',
    'Uninstall.ps1', 'Localization.ps1', 'Translations.json', 'BatteryOptimizer.ico', 'README.txt', 'Uninstall.exe'
$failureTitle = 'Uninstall could not be completed'

function Assert-InstallFolder([string]$Folder) {
    $fullPath = [IO.Path]::GetFullPath($Folder).TrimEnd('\')
    if ($fullPath.Length -le 3 -or -not [IO.Directory]::Exists($fullPath)) {
        throw (Get-Text 'FolderMissing')
    }
    for ($node = [IO.DirectoryInfo]::new($fullPath); $null -ne $node; $node = $node.Parent) {
        if ($node.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw (Get-Text 'LinkedFolder')
        }
    }
    foreach ($name in $payload + $markerName) {
        $file = Join-Path $fullPath $name
        if (Test-Path -LiteralPath $file) {
            $item = Get-Item -LiteralPath $file -Force
            if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw (Get-Text 'UnexpectedFile' @($name))
            }
        }
    }
    return $fullPath
}

function Remove-OwnedShortcut([string]$Folder, [string]$AppFolder) {
    if (-not $Folder) { return }
    $file = Join-Path $Folder 'Your Battery Optimizer.lnk'
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return }
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($file)
    if ($link.TargetPath -eq (Join-Path $AppFolder 'YourBatteryOptimizer.exe') -and -not $link.Arguments) {
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
    . (Join-Path $PSScriptRoot 'Localization.ps1')
    $translations = Import-Translations $PSScriptRoot $env:YBO_LANGUAGE
    $failureTitle = Get-Text 'UninstallFailed'
    $parentId = [int]$env:PILMODU_REMOVE_PID
    $parent = Get-Process -Id $parentId -ErrorAction SilentlyContinue
    if ($parent -and -not $parent.WaitForExit(15000)) {
        throw (Get-Text 'UninstallStillRunning')
    }
    $appFolder = Assert-InstallFolder $env:PILMODU_REMOVE_DIR
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($entry)
    if (-not $key) { throw (Get-Text 'NoRegistration') }
    try {
        $registered = [string]$key.GetValue('InstallLocation')
        $installId = [string]$key.GetValue('InstallId')
        $createdFolder = [int]$key.GetValue('CreatedFolder', 0)
    }
    finally { $key.Dispose() }
    if (-not $installId -or
        [IO.Path]::GetFullPath($registered).TrimEnd('\') -ne $appFolder -or
        [IO.File]::ReadAllText((Join-Path $appFolder $markerName)) -ne $installId) {
        throw (Get-Text 'RegistrationMismatch')
    }
    $profileFolder = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'PilModuProfile'
    $snapshot = Join-Path $profileFolder 'onceki-ayarlar.json'
    if ((Test-Path -LiteralPath $snapshot) -or (Test-Path -LiteralPath "$snapshot.new")) {
        throw (Get-Text 'RestoreBeforeRemoval')
    }
    $created = $false
    $appLock = [Threading.EventWaitHandle]::new($false, 'AutoReset', 'Local\PilModu.General.Window', [ref]$created)
    try {
        if (-not $created) { throw (Get-Text 'AppOpen') }
        Remove-Payload $appFolder ($payload | Where-Object { $_ -notin @('Uninstall.exe', 'Uninstall.ps1', 'Localization.ps1', 'Translations.json') })
        Remove-OwnedShortcut ([Environment]::GetFolderPath('Programs')) $appFolder
        Remove-OwnedShortcut ([Environment]::GetFolderPath('DesktopDirectory')) $appFolder
        Remove-Payload $appFolder @('Uninstall.exe')
        Remove-Payload $appFolder @('Uninstall.ps1', 'Localization.ps1', 'Translations.json')
        Remove-Item -LiteralPath (Join-Path $appFolder $markerName) -Force
        [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKey($entry, $false)
        if ($createdFolder -eq 1 -and -not (Get-ChildItem -LiteralPath $appFolder -Force)) {
            [IO.Directory]::Delete($appFolder)
        }
        if ([IO.Directory]::Exists($profileFolder) -and
            -not ((Get-Item -LiteralPath $profileFolder -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            $preferencesPath = Join-Path $profileFolder 'ProfileSettings.json'
            if (Test-Path -LiteralPath $preferencesPath -PathType Leaf) {
                $preferences = Get-Item -LiteralPath $preferencesPath -Force
                if (-not ($preferences.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                    Remove-Item -LiteralPath $preferencesPath -Force
                }
            }
            if (-not (Get-ChildItem -LiteralPath $profileFolder -Force)) { [IO.Directory]::Delete($profileFolder) }
        }
    }
    finally { $appLock.Dispose() }
    Add-Type -AssemblyName System.Windows.Forms
    [void][Windows.Forms.MessageBox]::Show((Get-Text 'Uninstalled'), 'Your Battery Optimizer', 'OK', 'Information')
}
catch {
    Add-Type -AssemblyName System.Windows.Forms
    [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, $failureTitle, 'OK', 'Warning')
    exit 1
}
