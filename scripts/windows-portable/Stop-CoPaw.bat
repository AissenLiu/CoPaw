@echo off
setlocal EnableDelayedExpansion

set "PORT=8088"
set "FOUND=0"

for /f "tokens=5" %%P in ('netstat -ano ^| findstr /R /C:":%PORT% .*LISTENING"') do (
  set "FOUND=1"
  taskkill /PID %%P /F >nul 2>&1
)

if "!FOUND!"=="0" (
  echo [copaw] No process is listening on port %PORT%.
) else (
  echo [copaw] Stopped process(es) on port %PORT%.
)

endlocal
