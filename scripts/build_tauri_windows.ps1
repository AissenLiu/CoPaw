param(
    [string]$OutputRoot = "",
    [switch]$CleanOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Info {
    param([string]$Message)
    Write-Host "[tauri-build] $Message" -ForegroundColor Cyan
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
    $OutputRoot = Join-Path $RepoRoot "dist\desktop-windows"
}
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)

if ($CleanOutput -and (Test-Path $OutputRoot)) {
    Remove-Item -Path $OutputRoot -Recurse -Force
}
New-Item -Path $OutputRoot -ItemType Directory -Force | Out-Null

$PortableOutput = Join-Path $OutputRoot "portable"
$PortableScript = Join-Path $ScriptDir "build_portable_windows.ps1"

Write-Info "Building portable backend payload..."
& $PortableScript -OutputRoot $PortableOutput -CleanOutput -SkipZip

$PortableRoot = Join-Path $PortableOutput "CoPaw-Windows-Portable"
if (-not (Test-Path $PortableRoot)) {
    throw "Portable backend folder not found: $PortableRoot"
}

$DesktopDir = Join-Path $RepoRoot "desktop-tauri"
Ensure-Command "npm"
Ensure-Command "python"

Write-Info "Building Tauri desktop binary..."
Push-Location $DesktopDir
try {
    npm install
    npm run tauri:build
}
finally {
    Pop-Location
}

$DesktopExe = Join-Path $DesktopDir "src-tauri/target/release/copaw-desktop.exe"
if (-not (Test-Path $DesktopExe)) {
    throw "Desktop executable not found: $DesktopExe"
}

$BundleDirName = "CoPaw-Desktop-Windows"
$BundleRoot = Join-Path $OutputRoot $BundleDirName
if (Test-Path $BundleRoot) {
    Remove-Item -Path $BundleRoot -Recurse -Force
}
New-Item -Path $BundleRoot -ItemType Directory -Force | Out-Null

Copy-Item -Path $DesktopExe -Destination (Join-Path $BundleRoot "CoPaw-Desktop.exe") -Force
Copy-Item -Path $PortableRoot -Destination (Join-Path $BundleRoot "copaw-portable") -Recurse -Force

$Launcher = @'
@echo off
setlocal
set "ROOT=%~dp0"
start "" "%ROOT%CoPaw-Desktop.exe"
endlocal
'@
$Launcher | Set-Content -Path (Join-Path $BundleRoot "Start-CoPaw-Desktop.bat") -Encoding ASCII

$env:COPAW_REPO_ROOT = $RepoRoot
$Version = (& (Get-Command python).Source -c "import os,re,pathlib; p = pathlib.Path(os.environ['COPAW_REPO_ROOT']) / 'src' / 'copaw' / '__version__.py'; text = p.read_text(encoding='utf-8'); print(re.search(r'\"([^\"]+)\"', text).group(1))" 2>$null)
$Version = ($Version | Out-String).Trim()
if (-not $Version) {
    $Version = "unknown"
}

$ZipPath = Join-Path $OutputRoot "CoPaw-Desktop-Windows-$Version.zip"
if (Test-Path $ZipPath) {
    Remove-Item -Path $ZipPath -Force
}

Write-Info "Creating desktop zip: $ZipPath"
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

Write-Info "Desktop package ready: $ZipPath"
Write-Info "SHA256 file: $HashPath"
