# WinTunnel

Aplikasi portable Windows untuk membagikan (share) sebuah folder ke internet lewat browser — **tanpa install apa-apa**.

Cukup **extract dan jalankan `start.bat`** lalu GUI muncul tanpa terminal. Tidak perlu Python, Node, atau web server tambahan. Server file berjalan di PowerShell bawaan Windows, dan tunneling publik memakai **cloudflared** (Quick Tunnel / `trycloudflare.com`, gratis tanpa daftar akun).

## Fitur

- **GUI Window** (WPF bawaan Windows, tanpa install)
- Pilih folder yang mau di-share **lewat dialog file explorer**
- Auto-download `cloudflared.exe` saat pertama kali memilih berbagi ke internet, dengan progres dan hasil verifikasi yang jelas
- URL publik `https://xxxx.trycloudflare.com` langsung tampil di GUI
- Tampilan file manager di browser (navigasi folder, download file)
- Upload file dari browser (bisa diaktifkan/dimatikan)
- Hapus file dari browser (bisa diaktifkan/dimatikan)
- Password proteksi (opsional)
- Anti directory-traversal (akses dibatasi hanya di folder yang di-share)
- Start / stop server & tunnel dari GUI
- Log aktivitas real-time di GUI
- Pemeriksaan update otomatis dari GitHub saat aplikasi dibuka
- Popup update terpisah yang menampilkan ringkasan fitur/perbaikan sebelum pengguna memilih update atau nanti

## Cara pakai

1. Jalankan `start.bat`
2. Klik **Pilih folder** → pilih folder lewat file explorer
3. (Opsional) isi password, centang izin upload/hapus
4. Klik **Bagikan ke internet**
5. URL publik muncul di kotak "URL PUBLIK" — bagikan ke siapa pun
6. Klik **Stop semua** untuk menghentikan

> Jendela GUI harus tetap terbuka selama tunnel dipakai (boleh minimize). Saat ditutup, aplikasi menawarkan untuk menghentikan tunnel.

## File

| File | Fungsi |
|---|---|
| `start.bat` | Launcher utama |
| `WinTunnel Internet.url` | Shortcut menuju URL publik aktif terbaru |
| `app/` | Kode aplikasi, updater, serta file web HTML/CSS/JavaScript |
| `data/` | Konfigurasi, cloudflared, backup update, dan folder `logs/` |

File runtime disimpan terpisah di dalam `data/`, sehingga folder utama tetap ringkas.

## Catatan

- Cloudflare Quick Tunnel bersifat sementara: URL berubah setiap kali tunnel dimulai ulang.
- Selalu aktifkan password jika folder berisi data sensitif.
- Butuh koneksi internet untuk download cloudflared pertama kali dan menjaga tunnel.
