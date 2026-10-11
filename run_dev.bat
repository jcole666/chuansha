@echo off
setlocal
REM ============================================================
REM  Chuansha App - Dev mode (hot reload, no APK rebuild)
REM
REM  Instead of "build APK -> copy to phone -> install", this
REM  attaches to a connected device and gives you HOT RELOAD:
REM  edit a .dart file, press r (or just save in some IDEs) and
REM  the change is on screen in about a second.
REM
REM  First run still compiles + installs once (a few minutes).
REM  After that, every change is instant.
REM
REM  Pure ASCII on purpose (see build_apk.bat for why).
REM ============================================================

cd /d "F:\self\chuansha"

REM ------------------------------------------------------------
REM  Proxy detection - identical to build_apk.bat.
REM  Clash rotates its port, so we validate before trusting it.
REM ------------------------------------------------------------
set "ENV_PORT="
for /f "tokens=3 delims=/:" %%a in ("%HTTPS_PROXY%") do if not defined ENV_PORT set "ENV_PORT=%%a"
for /f "tokens=3 delims=/:" %%a in ("%HTTP_PROXY%") do if not defined ENV_PORT set "ENV_PORT=%%a"

set "CANDS="
if defined ENV_PORT set "CANDS=%ENV_PORT%"
set "CANDS=%CANDS% 7890 10881 10879 7891 7897 10808 10809 1080 8889 15417 43024 11996 25230 2080 1081"

REM --- Manual override: uncomment to force a port ---
REM set "PROXY_PORT=7890"

if not defined PROXY_PORT (
  where curl.exe >NUL 2>&1
  if errorlevel 1 (
    echo ERROR: curl.exe not found in C:\Windows\System32.
    echo.
    pause
    exit /b 1
  )
  echo Probing local proxy ports...
  for %%p in (%CANDS%) do call :try_port %%p
)

if not defined PROXY_PORT (
  echo ============================================================
  echo  ERROR: no working local proxy port found.
  echo  Open Clash for Windows and turn ON System Proxy, then retry.
  echo ============================================================
  echo.
  pause
  exit /b 1
)

set "HTTP_PROXY=http://127.0.0.1:%PROXY_PORT%"
set "HTTPS_PROXY=http://127.0.0.1:%PROXY_PORT%"
set "http_proxy=http://127.0.0.1:%PROXY_PORT%"
set "https_proxy=http://127.0.0.1:%PROXY_PORT%"
set "NO_PROXY=localhost,127.0.0.1,::1"
set "no_proxy=localhost,127.0.0.1,::1"
set "JAVA_TOOL_OPTIONS=-Dfile.encoding=GBK -Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=%PROXY_PORT% -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=%PROXY_PORT%"
echo Using local proxy at 127.0.0.1:%PROXY_PORT%

REM --- Toolchain paths (edit if yours differ) ---
set "ANDROID_HOME=F:\develop\android-sdk"
set "FLUTTER_BIN=F:\develop\flutter\bin"
set "PATH=%FLUTTER_BIN%;%ANDROID_HOME%\platform-tools;%PATH%"

REM --- OpenWeatherMap API key (same as build_apk.bat) ---
set "OWM_API_KEY="
if exist ".env.local" set /p OWM_API_KEY=<.env.local
if "%OWM_API_KEY%"=="" (
  echo .env.local not found - weather will be disabled.
  echo Press any key to continue, or Ctrl+C to abort.
  pause >NUL
)

echo.
echo ====== Connected devices ======
flutter devices
echo.
echo ============================================================
echo  If your phone is NOT listed above:
echo    1. On the phone: Settings - About - tap Build number 7x
echo       to unlock Developer options.
echo    2. Developer options - enable USB debugging.
echo    3. Plug in USB, accept the "Allow USB debugging" prompt.
echo    4. Re-run this script.
echo.
echo  Wireless (phone and PC on the same Wi-Fi):
echo    a. Connect USB once, then run:
echo         adb tcpip 5555
echo         adb shell ip route        (note the phone IP)
echo         adb connect PHONE_IP:5555
echo    b. Unplug USB and re-run this script.
echo ============================================================
echo.
echo ====== Starting dev mode ======
echo   r  = hot reload   (apply your code changes, ~1s)
echo   R  = hot restart  (reset app state)
echo   q  = quit
echo ============================================================
echo.

if "%OWM_API_KEY%"=="" (
  flutter run
) else (
  flutter run --dart-define=OWM_API_KEY=%OWM_API_KEY%
)

echo.
echo Dev session ended.
pause
goto :eof

:try_port
if defined PROXY_PORT goto :eof
curl.exe -x http://127.0.0.1:%1 -s -m 6 -o NUL https://pub.dev >NUL 2>&1
if errorlevel 1 goto :eof
set "PROXY_PORT=%1"
echo   OK 127.0.0.1:%1
goto :eof
