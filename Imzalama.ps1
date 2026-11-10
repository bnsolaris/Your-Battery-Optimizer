function Get-PilModuSigningCertificate([string]$Thumbprint) {
    $certificates = @(
        foreach ($store in 'Cert:\CurrentUser\My', 'Cert:\LocalMachine\My') {
            Get-ChildItem -Path $store -CodeSigningCert -ErrorAction Stop
        }
    ) | Where-Object {
        $_.HasPrivateKey -and $_.NotBefore -le (Get-Date) -and $_.NotAfter -gt (Get-Date)
    }
    if ($Thumbprint) {
        $fingerprint = $Thumbprint -replace '\s', ''
        if ($fingerprint -notmatch '^[a-fA-F0-9]{40}$') {
            throw 'Sertifika parmak izi 40 onaltılık karakter olmalı.'
        }
        $certificates = @($certificates | Where-Object Thumbprint -EQ $fingerprint)
    }
    else { $certificates = @($certificates) }
    if ($certificates.Count -eq 0) {
        throw 'Kullanılabilir kod imzalama sertifikası yok. Önce güvenilir sağlayıcıdan sertifika alıp özel anahtarı veya sağlayıcının güvenli imzalama bağlantısını kurmalısın.'
    }
    if ($certificates.Count -ne 1) {
        throw 'Birden fazla kod imzalama sertifikası var. -CertificateThumbprint ile kullanılacak sertifikayı belirt.'
    }
    $certificate = $certificates[0]
    if ($certificate.Subject -eq $certificate.Issuer) {
        throw 'Genel dağıtım için güvenilir sağlayıcı tarafından verilmiş sertifika gerekli.'
    }
    $chain = [Security.Cryptography.X509Certificates.X509Chain]::new()
    try {
        if (-not $chain.Build($certificate)) {
            throw 'Kod imzalama sertifikasının güven zinciri doğrulanamadı.'
        }
    }
    finally { $chain.Dispose() }
    return $certificate
}

function Set-PilModuSignature(
    [string]$File,
    [Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
    [string]$TimestampServer
) {
    $signature = Set-AuthenticodeSignature -LiteralPath $File -Certificate $Certificate -HashAlgorithm SHA256 -IncludeChain NotRoot -TimestampServer $TimestampServer
    $verified = Get-AuthenticodeSignature -LiteralPath $File
    if ($signature.Status -ne 'Valid' -or $verified.Status -ne 'Valid' -or
        -not $verified.TimeStamperCertificate -or
        $verified.SignerCertificate.Thumbprint -ne $Certificate.Thumbprint) {
        throw "İmza veya zaman damgası doğrulanamadı. $File — $($verified.StatusMessage)"
    }
    Write-Host ("İmza doğrulandı: " + [IO.Path]::GetFileName($File))
}
