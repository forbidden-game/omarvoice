# omaboard-voice

Push-to-talk voice input daemon for omarchy/Hyprland.

## What it does

- Press hotkey -> start recording (`pw-record`)
- Release hotkey -> stop recording, send audio to backend LLM/STT API
- Get transcription text -> copy to clipboard (`wl-copy`)
- Show desktop notification (`notify-send`)

## Architecture

- `voice-daemon`: long-running local daemon, listens on Unix socket.
- `voicectl start|stop|status`: tiny client command used by hotkey bindings.
- State machine is strict: `idle -> recording -> submitting -> idle`.

## Install

```bash
npm install
npm run build
npm link
```

## Run

1. Start daemon in one terminal:

```bash
VOICE_ENDPOINT=http://127.0.0.1:8787/transcribe node dist/daemon.js
```

2. Trigger actions in another terminal:

```bash
node dist/cli.js start
# speak...
node dist/cli.js stop
```

If successful, recognized text is copied to your clipboard.

## Omarchy / Hyprland binding example

Use "press" to start and "release" to stop:

```ini
bind = SUPER, V, exec, voicectl start
bindr = SUPER, V, exec, voicectl stop
```

## Environment variables

- `VOICE_ENDPOINT`: HTTP endpoint for transcription API.
- `VOICE_API_KEY`: optional bearer token.
- `VOICE_SOCKET_PATH`: Unix socket path. Default: `$XDG_RUNTIME_DIR/omaboard-voice.sock`.
- `VOICE_TMP_DIR`: temp dir for wav file. Default: `/tmp`.
- `VOICE_RECORD_COMMAND`: recorder command. Default: `pw-record`.
- `VOICE_RECORD_ARGS`: recorder args. Default: `--rate 16000 --channels 1`.
- `VOICE_CLIPBOARD_COMMAND`: clipboard command. Default: `wl-copy`.
- `VOICE_NOTIFY_COMMAND`: notification command. Default: `notify-send`.
- `VOICE_AUDIO_FIELD`: multipart field name for audio. Default: `file`.
- `VOICE_TEXT_FIELD`: JSON text field path. Default: `text`.
- `VOICE_MODEL`: optional model field in multipart form.
- `VOICE_LANGUAGE`: optional language field in multipart form.
- `VOICE_REQUEST_TIMEOUT_MS`: request timeout in ms. Default: `45000`.

## Local mock backend (for smoke test)

Run:

```bash
node examples/mock-backend.mjs
```

This server accepts multipart uploads and always returns:

```json
{ "text": "mock transcription from local backend" }
```

## Production note

This tool touches input flow and clipboard. Keep changes small and reversible.
