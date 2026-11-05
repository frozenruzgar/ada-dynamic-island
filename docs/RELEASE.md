# Dağıtım

`./scripts/release.sh` sürümü Info.plist’ten okuyarak Apple Silicon ZIP, DMG ve SHA-256 dosyası üretir. Intel ikilisi bu sürümde desteklenmez; evrensel paket üretilmiş veya test edilmiş sayılmaz.

Varsayılan yerel imza ad-hoc’tur. `SIGN_IDENTITY` bir Developer ID Application kimliği içerirse hardened runtime ve timestamp kullanılır. Ayna için camera entitlement eklenmiştir; kamera izni uygulama açılışında değil, Ayna ilk kullanıldığında istenir.

```sh
SIGN_IDENTITY='Developer ID Application: …' NOTARY_PROFILE='ada-notary' ./scripts/release.sh
```

NOTARY_PROFILE, önceden macOS Anahtar Zinciri’nde hazırlanmış notarytool profil adıdır. Parolalar kaynak koduna veya loglara yazılmaz. Profil varsa ZIP Apple’a gönderilir, uygulama bileti iliştirilir; ardından DMG de imzalanıp noter onayına gönderilir. Profil yoksa çevrimiçi noter işlemi yapılmaz.

[Apple: Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

Gerçek Developer ID imzası ve noter onayı bu Mac’te doğrulanmadı. Gatekeeper veya karantina ayarları otomatik değiştirilmez. İmzalanmamış yerel sürümler için [Apple’ın uygulama açma kılavuzu](https://support.apple.com/tr-tr/102445) geçerlidir.

## GitHub Actions

CI, `macos-15` üzerinde Xcode 16.4 ve 26.3 için ayrı işler içerir. Seçimler [GitHub’ın resmi runner manifestinden](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md) kontrol edildi. Action sürümleri tam commit kimliğine sabittir.

Etiket sürümü Info.plist ile eşleşmek zorundadır. `v*` etiketi ZIP/DMG/kontrol toplamlarını GitHub Release’e yükler. İmza sırları yoksa paket açıkça noter onaysız önizleme olarak yayımlanır. Gerçek imza için `SIGN_IDENTITY`, `CERTIFICATE_P12` (base64), `CERTIFICATE_PASSWORD`, `KEYCHAIN_PASSWORD` gerekir. Noter onayı ayrıca `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD` gerektirir. Sırlar yalnız etiket işinde kullanılır; PR işleri sırlara erişmez. Geçici sertifika ve anahtar zinciri silinir.

Workflow dosyaları yerel olarak sözdizimi kontrolünden geçirildi. Henüz GitHub üzerinde çalıştırılmadı; uzaktaki yeşil CI durumu iddia edilmez.

Yayın paketi oluşturulunca `dist/Casks/ada-island.rb` aynı ZIP’in SHA-256 özetiyle üretilir. Cask, yayın ZIP’i erişilebilir olduğunda bir Homebrew tap deposuna eklenebilir.
