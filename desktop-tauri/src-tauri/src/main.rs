#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use serde::Serialize;
use std::net::{SocketAddr, TcpStream};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::Mutex;
use std::thread;
use std::time::{Duration, Instant};
use tauri::{AppHandle, Manager, State};
use url::Url;

#[derive(Default)]
struct BackendState {
    child: Mutex<Option<Child>>,
}

#[derive(Serialize)]
struct EnsureBackendResult {
    url: String,
    already_running: bool,
    started: bool,
}

fn backend_url() -> String {
    "http://127.0.0.1:8088".to_string()
}

fn backend_socket_addr() -> SocketAddr {
    "127.0.0.1:8088".parse().expect("invalid backend socket addr")
}

fn is_backend_running() -> bool {
    TcpStream::connect_timeout(&backend_socket_addr(), Duration::from_millis(350)).is_ok()
}

fn wait_for_backend_ready(timeout: Duration) -> bool {
    let start = Instant::now();
    while start.elapsed() < timeout {
        if is_backend_running() {
            return true;
        }
        thread::sleep(Duration::from_millis(500));
    }
    false
}

fn navigate_main_window(app: &AppHandle, target_url: &str) -> Result<(), String> {
    let window = app
        .get_webview_window("main")
        .ok_or_else(|| "Main window not found".to_string())?;
    let parsed = Url::parse(target_url).map_err(|err| format!("Invalid URL: {err}"))?;
    window
        .navigate(parsed)
        .map_err(|err| format!("Failed to navigate main window: {err}"))?;
    Ok(())
}

fn infer_playwright_browsers_path(python: &Path) -> Option<PathBuf> {
    let runtime_dir = python.parent()?.parent()?;
    let runtime_name = runtime_dir.file_name()?.to_string_lossy().to_ascii_lowercase();
    if runtime_name != "runtime" {
        return None;
    }
    Some(runtime_dir.join("ms-playwright"))
}

fn dedup_paths(paths: Vec<PathBuf>) -> Vec<PathBuf> {
    let mut out = Vec::new();
    for path in paths {
        if !out.iter().any(|p| p == &path) {
            out.push(path);
        }
    }
    out
}

fn candidate_portable_roots(app: &AppHandle) -> Vec<PathBuf> {
    let mut roots = Vec::new();

    if let Ok(root) = std::env::var("COPAW_PORTABLE_DIR") {
        roots.push(PathBuf::from(root));
    }

    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            roots.push(dir.join("copaw-portable"));
        }
    }

    if let Ok(resource_dir) = app.path().resource_dir() {
        roots.push(resource_dir.join("copaw-portable"));
    }

    if let Ok(cwd) = std::env::current_dir() {
        roots.push(cwd.join("copaw-portable"));
    }

    dedup_paths(roots)
}

fn resolve_python_and_working(app: &AppHandle) -> Result<(PathBuf, PathBuf), String> {
    if let Ok(explicit_python) = std::env::var("COPAW_PYTHON") {
        let python = PathBuf::from(explicit_python);
        if python.exists() {
            let working = std::env::var("COPAW_WORKING_DIR")
                .map(PathBuf::from)
                .ok()
                .unwrap_or_else(|| {
                    app.path()
                        .app_data_dir()
                        .unwrap_or_else(|_| PathBuf::from("."))
                        .join("copaw-working")
                });
            return Ok((python, working));
        }
    }

    for root in candidate_portable_roots(app) {
        let python = root.join("runtime").join("python").join("python.exe");
        if python.exists() {
            let working = root.join("working");
            return Ok((python, working));
        }
    }

    if let Ok(system_python) = std::env::var("PYTHON") {
        let python = PathBuf::from(system_python);
        if python.exists() {
            let working = std::env::var("COPAW_WORKING_DIR")
                .map(PathBuf::from)
                .ok()
                .unwrap_or_else(|| {
                    app.path()
                        .app_data_dir()
                        .unwrap_or_else(|_| PathBuf::from("."))
                        .join("copaw-working")
                });
            return Ok((python, working));
        }
    }

    Ok((
        PathBuf::from("python"),
        std::env::var("COPAW_WORKING_DIR")
            .map(PathBuf::from)
            .ok()
            .unwrap_or_else(|| {
                app.path()
                    .app_data_dir()
                    .unwrap_or_else(|_| PathBuf::from("."))
                    .join("copaw-working")
            }),
    ))
}

fn run_copaw_init(python: &Path, working_dir: &Path) -> Result<(), String> {
    std::fs::create_dir_all(working_dir)
        .map_err(|err| format!("Failed to create working dir: {err}"))?;

    if working_dir.join("config.json").exists() {
        return Ok(());
    }

    let status = Command::new(python)
        .args([
            "-m",
            "copaw",
            "init",
            "--defaults",
            "--accept-security",
        ])
        .env("COPAW_WORKING_DIR", working_dir)
        .status()
        .map_err(|err| format!("Failed to run copaw init: {err}"))?;

    if status.success() {
        Ok(())
    } else {
        Err(format!("copaw init exited with status {status}"))
    }
}

#[tauri::command]
fn ensure_backend(
    app: AppHandle,
    state: State<'_, BackendState>,
) -> Result<EnsureBackendResult, String> {
    let url = backend_url();
    let mut already_running = false;
    let mut started = false;

    if is_backend_running() {
        already_running = true;
        navigate_main_window(&app, &url)?;
        return Ok(EnsureBackendResult {
            url,
            already_running,
            started,
        });
    }

    {
        let mut guard = state
            .child
            .lock()
            .map_err(|_| "Backend state lock poisoned".to_string())?;
        if let Some(child) = guard.as_mut() {
            match child
                .try_wait()
                .map_err(|err| format!("Failed to inspect backend process: {err}"))?
            {
                None => {
                    if !wait_for_backend_ready(Duration::from_secs(30)) {
                        return Err("Backend process started but did not become ready in time.".to_string());
                    }
                    started = true;
                    navigate_main_window(&app, &url)?;
                    return Ok(EnsureBackendResult {
                        url,
                        already_running,
                        started,
                    });
                }
                Some(_) => {
                    *guard = None;
                }
            }
        }
    }

    let (python, working_dir) = resolve_python_and_working(&app)?;
    run_copaw_init(&python, &working_dir)?;

    let mut backend_cmd = Command::new(&python);
    backend_cmd
        .args([
            "-m",
            "copaw",
            "app",
            "--host",
            "127.0.0.1",
            "--port",
            "8088",
        ])
        .env("COPAW_WORKING_DIR", &working_dir)
        .env("COPAW_OPENAPI_DOCS", "false");

    if std::env::var_os("PLAYWRIGHT_BROWSERS_PATH").is_none() {
        if let Some(playwright_browsers_path) = infer_playwright_browsers_path(&python) {
            if playwright_browsers_path.exists() {
                backend_cmd.env("PLAYWRIGHT_BROWSERS_PATH", playwright_browsers_path);
            }
        }
    }

    let child = backend_cmd
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|err| format!("Failed to start backend: {err}"))?;

    let mut guard = state
        .child
        .lock()
        .map_err(|_| "Backend state lock poisoned".to_string())?;
    *guard = Some(child);

    if !wait_for_backend_ready(Duration::from_secs(30)) {
        if let Some(mut child) = guard.take() {
            let _ = child.kill();
        }
        return Err("Backend startup timed out (30s).".to_string());
    }
    started = true;
    navigate_main_window(&app, &url)?;

    Ok(EnsureBackendResult {
        url,
        already_running,
        started,
    })
}

#[tauri::command]
fn stop_backend(state: State<'_, BackendState>) -> Result<(), String> {
    let mut guard = state
        .child
        .lock()
        .map_err(|_| "Backend state lock poisoned".to_string())?;

    if let Some(mut child) = guard.take() {
        child
            .kill()
            .map_err(|err| format!("Failed to stop backend: {err}"))?;
    }

    Ok(())
}

fn main() {
    tauri::Builder::default()
        .manage(BackendState::default())
        .invoke_handler(tauri::generate_handler![ensure_backend, stop_backend])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
