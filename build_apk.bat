@echo off
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
setlocal

REM --- Network proxy (this machine routes outbound via a local proxy) ---
REM Gradle does NOT read HTTP_PROXY/HTTPS_PROXY env vars; pass the proxy as
REM JVM system props so the Gradle daemon can download dependencies.
REM Clash for Windows randomly rotates its system-proxy port on each
REM launch, so auto-detect the current port from HTTPS_PROXY/HTTP_PROXY
REM instead of hardcoding it (15417 -> 43024 broke a previous build).
set "PROXY_PORT="
for /f "tokens=3 delims=/:" %%a in ("%HTTPS_PROXY%") do set "PROXY_PORT=%%a"
if "%PROXY_PORT%"=="" for /f "tokens=3 delims=/:" %%a in ("%HTTP_PROXY%") do set "PROXY_PORT=%%a"
if not "%PROXY_PORT%"=="" (
  set JAVA_TOOL_OPTIONS=-Dfile.encoding=GBK -Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=%PROXY_PORT% -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=%PROXY_PORT%
  echo Using local proxy at 127.0.0.1:%PROXY_PORT%
) else (
  echo WARNING: no proxy port detected. Gradle will try direct, may hang/fail.
)

REM --- Your toolchain paths (edit these if yours differ) ---
set ANDROID_HOME=F:\develop\android-sdk
set FLUTTER_BIN=F:\develop\flutter\bin
set PATH=%FLUTTER_BIN%;%ANDROID_HOME%\platform-tools;%PATH%

REM --- OpenWeatherMap API key ---
REM Prefer reading from local .env.local (gitignored, never committed).
REM If absent, prompt. Press Enter to skip - weather/recommend will
REM be disabled but everything else still works.
set "OWM_API_KEY="
if exist .env.local (
  set /p OWM_API_KEY=<.env.local
)
if "%OWM_API_KEY%"=="" (
  set /p OWM_API_KEY=.env.local not found. Enter OWM_API_KEY, or press Enter to skip weather:
)

cd /d F:\self\chuansha

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
