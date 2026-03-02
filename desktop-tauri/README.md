# CoPaw Desktop (Tauri)

This directory contains a lightweight Tauri desktop shell for CoPaw.

## What it does

- Starts (or reuses) a local CoPaw backend at `http://127.0.0.1:8088`.
- Opens the built-in Console UI in a desktop window.
- Can run with:
  - bundled portable backend (`copaw-portable/` next to the desktop exe), or
  - a custom Python path via `COPAW_PYTHON`.

## Local development

```bash
cd desktop-tauri
npm install
npm run tauri:dev
```

## Build desktop binary (no installer)

```bash
cd desktop-tauri
npm install
npm run build
cargo build --manifest-path src-tauri/Cargo.toml --release
```

The output binary is under `desktop-tauri/src-tauri/target/release/`.

## Environment variables

- `COPAW_PORTABLE_DIR`: path to portable backend root.
- `COPAW_PYTHON`: explicit python executable path (fallback mode).
- `COPAW_WORKING_DIR`: override CoPaw working directory.
