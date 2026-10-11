@echo off
setlocal
REM ============================================================
REM  Chuansha App - Release build (fast + much smaller)
REM
REM  The debug APK is several times SLOWER at runtime and roughly
REM  twice the size. For actually using / judging the app on a
REM  phone, build release instead.
REM
REM  Notes:
REM   - No signing key configured, so Flutter signs with the debug
REM     key. That is fine for installing on your own phone; it is
REM     NOT good enough for publishing to a store.
REM   - Release mode strips asserts and debug-only code, so it is
REM     also the honest way to judge performance (the matting
REM     preview, scrolling, image decoding).
REM
REM  Pure ASCII on purpose (see build_apk.bat for why).
REM ============================================================

cd /d "F:\self\chuansha"

REM ------------------------------------------------------------
REM  Proxy detection - identical to build_apk.bat.
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

set "ANDROID_HOME=F:\develop\android-sdk"
set "FLUTTER_BIN=F:\develop\flutter\bin"
set "PATH=%FLUTTER_BIN%;%ANDROID_HOME%\platform-tools;%PATH%"

set "OWM_API_KEY="
if exist ".env.local" set /p OWM_API_KEY=<.env.local
if "%OWM_API_KEY%"=="" (
  set /p OWM_API_KEY=.env.local not found. Enter OWM_API_KEY, or press Enter to skip weather:
)

echo.
echo ====== Building RELEASE (slower to compile, much faster to run) ======
if "%OWM_API_KEY%"=="" (
  flutter build apk --release
) else (
  flutter build apk --release --dart-define=OWM_API_KEY=%OWM_API_KEY%
)

echo.
if errorlevel 1 (
  echo ====== BUILD FAILED ======
  echo See the messages above. Common causes:
  echo   1) Android SDK licenses not accepted
  echo   2) Network issue during pub get
) else (
  echo ====== BUILD SUCCESS ======
  echo APK location:
  echo   F:\self\chuansha\build\app\outputs\flutter-apk\app-release.apk
  echo.
  echo Install on your phone:
  echo   adb install -r build\app\outputs\flutter-apk\app-release.apk
)
echo.
pause
goto :eof

:try_port
if defined PROXY_PORT goto :eof
curl.exe -x http://127.0.0.1:%1 -s -m 6 -o NUL https://pub.dev >NUL 2>&1
if errorlevel 1 goto :eof
set "PROXY_PORT=%1"
echo   OK 127.0.0.1:%1
goto :eof
