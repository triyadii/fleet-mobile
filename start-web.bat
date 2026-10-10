@echo off
setlocal EnableExtensions
title FleetTrack - Web Debug

rem ── FleetTrack Driver — debug versi web, memanggil API remote ──
rem   Mode 1 (default) : Chrome debug + CORS dimatikan (khusus dev)
rem                      -> aman bila API belum mengirim header CORS
rem   Mode 2           : web-server di http://127.0.0.1:%WEB_PORT%
rem                      -> buka di browser mana pun (butuh CORS dari API)
rem
rem Pemakaian:  start-web.bat            (tanya mode)
rem             start-web.bat chrome     (langsung mode 1)
rem             start-web.bat server     (langsung mode 2)

set "PROJ=%~dp0"
set "PROJ=%PROJ:~0,-1%"

rem URL API — diteruskan ke aplikasi lewat --dart-define (lihat AppConfig).
set "API_URL=https://dicotriyadi.site/fleet"
set "WEB_HOST=127.0.0.1"
set "WEB_PORT=5173"

echo.
echo  ==========================================================
echo   FleetTrack Driver - web debug
echo  ==========================================================
echo.

rem ── Prasyarat ──
if not exist "%PROJ%\pubspec.yaml" (
    echo  [X] pubspec.yaml tidak ditemukan di %PROJ%
    goto :fail
)

set "SDK="
for /f "delims=" %%F in ('where flutter 2^>nul') do if not defined SDK set "SDK=%%~dpF"
if not defined SDK (
    echo  [X] Flutter tidak ada di PATH.
    goto :fail
)
if not exist "%SDK%flutter.bat" (
    echo  [X] SDK Flutter tidak terjangkau di: %SDK%
    goto :fail
)
set "FLUTTER=%SDK%flutter.bat"
echo  [OK] Flutter : %SDK%

rem Cek API bisa dijangkau (tidak fatal bila gagal).
curl -s -o nul -m 10 -w "%%{http_code}" "%API_URL%/api/documentation" > "%TEMP%\fleet_api_check.txt" 2>nul
set /p API_CODE=<"%TEMP%\fleet_api_check.txt"
del "%TEMP%\fleet_api_check.txt" >nul 2>nul
if "%API_CODE%"=="200" (
    echo  [OK] API     : %API_URL%
) else (
    echo  [*]  API     : %API_URL% belum merespons ^(kode: %API_CODE%^)
)

rem ── Pilih mode ──
set "MODE=%~1"
if /i "%MODE%"=="chrome" goto :chrome
if /i "%MODE%"=="server" goto :server
echo.
echo   [1] Chrome debug, CORS dimatikan  ^(disarankan untuk dev^)
echo   [2] Web-server, buka di browser apa saja
echo.
choice /c 12 /n /m "  Pilih mode [1/2]: "
if errorlevel 2 goto :server

:chrome
echo.
echo  Menyiapkan dependensi...
pushd "%PROJ%"
call "%FLUTTER%" pub get
echo.
echo  Menjalankan di Chrome ^(profil terpisah, web security off^)...
echo  Hot reload: tekan r  ^|  Hot restart: R  ^|  Keluar: q
echo.
call "%FLUTTER%" run -d chrome ^
  --dart-define=FLEET_BASE_URL=%API_URL% ^
  --web-browser-flag=--disable-web-security ^
  --web-browser-flag=--user-data-dir=%TEMP%\fleettrack-chrome-dev
popd
goto :done

:server
echo.
echo  Menyiapkan dependensi...
pushd "%PROJ%"
call "%FLUTTER%" pub get
echo.
echo  Buka: http://%WEB_HOST%:%WEB_PORT%
echo  Catatan: bila login gagal "No connection", API belum mengizinkan CORS
echo           dari origin ini - pakai mode 1.
echo.
call "%FLUTTER%" run -d web-server ^
  --dart-define=FLEET_BASE_URL=%API_URL% ^
  --web-hostname %WEB_HOST% --web-port %WEB_PORT%
popd
goto :done

:fail
echo.
echo  Perbaiki dulu yang bertanda [X].
pause
exit /b 1

:done
exit /b 0
