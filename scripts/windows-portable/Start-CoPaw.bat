@echo off
setlocal

set "ROOT=%~dp0"
set "PYTHON=%ROOT%runtime\python\python.exe"
set "WORKING_DIR=%ROOT%working"

if not exist "%PYTHON%" (
  echo [qwenpaw] Python runtime not found: %PYTHON%
  pause
  exit /b 1
)

set "QWENPAW_WORKING_DIR=%WORKING_DIR%"
set "QWENPAW_OPENAPI_DOCS=false"
set "PLAYWRIGHT_BROWSERS_PATH=%ROOT%runtime\ms-playwright"

if not exist "%WORKING_DIR%\config.json" (
  echo [qwenpaw] First run initialization...
  "%PYTHON%" -m qwenpaw init --defaults --accept-security
  if errorlevel 1 (
    echo [qwenpaw] Initialization failed.
    pause
    exit /b 1
  )
)

echo [qwenpaw] Starting server on http://127.0.0.1:8088 ...
start "QwenPaw Server" "%PYTHON%" -m qwenpaw app --host 127.0.0.1 --port 8088

rem Give the server a short head start before opening browser.
timeout /t 2 /nobreak >nul
start "" "http://127.0.0.1:8088/"

echo [qwenpaw] QwenPaw started. Use Stop-CoPaw.bat to stop the server.
endlocal
