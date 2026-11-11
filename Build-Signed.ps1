param(
    [string]$CertificateThumbprint,
    [string]$TimestampServer = 'http://timestamp.digicert.com',
    [switch]$NoPause
)

& (Join-Path $PSScriptRoot 'Build.ps1') -Sign -CertificateThumbprint $CertificateThumbprint -TimestampServer $TimestampServer -NoPause:$NoPause
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
