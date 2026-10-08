@echo off
setlocal
REM ============================================================
REM  Chuansha App - One-click build script
REM  Builds a debug APK you can install directly on your phone.
REM
REM  IMPORTANT: This file is intentionally pure ASCII.
REM  On Chinese Windows, CMD defaults to code page 936 (GBK).
REM  A UTF-8 .bat with any non-ASCII chars will be garbled on
REM  double-click, splitting commands like echo/set/pause into
REM  fragments and breaking the script. chcp 65001 does NOT fix
REM  this (CMD reads the whole file in the startup code page).
REM  Pure ASCII is the only encoding-independent fix.
REM ============================================================

cd /d "F:\self\chuansha"

REM ------------------------------------------------------------
REM  Network proxy detection.
REM
REM  This machine reaches the outside world only through a local
REM  proxy (Clash for Windows); a direct connection can stall
REM  forever with no error and no timeout.
REM
REM  Why we cannot simply trust the environment:
REM    * Clash rotates its listen port on every launch, so the
REM      HTTPS_PROXY / HTTP_PROXY variables go STALE and may
REM      point at a dead or wrong port.
REM    * Gradle ignores HTTP_PROXY / HTTPS_PROXY; it needs JVM
REM      system properties (-Dhttp.proxyHost / -Dhttps.proxyPort).
REM      Dart / pub DOES read the environment variables.
REM  So we VALIDATE the env port, fall back to probing known
REM  ports, then export the winner BOTH as env vars (for Dart)
REM  and as JVM props (for Gradle).
REM
REM  A port is accepted only if a real HTTPS request through it
REM  succeeds within a timeout. A bare TCP-connect test is NOT
REM  enough: some Clash ports accept TCP but are not HTTP proxies
REM  (they answer curl with error 56) and would still break the
REM  download.
REM ------------------------------------------------------------

REM Step 1: read the (possibly stale) port out of the env vars.
set "ENV_PORT="
for /f "tokens=3 delims=/:" %%a in ("%HTTPS_PROXY%") do if not defined ENV_PORT set "ENV_PORT=%%a"
for /f "tokens=3 delims=/:" %%a in ("%HTTP_PROXY%") do if not defined ENV_PORT set "ENV_PORT=%%a"

REM Step 2: build the candidate list. The env port is tried first,
REM then the ports Clash is known to use here, then common ones.
set "CANDS="
if defined ENV_PORT set "CANDS=%ENV_PORT%"
set "CANDS=%CANDS% 7890 10881 10879 7891 7897 10808 10809 1080 8889 15417 43024 11996 25230 2080 1081"

REM --- Manual override: uncomment the next line to force a port ---
REM set "PROXY_PORT=7890"

if not defined PROXY_PORT (
  where curl.exe >NUL 2>&1
  if errorlevel 1 (
    echo ============================================================
    echo  ERROR: curl.exe not found.
    echo  This script validates the proxy with curl, which ships
    echo  with Windows 10 1803+ in C:\Windows\System32.
    echo ============================================================
    echo.
    pause
    exit /b 1
  )
  echo Probing local proxy ports - a direct connection would hang...
  for %%p in (%CANDS%) do call :try_port %%p
)

if not defined PROXY_PORT (
  echo ============================================================
  echo  ERROR: no working local proxy port found.
  echo  A direct connection WILL hang forever on this network.
  echo.
  echo  What to do:
  echo   1. Open Clash for Windows and turn ON System Proxy.
  echo   2. Re-run this script.
  echo   3. If it still fails, find Clash HTTP/Mixed port and set
  echo      it on the Manual override line near the top.
  echo ============================================================
  echo.
  pause
  exit /b 1
)

REM Step 3: export the winning port for BOTH tool chains.
REM (a) Dart / pub read these environment variables:
set "HTTP_PROXY=http://127.0.0.1:%PROXY_PORT%"
set "HTTPS_PROXY=http://127.0.0.1:%PROXY_PORT%"
set "http_proxy=http://127.0.0.1:%PROXY_PORT%"
set "https_proxy=http://127.0.0.1:%PROXY_PORT%"
set "NO_PROXY=localhost,127.0.0.1,::1"
set "no_proxy=localhost,127.0.0.1,::1"
REM (b) Gradle / the JVM read system properties:
set "JAVA_TOOL_OPTIONS=-Dfile.encoding=GBK -Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=%PROXY_PORT% -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=%PROXY_PORT%"
echo Using local proxy at 127.0.0.1:%PROXY_PORT%

REM --- Your toolchain paths (edit these if yours differ) ---
set "ANDROID_HOME=F:\develop\android-sdk"
set "FLUTTER_BIN=F:\develop\flutter\bin"
set "PATH=%FLUTTER_BIN%;%ANDROID_HOME%\platform-tools;%PATH%"

REM --- OpenWeatherMap API key ---
REM Prefer reading from local .env.local (gitignored, never committed).
REM If absent, prompt. Press Enter to skip - weather/recommend will
REM be disabled but everything else still works.
set "OWM_API_KEY="
if exist ".env.local" set /p OWM_API_KEY=<.env.local
if "%OWM_API_KEY%"=="" set /p OWM_API_KEY=.env.local not found. Enter OWM_API_KEY, or press Enter to skip weather:

echo.
echo ====== Building (first run is slow: downloads deps + compiles) ======
if "%OWM_API_KEY%"=="" (
  flutter build apk --debug
) else (
  flutter build apk --debug --dart-define=OWM_API_KEY=%OWM_API_KEY%
)

echo.
if errorlevel 1 (
  echo ====== BUILD FAILED ======
  echo Common causes:
  echo   1) Android SDK licenses not accepted - run: sdkmanager --licenses
  echo      or: flutter doctor --android-licenses
  echo   2) Network issue during pub get - check network and retry
  echo   3) flutter/android not found - check ANDROID_HOME / FLUTTER_BIN above
) else (
  echo ====== BUILD SUCCESS ======
  echo APK location:
  echo   F:\self\chuansha\build\app\outputs\flutter-apk\app-debug.apk
  echo.
  echo Install on your phone - USB cable connected, USB debugging ON:
  echo   A) adb install -r build\app\outputs\flutter-apk\app-debug.apk
  echo   B) Copy app-debug.apk to phone, tap to install
  echo      enable "Install unknown apps" for your file manager
  echo   C) flutter install --debug
)
echo.
pause
goto :eof

REM ------------------------------------------------------------
REM  :try_port <port> - accept the first port that really works.
REM  Uses a real HTTPS request through the proxy with a timeout,
REM  so a dead port (refused) and a non-proxy port (curl err 56)
REM  are both rejected instead of being trusted blindly.
REM ------------------------------------------------------------
:try_port
if defined PROXY_PORT goto :eof
curl.exe -x http://127.0.0.1:%1 -s -m 6 -o NUL https://pub.dev >NUL 2>&1
if errorlevel 1 (
  echo   -- 127.0.0.1:%1
  goto :eof
)
set "PROXY_PORT=%1"
echo   OK 127.0.0.1:%1
goto :eof
