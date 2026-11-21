# Oturumlar arası not — koridor verisi

**Yazan:** koridor-verisi oturumu (dal `ccr-2cc5b451-24r8sp`)
**Okuyan:** uygulama kodunu düzenleyen oturum
**Tarih:** 2026-11-21 · Yarın (22.11) Ankara → İzmir yolculuğunda sahada denenecek.

Bu oturum `lib/` altına dokunmuyor. Sadece `koridor-verisi/` klasöründe çalışıyor.
Cevap/soru yazmak istersen bu dosyanın altındaki **Mesajlar** bölümüne ekle ve push et.

## Ne var
- `ankara-izmir.json`: 13 koridor (6 tanesi Ankara→İzmir, 7 tanesi İzmir→Ankara yönünde).
  Biçim `Corridor.toJson()` ile birebir aynı. `Corridor.fromJson` dosyayı olduğu gibi okur.
  Ek alanlar var (`source`, `sourceId`, `officialLengthKm`, `vehicleType`, `yon`).
  `fromJson` bunları yok sayar.
- `olustur.py`: Ham bakanlık cevabından bu JSON'u üreten betik.

## Kaynak
`https://www.icisleri.gov.tr/iller-arasi-radar-ve-kontrol-noktasi-uygulama-sayilari` sayfasının
kullandığı uçlar şunlar:
- `GET  /ISAYWebPart/PolGenControlPointV2/GetCities` → `[{Id, Name}]`
- `GET  /ISAYWebPart/PolGenControlPointV2/GetDistricts?cityId=6` → `[{Id, Name, Latitude, Longitude}]`
- `POST /ISAYWebPart/PolGenControlPointV2/CreateRoute` (form: `fromLatitude, fromLongitude,
  toLatitude, toLongitude, fromDistrictId, toDistrictId`) → `{success, message, data}`
  - `data.SpeedTunnels[]`: `id, name, speedLimit, vehicleType, length (km, tam sayı),
    startLatY, startLonX, endLatY, endLonX, activity (3 = aktif), coordinates[{x: lng, y: lat}]`
  - `data.Coordinates[]`: rota çizgisi, `data.Radars[]`
  - Sorgu Çankaya (1231) → Konak (1819) için yapıldı. Ters yönde de aynı 13 koridor geldi.
  - Tarayıcı User-Agent'ı olmadan site 500 döndürüyor.

## Dönüştürürken yaptıklarım
- `coordinates` bazı koridorlarda **çıkıştan girişe ters sırada** geliyor. İzi giriş→çıkış yönüne çevirdim.
- `startBearing`: girişten iz boyunca ~150 m sonraki noktaya olan yön.
- `lengthM`: izin uzunluğu (resmi `length` km yuvarlanmış geliyor). Arada en büyük fark
  1718'de var (resmi 15 km, iz 17,2 km).
- İzi ~50 m aralıkla seyrelttim.
- `limitKmh`: tümü 110 (vehicleType 1, büyük ihtimalle otomobil).

## Uygulama koduna dair dikkat (sen karar ver)
1. **Aynı girişi paylaşan koridorlar var.** `tracker.dart:173` ilk eşleşeni alıyor ve aynı anda
   tek koridor izliyor.
   - Sivrihisar girişi: 1233 (→Afyon) ve 1261 (→Ankara) aynı nokta ve aynı yön (115,5°).
     Gerçekte hangisi olduğu çıkışta belli oluyor. JSON'da 1233'ü öne koydum, yarınki yönde doğru olan o.
   - Afyon girişi (dönüş): 1234 (→Sivrihisar, 128 km) ve 1260 (→Ankara, 226 km) aynı anda geçerli.
     İkisini paralel izlemek gerekebilir.
2. **Arka arkaya koridorlar:** 1720'nin çıkışı 1560'ın girişi; 1563'ün çıkışı 1569'un girişi.
   Çıkış yakalanınca aynı noktadaki yeni girişin de hemen tetiklenmesi gerekiyor. Yarın sahada bakılacak.
3. **1233'ün girişi bakanlığın kendi rotasından ~900 m uzakta.** İz %97 rotanın üzerinde ama giriş
   noktası değil, 80 m yarıçapla tetiklenmeyebilir. Yarın burada elle kayıt da yapılacak,
   ikisi karşılaştırılacak.
4. Uygulamaya JSON içe aktarma yoksa bu dosyayı `corridors.json` olarak yüklemenin bir yolu lazım
   (ör. "Dosyadan koridor içe aktar" ya da asset olarak gömme). Hangisini yaparsan buraya yaz.

## Yarınki test planı (Ankara → İzmir)
Sırasıyla: 1433 → 1233 → (Afyon–Uşak arası koridor yok) → 1720 → 1560 → 1563 → 1569.
Her koridorda: otomatik başladı mı, otomatik bitti mi, uygulamanın ortalaması ve uzunluğu.
Şüpheli yerlerde elle kayıt ("Koridor başlangıcı"/"Bitiş") yapılıp karşılaştırılacak.

## Mesajlar
- (koridor-verisi oturumu) Dosya hazır. İçe aktarma yolunu sen eklersen JSON'u ona göre
  güncellerim. Alan adı ya da biçim değişikliği istersen buraya yaz.
