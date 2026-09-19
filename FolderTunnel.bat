@echo off
setlocal
title Folder Tunnel
cd /d "%~dp0"

if not exist "settings.bat" (
  set "PORT=8080"
  set "PASSWORD="
  set "ALLOW_UPLOAD=1"
  set "ALLOW_DELETE=0"
  if not exist "%~dp0shared" mkdir "%~dp0shared"
  set "FOLDER=%~dp0shared"
  call :save
)
call "settings.bat"

:menu
cls
echo ==================================================
echo              F O L D E R   T U N N E L
echo      Share folder ke internet tanpa install
echo ==================================================
echo   Folder : %FOLDER%
echo   Port   : %PORT%
if "%PASSWORD%"=="" (echo   Pass   : TIDAK ADA - siapapun bisa akses!) else (echo   Pass   : aktif)
echo   Upload : %ALLOW_UPLOAD% (1=boleh, 0=tidak)   Hapus: %ALLOW_DELETE%
echo.
if exist "tunnel.url" (
  echo   URL PUBLIK AKTIF:
  type "tunnel.url"
  echo.
)
echo   1. Pilih folder yang akan di-share
echo   2. Atur password
echo   3. Atur izin upload / hapus
echo   4. SHARE KE INTERNET (mulai)
echo   5. Server lokal saja (localhost/LAN)
echo   6. Stop semua
echo   7. Buka di browser
echo   8. Buka folder aplikasi ini
echo   0. Keluar (stop semua)
echo.
set /p "pilih=  Pilih nomor: "
if "%pilih%"=="1" goto pilihfolder
if "%pilih%"=="2" goto setpass
if "%pilih%"=="3" goto toggles
if "%pilih%"=="4" goto startnet
if "%pilih%"=="5" goto startlocal
if "%pilih%"=="6" goto stopmenu
if "%pilih%"=="7" goto browse
if "%pilih%"=="8" start "" explorer.exe "%~dp0"
if "%pilih%"=="0" goto keluar
goto menu

:pilihfolder
echo.
echo Folder sekarang: %FOLDER%
set /p "nf=Path folder baru (Enter = batal): "
if "%nf%"=="" goto menu
if not exist "%nf%\" (
  echo Folder tidak ditemukan!
  pause
  goto menu
)
set "FOLDER=%nf%"
call :save
echo Folder diubah.
timeout /t 1 >nul
goto menu

:setpass
echo.
echo Password sekarang: %PASSWORD%
echo Password proteksi folder lewat web. Boleh pakai spasi/huruf/angka.
set /p "npw=Password baru (kosong = tanpa password): "
set "PASSWORD=%npw%"
call :save
echo Password diatur.
timeout /t 1 >nul
goto menu

:toggles
echo.
set /p "u=Izin upload dari web? (0/1) [%ALLOW_UPLOAD%]: "
if "%u%"=="" set "u=%ALLOW_UPLOAD%"
set "ALLOW_UPLOAD=%u%"
set /p "d=Izin hapus dari web? (0/1) [%ALLOW_DELETE%]: "
if "%d%"=="" set "d=%ALLOW_DELETE%"
set "ALLOW_DELETE=%d%"
call :save
echo Izin disimpan.
timeout /t 1 >nul
goto menu

:startnet
call :stopall
if not exist "cloudflared.exe" (
  echo.
  echo Butuh cloudflared.exe ^(portable ~15MB, TIDAK perlu install, hanya 1x download^).
  choice /c YN /m "Download sekarang"
  if errorlevel 2 goto menu
  echo Mengunduh...
  powershell -NoProfile -Command "$ProgressPreference='SilentlyContinue'; try { Invoke-WebRequest 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe' -OutFile 'cloudflared.exe' -UseBasicParsing } catch { exit 1 }"
  if not exist "cloudflared.exe" (
    echo GAGAL download. Cek koneksi internet lalu coba lagi.
    pause
    goto menu
  )
)
call :startserver
start "FT Tunnel" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tunnel.ps1" -Port %PORT%
echo.
echo Menunggu URL publik (maks 45 detik)...
set /a tries=0
:waiturl
if exist "tunnel.url" goto goturl
set /a tries+=1
if %tries% geq 45 goto nourl
timeout /t 1 >nul
goto waiturl
:goturl
echo.
echo   ==========================================
echo   URL PUBLIK (bagikan ini):
for /f "usebackq delims=" %%u in ("tunnel.url") do echo   %%u
echo   ==========================================
choice /c YN /m "Buka browser sekarang"
if errorlevel 2 goto menu
for /f "usebackq delims=" %%u in ("tunnel.url") do start "" "%%u"
goto menu
:nourl
echo.
echo URL belum muncul. Lihat jendela "FT Tunnel" atau cek tunnel.err
pause
goto menu

:startlocal
call :stopall
call :startserver
echo.
echo Server lokal jalan: http://localhost:%PORT%
timeout /t 2 >nul
goto menu

:startserver
start "FT Server" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1" -Root "%FOLDER%" -Port %PORT% -Password "%PASSWORD%" -AllowUpload %ALLOW_UPLOAD% -AllowDelete %ALLOW_DELETE%
exit /b

:stopmenu
call :stopall
echo Semua server & tunnel dihentikan.
timeout /t 1 >nul
goto menu

:browse
start "" "http://localhost:%PORT%"
if exist "tunnel.url" (
  for /f "usebackq delims=" %%u in ("tunnel.url") do start "" "%%u"
)
goto menu

:keluar
choice /c YN /m "Stop server & tunnel sebelum keluar"
if errorlevel 2 exit
call :stopall
exit

:save
> "%~dp0settings.bat" echo set "PORT=%PORT%"
>> "%~dp0settings.bat" echo set "PASSWORD=%PASSWORD%"
>> "%~dp0settings.bat" echo set "ALLOW_UPLOAD=%ALLOW_UPLOAD%"
>> "%~dp0settings.bat" echo set "ALLOW_DELETE=%ALLOW_DELETE%"
>> "%~dp0settings.bat" echo set "FOLDER=%FOLDER%"
exit /b