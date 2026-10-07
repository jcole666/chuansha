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
REM launch, so auto-detect the current port instead of hardcoding it.
REM Step 1: parse it from HTTPS_PROXY / HTTP_PROXY.
REM Step 2: if the env vars are empty (Clash was restarted / system-proxy
REM         toggled off), fall back to probing common local proxy ports with
REM         PowerShell, so we never silently fall through to a direct
REM         connection (which hangs forever on this network).
set "PROXY_PORT="
for /f "tokens=3 delims=/:" %%a in ("%HTTPS_PROXY%") do set "PROXY_PORT=%%a"
if "%PROXY_PORT%"=="" for /f "tokens=3 delims=/:" %%a in ("%HTTP_PROXY%") do set "PROXY_PORT=%%a"

if "%PROXY_PORT%"=="" (
  echo Environment proxy vars empty - probing common local proxy ports...
  for /f %%p in ('powershell -NoProfile -Command "$ports=@(25230,15417,7890,7891,7897,10808,10809,1080,8889,43024,11996); foreach($p in $ports){$c=New-Object Net.Sockets.TcpClient; try{$c.Connect('127.0.0.1',$p); if($c.Connected){Write-Output $p; $c.Close(); break}}catch{}} " ') do set "PROXY_PORT=%%p"
)

if not "%PROXY_PORT%"=="" (
  set JAVA_TOOL_OPTIONS=-Dfile.encoding=GBK -Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=%PROXY_PORT% -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=%PROXY_PORT%
  echo Using local proxy at 127.0.0.1:%PROXY_PORT%
) else (
  echo ============================================================
  echo  ERROR: no local proxy port found.
  echo  A direct connection WILL hang forever on this network.
  echo  1. Open Clash for Windows and turn ON "System Proxy".
  echo  2. Re-run this script.
  echo ============================================================
  echo.
  pause
  exit /b 1
)
REM Manual override if auto-detect ever picks the wrong port:
REM set JAVA_TOOL_OPTIONS=-Dfile.encoding=GBK -Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=7890 -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=7890

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
