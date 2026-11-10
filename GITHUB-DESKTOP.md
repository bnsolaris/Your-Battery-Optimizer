# GitHub Desktop ile çalışma

## Bir defalık kurulum

GitHub Desktop'ta File → Add Local Repository seçeneğiyle bu kaynak klasörünü
ekle. Kaynak klasörü, Derle.ps1 ve src klasörünün bulunduğu klasördür.
Depo bnsolaris/Battery-Mode deposunun main dalına bağlıdır.

## Günlük güncelleme

1. Kaynak dosyalarını bu klasörde düzenle ve kaydet.
2. GitHub Desktop'ın Changes bölümünde değişiklikleri incele.
3. Summary alanına değişikliği anlatan kısa bir açıklama yaz ve Commit to main
   düğmesine bas. Bu, değişikliği bilgisayarındaki Git geçmişine kaydeder.
4. Push origin düğmesine bas. Bu, commit'i GitHub'a gönderir.
5. GitHub'daki Actions → Build Windows installer çalışmasının tamamlanmasını bekle.
6. Çalışmanın Artifacts bölümünden Pil-Modu-Windows-Unsigned dosyasını indir.

Bu akışla EXE'yi elle derleyip GitHub'a yüklemek gerekmez. Kaydettiğin kaynak
değişikliklerini Desktop'ta commit edip göndermen yeterlidir.

Her push güncel test paketini üretir. Kullanıcılara duyurulacak bir beta veya
kararlı sürüm ayrıca GitHub Releases üzerinden seçilir.

## İmzalama

Şu anki Actions akışı imzasız test paketi üretir. SignPath başvurusu kabul
edilirse GitHub Actions'a onun imzalama adımı eklenir.
