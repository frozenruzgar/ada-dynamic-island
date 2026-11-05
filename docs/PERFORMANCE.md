# Performans ölçüm kaydı

## P2-1 — Kapalı panel fare izleme

macOS 26.3, Apple Silicon; aynı Mac’te uygulama kapalı panelle çalışırken `proc_pid_rusage` interrupt wakeup sayacı iki örnek arasında okundu. Bunlar 10 saniyelik kısa yerel örneklerdir; Instruments enerji ölçümü veya pil ömrü tahmini değildir.

| Sürüm / koşul | Süre | Interrupt wakeups | Saniyede |
|---|---:|---:|---:|
| 0.10.6, eski sürekli 60 ms izleme | 10,000 sn | 185 | 18,499 |
| 0.11.0, yerleşmiş boşta, panel kapalı | 10,044 sn | 26 | 2,589 |

Yeni örnekte mouse idle süresi 74,581 → 84,586 saniyeydi; örnek boyunca fare hareket etmedi. Yaklaşık %86 azalma görüldü. İlk yeni sürüm örneği 26,786/sn verdi; o örnekte giriş/yerleşme koşulları doğrulanmadığından boşta karşılaştırması olarak kullanılmadı. Eski örnekte ayrıca mouse idle kaydı alınmadı. İki sürüm arasında P0/P1 değişiklikleri de vardır; farkın tamamını yalnız tek bir değişikliğe atfetmiyoruz.

`top` kısa CPU örnekleri eski sürümde %0,3–0,7, yenide %0,5–1,7 aralığındaydı. Bu ölçüm CPU iyileşmesi iddiasını desteklemez. Sabit pil ömrü kazancı iddia edilmez. Panel açıkken çıkış takibi hâlâ 60 ms’dir; kapalı panelde mouse-only olay izleyicisi kullanılır, küresel izleme kurulamazsa 200 ms yedek çalışır.

PR açıklaması için: Kapalı panelin sürekli fare zamanlayıcısı kaldırıldı. Aynı Mac’te kısa boşta örnekler 18,5 → 2,6 interrupt wakeup/sn gösterdi; tekrarlanabilir uzun enerji ölçümü henüz yapılmadı.


## Açık ana ekran

Aynı Apple Silicon Mac ve macOS 26.3 üzerinde, ana ekran açık ve sabitlenmişken yaklaşık 10 saniyelik üç örnek alındı. Her örnekte fare hareketsizdi.

| Sürüm | Açık panel yedek aralığı | Uyandırma/sn |
| --- | ---: | ---: |
| 0.11.1 | 60 ms | 16,64 |
| 0.12.0 ilk paket | 60 ms | 16,72 |
| 0.12.0 güncel paket | 120 ms | 8,47 |

Fare hareketi olaylardan alınmaya devam ediyor. Geometri yalnızca ekran veya yerleşim değiştiğinde yeniden okunuyor. Yedek yoklama sabit imleç, kapanma gecikmesi ve biten pencere animasyonu gibi durumları takip ediyor. Bunlar kısa süreç sayacı örnekleri. Pil ömrü veya farklı donanımlardaki tüketim ayrıca ölçülmelidir.
