# Pil Modu kaynak dosyaları

Bu klasör kurulum paketini yeniden derlemek için gereken kaynakları içerir.
Başka bir proje klasörüne veya bu bilgisayardaki özel bir yola bağımlı değildir.

| Dosya | İçeriği |
| --- | --- |
| src/Kurulum.cs | Kurulum sihirbazı, koşullar metni, klasör seçimi, son ekran ve kaldırıcı başlatıcısı |
| src/Baslatici.cs | Kurulan PilModu.exe uygulamasının başlatıcısı |
| src/Pil-Modu-Uygulamasi.ps1 | Ana pencere, buton renkleri, pil simgesi ve sağ tık menüsü |
| src/Pil-Modu.ps1 | Ekran, parlaklık, ses ve güç işlemleri, önceki ayarları kaydetme ve geri yükleme |
| src/Kaldir.ps1 | Kurulan dosyaları ve kısayolları kaldırma işlemleri |
| src/README.txt | Kurulumla birlikte bilgisayara kopyalanan kullanım belgesi |
| src/app.manifest | Windows yönetici izni ve DPI bildirimleri |
| src/Pil-Modu.ico | Uygulama logosu |
| Derle.ps1 | EXE dosyalarını üretir |

## Derleme

Windows PowerShell'de bu klasöre geçip ./Derle.ps1 dosyasını çalıştır.
Windows .NET Framework C# derleyicisi kullanılır.
Derlenen kurulum dosyası bin/Pil-Modu-Setup-0.3.1.exe yoluna yazılır.
Ara dosyalar obj klasörüne yazılır.

Derle.ps1 dosyasını sağ tıklayıp PowerShell ile çalıştır seçeneğini de
kullanabilirsin. Pencere derleme sonucunu ve güncel EXE'nin tam yolunu
gösterir, Enter'a basana kadar açık kalır. Derleyici mesajları Derleme.log
dosyasına kaydedilir. Otomatik kullanımda -NoPause seçeneği eklenebilir.

Derleme yalnızca bu kaynak klasörünün bin klasöründeki EXE'yi günceller.
Başka klasörlerde aynı adla duran eski kurulum dosyaları ayrıca kopyalanmadığı
sürece güncellenmez.

src içindeki dosyaları değiştirdikten sonra tekrar derle.
README düzenlemelerini src/README.txt dosyasında yapabilirsin.
Kurulum koşulları src/Kurulum.cs dosyasındaki terms metnindedir.

Kurulum sihirbazının başlangıç boyutu src/Kurulum.cs içindeki ClientSize
değeridir. Bu sürümde 900 × 640 olarak ayarlanmıştır. Windows ekran ölçeğini
uygular ve sihirbaz küçük ekranlarda kullanılabilir alana sığdırılır.
Pencere elle büyütülebilir veya tam ekran yapılabilir.

Bu sürüm dijital imzasızdır. Windows Uygulama Denetimi veya kurum ilkeleri
EXE dosyalarının çalıştırılmasını engelleyebilir.

## İmzalı derleme

Imzali-Derle.ps1, güvenilir bir sağlayıcının sertifikası Windows sertifika
deposunda kullanıma hazır olduğunda imzalı paket üretir. İmzalama öncesi
gereksinimler ve komutlar IMZALAMA.md dosyasındadır.

Derleyici Windows API ve çizim kodlarını PilModu.Native.dll ve
PilModu.Visuals.dll dosyalarına ayırır. Kurulan uygulama bu dosyaları yükler.
Kaldırma işlemi kurulan Kaldir.ps1 dosyası üzerinden başlatılır.
Derleme betiği önce iç dosyaları imzalar, ardından onları içeren kurulum
paketini oluşturup en son bu paketi imzalar.
