# Input Switcher

Apple Silicon Mac için menü bar monitör input değiştirici.  
BetterDisplay'e gerek yok — `m1ddc` kullanılır, tamamen ücretsiz.

Mevcut sürüm: `1.5.1`

---

## Kurulum

Finder'dan tek tık kurulum:

1. Repo'yu indir
2. `install.command` dosyasına çift tıkla

Aynı dosyayı gelecekte tekrar çalıştırırsan mevcut `InputSwitcher.app` kurulumu yeni sürümle otomatik olarak değiştirilir.

DMG üretmek için:

1. `build_dmg.command` dosyasına çift tıkla
2. Çıktıyı `dist/InputSwitcher-<sürüm>.dmg` altında bul

Alternatif olarak Terminal'den:

```bash
chmod +x install.sh
./install.sh
```

Script otomatik olarak:
1. `m1ddc`'yi önce Homebrew yollarında (`/opt/homebrew/bin`, `/usr/local/bin`) ve `PATH` içinde arar; yoksa kurmayı dener
2. Swift uygulamasını derler
3. Eski kurulum varsa kapatır ve `~/Applications/InputSwitcher.app` üzerine yeni sürümü kurar
4. İsteğe bağlı: login item olarak ekler
5. LAN üzerinden diğer Mac'i bulabilmesi için gerekli local network/Bonjour ayarlarını bundle içine koyar

---

## Kullanım

Menü barındaki 🖥 ikonuna tıkla → Input seç → geçiş olur.

Aktif input listede mavi vurgulanır ve işaretlenir.

`Input Listesini Düzenle...` ekranından:
- Her input için nickname/alias ekleyebilir, değiştirebilir veya alanı boş bırakarak silebilirsin
- Her input için ham DDC değeri ve komut modunu (`Auto`, `input`, `input-alt`) ayrı ayrı ayarlayabilirsin
- Kısayol döngüsüne dahil olacak input'ları seçebilirsin
- Global kısayol kaydedebilirsin; bu kısayol yalnızca işaretlediğin input'lar arasında geçer
- Hedef monitörü seçebilirsin

Uygulama aynı ağdaki diğer Input Switcher instance'larını bulur. Monitör bu Mac'te bağlı değilse, seçilen input için diğer Mac'e uzaktan geçiş isteği gönderir.
Monitör sahipliği artık gerçek `m1ddc display list` sonucuna göre belirlenir; sahte display fallback kullanılmaz.
LAN eşleşmesi artık ham display başlığına değil, normalize edilmiş monitör kimliğine göre yapılır.

Homebrew ile kurulu `m1ddc` için Apple Silicon Mac'lerde tipik yol `/opt/homebrew/bin/m1ddc`'dir. Uygulama bunu otomatik bulur.

`Hakkında` penceresi sürümü, kurulum yolunu ve iki Mac'e kurulum notunu gösterir.
`Tanılama Günlüğü` penceresi peer keşfi, monitör sahipliği ve switch isteklerini loglar; `Copy All` ile tamamını kopyalayabilirsin.

---

## Input Değerleri

Varsayılan değerler (monitöre göre farklılık gösterebilir):

| Kaynak       | DDC Değeri |
|--------------|-----------|
| DisplayPort 1 | 15        |
| DisplayPort 2 | 16        |
| HDMI 1       | 17        |
| HDMI 2       | 18        |
| USB-C        | 27        |

**Kendi monitörünün değerlerini bulmak için:**
```bash
m1ddc get input
```
(Her MacBook'tan ayrı ayrı çalıştır, mevcut input'un değerini döner)

Menü barındaki **"Input Listesini Düzenle..."** seçeneğinden isim ve değerleri değiştirebilirsin.

---

## Gereksinimler

- Apple Silicon Mac (M1/M2/M3/M4)
- macOS 12 Monterey veya üzeri
- DDC/CI destekli monitör (LG dışı çoğu marka destekler)
- USB-C veya DisplayPort üzerinden bağlantı (M1/M2 yerleşik HDMI portu desteklenmez)

---

## Sorun Giderme

**Geçiş çalışmıyor:** Monitörünün DDC/CI'yı destekleyip desteklemediğini kontrol et:
```bash
m1ddc display list
```

**LG monitör:** LG, DDC/CI'yı tam desteklemez. `set input-alt` değerlerini dene:
DP1=208, DP2=209, HDMI1=144, HDMI2=145

**M1 Mac Mini / built-in HDMI:** Yerleşik HDMI portu desteklenmez, USB-C adaptör kullan.
