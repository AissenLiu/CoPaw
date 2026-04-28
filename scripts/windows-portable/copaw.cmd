@echo off
setlocal

set "ROOT=%~dp0"
set "PYTHON=%ROOT%runtime\python\python.exe"

if not exist "%PYTHON%" (
  echo [qwenpaw] Python runtime not found: %PYTHON%
  exit /b 1
)

set "QWENPAW_WORKING_DIR=%ROOT%working"
set "PLAYWRIGHT_BROWSERS_PATH=%ROOT%runtime\ms-playwright"
"%PYTHON%" -m qwenpaw %*

endlocal
