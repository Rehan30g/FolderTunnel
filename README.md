# Folder Tunnel

Aplikasi portable Windows untuk membagikan (share) sebuah folder ke internet lewat browser — **tanpa install apa-apa**.

Tinggal double-click `FolderTunnel.bat`, tidak perlu Python, Node, atau web server tambahan. Server file berjalan di PowerShell bawaan Windows, dan tunneling publik memakai **cloudflared** (Quick Tunnel / `trycloudflare.com`, gratis tanpa daftar akun).

## Fitur

- Share folder ke internet dengan URL publik `https://xxxx.trycloudflare.com`
- Tampilan file manager di browser (navigasi folder, download file)
- Upload file dari browser (bisa diaktifkan/dimatikan)
- Hapus file dari browser (bisa diaktifkan/dimatikan)
- Password proteksi (opsional)
- Anti directory-traversal (akses dibatasi hanya di folder yang di-share)
- Start / stop server & tunnel dari menu

## Cara pakai

1. Jalankan `FolderTunnel.bat`
2. Menu `1` — pilih folder yang mau di-share (default: folder `shared`)
3. Menu `2` — atur password (opsional tapi disarankan)
4. Menu `3` — atur izin upload/hapus
5. Menu `4` — **SHARE KE INTERNET**
   - Saat pertama kali, aplikasi otomatis mengunduh `cloudflared.exe` (portable, ±15 MB, tidak perlu install)
   - URL publik akan muncul di menu dan jendela "FT Tunnel"
6. Bagikan URL tersebut; penerima buka lewat browser

> Jendela "FT Server" dan "FT Tunnel" harus tetap terbuka selama tunnel dipakai (boleh minimize).

## File

| File | Fungsi |
|---|---|
| `FolderTunnel.bat` | Menu utama (start/stop/konfigurasi) |
| `server.ps1` | HTTP file server (PowerShell bawaan) |
| `tunnel.ps1` | Launcher tunnel cloudflared |

File yang dibuat saat runtime (tidak perlu di-commit): `settings.bat`, `cloudflared.exe`, `server.pid`, `tunnel.pid`, `tunnel.url`, `tunnel.err/out`.

## Catatan

- Cloudflare Quick Tunnel bersifat sementara: URL berubah setiap kali tunnel dimulai ulang.
- Selalu aktifkan password jika folder berisi data sensitif.
- Butuh koneksi internet hanya untuk download cloudflared pertama kali dan menjaga tunnel.