import { invoke } from "@tauri-apps/api/core";
import "./styles.css";

type EnsureBackendResult = {
  url: string;
  already_running: boolean;
  started: boolean;
};

const statusEl = document.querySelector<HTMLParagraphElement>("#status");

function setStatus(text: string): void {
  if (statusEl) {
    statusEl.textContent = text;
  }
}

async function bootstrap(): Promise<void> {
  try {
    setStatus("Checking backend status...");
    const result = await invoke<EnsureBackendResult>("ensure_backend");

    if (result.already_running) {
      setStatus("Backend already running. Opening console...");
    } else if (result.started) {
      setStatus("Backend started. Waiting for readiness...");
    } else {
      setStatus("Connecting to backend...");
    }
    setStatus("Opening console...");
    window.location.replace(result.url);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    setStatus(`Failed to start CoPaw: ${message}`);
  }
}

bootstrap();
