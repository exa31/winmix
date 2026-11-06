# 🎚️ WinMix

> **Open-Source Sound Mixer for macOS**  
> The Windows-style per-application volume mixer for macOS, built with Swift, SwiftUI, and low-latency C CoreAudio Process Taps.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%2014.4%2B-lightgrey.svg)](https://apple.com)
[![Swift](https://img.shields.io/badge/Swift-6.0%2B-orange.svg)](https://swift.org)

---

## ✨ Fitur Utama

- 🎛️ **Per-App Volume Control (0% – 100%)**: Atur volume masing-masing aplikasi (Google Chrome, Spotify, Apple Music, Safari, Discord, WhatsApp, Zoom, dan System Sounds) secara independen dengan batas normal 100% seperti di Windows SndVol asli.
- 🎧 **Per-App Audio Output Routing**: Bebas memilih perangkat output untuk setiap aplikasi (misalnya WhatsApp/Call ke **External Headphones/AirPods**, dan aplikasi lain ke **MacBook Air Speakers**, atau ikuti **Default**).
- 🔄 **Smart Auto-Follow Output Device**: Otomatis mengikuti perangkat output yang aktif di macOS (AirPods, speaker, headphone kabel) tanpa perlu ganti-ganti setting secara manual.
- 📊 **Real-Time Vertical VU Peak Meters**: Indikator lampu audio meter vertikal yang bergoyang (*bounce*) secara real-time mengikuti suara masing-masing aplikasi.
- 🎨 **Dua Pilihan Tema (Switchable)**:
  - **Modern Windows 11 Fluent** (Default): Tampilan bersih bernuansa Windows 11 Acrylic dengan slider modern dan gradien neon.
  - **Classic SndVol (Windows 7/10)**: Tampilan klasik retro dengan fader bertekstur logam dan lampu LED bertingkat hijau/kuning/merah.
- 🔊 **Master Device & Output Selector**: Kontrol volume master speaker serta pemilihan perangkat output langsung dari aplikasi.
- 🔇 **Mute Per-Aplikasi**: Tombol mute mandiri untuk setiap aplikasi tanpa mengganggu audio aplikasi lainnya.
- 🖥️ **Menu Bar & Dock Integration ("Dua-duanya")**:
  - Muncul di **Dock** dan dapat dibuka sebagai jendela mandiri (*standalone window*) seperti di Windows.
  - Muncul di **Menu Bar** (status bar atas) untuk akses cepat kapan saja melalui popover.
  - Tombol tutup (`X`) menyembunyikan jendela ke background; klik icon Dock atau Menu Bar untuk memunculkannya kembali seketika.
- 🚀 **Driver-Free & Zero-Latency**: Memanfaatkan API native Apple CoreAudio Process Taps (`CATapDescription`), tanpa perlu menginstal kernel extension atau virtual audio driver pihak ketiga (seperti BlackHole atau Soundflower).
- 🛡️ **Crash-Safe Architecture**: Menggunakan perilaku `.mutedWhenTapped` bawaan macOS. Jika aplikasi ditutup atau keluar, macOS secara otomatis mengembalikan audio seperti semula tanpa kehilangan suara.

---

## 📥 Download & Instalasi Cepat

Unduh rilis terbaru langsung dari [GitHub Releases](https://github.com/exa31/winmix/releases/latest):

- 📀 **[WinMix-v1.1.0.dmg](https://github.com/exa31/winmix/releases/download/v1.1.0/WinMix-v1.1.0.dmg)** (Rekomendasi): Buka file `.dmg`, lalu tarik icon **WinMix** ke folder **Applications**.
- 🗜️ **[WinMix-v1.1.0.zip](https://github.com/exa31/winmix/releases/download/v1.1.0/WinMix-v1.1.0.zip)** (Portable): Ekstrak file `.zip` dan letakkan `WinMix.app` di `/Applications`.

---

## ✨ Fitur Utama

- 🛡️ **Anti-Ducking (Bypass Call Attenuation)**: Mencegah WhatsApp, FaceTime, Zoom, atau Google Meet mengecilkan (*ducking*) volume Spotify, YouTube, atau game secara otomatis saat panggilan suara/video aktif. Dilengkapi tombol toggle `[🛡️ Anti-Duck: ON/OFF]`.
- 🎛️ **Per-App Volume Control (0% – 100%)**: Atur volume masing-masing aplikasi

- **Sistem Operasi**: macOS 14.4 (Sonoma) atau lebih baru (termasuk macOS 15+ Sequoia / macOS 27).
- **Arsitektur**: Apple Silicon (M1/M2/M3/M4) atau Intel Mac dengan Command Line Tools (`swiftc`, `clang`).

---

## 🛠️ Cara Build & Install

Aplikasi dapat dikompilasi langsung menggunakan script satu langkah:

```bash
chmod +x build.sh
./build.sh
```

Script akan:
1. Menghasilkan icon aplikasi `WinMix.icns`.
2. Mengompilasi engine C real-time `RTMixer.c`.
3. Mengompilasi seluruh source Swift & SwiftUI.
4. Membundel menjadi `WinMix.app`.
5. Menandatangani (*ad-hoc code sign*) dengan entitlement audio capture.
6. Memasang aplikasi langsung ke `/Applications/WinMix.app`.

---

## 🧪 Unit Tests

Untuk menjalankan pengujian unit otomatis (*unit tests*) untuk C audio core dan Swift logic:

```bash
chmod +x test.sh
./test.sh
```

Pengujian ini mencakup:
- **Ketepatan Matematis DSP**: Perhitungan *gain*, penjumlahan buffer audio, isolasi volume antar-aplikasi, dan *soft overdrive clamping* `[-1.0, 1.0]`.
- **Pre-gain Metering**: Memastikan VU meter tetap merespons sumber audio asli meskipun aplikasi sedang di-*mute*.
- **Real-Time Safety (Zero-Allocation)**: Verifikasi 500.000 siklus audio CoreAudio IOProc dengan 0 (*zero*) alokasi heap (`malloc_zone_statistics`).
- **Logika Swift**: Persistensi nilai volume di `UserDefaults`, resolusi nama/icon aplikasi (Chrome, Safari, Spotify, System Sounds), dan konversi logaritmik skala dB.

---

## 🚀 Cara Menjalankan & Izin macOS

1. Buka aplikasi dari Finder atau Terminal:
   ```bash
   open /Applications/WinMix.app
   ```
2. **Izin Perekaman Audio (Pertama Kali)**:
   - Saat pertama kali dibuka, layar panduan aktivasi WinMix akan muncul.
   - Klik **"Aktifkan WinMix / Enable"**.
   - macOS akan memunculkan dialog permintaan izin **Screen & System Audio Recording**.
   - Klik **Allow / Izinkan** (atau aktifkan di **System Settings > Privacy & Security > Screen & System Audio Recording**).
   - Audio diproses secara lokal (*real-time zero latency*) dan tidak pernah disimpan ke file.

---

## 📂 Struktur Proyek

```
.
├── LICENSE                          # MIT Open Source License
├── Sources/
│   ├── RTMixer.h                    # Header C untuk engine real-time mixing
│   ├── RTMixer.c                    # Engine C11 lock-free untuk CoreAudio IOProc
│   ├── Bridging.h                   # Bridge C ke Swift
│   ├── CoreAudioHelpers.swift       # Wrapper aman untuk CoreAudio HAL API
│   ├── AudioProcesses.swift         # Deteksi proses audio & pemetaan nama/icon aplikasi
│   ├── TapEngine.swift              # Manajemen CATapDescription & aggregate device
│   ├── MixerModel.swift             # MainActor observable model & 40Hz VU meter ticker
│   ├── Persistence.swift            # Penyimpanan volume & mute di UserDefaults
│   ├── AppDelegate.swift            # Pengelola Window, Dock, dan Menu Bar status item
│   ├── WinMixApp.swift              # Entry point SwiftUI
│   └── UI/
│       ├── Theme.swift              # Palet warna Windows 11 & Classic SndVol
│       ├── VerticalFader.swift      # Slider vertikal kustom khas Windows
│       ├── VerticalVUMeter.swift    # VU peak meter vertikal (LED & Gradient)
│       ├── WindowsDeviceColumn.swift# Kolom Device (Master volume & output picker)
│       ├── WindowsAppColumn.swift   # Kolom per-aplikasi (Icon, fader, meter, mute, %)
│       ├── PrimerView.swift         # Layar panduan izin audio capture
│       └── WindowsMixerView.swift   # Kontainer utama WinMix UI
├── Resources/
│   ├── Info.plist                   # Bundle metadata & NSAudioCaptureUsageDescription
│   ├── WinMix.entitlements          # Entitlement audio-input
│   └── icongen.m                    # Generator icon aplikasi WinMix
├── tests/
│   ├── rt_test.c                    # Unit test C audio core & zero-allocation benchmark
│   └── SwiftUnitTests.swift         # Unit test Swift model & persistence
├── test.sh                          # Script otomatis run all unit tests
├── build.sh                         # Script otomatis build, sign, dan install
└── README.md
```

---

## 📄 Lisensi

Proyek ini berlisensi [MIT License](LICENSE).
