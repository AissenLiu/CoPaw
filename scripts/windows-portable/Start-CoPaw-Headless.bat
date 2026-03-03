@echo off
setlocal

set "ROOT=%~dp0"
set "PYTHON=%ROOT%runtime\python\python.exe"
set "WORKING_DIR=%ROOT%working"

if not exist "%PYTHON%" (
  echo [copaw] Python runtime not found: %PYTHON%
  exit /b 1
)

set "COPAW_WORKING_DIR=%WORKING_DIR%"
set "COPAW_OPENAPI_DOCS=false"
set "PLAYWRIGHT_BROWSERS_PATH=%ROOT%runtime\ms-playwright"

if not exist "%WORKING_DIR%\config.json" (
  "%PYTHON%" -m copaw init --defaults --accept-security
  if errorlevel 1 (
    exit /b 1
  )
)

"%PYTHON%" -m copaw app --host 127.0.0.1 --port 8088
exit /b %errorlevel%
