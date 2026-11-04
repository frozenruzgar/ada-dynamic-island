# Ada · Dynamic Island for Mac

MacBook çentiğinden açılan yerel çalışma alanı. Panel, arkasındaki pencere ve masaüstünü macOS’un buzlu cam efektiyle yumuşatır. Cam tonunu ayarlayabilirsin. Panel ve menü kartları macOS 26 ve üstünde yerel Liquid Glass kullanır. Düğmeler basınca hafif büyür, ışığı belirginleşir ve bırakınca yaylanarak eski boyutuna döner. Ayarlar ve yardımcı pencereler de aynı tepkiyi kullanır.

## İndir

[**Ada 0.9.1’i indir**](https://github.com/frozenruzgar/ada-dynamic-island/releases/download/v0.9.1/Ada-0.9.1-AppleSilicon.zip) · [Sürüm notları](https://github.com/frozenruzgar/ada-dynamic-island/releases/tag/v0.9.1)

Hazır paket Apple Silicon işlemcili ve macOS 14 veya üstünü çalıştıran Mac’ler içindir. Liquid Glass görünümü macOS 26 ve üstünde kullanılabilir. ZIP’i açıp `Ada.app` dosyasını **Uygulamalar** klasörüne taşı, ardından Ada’yı aç.

Önizleme paketi yerel olarak imzalandı ve Apple noter onayı bulunmuyor. macOS ilk açılışta geliştiriciyi doğrulayamadığını belirtebilir. [Apple’ın uygulama açma kılavuzu](https://support.apple.com/tr-tr/102445)

## Kullanım

Fareyi çentiğe yaklaştırınca Ada açılır. Panelin kenarından biraz uzaklaşınca yumuşakça küçülür. Tıklayarak, dosya sürükleyerek veya ⌃⌥A ile de açabilirsin.

Sağ üstteki **Menü** düğmesinden Ana ekran, Asistan, Dosyalar, Sistem, Bulut, Araçlar, Teleprompter ve Ayarlar'a geç. Menü çubuğundaki Ada simgesinden de paneli gizleyebilir veya uygulamadan çıkabilirsin.

Çentikle birleşen düzende panelin üst kenarı ekranın üstüne oturur. macOS menüleri önünde kalır. Yüzen düzende panel üstten boşluklu açılır. Varsayılan genişlik 660 pt. Panelin yüksekliği bölüme göre değişir. Ada Menü’den seçtiğin son bölümü kaydeder. İlk kurulumda ChatGPT taslağı açılır. Sohbeti aç düğmesi ChatGPT’nin sayfasını ayrı Ada penceresine getirir.

## Otomatik başlangıç

**Menü → Ayarlar → Davranış → Mac açıldığında başlat** seçeneği Ada’yı sonraki Mac oturum açılışlarında başlatır. macOS onayı gerekiyorsa aynı yerdeki düğme Giriş Öğeleri ayarını açar. Durum macOS’tan okunur; onay bekliyorsa ayrıca belirtilir.

Panelin küçülmesi ve ayar penceresinin kapanması uygulamayı sonlandırmaz. Ada, **Ada’dan çık** komutuna veya oturum/bilgisayar kapanışına kadar çalışır. Elle çıkış yaptığında o oturumda kendiliğinden yeniden açılmaz. Otomatik başlangıç açık kaldığında sonraki girişte yeniden başlar. Ayarı kapatmak mevcut Ada oturumunu kapatmaz.

## Bölümler

### Ana ekran ve kutucuklar

Sağ üstteki **+** ile birden fazla kutucuk ekle. **Düzenle** içinde her kutucuğu değiştirebilir, oklarla sıralayabilir veya kaldırabilirsin. Normal görünümde sağ tıklayarak da aynı işlemlere ulaşılır. En fazla 12 kutucuk eklenebilir; iki satırdan fazlası kaydırılır. Düzen uygulama kapatılınca da korunur. Kutucuğu kaldırmak notları, görevleri veya uygulamayı silmez.

Spotify, Apple Müzik, ChatGPT, Claude ve Ada araçları hazırdır. **Uygulama seç…** ile Mac’teki başka bir uygulamayı, **Web sitesi** ile bir HTTPS adresini ekleyebilirsin. Spotify veya Müzik’i uygulama seçicisinden seçmek de medya kutucuğu oluşturur. Aynı türden birden fazla kutucuk eklenebilir.

İlk geçişte mevcut görünür kartların seçimi korunur. Eski yerel müzik kutucuğu yerine kuruluysa Spotify, diğer durumda Apple Müzik eklenir. Yerel ses oynatıcısı ayrıca seçilebilir.


- **AirDrop:** Dosya seçimi sonrası macOS paylaşım servisini açar. Alıcıyı ve gönderimi macOS penceresinde seçersin.
- **Ayna:** Yalnız düğmesine bastığında kamera izni ister. Ayrı pencerede aynalanmış kamera önizlemesi açar; pencere kapanınca kamerayı durdurur.
- **Pil:** Gerçek yüzde, şarj ve adaptör bilgisi. 30 saniyede bir yenilenir.
- **Yerel müzik:** Bu Mac’teki MP3, M4A, WAV veya AIFF dosyasını seçme ve oynat/duraklat. Dosya seçmek otomatik ses başlatmaz.
- **Notlar:** Düzenlenebilir, yerel olarak saklanan metin. Menüden kopyalama/temizleme. Standart kopyala, yapıştır, tümünü seç ve geri al kısayolları.
- **Odak:** Hazır süreler, başlat/duraklat/devam, sıfırla, çalışırken ±5 dakika. Ayarlardan 1–180 dakika özel süre. Odak tamamlandığında seçeneğe göre bir sonraki başlatma molayı başlatır; mola kendiliğinden başlamaz.
- **Görevler:** Ekleme, tamamlama, yeniden açma ve kaldırma. Görevler uygulama kapatıldıktan sonra da korunur.

### Spotify ve Apple Müzik

Medya kutucukları çalışan Mac uygulamasından parça adı, sanatçı ve sağlandığında albüm kapağını okur. Önceki, oynat/duraklat ve sonraki düğmeleri ilgili uygulamayı denetler. Parça çalarken küçük ada çentiğin iki yanında albüm kapağı ve hareketli bir gösterge açar. Açık panelin başlığında da parça görünür. Duraklatıldığında kutucuktaki kapak korunur, küçük gösterge kapanır. İki uygulama aynı anda çalarsa yeni başlayan kaynak öne geçer.

İlk erişimde macOS Otomasyon izni isteyebilir. İzin kapalıysa kutucuktaki **İzinler** düğmesinden açabilirsin. Bilgiler iki saniyede bir arka planda okunur. Bu okuma uygulamaları veya şarkıları kendiliğinden başlatmaz. Müzik kutucuğu kalmayınca veya Ayarlar → Ana ekran → **Çalan parçayı adada göster** kapatılınca okuma durur.

Spotify’ın Mac uygulaması gerekir; tarayıcıdaki Spotify/YouTube sesi bu bağlantının kapsamında değildir. Spotify kurulu değilse kutucuk web sitesini açabilir. Kapak sağlanmadığında müzik simgesi gösterilir. Apple Müzik aboneliği, yerel parçaları denetlemek için gerekli değildir.

Medya bağlantısı Apple’ın [genel Apple Events arayüzünü](https://developer.apple.com/documentation/foundation/nsappleeventdescriptor/sendevent(options:timeout:)) ve uygulamaların macOS betik sözlüklerini kullanır. Özel MediaRemote API’si veya Spotify erişim anahtarı gerekmez.

### Asistan

ChatGPT ve Claude'un web sayfalarını Ada'nın sohbet penceresinde aç. Özet, düzeltme, İngilizce çeviri ve e-posta şablonlarıyla bir istek hazırla. **Kopyala ve aç** metni panoya alır. Sohbet alanına yapıştırıp gönderirsin. Not seçeneklerinden **Notu Asistana aktar** aynı taslağı açar. Gömülü giriş yöntemi takılırsa **Tarayıcıda aç** düğmesiyle devam edebilirsin.

### Sistem

CPU, fiziksel bellek kullanımı, sıkıştırılmış bellek, kullanılabilir disk alanı, düşük güç modu ve macOS ısıl durumu. Sistem ekranı açıkken CPU ve bellek iki saniyede bir, disk otuz saniyede bir güncellenir. **Uyanık tut** otomatik ekran uykusunu seçtiğin süre boyunca erteler.

### Bulut

iCloud Drive klasörü bu Mac'te bulunuyorsa Finder'da açılır. **Sabit klasörler** bölümüne yerel veya Mac'ine eşitlenen klasörleri ekleyebilirsin. iCloud, Google Drive, Dropbox ve OneDrive web kısayolları tarayıcıda açılır. Dosya eşitlemesini mevcut bulut uygulaman yürütür.

### Dosyalar

Dosya veya klasörü çentiğe/rafa sürükle ya da Dosya ekle'yi kullan. Raf kendi kopyasını saklar; orijinali değiştirmez. Dosyaya tıklayarak açabilir, sağ tıklayıp Finder'da gösterebilir, başka uygulamaya sürükleyebilir veya raftan kaldırabilirsin. Saklama süresi 1/2/3/7 gün ya da elle kaldırana kadar seçilebilir. İlk kullanımda sınırsız saklama seçilidir. Süreli temizlik yalnız Ada çalışırken yapılır; açılışta da süresi dolan kopyalar temizlenir.

Kopyalar `~/Library/Application Support/dev.ada.island/Shelf` altında tutulur. Raftan kaldırma yalnız raf kopyasını siler. Disk alanı yetersizliği, desteklenmeyen bırakma veya erişim sorunları panelde hata olarak gösterilir.

### Araçlar

Pil ayrıntıları, çevrimdışı uzunluk/ağırlık/sıcaklık çevirici, altı uygulama kısayolu ve aylık takvim. Kısayol eklemek için +; kaldırmak için sağ tık. Takvim ayları arasında gezinebilir ve Bugüne dön ile geri gelebilirsin. Döviz, tatil verisi ve bağlantı kısaltma servisi bu sürümde yoktur.

### Metin

Teleprompter: ayrı düzenleme penceresinde konuşma metnini yazıp kaydet. Başlat/duraklat, başa dön, kaydırma hızı, yazı boyutu, hizalama ve yatay ayna seçenekleri var. Metin kameranın altındaki orta alana hizalanır. Metin üzerinde sürükleyerek konumu değiştirebilirsin. Panel klavye odağına sahipken boşluk tuşu başlatır/duraklatır. Sekmeden ayrılınca okuma durur. Teleprompter kamera izni gerektirmez.

## Özelleştirme

**Menü → Ayarlar** ayrı bir pencere açar.

- **Görünüm:** Açılışta ChatGPT, Claude, Ana ekran veya Menü. 620/660/760 pt hazır genişlikler, 620–880 pt genişlik, 210–340 pt içerik yüksekliği ve yüzen panel uzaklığı.
- **Tema:** Aurora, Mor, Grafit, Orman; dört vurgu rengi, cam tonu, kart görünürlüğü, köşe yuvarlaklığı ve not yazısı ölçeği.
- **Ana ekran:** Kutucuk ekle veya düzenle; çalan parçayı küçük adada gösterme ve dosya saklama süresi.
- **Davranış:** Mac’e girişte otomatik başlatma, fareyle açma, açık tutma, kapanma gecikmesi, küçük görünümde pil, ekran seçimi, klavye kısayolu ve donanım izleme.
- **Odak:** Özel süre, mola hazırlama, mola süresi, bitiş sesi ve bitince paneli açma.

Ayarlar Mac’te saklanır. Paneli açık tutma mevcut oturuma özeldir. Bu sürüme geçişte fareyle açılma varsayılan olarak etkinleşir. macOS Saydamlığı Azalt ve Hareketi Azalt ayarları uygulanır.

## Derleme ve doğrulama

Ada macOS 14 ve üstünde çalışır. Kaynaktan derlemek için macOS 26 SDK’sını içeren Apple Command Line Tools gerekir.

```sh
./scripts/build.sh
./scripts/check.sh
open dist/Ada.app
```

Doğrulama kapsamı:

- 13 sayaç kontrolü: uyku/gecikme, duraklat/devam, kaydet/geri yükle, tek seferlik tamamlanma, süre ekleme/çıkarma.
- Dosya rafı kontrolleri: aynı adlı bağımsız kopyalar, kalıcılık, kaynak dosyanın korunması, süresi dolan kopya temizliği ve hatalar. Kontroller geçici klasör kullanır.
- Teleprompter kontrolleri: kaydırma, duraklama, sürükleme, sıfırlama, tamamlanma ve tercihler.
- macOS 26.3 üzerinde görsel kontrol: dört sekme, görev ekle/tamamla/kaldır, not yazma/temizleme, Cmd+A, gerçek dosya seçip rafa kopyalama/kaldırma, teleprompter metin editörü ve başlat/duraklat, hazır genişlik değiştirme.
- Canlı donanım ölçümleri, istem hazırlama ve bulut klasörü kısayolları için ayrı kontroller.
- Kutucuk kontrolleri: ekleme, değiştirme, sıralama, kaldırma, boş düzen, kayıt/geri yükleme, bozuk kayıtların kısmi kurtarılması, uygulama ve HTTPS doğrulaması.
- Medya kontrolleri: kaynak önceliği, duraklatılmış kapak, boş/durmuş parça, eski yanıtların reddi, kapak indirme adresleri ve kapalı yaşam döngüsü.
- macOS 26.3 üzerinde canlı Apple Müzik denemesi: sessiz yerel parçanın adı/sanatçısı/kapağı, Ada’dan oynat/duraklat, önceki/sonraki, çentiğin yanında gerçek kapak ve gösterge, duraklayınca kapağın korunması, parçalar kaldırılınca bilginin temizlenmesi; düzenin yeniden başlatmada korunması. Deneme parçaları daha sonra arşivden kaldırıldı. Spotify bu Mac’te kurulu olmadığından canlı Spotify doğrulaması yapılmadı.
- Otomatik başlangıç kontrolleri: açık/kapalı sistem durumu, tekrar kayıt, onay bekleme, hata ve dışarıdan durum değişikliği. Kontroller deneme hizmeti kullanır; gerçek giriş öğelerini değiştirmez.
- macOS 26.3 üzerinde gerçek giriş öğesi kaydı etkinleştirildi; uygulama yeniden açılınca açık kaldığı doğrulandı. Ayar penceresinin kapanması aynı uygulama oturumunu sürdürdü; elle çıkış otomatik yeniden açılmaya yol açmadı. Mac yeniden başlatılmadı.
- Yerel uygulama imzası ve Info.plist doğrulaması.

ChatGPT ve Claude sayfaları Ada’da açıldı. Hesapla giriş ve sohbet gönderimi denenmedi. Kamera izni, AirDrop gönderimi ve ses oynatma da bu doğrulamaya dahil edilmedi. Farklı macOS sürümleri, Intel, farklı ekran ölçekleri, çoklu ekran ve tüm tam ekran senaryoları ayrıca doğrulanmalı. Hazır paket Apple Silicon içindir; evrensel ikili değildir.

## Gizlilik ve paylaşım

Notlar, görevler, sayaç, kutucuk düzeni, görünüm tercihleri ve donanım ölçümleri Mac’te kalır. Spotify kapakları Spotify’ın HTTPS kapak sunucularından, oturum çerezi kullanılmadan alınır. Apple Müzik kapağı yerel uygulamadan okunur. Asistan sayfaları, ilgili düğmeye bastığında açılır. Sohbet ve oturum işlemlerini seçtiğin sağlayıcının web sayfası yürütür. Kamera yalnız Ayna düğmesiyle önizleme için kullanılır. AirDrop, seçtiğin dosyalarla macOS paylaşım servisini açar.

Uygulama ücretsiz indirilebilir. Kaynak kod herkese açık depoda incelenebilir. Depo için ayrıca bir kaynak kod lisansı seçilmedi.
