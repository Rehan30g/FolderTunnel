# Folder Tunnel

Aplikasi portable Windows untuk membagikan (share) sebuah folder ke internet lewat browser — **tanpa install apa-apa**.

Cukup **extract & jalankan `FolderTunnel.bat`** → muncul window GUI. Tidak perlu Python, Node, atau web server tambahan. Server file berjalan di PowerShell bawaan Windows, dan tunneling publik memakai **cloudflared** (Quick Tunnel / `trycloudflare.com`, gratis tanpa daftar akun).

## Fitur

- **GUI Window** (WPF bawaan Windows, tanpa install)
- Pilih folder yang mau di-share **lewat dialog file explorer**
- Auto-download `cloudflared.exe` saat aplikasi pertama dibuka (portable, tidak perlu install)
- URL publik `https://xxxx.trycloudflare.com` langsung tampil di GUI
- Tampilan file manager di browser (navigasi folder, download file)
- Upload file dari browser (bisa diaktifkan/dimatikan)
- Hapus file dari browser (bisa diaktifkan/dimatikan)
- Password proteksi (opsional)
- Anti directory-traversal (akses dibatasi hanya di folder yang di-share)
- Start / stop server & tunnel dari GUI
- Log aktivitas real-time di GUI

## Cara pakai

1. Jalankan `FolderTunnel.bat` (cloudflared otomatis diunduh sekali saat pertama dibuka)
2. Klik **Pilih folder...** → pilih folder lewat file explorer
3. (Opsional) isi password, centang izin upload/hapus
4. Klik **Share ke INTERNET**
5. URL publik muncul di kotak "URL PUBLIK" — bagikan ke siapa pun
6. Klik **Stop semua** untuk menghentikan

> Jendela GUI harus tetap terbuka selama tunnel dipakai (boleh minimize). Saat ditutup, aplikasi menawarkan untuk menghentikan tunnel.

## File

| File | Fungsi |
|---|---|
| `FolderTunnel.bat` | Launcher GUI |
| `GUI.ps1` | Window GUI (WPF) + kontrol server/tunnel |
| `server.ps1` | HTTP file server (PowerShell bawaan) |
| `tunnel.ps1` | Launcher tunnel cloudflared |

File yang dibuat saat runtime (tidak perlu di-commit): `settings.json`, `cloudflared.exe`, `server.pid`, `tunnel.pid`, `tunnel.url`, `server.log/err`, `tunnel.out/err`.

## Catatan

- Cloudflare Quick Tunnel bersifat sementara: URL berubah setiap kali tunnel dimulai ulang.
- Selalu aktifkan password jika folder berisi data sensitif.
- Butuh koneksi internet untuk download cloudflared pertama kali dan menjaga tunnel.