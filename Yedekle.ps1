[CmdletBinding()]
param(
    [string]$Reason = 'Manuel yedek',
    [string]$SourceRoot,
    [string]$BackupRoot
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression

if (-not $SourceRoot) { $SourceRoot = $PSScriptRoot }
$source = (Resolve-Path -LiteralPath $SourceRoot).Path.TrimEnd('\')
if (-not $BackupRoot) {
    $BackupRoot = Join-Path (Split-Path -Parent $source) 'Pil-Modu-Yedekler'
}
$destination = [IO.Path]::GetFullPath($BackupRoot).TrimEnd('\')
if ($destination -eq $source -or $destination.StartsWith($source + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Yedek klasörü kaynak klasörünün dışında olmalı.'
}
if ((Get-Item -LiteralPath $source -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
    throw 'Kaynak klasörü bir bağlantı olamaz.'
}

$files = [Collections.Generic.List[IO.FileInfo]]::new()
$folders = [Collections.Generic.Stack[string]]::new()
$folders.Push($source)
while ($folders.Count) {
    foreach ($item in Get-ChildItem -LiteralPath $folders.Pop() -Force) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        if ($item.PSIsContainer) {
            if ($item.Name -notin @('.git', 'obj', '.vs')) { $folders.Push($item.FullName) }
        }
        elseif ($item.Extension -notin @('.log', '.pfx', '.p12', '.key')) {
            $files.Add($item)
        }
    }
}
if ($files.Count -eq 0) { throw 'Yedeklenecek dosya bulunamadı.' }

[void][IO.Directory]::CreateDirectory($destination)
$stamp = [DateTime]::UtcNow.ToString("yyyy-MM-dd_HH-mm-ss'Z'")
$name = 'Pil-Modu_' + $stamp + '_' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.zip'
$finalPath = Join-Path $destination $name
$pendingPath = $finalPath + '.partial'
$records = [Collections.Generic.List[object]]::new()
$sha = [Security.Cryptography.SHA256]::Create()
try {
    $stream = [IO.File]::Open($pendingPath, 'CreateNew', 'ReadWrite', 'None')
    try {
        $zip = [IO.Compression.ZipArchive]::new($stream, 'Create', $true)
        try {
            foreach ($file in $files) {
                $relative = $file.FullName.Substring($source.Length + 1).Replace('\', '/')
                $input = [IO.File]::Open($file.FullName, 'Open', 'Read', 'Read')
                try {
                    $hash = [BitConverter]::ToString($sha.ComputeHash($input)).Replace('-', '')
                    $input.Position = 0
                    $entry = $zip.CreateEntry('project/' + $relative, 'Optimal')
                    if ($file.LastWriteTime.Year -ge 1980) { $entry.LastWriteTime = $file.LastWriteTime }
                    $output = $entry.Open()
                    try { $input.CopyTo($output) }
                    finally { $output.Dispose() }
                    $records.Add([pscustomobject]@{ Path = $relative; SHA256 = $hash; Length = $input.Length })
                }
                finally { $input.Dispose() }
            }
            $manifest = [ordered]@{
                CreatedUtc = [DateTime]::UtcNow.ToString('o')
                Reason = $Reason
                SourceRoot = $source
                Files = @($records)
                Excluded = @('.git', 'obj', '.vs', '*.log', '*.pfx', '*.p12', '*.key', 'Reparse points')
            } | ConvertTo-Json -Depth 5
            $writer = [IO.StreamWriter]::new($zip.CreateEntry('backup-manifest.json').Open(), [Text.Encoding]::UTF8)
            try { $writer.Write($manifest) }
            finally { $writer.Dispose() }
        }
        finally { $zip.Dispose() }
        $stream.Position = 0
        $check = [IO.Compression.ZipArchive]::new($stream, 'Read', $true)
        try {
            foreach ($record in $records) {
                $entryStream = $check.GetEntry('project/' + $record.Path).Open()
                try { $actual = [BitConverter]::ToString($sha.ComputeHash($entryStream)).Replace('-', '') }
                finally { $entryStream.Dispose() }
                if ($actual -ne $record.SHA256) { throw "Yedek doğrulanamadı. $($record.Path)" }
            }
        }
        finally { $check.Dispose() }
    }
    finally { $stream.Dispose() }
    [IO.File]::Move($pendingPath, $finalPath)
}
catch {
    if ([IO.File]::Exists($pendingPath)) { [IO.File]::Delete($pendingPath) }
    throw
}
finally { $sha.Dispose() }

Write-Host "Yedek oluşturuldu ve doğrulandı: $finalPath"
Write-Output $finalPath
