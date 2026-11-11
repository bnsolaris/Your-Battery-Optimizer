# Code signing

A signed build requires a valid code-signing certificate from a trusted
provider, its private key through the provider's Windows integration, and
access to the provider's timestamp service.

The certificate must be available in `CurrentUser/My` or `LocalMachine/My`
and usable for code signing. A locally trusted certificate does not
establish trust on other computers. Complete the identity verification with
the signing provider before distributing the app.

Run `.\Build-Signed.ps1` in Windows PowerShell. If more than one certificate
qualifies, pass its thumbprint:

    .\Build-Signed.ps1 -CertificateThumbprint 'CERTIFICATE_THUMBPRINT'

Use `-TimestampServer` to supply your provider's timestamp URL if it differs
from the default. This Windows PowerShell 5.1 script expects an HTTP timestamp
URL.

The signed installer is written to
`bin-signed/Your-Battery-Optimizer-Setup-<version>.exe`. Build details are in
`Build.log`. The regular `Build.ps1` produces an unsigned installer in `bin`.

The build signs and verifies the app, uninstaller, native DLL and PowerShell
scripts first. It packages those files, signs the installer and verifies the
signatures and timestamps before publishing the local output.

[Microsoft guide to signing for Smart App Control](https://learn.microsoft.com/en-us/windows/apps/develop/smart-app-control/code-signing-for-smart-app-control)
