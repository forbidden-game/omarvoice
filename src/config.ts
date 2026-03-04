import { join } from "node:path";

export interface AppConfig {
  socketPath: string;
  endpoint: string;
  apiKey: string | undefined;
  tmpDir: string;
  recordCommand: string;
  recordArgs: string[];
  clipboardCommand: string;
  notifyCommand: string;
  audioField: string;
  textField: string;
  model: string | undefined;
  language: string | undefined;
  requestTimeoutMs: number;
}

const DEFAULT_RECORD_ARGS = ["--rate", "16000", "--channels", "1"];

export function loadConfig(env: NodeJS.ProcessEnv = process.env): AppConfig {
  const runtimeDir = env.XDG_RUNTIME_DIR ?? "/tmp";

  return {
    socketPath: env.VOICE_SOCKET_PATH ?? join(runtimeDir, "omaboard-voice.sock"),
    endpoint: env.VOICE_ENDPOINT ?? "http://127.0.0.1:8787/transcribe",
    apiKey: normalizeOptional(env.VOICE_API_KEY),
    tmpDir: env.VOICE_TMP_DIR ?? "/tmp",
    recordCommand: env.VOICE_RECORD_COMMAND ?? "pw-record",
    recordArgs: parseArgs(env.VOICE_RECORD_ARGS) ?? DEFAULT_RECORD_ARGS,
    clipboardCommand: env.VOICE_CLIPBOARD_COMMAND ?? "wl-copy",
    notifyCommand: env.VOICE_NOTIFY_COMMAND ?? "notify-send",
    audioField: env.VOICE_AUDIO_FIELD ?? "file",
    textField: env.VOICE_TEXT_FIELD ?? "text",
    model: normalizeOptional(env.VOICE_MODEL),
    language: normalizeOptional(env.VOICE_LANGUAGE),
    requestTimeoutMs: parsePositiveInt(env.VOICE_REQUEST_TIMEOUT_MS, 45_000)
  };
}

function normalizeOptional(value: string | undefined): string | undefined {
  if (value === undefined) {
    return undefined;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function parseArgs(raw: string | undefined): string[] | undefined {
  if (!raw || raw.trim().length === 0) {
    return undefined;
  }

  return raw
    .split(/\s+/)
    .map((segment) => segment.trim())
    .filter((segment) => segment.length > 0);
}

function parsePositiveInt(raw: string | undefined, fallback: number): number {
  if (!raw) {
    return fallback;
  }

  const parsed = Number.parseInt(raw, 10);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return fallback;
  }

  return parsed;
}
