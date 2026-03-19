#!/usr/bin/env bash
# One-command macOS setup for ohmyvoice.
#
# Usage: git clone <repo> && cd ohmyvoice && ./setup-macos.sh
#
# Idempotent — safe to run again after partial failure.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKEND_DIR="${PROJECT_DIR}/contrib/sensevoice-backend"
VENV_DIR="${BACKEND_DIR}/.venv"

node_major() {
  local node_bin="${1:-}"
  if [ -z "${node_bin}" ] || [ ! -x "${node_bin}" ]; then
    echo 0
    return
  fi

  "${node_bin}" -p "process.versions.node.split('.')[0]"
}

resolve_node_bin() {
  local brew_prefix

  if [ -n "${OHMYVOICE_NODE_BIN:-}" ] && [ -x "${OHMYVOICE_NODE_BIN}" ]; then
    printf '%s\n' "${OHMYVOICE_NODE_BIN}"
    return 0
  fi

  if command -v brew >/dev/null 2>&1; then
    brew_prefix="$(brew --prefix node 2>/dev/null || true)"
    if [ -n "${brew_prefix}" ] && [ -x "${brew_prefix}/bin/node" ]; then
      printf '%s\n' "${brew_prefix}/bin/node"
      return 0
    fi
  fi

  if command -v node >/dev/null 2>&1; then
    command -v node
    return 0
  fi

  return 1
}

echo "=== ohmyvoice macOS setup ==="
echo ""

# ------------------------------------------------------------------
# 1. Check system dependencies
# ------------------------------------------------------------------

echo "[1/6] Checking dependencies..."

missing=()
NODE_BIN="$(resolve_node_bin || true)"

if [ -z "${NODE_BIN}" ]; then
  missing+=("node")
else
  export OHMYVOICE_NODE_BIN="${NODE_BIN}"
  export PATH="$(dirname "${NODE_BIN}"):${PATH}"
fi

command -v npm >/dev/null 2>&1 || missing+=("npm")
command -v ffmpeg >/dev/null 2>&1 || missing+=("ffmpeg")
command -v python3 >/dev/null 2>&1 || missing+=("python3")

if ! [ -d "/Applications/Hammerspoon.app" ] && ! [ -d "${HOME}/Applications/Hammerspoon.app" ]; then
  missing+=("Hammerspoon")
fi

if [ ${#missing[@]} -gt 0 ]; then
  echo ""
  echo "Missing dependencies: ${missing[*]}"
  echo ""
  echo "Install them with:"
  echo "  brew install node ffmpeg python3"
  echo "  brew install --cask hammerspoon"
  exit 1
fi

if [ "$(node_major "${NODE_BIN}")" -lt 20 ]; then
  echo "Node.js 20+ is required. Current version: $("${NODE_BIN}" --version)" >&2
  exit 1
fi

echo "  All dependencies found."

# ------------------------------------------------------------------
# 2. Build Node.js project
# ------------------------------------------------------------------

echo "[2/6] Building project..."

cd "${PROJECT_DIR}"
npm ci --silent
npm run build

echo "  Build complete."

# ------------------------------------------------------------------
# 3. Set up Python venv and install backend dependencies
# ------------------------------------------------------------------

echo "[3/6] Setting up Python backend..."

if [ ! -d "${VENV_DIR}" ]; then
  python3 -m venv "${VENV_DIR}"
  echo "  Created venv at ${VENV_DIR}"
fi

"${VENV_DIR}/bin/pip3" install -q -r "${BACKEND_DIR}/requirements.txt"
echo "  Python dependencies installed."

# ------------------------------------------------------------------
# 4. Download SenseVoice model (skip if already present)
# ------------------------------------------------------------------

echo "[4/6] Checking SenseVoice model..."

if [ -f "${BACKEND_DIR}/model/model.int8.onnx" ]; then
  echo "  Model already downloaded."
else
  echo "  Downloading SenseVoice-Small model (~228 MB)..."
  bash "${BACKEND_DIR}/download_model.sh"
fi

# ------------------------------------------------------------------
# 5. Install Hammerspoon integration
# ------------------------------------------------------------------

echo "[5/6] Installing Hammerspoon integration..."

bash "${PROJECT_DIR}/contrib/macos/install.sh"

# ------------------------------------------------------------------
# 6. Trigger microphone permission
# ------------------------------------------------------------------

echo "[6/6] Triggering microphone permission..."

# A short ffmpeg recording triggers the macOS mic permission prompt.
# If already granted, this finishes silently in <1s.
ffmpeg -f avfoundation -i ":default" -t 0.1 -f null - 2>/dev/null && echo "  Microphone access OK." || echo "  Please grant microphone access when prompted."

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------

echo ""
echo "========================================="
echo "  ohmyvoice setup complete!"
echo "========================================="
echo ""
echo "Permissions checklist:"
echo "  [ ] Accessibility: System Settings > Privacy & Security > Accessibility > Hammerspoon"
echo "  [ ] Microphone:    System Settings > Privacy & Security > Microphone > Hammerspoon"
echo ""
echo "Usage:"
echo "  Hold Right Command to record, release to stop."
echo "  Transcript lands in your clipboard."
echo ""
echo "The SenseVoice backend starts automatically with the daemon."
echo "No need to run server.py manually."
echo ""
echo "To verify:"
echo "  node dist/cli.js status"
