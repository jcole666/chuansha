@echo off
REM ============================================================
REM  Chuansha App - Verbose build script (logs to build_log.txt)
REM  Same as build_apk.bat but adds --verbose and writes the full
REM  flutter/gradle output to build_log.txt so we can diagnose
REM  where a build hangs. Pure ASCII on purpose (see build_apk.bat).
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
set "OWM_API_KEY="
if exist .env.local (
  set /p OWM_API_KEY=<.env.local
)
if "%OWM_API_KEY%"=="" (
  set /p OWM_API_KEY=.env.local not found. Enter OWM_API_KEY, or press Enter to skip weather:
)

cd /d F:\self\chuansha

echo.
echo ====== Verbose build started ======
echo Full log is being written to:
echo   F:\self\chuansha\build_log.txt
echo (open it in Notepad to watch progress)
echo.

if "%OWM_API_KEY%"=="" (
  flutter build apk --debug --verbose > build_log.txt 2>&1
) else (
  flutter build apk --debug --verbose --dart-define=OWM_API_KEY=%OWM_API_KEY% > build_log.txt 2>&1
)

echo.
if errorlevel 1 (
  echo ====== BUILD FAILED ======
  echo See build_log.txt (last lines) for the exact error.
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
