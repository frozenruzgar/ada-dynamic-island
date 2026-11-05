# Ada doğrulama kaydı

`./scripts/build.sh` ürün derlemesini, ad-hoc imzayı ve paketli çeviri kaynağını doğrular. `./scripts/check.sh` aynı işlevsel kontrolleri tam Xcode’da XCTest ile, Command Line Tools ortamında ortak SwiftPM çalıştırıcısıyla yürütür.

- Yerel kontroller odak süresini, raf kopyalarını, eski uygulama kimliğinden geçişi, kısayol doğrulamasını ve oturum temizleme akışını örnek verilerle sınar.
- Arama hesabı, takvim bağlantıları, görev tarihleri, yedek doğrulaması, canlı etkinlik politikası ve sürüm karşılaştırması izin veya internet gerektirmeyen testlerle sınanır.
- Tek süreç açılışı, paneli klavyeyle açma, ayar penceresi ve rafın ⌘V akışı macOS 26.3 üzerinde önceki 0.11 sürümlerinde elle doğrulandı.
- Gerçek Spotify ve Apple Müzik parça bilgisi ve kontrolleri önceki sürümlerde ayrı ayrı görüldü. Bildirim teslimi ve izin reddinden geri dönüş, her oynatıcı sürümü için ayrıca denenmelidir.
- Çoklu fiziksel ekran, tam ekran Spaces, VoiceOver, AirDrop alıcısı ve Bluetooth donanımının tamamı yerel otomatik kontrol kapsamında değildir.
- Yerel paket Apple Silicon içindir. Developer ID imzası ve noter onayı ayrı yayın gereksinimleridir.

[Performans ölçümleri](PERFORMANCE.md) · [Paketleme ve yayın](RELEASE.md)

0.12.0 Apple Silicon Mac üzerinde yeni kimlikle başlatıldı. Mevcut not ve raf kaydı kopyaları karşılaştırıldı. Arayüzde başlangıç rehberi, klavyeyle panel açılışı, ayrı Dosyalar kısayolu, hesap sonucu ve yeni giriş öğesi kaydı gözlendi.
