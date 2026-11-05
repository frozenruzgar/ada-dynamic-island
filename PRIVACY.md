# Gizlilik ve izinler

Ada analitik veya reklam SDK’sı içermez. Notlar, görevler, sayaç, kutucuk düzeni ve tercihler Mac’te tutulur. Arayüzdeki donanım ölçümleri sunucuya gönderilmez.

| Erişim | Neden | Ne zaman |
| --- | --- | --- |
| Otomasyon: Spotify / Apple Müzik | Parça adı, sanatçı, kapak, süre ve seçtiğin oynatma komutları | Medya bağlantısı ilgili uygulamaya ilk eriştiğinde macOS sorabilir |
| Kamera | Ayna penceresinde yerel önizleme | Ayna’yı açtığında; açılışta istenmez |
| Dosya / klasör seçimi | Seçtiğin öğelerin yerel kopyası veya klasör kısayolu | Dosya seçici, klasör seçici veya sürükle-bırak kullandığında |
| Spotify kapak ağı | Yalnız izin verilen HTTPS kapak sunucularından kapak indirme | Medya göstergesi açıkken kapak gerektiğinde |
| Web sayfaları | Seçtiğin ChatGPT, Claude, bulut veya web kısayolu | İlgili sayfayı açtığında |

Spotify kapağı çerez gönderilmeden alınır; adres, yönlendirme, dosya boyutu ve görüntü çözümü kontrolleri uygulanır. Apple Müzik kapağı yerel uygulamadan okunur. Medya okuması kapalı oynatıcıları başlatmaz veya şarkı oynatmaz. Göstergeyi kapatmak arka plan medya okumasını durdurur.

Kamera görüntüsü Ada tarafından kaydedilmez veya gönderilmez. Ayna penceresi kapatılınca kamera durur. ChatGPT/Claude sohbet ve hesap işlemlerini sağlayıcının web sayfası yürütür; ilgili sağlayıcının gizlilik kuralları geçerlidir. Kopyala ve aç işlemi kullanıcı seçimiyle metni sistem panosuna koyar; otomatik sohbet gönderimi yapmaz.

Dosya rafı `~/Library/Application Support/io.github.frozenruzgar.ada/Shelf` altında bağımsız kopyalar kullanır. Orijinaller yerinde kalır. Raftan kaldırma raf kopyasını kaldırır. İlk kullanımda sınırsız saklama seçilidir; süre seçilirse uygulama çalışırken ve açılışta süresi dolan kopyalar temizlenir. Bulut kısayolları Ada’nın dosyaları sunucuya yüklediği anlamına gelmez; eşitlemeyi mevcut bulut uygulaman yürütür. AirDrop alıcısını macOS paylaşım penceresinde kullanıcı seçer.

Yerel ayarlar UserDefaults içinde tutulur. Uygulama silinince Application Support ve tercihler otomatik temizlenmeyebilir; yedeklemek istediğin verileri silmeden önce kontrol et.

Uygulamanın çalışma zamanındaki veri akışıyla geliştiricinin isteğe bağlı Apple noter onayına paket yüklemesi farklıdır. Dağıtım script’i yalnız geliştirici NOTARY_PROFILE tanımladığında derlenmiş uygulamayı Apple’a gönderir.

Raf boyutu yerel dosyalardan hesaplanır. Kopyalama raf toplamını 2 GB üzerine çıkaracaksa kullanıcı onayı istenir. Ayarlardan boyut üst sınırı seçilebilir; mevcut veriler kendiliğinden silinmez. Eski sınırsız üst sınır varsayılanı korunur. Tahminler mantıksal dosya boyutudur; APFS kopyaları fiziksel olarak daha az alan kullanabilir. Disk alanı ve üst sınır kopyalama öncesi, gerçek kopya boyutu da kayıt öncesi kontrol edilir; dışarıdan değiştirilen dosyalar için kopyalama sırasında geçici disk kullanımı tahminden farklı olabilir.

Notlar `~/Library/Application Support/dev.ada.island/Notes/current.md` dosyasına, son tuştan yaklaşık 0,5 saniye sonra atomik olarak kaydedilir. Eski workspaceNote tercihi bir kez taşınır; başarısız taşıma eski kopyayı silmez. Normal çıkış bekleyen kaydı tamamlar. Okunamayan bir notun üzerine boş metin yazılmaz; kullanıcı yeni metin kaydederse önce özgün baytların yerel kurtarma kopyası saklanır. `.md` dışa aktarma yalnız seçtiğin konuma yazar. Zorla sonlandırma veya elektrik kesintisinde henüz kaydedilmemiş son tuşlar korunamayabilir.

Aynı Ada’nın ikinci kopyası açıldığında süreçler arasında yalnız hedef süreç kimliği ve aç/ayarlar eylemi taşıyan yerel macOS bildirimi kullanılır; bu iletişim ağ kullanmaz ve not/dosya içeriği taşımaz.

İsteğe bağlı odak bitişi bildirimi varsayılan kapalıdır. Ayardan etkinleştirildiğinde macOS bildirim izni istenir. Yalnız yerel odak/mola tamamlanma başlığı gönderilir; bildirimde not veya dosya içeriği bulunmaz. Ada gizli olsa da bu tercih etkinse bildirim gönderilebilir. İzin reddedilirse özellik açılmaz. Uygulama bu özellik için ağa veya uzak push servisine bağlanmaz.

Ada, Mac App Store dışında dağıtılır ve App Sandbox kullanmaz. macOS’un Otomasyon ve Kamera izinleri geçerlidir.

Ayarlar → Davranış → Sohbet oturumlarını temizle, Ada’nın WebKit çerezlerini ve web depolamasını siler. ChatGPT ve Claude pencereleri kapanır ve Ada’da yeniden giriş gerekir. Tarayıcıdaki oturumlar, sunucudaki konuşmalar ve Ada’nın yerel taslağı korunur.

Sürüm kontrolü varsayılan kapalıdır. Açıp Kontrol et düğmesine bastığında Ada, GitHub’ın herkese açık yayın adresine tek istek gönderir. İstek kullanıcı içeriği veya kimlik bilgisi içermez.

Takvim varsayılan kapalıdır. Araçlar’daki Takvimi bağla düğmesi Apple Takvim erişimini ister. macOS izni tam erişim olarak adlandırır. Ada etkinlikleri yalnızca görüntülemek ve kullanıcının seçtiği toplantı bağlantısını açmak için okur.

Bluetooth göstergesi varsayılan kapalıdır. Açıldığında sistemin bağlantı olayları dinlenir. Aygıt adı kısa süreli göstergede kullanılır.
