@echo off
setlocal

set "ROOT=%~dp0"
set "PYTHON=%ROOT%runtime\python\python.exe"
set "WORKING_DIR=%ROOT%working"

if not exist "%PYTHON%" (
  echo [copaw] Python runtime not found: %PYTHON%
  pause
  exit /b 1
)

set "COPAW_WORKING_DIR=%WORKING_DIR%"
set "COPAW_OPENAPI_DOCS=false"

if not exist "%WORKING_DIR%\config.json" (
  echo [copaw] First run initialization...
  "%PYTHON%" -m copaw init --defaults --accept-security
  if errorlevel 1 (
    echo [copaw] Initialization failed.
    pause
    exit /b 1
  )
)

echo [copaw] Starting server on http://127.0.0.1:8088 ...
start "CoPaw Server" "%PYTHON%" -m copaw app --host 127.0.0.1 --port 8088

rem Give the server a short head start before opening browser.
timeout /t 2 /nobreak >nul
start "" "http://127.0.0.1:8088/"

echo [copaw] CoPaw started. Use Stop-CoPaw.bat to stop the server.
endlocal
