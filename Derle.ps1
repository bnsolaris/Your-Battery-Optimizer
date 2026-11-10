param(
    [switch]$NoPause,
    [switch]$Sign,
    [string]$CertificateThumbprint,
    [string]$TimestampServer = 'http://timestamp.digicert.com'
)

$ErrorActionPreference = 'Stop'

function Get-PilModuAst([string]$Text) {
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$errors)
    if ($errors.Count) { throw ($errors | Out-String) }
    return $ast
}

function Invoke-PilModuCompiler([string[]]$Arguments) {
    $messages = & $compiler @Arguments 2>&1
    foreach ($message in $messages) { Write-Host $message }
    if ($LASTEXITCODE -ne 0) { throw 'C# derlemesi tamamlanamadı. Yukarıdaki derleyici mesajını kontrol et.' }
}

function Convert-PilModuRuntimeCode([string]$ScriptName, [string]$TypeMarker, [string]$DllName) {
    $text = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $source $ScriptName)
    $ast = Get-PilModuAst $text
    $commands = @($ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.CommandAst] -and
            $node.GetCommandName() -eq 'Add-Type' -and $node.Extent.Text.Contains($TypeMarker)
    }, $true))
    if ($commands.Count -ne 1) { throw "Yerel C# kodu bulunamadı. $ScriptName" }
    $codeLiteral = @($commands[0].CommandElements | Where-Object {
        $_ -is [Management.Automation.Language.StringConstantExpressionAst] -and $_.Value.Contains($TypeMarker)
    })
    if ($codeLiteral.Count -ne 1) { throw "C# kod bloğu belirsiz. $ScriptName" }
    $codePath = Join-Path $intermediate ($DllName + '.cs')
    [IO.File]::WriteAllText($codePath, $codeLiteral[0].Value, [Text.Encoding]::UTF8)
    $compileArgs = @('/nologo', '/warn:4', '/warnaserror', '/codepage:65001',
        '/target:library', '/platform:anycpu', '/r:System.Drawing.dll',
        "/out:$(Join-Path $intermediate $DllName)", $codePath)
    Invoke-PilModuCompiler $compileArgs
    $loadCode = "Add-Type -Path (Join-Path `$PSScriptRoot '$DllName')"
    $extent = $commands[0].Extent
    $prepared = $text.Remove($extent.StartOffset, $extent.EndOffset - $extent.StartOffset).
        Insert($extent.StartOffset, $loadCode)
    [void](Get-PilModuAst $prepared)
    [IO.File]::WriteAllText((Join-Path $intermediate $ScriptName), $prepared, [Text.Encoding]::UTF8)
}

function Invoke-PilModuBuild {
    $source = Join-Path $PSScriptRoot 'src'
    $outputFolder = Join-Path $PSScriptRoot $(if ($Sign) { 'bin-imzali' } else { 'bin' })
    $intermediate = Join-Path $PSScriptRoot ('obj\build-' + [guid]::NewGuid().ToString('N'))
    $windows = [Environment]::GetFolderPath('Windows')
    $compiler = Join-Path $windows 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
        $compiler = Join-Path $windows 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
    }
    if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
        throw 'Windows .NET Framework C# derleyicisi bulunamadı.'
    }
    if ($CertificateThumbprint -and -not $Sign) {
        throw 'Sertifika belirtildiğinde -Sign seçeneği de kullanılmalı.'
    }
    $certificate = $null
    if ($Sign) {
        . (Join-Path $PSScriptRoot 'Imzalama.ps1')
        $timestampUri = [uri]$TimestampServer
        if (-not $timestampUri.IsAbsoluteUri -or $timestampUri.Scheme -ne 'http') {
            throw 'Windows PowerShell 5.1 için sağlayıcının http:// ile başlayan zaman damgası adresini kullan.'
        }
        $certificate = Get-PilModuSigningCertificate $CertificateThumbprint
        Write-Host "İmzalama sertifikası: $($certificate.Subject)"
    }
    [void][IO.Directory]::CreateDirectory($intermediate)
    foreach ($file in Get-ChildItem -LiteralPath $source -Filter '*.ps1') {
        [void](Get-PilModuAst (Get-Content -Raw -Encoding UTF8 -LiteralPath $file.FullName))
    }
    Convert-PilModuRuntimeCode 'Pil-Modu.ps1' 'namespace PilModu' 'PilModu.Native.dll'
    Convert-PilModuRuntimeCode 'Pil-Modu-Uygulamasi.ps1' 'class PilModuVisuals' 'PilModu.Visuals.dll'
    $removeCode = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $source 'Kaldir.ps1')
    [IO.File]::WriteAllText((Join-Path $intermediate 'Kaldir.ps1'), $removeCode, [Text.Encoding]::UTF8)
    foreach ($name in 'Pil-Modu.ico', 'README.txt') {
        Copy-Item -LiteralPath (Join-Path $source $name) -Destination (Join-Path $intermediate $name)
    }
    $common = @('/nologo', '/warn:4', '/warnaserror', '/codepage:65001', '/target:winexe', '/platform:anycpu',
        "/win32manifest:$(Join-Path $source 'app.manifest')",
        "/win32icon:$(Join-Path $source 'Pil-Modu.ico')",
        '/r:System.Windows.Forms.dll', '/r:System.Drawing.dll', '/r:Microsoft.CSharp.dll')
    $launcher = Join-Path $intermediate 'PilModu.exe'
    Invoke-PilModuCompiler ($common + @("/out:$launcher", (Join-Path $source 'Baslatici.cs')))
    $uninstaller = Join-Path $intermediate 'Uninstall.exe'
    Invoke-PilModuCompiler ($common + @('/define:UNINSTALL', "/out:$uninstaller", (Join-Path $source 'Kurulum.cs')))

    $runtimeFiles = @('PilModu.exe', 'Uninstall.exe', 'PilModu.Native.dll', 'PilModu.Visuals.dll',
        'Pil-Modu-Uygulamasi.ps1', 'Pil-Modu.ps1', 'Kaldir.ps1')
    if ($Sign) {
        foreach ($name in $runtimeFiles) {
            Set-PilModuSignature (Join-Path $intermediate $name) $certificate $TimestampServer
        }
    }
    $resources = @()
    foreach ($name in $runtimeFiles + @('Pil-Modu.ico', 'README.txt')) {
        $resources += "/resource:$(Join-Path $intermediate $name),$name"
    }
    $builtInstaller = Join-Path $intermediate 'Pil-Modu-Setup-0.3.1.exe'
    Invoke-PilModuCompiler ($common + @("/out:$builtInstaller") + $resources + @((Join-Path $source 'Kurulum.cs')))
    if ($Sign) { Set-PilModuSignature $builtInstaller $certificate $TimestampServer }

    [void][IO.Directory]::CreateDirectory($outputFolder)
    $installer = Join-Path $outputFolder 'Pil-Modu-Setup-0.3.1.exe'
    if ([IO.File]::Exists($installer)) {
        [IO.File]::Replace($builtInstaller, $installer, [NullString]::Value)
    }
    else { [IO.File]::Move($builtInstaller, $installer) }
    return $installer
}

$logPath = Join-Path $PSScriptRoot 'Derleme.log'
$loggingStarted = $false
$buildFailed = $false
try {
    if ($env:GITHUB_ACTIONS -ne 'true') {
        $backupPath = & (Join-Path $PSScriptRoot 'Yedekle.ps1') -Reason 'Derleme öncesi'
        if (-not $backupPath -or -not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
            throw 'Doğrulanmış yedek oluşturulamadığı için derleme durduruldu.'
        }
    }
    Start-Transcript -LiteralPath $logPath -Force | Out-Null
    $loggingStarted = $true
    Write-Host 'Pil Modu derleniyor...'
    $resultPath = Invoke-PilModuBuild
    Write-Host ''
    Write-Host 'Derleme tamamlandı.' -ForegroundColor Green
    if ($Sign) { Write-Host 'Paket ve çalıştırılan tüm dosyaların imzaları ile zaman damgaları doğrulandı.' }
    else { Write-Host 'Bu derleme imzasızdır.' }
    Write-Host 'Güncellenen EXE dosyası:'
    Write-Host $resultPath -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'Bu EXE dosyasını aç. Başka klasörlerdeki eski kopyalar otomatik güncellenmez.'
}
catch {
    $buildFailed = $true
    Write-Host ''
    Write-Host 'Derleme tamamlanamadı.' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "Ayrıntılar: $logPath"
}
finally {
    if ($loggingStarted) { Stop-Transcript | Out-Null }
    $unattended = [Environment]::CommandLine -match '(?i)(?:^|\s)-NonInteractive(?:\s|$)'
    if (-not $NoPause -and -not $unattended -and [Environment]::UserInteractive) {
        [void](Read-Host 'Pencereyi kapatmak için Enter')
    }
}
if ($buildFailed) { exit 1 }
