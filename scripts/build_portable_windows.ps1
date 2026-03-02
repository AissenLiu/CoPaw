param(
    [string]$OutputRoot = "",
    [string]$PythonExe = "",
    [switch]$SkipConsoleBuild,
    [switch]$SkipZip,
    [switch]$CleanOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Info {
    param([string]$Message)
    Write-Host "[portable] $Message" -ForegroundColor Green
}

function Ensure-Command {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $Name"
    }
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir "..")).Path

if (-not $OutputRoot) {
    $OutputRoot = Join-Path $RepoRoot "dist\portable-windows"
}
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)

if (-not $PythonExe) {
    Ensure-Command "python"
    $PythonExe = (Get-Command "python").Source
}
$PythonExe = (Resolve-Path $PythonExe).Path

if ($CleanOutput -and (Test-Path $OutputRoot)) {
    Remove-Item -Path $OutputRoot -Recurse -Force
}
New-Item -Path $OutputRoot -ItemType Directory -Force | Out-Null

$env:COPAW_REPO_ROOT = $RepoRoot
$Version = (& $PythonExe -c "import os,re,pathlib; p = pathlib.Path(os.environ['COPAW_REPO_ROOT']) / 'src' / 'copaw' / '__version__.py'; text = p.read_text(encoding='utf-8'); print(re.search(r'\"([^\"]+)\"', text).group(1))" 2>$null)
if (-not $Version) {
    throw "Failed to detect CoPaw version."
}
$Version = $Version.Trim()

$ConsoleDir = Join-Path $RepoRoot "console"
$ConsoleDistDir = Join-Path $ConsoleDir "dist"
$ConsolePackageDir = Join-Path $RepoRoot "src/copaw/console"

if (-not $SkipConsoleBuild) {
    Ensure-Command "npm"
    Write-Info "Building console frontend..."
    Push-Location $ConsoleDir
    try {
        npm ci
        npm run build
    }
    finally {
        Pop-Location
    }
}

if (-not (Test-Path (Join-Path $ConsoleDistDir "index.html"))) {
    throw "Console dist not found at $ConsoleDistDir. Run with npm build first or remove -SkipConsoleBuild."
}

Write-Info "Syncing console assets into Python package..."
New-Item -Path $ConsolePackageDir -ItemType Directory -Force | Out-Null
Get-ChildItem -Path $ConsolePackageDir -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
Copy-Item -Path (Join-Path $ConsoleDistDir "*") -Destination $ConsolePackageDir -Recurse -Force

$WheelOutDir = Join-Path $OutputRoot "wheel"
New-Item -Path $WheelOutDir -ItemType Directory -Force | Out-Null

Write-Info "Building wheel..."
Push-Location $RepoRoot
try {
    & $PythonExe -m pip install --upgrade pip build
    & $PythonExe -m build --wheel --outdir $WheelOutDir .
}
finally {
    Pop-Location
}

$Wheel = Get-ChildItem -Path $WheelOutDir -Filter "copaw-*.whl" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $Wheel) {
    throw "No wheel found under $WheelOutDir"
}

$BundleDirName = "CoPaw-Windows-Portable"
$BundleRoot = Join-Path $OutputRoot $BundleDirName
$RuntimePythonRoot = Join-Path $BundleRoot "runtime/python"
$WorkingDir = Join-Path $BundleRoot "working"

if (Test-Path $BundleRoot) {
    Remove-Item -Path $BundleRoot -Recurse -Force
}
New-Item -Path $BundleRoot -ItemType Directory -Force | Out-Null
New-Item -Path $WorkingDir -ItemType Directory -Force | Out-Null
New-Item -Path $RuntimePythonRoot -ItemType Directory -Force | Out-Null

$PythonHome = Split-Path -Parent $PythonExe
Write-Info "Copying Python runtime from $PythonHome"
Copy-Item -Path (Join-Path $PythonHome "*") -Destination $RuntimePythonRoot -Recurse -Force

$RuntimePythonExe = Join-Path $RuntimePythonRoot "python.exe"
if (-not (Test-Path $RuntimePythonExe)) {
    throw "Runtime python.exe not found after copy: $RuntimePythonExe"
}

Write-Info "Installing CoPaw and dependencies into portable runtime..."
& $RuntimePythonExe -m pip install --upgrade pip setuptools wheel
& $RuntimePythonExe -m pip install --no-cache-dir $Wheel.FullName

Write-Info "Initializing default working directory..."
$env:COPAW_WORKING_DIR = $WorkingDir
& $RuntimePythonExe -m copaw init --defaults --accept-security

Write-Info "Applying offline-safe default config..."
& $RuntimePythonExe -c @'
import json
import os
from pathlib import Path

root = Path(os.environ["COPAW_WORKING_DIR"])
config_path = root / "config.json"
if config_path.exists():
    data = json.loads(config_path.read_text(encoding="utf-8"))
else:
    data = {}

mcp = data.setdefault("mcp", {})
clients = mcp.setdefault("clients", {})
tavily = clients.setdefault("tavily_search", {})
tavily["enabled"] = False

config_path.write_text(
    json.dumps(data, ensure_ascii=False, indent=2),
    encoding="utf-8",
)
'@

$TemplateDir = Join-Path $RepoRoot "scripts/windows-portable"
Write-Info "Copying Windows launcher scripts..."
Copy-Item -Path (Join-Path $TemplateDir "Start-CoPaw.bat") -Destination (Join-Path $BundleRoot "Start-CoPaw.bat") -Force
Copy-Item -Path (Join-Path $TemplateDir "Start-CoPaw-Headless.bat") -Destination (Join-Path $BundleRoot "Start-CoPaw-Headless.bat") -Force
Copy-Item -Path (Join-Path $TemplateDir "Stop-CoPaw.bat") -Destination (Join-Path $BundleRoot "Stop-CoPaw.bat") -Force
Copy-Item -Path (Join-Path $TemplateDir "copaw.cmd") -Destination (Join-Path $BundleRoot "copaw.cmd") -Force

$BuildInfo = @(
    "CoPaw Version: $Version",
    "Build Time (UTC): $(Get-Date -AsUTC -Format 'yyyy-MM-dd HH:mm:ss')",
    "Runtime Python: $($RuntimePythonExe)",
    "Wheel: $($Wheel.Name)"
)
$BuildInfo | Set-Content -Path (Join-Path $BundleRoot "BUILD-INFO.txt") -Encoding UTF8

if (-not $SkipZip) {
    $ZipPath = Join-Path $OutputRoot "CoPaw-Windows-Portable-$Version.zip"
    if (Test-Path $ZipPath) {
        Remove-Item -Path $ZipPath -Force
    }

    Write-Info "Creating zip archive: $ZipPath"
    Push-Location $OutputRoot
    try {
        Compress-Archive -Path $BundleDirName -DestinationPath $ZipPath
    }
    finally {
        Pop-Location
    }

    $HashPath = "$ZipPath.sha256"
    $Hash = (Get-FileHash -Path $ZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    "$Hash  $(Split-Path $ZipPath -Leaf)" | Set-Content -Path $HashPath -Encoding ASCII

    Write-Info "Portable zip ready: $ZipPath"
    Write-Info "SHA256 file: $HashPath"
}
else {
    Write-Info "Portable directory ready: $BundleRoot"
}

Write-Info "Done."
