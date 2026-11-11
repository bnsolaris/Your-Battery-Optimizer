# Pil Modu imzalama

İmzalı derleme için kimliği doğrulanmış bir kod imzalama sertifikası ve
bu sertifikanın özel anahtarını kullanabilen sağlayıcı bağlantısı gerekir.
USB anahtar veya bulut anahtarı, sağlayıcının Windows yazılımıyla Windows
sertifika deposunda kullanılabilir olmalıdır.

## Gereksinimler

- Sertifika CurrentUser/My veya LocalMachine/My deposunda bulunmalı.
- Kod imzalama amacı, geçerli tarih ve kullanılabilir özel anahtar gerekli.
- Sertifika güven zinciri Windows tarafından doğrulanmalı.
- Sağlayıcının zaman damgası hizmetine internet erişimi gerekli.
- Sertifikanın genel dağıtım için güvenilir sağlayıcıdan alınması gerekli.
  Yerel güven zinciri denetimi, diğer bilgisayarların sertifikaya güveneceğini
  tek başına kanıtlamaz.

## Derleme

Imzali-Derle.ps1 dosyasına sağ tıklayıp PowerShell ile çalıştırabilirsin.
Tek bir geçerli kod imzalama sertifikası varsa otomatik seçilir.
Birden fazla sertifika varsa PowerShell'de şu komutu kullan.

    .\Imzali-Derle.ps1 -CertificateThumbprint 'SERTIFIKANIN_40_KARAKTERLIK_PARMAK_IZI'

Sağlayıcın farklı bir zaman damgası hizmeti öneriyorsa TimestampServer
parametresini kullan. Windows PowerShell 5.1 için HTTP adresi gerekir.
Varsayılan adres http://timestamp.digicert.com olarak ayarlanmıştır.

İmzalı paket bin-imzali/Pil-Modu-Setup-0.3.3.exe yoluna yazılır.
Normal Derle.ps1, bin klasöründe imzasız paket üretmeye devam eder.
Derleme sonucu ve hatalar Derleme.log dosyasında görülür.

## İmzalanan dosyalar

- PilModu.exe
- Uninstall.exe
- PilModu.Native.dll
- PilModu.Visuals.dll
- Pil-Modu-Uygulamasi.ps1
- Pil-Modu.ps1
- Kaldir.ps1
- Son olarak bu dosyaları içeren Setup EXE

Her dosyada imza, imzalayan sertifika ve zaman damgası doğrulanır.
İmzalı paketin çıktısı ancak tüm kontroller tamamlandığında yayımlanır.
Sertifika yoksa işlem hata ile durur.

Kimlik doğrulama ve sertifika sağlayıcısının hesabını açma işlemleri hesap
sahibi tarafından tamamlanmalıdır. Azure Artifact Signing, bireysel Public
Trust başvurularında şu anda ABD ve Kanada ile sınırlıdır.

Microsoft belgeleri

- https://learn.microsoft.com/en-us/windows/apps/develop/smart-app-control/code-signing-for-smart-app-control
- https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart
- https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/set-authenticodesignature
