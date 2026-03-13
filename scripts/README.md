# Scripts

Run from **repo root**.

## Build wheel (with latest console)

```bash
bash scripts/wheel_build.sh
```

- Builds the console frontend (`console/`), copies `console/dist` to `src/copaw/console/dist`, then builds the wheel. Output: `dist/*.whl`.

## Build website

```bash
bash scripts/website_build.sh
```

- Installs dependencies (pnpm or npm) and runs the Vite build. Output: `website/dist/`.

## Build Docker image

```bash
bash scripts/docker_build.sh [IMAGE_TAG] [EXTRA_ARGS...]
```

- Default tag: `copaw:latest`. Uses `deploy/Dockerfile` (multi-stage: builds console then Python app).
- Example: `bash scripts/docker_build.sh myreg/copaw:v1 --no-cache`.

## Run Test

```bash
# Run all tests
python scripts/run_tests.py

# Run all unit tests
python scripts/run_tests.py -u

# Run unit tests for a specific module
python scripts/run_tests.py -u providers

# Run integration tests
python scripts/run_tests.py -i

# Run all tests and generate a coverage report
python scripts/run_tests.py -a -c

# Run tests in parallel (requires pytest-xdist)
python scripts/run_tests.py -p

# Show help
python scripts/run_tests.py -h
```

## Build Windows portable package (no dependency install on target)

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build_portable_windows.ps1
```

- Produces `dist/portable-windows/CoPaw-Windows-Portable-<version>.zip`.
- Target Windows machines only need unzip + double-click `Start-CoPaw.bat`.
- Includes Python runtime, CoPaw package, dependencies, launcher scripts, built-in skills Python deps, and Playwright Chromium browser binaries.
- Optional flags:
  - `-SkipSkillDeps`: skip preinstalling built-in skills Python deps.
  - `-SkipPlaywrightBrowserDownload`: skip pre-downloading Chromium.
- Some skills still require external tools from system `PATH` (for example LibreOffice, Poppler, Himalaya CLI). See package file: `EXTERNAL-DEPENDENCIES.txt`.

## Build Windows Tauri desktop package

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build_tauri_windows.ps1
```

- Produces `dist/desktop-windows/CoPaw-Desktop-Windows-<version>.zip`.
- Bundle includes:
  - `CoPaw-Desktop.exe` (Tauri desktop shell)
  - `copaw-portable/` (portable backend runtime payload)
  - `Start-CoPaw-Desktop.bat` (desktop launcher)
