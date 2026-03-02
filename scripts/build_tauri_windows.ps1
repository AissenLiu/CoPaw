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
Ensure-Command "cargo"

$IconPath = Join-Path $DesktopDir "src-tauri/icons/icon.ico"
if (-not (Test-Path $IconPath)) {
    Write-Info "Tauri icon not found, generating fallback icon..."
    $env:COPAW_ICON_PATH = $IconPath
    $IconGenCode = @'
import os
import struct
from pathlib import Path

out = Path(os.environ["COPAW_ICON_PATH"])
out.parent.mkdir(parents=True, exist_ok=True)

w = h = 32
header = struct.pack("<HHH", 0, 1, 1)
dib_header = struct.pack(
    "<IIIHHIIIIII",
    40,
    w,
    h * 2,
    1,
    32,
    0,
    w * h * 4,
    0,
    0,
    0,
    0,
)
pixel = bytes((0xD2, 0x7A, 0x16, 0xFF))
xor_bitmap = pixel * (w * h)
and_row_bytes = ((w + 31) // 32) * 4
and_mask = bytes(and_row_bytes * h)
image_data = dib_header + xor_bitmap + and_mask
entry = struct.pack(
    "<BBBBHHII",
    w,
    h,
    0,
    0,
    1,
    32,
    len(image_data),
    6 + 16,
)
out.write_bytes(header + entry + image_data)
'@
    & (Get-Command python).Source -c $IconGenCode
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $IconPath)) {
        throw "Failed to generate fallback icon: $IconPath"
    }
}

Write-Info "Building Tauri desktop binary..."
Push-Location $DesktopDir
try {
    npm install
    if ($LASTEXITCODE -ne 0) {
        throw "npm install failed with exit code $LASTEXITCODE"
    }
    npm run build
    if ($LASTEXITCODE -ne 0) {
        throw "npm run build failed with exit code $LASTEXITCODE"
    }
    cargo build --manifest-path src-tauri/Cargo.toml --release --bin copaw-desktop
    if ($LASTEXITCODE -ne 0) {
        throw "cargo build failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

$ExeCandidates = @(
    (Join-Path $DesktopDir "src-tauri/target/release/copaw-desktop.exe"),
    (Join-Path $DesktopDir "src-tauri/target/release/copaw_desktop.exe"),
    (Join-Path $DesktopDir "target/release/copaw-desktop.exe"),
    (Join-Path $DesktopDir "target/release/copaw_desktop.exe")
)

$DesktopExe = $null
foreach ($candidate in $ExeCandidates) {
    if (Test-Path $candidate) {
        $DesktopExe = $candidate
        break
    }
}

if (-not $DesktopExe) {
    $foundExe = @(
        Get-ChildItem -Path (Join-Path $DesktopDir "src-tauri/target/release") -Filter "*.exe" -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName
        Get-ChildItem -Path (Join-Path $DesktopDir "target/release") -Filter "*.exe" -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName
    ) | Where-Object { $_ } | Sort-Object -Unique

    if ($foundExe.Count -gt 0) {
        throw "Desktop executable not found in expected paths. Found exe files: $($foundExe -join '; ')"
    }
    throw "Desktop executable not found. Checked: $($ExeCandidates -join '; ')"
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
$VersionCode = @'
import os
import pathlib
import re

p = pathlib.Path(os.environ["COPAW_REPO_ROOT"]) / "src" / "copaw" / "__version__.py"
text = p.read_text(encoding="utf-8")
m = re.search(r'"([^"]+)"', text)
print(m.group(1) if m else "")
'@
$Version = (& (Get-Command python).Source -c $VersionCode 2>$null)
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
