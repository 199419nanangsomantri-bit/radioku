# Radio Saya

Radio streaming sederhana, tanpa iklan dan tanpa tracking.
Mendukung **background playback** — radio tetap berbunyi saat layar mati atau HP masuk mode tidur.

## Edit daftar stasiun
Buka `lib/main.dart`, cari bagian `DAFTAR STASIUN`. Tambah/ubah baris:

    Station('Nama Stasiun', 'https://alamat-stream-anda'),

Commit ke branch main.

## Build APK
1. Commit ke branch main (build otomatis), atau tab Actions → "Build APK" → Run workflow.
2. Tunggu 5-10 menit sampai centang hijau.
3. Buka run, scroll ke Artifacts, unduh `radio-apk`.
4. Ekstrak zip, pasang .apk di HP.

## Background playback
Aplikasi memakai `just_audio_background` sehingga audio tetap berjalan saat:
- Layar mati
- HP masuk mode tidur
- Aplikasi di-minimize

Akan muncul notifikasi media dengan tombol play/pause/stop.

## Catatan baterai
Beberapa produsen HP (Xiaomi, Oppo, Vivo, Huawei) punya manajemen baterai agresif
yang bisa mematikan service. Setelah install:
- Buka Pengaturan → Aplikasi → Radio Saya → Baterai
- Pilih "Tidak dibatasi" / "Unrestricted"
- Aktifkan "Autostart" jika ada

## Error umum
- **Build gagal**: cek indentasi YAML (harus spasi, bukan tab).
- **Tidak ada suara**: pastikan izin INTERNET ada (sudah ada di manifest).
- **Notifikasi tidak muncul**: Android 13+ butuh izin POST_NOTIFICATIONS,
  biasanya diminta otomatis saat pertama kali play. Jika tidak, buka
  Pengaturan → Aplikasi → Radio Saya → Notifikasi → izinkan.
- **Suara tetap berhenti saat layar mati**: matikan optimasi baterai (lihat di atas).
