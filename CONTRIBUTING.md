# Katkı rehberi

Ada bir Swift Package ve AppKit/SwiftUI menü çubuğu uygulamasıdır. Kaynak kod lisansı henüz seçilmedi; lisans kararı kullanıcıya aittir.

## Kurulum ve doğrulama

macOS, Swift 5.9+ içeren Command Line Tools/Xcode ve Python 3 gerekir. Hazır paketler Apple Silicon içindir; Intel desteği doğrulanmadı.

```sh
./scripts/build.sh
./scripts/check.sh
open dist/Ada.app
```

Tam Xcode’da check.sh `swift test` çalıştırır. Command Line Tools XCTest içermediğinden aynı AdaCheckSuite yerelde SwiftPM AdaChecks çalıştırıcısıyla sınanır; bu yedek XCTest sonucu sayılmaz. Test dosyaları Tests/Checks altında, gerçek testTarget Tests/AdaTests altındadır. Release ürününü `swift build -c release --product Ada` ile derle; test destek hedefleri debug içindir.

Her davranış değişikliğine ilgili kontrolü ekle. Denemeler gerçek kullanıcı notlarını, dosyalarını, görevlerini veya giriş öğelerini değiştirmemeli; geçici klasör ve UserDefaults suite kullan. Eski araç zinciri, çoklu ekran veya gerçek donanım kontrolü yapılmadıysa açıkça yaz.

## Kod ve metin

- Swift’te dört boşluk; UI durumunu MainActor üzerinde tut.
- Dosya kopyalama ve diğer yavaş işleri ana iş parçacığından uzak tut.
- Yeni kullanıcı metinleri `L10n.string` üzerinden geçsin. `Sources/Ada/Resources/Localizable.xcstrings` içine Türkçe/İngilizce karşılık ekle ve `python3 scripts/sync-localizations.py` çalıştır.
- Ağ erişimini Spotify kapakları, kullanıcının açtığı sayfalar ve isteğe bağlı GitHub sürüm kontrolü ile sınırlı tut.
- Yeni izin isteyen özellikleri kapalı başlat; izni ilk kullanımda iste.
- Kurulu Spotify ikonunu oku; üçüncü taraf logolarını pakete ekleme.

## Pull request

Tek bir anlaşılır değişiklik sun. Somut önce/sonra davranışını, çalıştırılan kontrolleri ve doğrulanmayan ortamları yaz. Arayüz görsellerinde özel not, dosya adı ve hesap bilgisi kullanma. Geliştirme planındaki her görev ayrı commit’tir. Katkı davranışı için [davranış kuralları](CODE_OF_CONDUCT.md), gizli güvenlik bildirimleri için [SECURITY.md](SECURITY.md).


## Yeni dil ekleme

`Sources/Ada/Resources/Localizable.xcstrings` arayüz metinlerini, `InfoPlist.xcstrings` sistem izin açıklamalarını içerir. Her ikisine yeni dil koduyla çeviri ekle. Katalog anahtarlarını ve `{0}`, `{1}` gibi yer tutucuları koru. Yeni dili `Resources/Info.plist` içindeki `CFBundleLocalizations` listesine ve `scripts/sync-localizations.py` dil listesine ekle. `L10n.string` dil seçimini ve İngilizce geri dönüşü yeni dille test et. Çeviri oluşturucuyu çalıştırdıktan sonra paketli uygulamayı yeni sistem diliyle açıp metin taşması ve erişilebilirlik etiketlerini kontrol et.
