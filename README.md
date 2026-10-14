# Input Switcher

Apple Silicon Mac için menü bar monitör input değiştirici.  
BetterDisplay'e gerek yok — `m1ddc` kullanılır, tamamen ücretsiz.

Mevcut sürüm: `1.6.0` · [English](#english)

---

## Kurulum

Finder'dan tek tık kurulum:

1. Repo'yu indir
2. `install.command` dosyasına çift tıkla

Aynı dosyayı gelecekte tekrar çalıştırırsan mevcut `InputSwitcher.app` kurulumu yeni sürümle otomatik olarak değiştirilir.

DMG ve ZIP üretmek için (kurulu uygulamaya dokunmaz):

1. `build_dmg.command` dosyasına çift tıkla
2. Çıktıyı `dist/InputSwitcher-<sürüm>.dmg` ve `.zip` olarak bul

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

Menüde ayrıca:
- **Parlaklık ve ses kaydırıcıları** (monitör bu Mac'e bağlıyken, DDC ile). Hoparlör simgesine tıklamak sesi kapatır/açar.
- **Ekranda: …** satırı monitörün o an hangi Mac'te olduğunu gösterir. `Ekrandaki Mac'i Menü Çubuğunda Göster` ile bu bilgi menü çubuğunda da görünür.
- **Klavye Tuşları**: parlaklık tuşları (imleç harici monitördeyken) ve ses/sessiz tuşları monitörü DDC ile ayarlayabilir. Option+Shift ince adım verir. Erişilebilirlik izni gerekir; uygulama her yeniden kurulduğunda imza değiştiği için izni tekrar vermen gerekebilir.
- **Dil**: Sistem / Türkçe / English.

Uygulama hangi Mac'in hangi girişte olduğunu kendiliğinden öğrenir (iki kararlı ölçüm sonrası) ve takma adı boş olan input'ların yanında `◦ Mac adı` olarak gösterir.

`Input Listesini Düzenle...` ekranından:
- Her input için nickname/alias ekleyebilir, değiştirebilir veya alanı boş bırakarak silebilirsin
- Her input için ham DDC değeri ve komut modunu (`Auto`, `input`, `input-alt`) ayrı ayrı ayarlayabilirsin
- Kısayol döngüsüne dahil olacak input'ları seçebilirsin
- Global döngü kısayolu kaydedebilirsin; bu kısayol yalnızca `Döngüde` işaretli input'lar arasında geçer
- Her input için ayrı bir global kısayol atayabilirsin (`Kısayol` sütunu); aynı kısayol iki yerde kullanılamaz
- `Input Keşfet...` yaygın DDC değerlerini dener, ekran değişirse otomatik geri döner (doğrudan ya da diğer Mac üzerinden) ve çalışan değerleri tek tıkla listeye uygular
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

## Güncellemeler

Uygulama, GitHub Releases üzerinden yeni sürümleri kendisi bulur ve yerinde günceller.

- Açılıştan ~10 saniye sonra ve her 6 saatte bir yeni sürüm denetlenir (menü: **Güncellemeler > Güncellemeleri otomatik denetle**, varsayılan açık). Elle denetlemek için **Güncellemeleri Denetle...**.
- Yeni sürüm varsa menünün en üstünde **Güncelleme var: x.y.z — Yükle** görünür; her yeni sürüm için bir kez bildirim penceresi de açılır.
- **Yükle**: `InputSwitcher-<sürüm>.zip` indirilir, doğrulanır (bundle kimliği ve sürüm), uygulama kapanır, eski sürümün yerine yenisi konur ve otomatik açılır. İlerleme menü başlığında görünür.
- **Güncellemeleri otomatik yükle** (varsayılan kapalı) açıksa bulunan güncelleme sormadan yüklenir.
- Uygulamanın bulunduğu klasöre yazma izni yoksa sürüm sayfası açılır, elle kurarsın.
- Uygulama ad-hoc imzalı olduğu için her güncellemeden sonra macOS **Erişilebilirlik** iznini (parlaklık/ses tuşları özelliği) yeniden isteyebilir; gerekirse Sistem Ayarları > Gizlilik ve Güvenlik > Erişilebilirlik altında yeniden ver.
- Depo herkese açık (public) olmalıdır; aksi halde diğer Mac'ler sürümleri göremez. Depo adı `InputSwitcher.swift` içindeki `updateRepository` sabitindedir.

## Yeni sürüm yayınlama

1. `VERSION` dosyasındaki sürümü artır ve commit et (çalışma dizini temiz olmalı).
2. `release.command` dosyasına çift tıkla (ya da `./release.sh [notlar.md]`). Script paketleri derler, özeti gösterir, onayınla `v<sürüm>` etiketini gönderir ve ZIP + DMG ile GitHub Release oluşturur.
3. Gereksinimler: `origin` remote'u, `gh` (GitHub CLI) kurulu ve `gh auth login` yapılmış olmalı.

Diğer Mac'lerdeki uygulamalar yeni sürümü bir sonraki denetimde bulur.

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

---

## English

Menu bar display input switcher for Apple Silicon Macs, powered by `m1ddc` (free, no BetterDisplay needed). The UI follows the macOS language; switch it under **Language** in the menu.

- Install: double-click `install.command` (re-running it upgrades the existing app). Build a DMG and ZIP (without touching the installed app) with `build_dmg.command`.
- Switch inputs from the menu, with a cycle shortcut, or with a dedicated global hotkey per input.
- Brightness and volume sliders in the menu; optionally let the brightness keys (while the pointer is on the external display) and volume/mute keys control the display over DDC (needs Accessibility permission).
- With Input Switcher on both Macs, they find each other over Bonjour: the menu shows which Mac is on screen, learns which input belongs to which Mac, and forwards a switch to the Mac that currently owns the display.
- **Discover Inputs...** probes common DDC values, switches back automatically, and applies the working values to the list.
- **Diagnostics Log** shows peer discovery, display ownership and switch requests; **Copy All** copies everything.

- **Updates:** the app checks GitHub Releases ~10 seconds after launch and every 6 hours (**Updates > Automatically check for updates**, on by default; **Check for Updates...** runs it manually). When a new version exists, an **Update available: x.y.z — Install** item appears at the top of the menu, plus a one-time alert per version. Install downloads `InputSwitcher-<version>.zip`, validates it (bundle identifier and version), quits, swaps the app in place and relaunches it. **Install updates automatically** (off by default) skips the prompt. If the app's folder isn't writable, the release page opens instead. Because the app is ad-hoc signed, macOS may ask for the Accessibility permission again after an update (media keys feature). The repository must be public, and its name lives in `updateRepository` in `InputSwitcher.swift`.
- **Publishing a release:** bump `VERSION`, commit (clean working tree), then double-click `release.command` (or run `./release.sh [notes.md]`). It builds the ZIP and DMG, shows a summary, and on confirmation tags `v<version>`, pushes, and creates the GitHub Release. Needs an `origin` remote and an authenticated `gh` CLI.
