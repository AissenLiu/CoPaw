@echo off
setlocal

set "ROOT=%~dp0"
set "PYTHON=%ROOT%runtime\python\python.exe"

if not exist "%PYTHON%" (
  echo [copaw] Python runtime not found: %PYTHON%
  exit /b 1
)

set "COPAW_WORKING_DIR=%ROOT%working"
"%PYTHON%" -m copaw %*

endlocal
