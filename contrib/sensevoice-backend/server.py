"""Minimal OpenAI Chat Completions-compatible wrapper around SenseVoice-Small.

Accepts the same multimodal request format that ohmyvoice sends
(audio_url with base64 data URI) and returns a Chat Completions response.

Usage:
    pip install sherpa-onnx fastapi uvicorn
    # Download model (see README or run download_model.sh)
    python server.py                       # default: 127.0.0.1:8000
    python server.py --port 9000           # custom port
    SENSEVOICE_MODEL_DIR=./my-model python server.py
"""

from __future__ import annotations

import argparse
import base64
import re
import subprocess
import time
from pathlib import Path

import numpy as np
import sherpa_onnx
import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

DEFAULT_MODEL_DIR = Path(__file__).parent / "model"
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8000
DEFAULT_NUM_THREADS = 4


def resolve_model_dir() -> Path:
    import os

    env = os.environ.get("SENSEVOICE_MODEL_DIR")
    return Path(env) if env else DEFAULT_MODEL_DIR


# ---------------------------------------------------------------------------
# Audio decoding via ffmpeg
# ---------------------------------------------------------------------------

_DATA_URI_RE = re.compile(r"^data:[^;]+;base64,")


def extract_audio_bytes(data_uri: str) -> bytes:
    """Strip the data-URI prefix and base64-decode."""
    raw = _DATA_URI_RE.sub("", data_uri)
    return base64.b64decode(raw)


def decode_audio(audio_bytes: bytes) -> np.ndarray:
    """Decode any audio format to 16 kHz mono float32 PCM via ffmpeg."""
    proc = subprocess.run(
        [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-i",
            "pipe:0",
            "-f",
            "f32le",
            "-acodec",
            "pcm_f32le",
            "-ac",
            "1",
            "-ar",
            "16000",
            "pipe:1",
        ],
        input=audio_bytes,
        capture_output=True,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"ffmpeg decode failed: {proc.stderr.decode().strip()}")
    return np.frombuffer(proc.stdout, dtype=np.float32)


# ---------------------------------------------------------------------------
# Request parsing
# ---------------------------------------------------------------------------


def extract_audio_uri(body: dict) -> str:
    """Walk the Chat Completions request to find the audio data URI."""
    messages = body.get("messages") or []
    for msg in messages:
        content = msg.get("content")
        if isinstance(content, str):
            continue
        if not isinstance(content, list):
            continue
        for part in content:
            if part.get("type") == "audio_url":
                url = (part.get("audio_url") or {}).get("url", "")
                if url:
                    return url
    raise HTTPException(status_code=400, detail="No audio_url found in request")


# ---------------------------------------------------------------------------
# Application
# ---------------------------------------------------------------------------


def create_app(recognizer: sherpa_onnx.OfflineRecognizer) -> FastAPI:
    app = FastAPI(title="SenseVoice Backend", docs_url=None, redoc_url=None)

    @app.post("/v1/chat/completions")
    async def chat_completions(request: dict) -> JSONResponse:
        audio_uri = extract_audio_uri(request)
        audio_bytes = extract_audio_bytes(audio_uri)
        samples = decode_audio(audio_bytes)

        if samples.size == 0:
            raise HTTPException(status_code=400, detail="Audio is empty after decoding")

        stream = recognizer.create_stream()
        stream.accept_waveform(16000, samples)
        recognizer.decode_stream(stream)

        text = stream.result.text.strip()

        return JSONResponse(
            {
                "choices": [
                    {
                        "index": 0,
                        "message": {"role": "assistant", "content": text},
                        "finish_reason": "stop",
                    }
                ],
                "model": "sensevoice-small",
                "usage": {
                    "prompt_tokens": 0,
                    "completion_tokens": 0,
                    "total_tokens": 0,
                },
            }
        )

    @app.get("/health")
    async def health() -> dict:
        return {"status": "ok"}

    return app


def build_recognizer(model_dir: Path, num_threads: int) -> sherpa_onnx.OfflineRecognizer:
    model_path = model_dir / "model.int8.onnx"
    tokens_path = model_dir / "tokens.txt"

    if not model_path.exists():
        raise FileNotFoundError(
            f"Model not found at {model_path}. "
            "Run download_model.sh or set SENSEVOICE_MODEL_DIR."
        )
    if not tokens_path.exists():
        raise FileNotFoundError(f"Tokens file not found at {tokens_path}.")

    t0 = time.monotonic()
    recognizer = sherpa_onnx.OfflineRecognizer.from_sense_voice(
        model=str(model_path),
        tokens=str(tokens_path),
        use_itn=True,
        num_threads=num_threads,
    )
    elapsed = time.monotonic() - t0
    print(f"SenseVoice model loaded in {elapsed:.1f}s ({model_path})")
    return recognizer


def main() -> None:
    parser = argparse.ArgumentParser(description="SenseVoice ASR backend")
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--threads", type=int, default=DEFAULT_NUM_THREADS)
    args = parser.parse_args()

    model_dir = resolve_model_dir()
    recognizer = build_recognizer(model_dir, args.threads)
    app = create_app(recognizer)

    uvicorn.run(app, host=args.host, port=args.port, log_level="info")


if __name__ == "__main__":
    main()
