# Koridor — Ortalama Hız Koridoru Takibi

Android (Pixel 7 Pro ile test hedefi) için Flutter uygulaması. Kayıtlı bir ortalama hız
koridorunun giriş noktasına doğru yönde girince otomatik başlar, ortalama hızı canlı
hesaplar, limite yaklaşınca/limit aşılınca Türkçe sesli uyarır, çıkışta geçişi kaydeder.

## Nasıl çalışır
- **Koridor** = giriş noktası + giriş yönü + çıkış noktası + limit + yol boyunca uzunluk.
- **Otomatik tetikleme:** Giriş noktasının 80 m yarıçapına, koridor yönüyle ±35° uyumlu
  girilince sayaç başlar. Aynı yolun karşı şeridi tetiklenmez.
- **Ortalama:** GPS noktaları arası mesafe toplanarak (yol boyunca) hesaplanır.
- **"En fazla"** değeri: kalan mesafede ortalamayı limitin altında tutmak için
  gidilebilecek azami hız.
- **Çıkış:** Çıkış noktasının 80 m yakınına gelince biter; geçiş "Geçmiş" sekmesine düşer.
  Aynı koridor 3 dk içinde tekrar tetiklenmez.
- **Koridor ekleme (sürüş sırasında):** Takip açıkken giriş tabelasında
  "Koridor başlangıcı", çıkış tabelasında "Bitiş" bas; ad ve limiti gir. Uzunluk ve yön
  otomatik ölçülür. Sonradan "Koridorlar" sekmesinden düzenlenebilir / haritada görülür.

## APK üretme

### Yol A — GitHub Actions (bilgisayara hiçbir şey kurmadan)
1. GitHub'da yeni bir repo aç (private olabilir).
2. Bu klasörü repoya yükle (`main` dalı).
3. **Actions** sekmesinde "APK derle" iş akışı kendiliğinden çalışır (~5 dk).
4. Bitince "Artifacts" altından `koridor-apk` dosyasını indir, içindeki
   `app-release.apk`'yı telefona at ve kur ("bilinmeyen kaynak" iznini ver).

### Yol B — Bilgisayarda
Flutter SDK + Android Studio kuruluysa, bu klasörde:
```
flutter create . --org com.furkanvarol --project-name koridor --platforms android
flutter pub get
flutter build apk --release
```
APK: `build/app/outputs/flutter-apk/app-release.apk`. Telefon USB ile bağlıyken
`flutter run --release` doğrudan yükler.

## Telefon ayarları
- İlk açılışta konum iznini **"Uygulama kullanımdayken"** olarak ver; takip açıkken
  kalıcı bir bildirimle ön planda çalışır (ekran kapalıyken de devam eder).
- Android 13+ bildirim iznini de ver (uyarı bildirimi için).
- Pil ayarlarında Koridor için "Kısıtlanmamış" seç; aksi halde Pixel arka planda GPS'i
  kısabilir.
- Sesli uyarı için Google TTS'te Türkçe ses paketi yüklü olmalı (Pixel'de genelde hazır).

## Dosyalar
- `lib/tracker.dart` — konum akışı, otomatik giriş/çıkış, ortalama ve uyarı mantığı
- `lib/models.dart` — Corridor, Passage
- `lib/storage.dart` — JSON kalıcılık
- `lib/screens/` — Sürüş, Koridorlar (+ harita), Geçmiş
- `android/app/src/main/AndroidManifest.xml` — konum/ön plan servisi izinleri
