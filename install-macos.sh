#!/usr/bin/env bash
# Bootstrap ohmyvoice on macOS from a single command.
set -euo pipefail

REPO="${OHMYVOICE_GITHUB_REPO:-forbidden-game/ohmyvoice}"
REF="${OHMYVOICE_REF:-main}"
INSTALL_DIR="${OHMYVOICE_INSTALL_DIR:-${HOME}/.local/share/ohmyvoice}"
ARCHIVE_URL="${OHMYVOICE_ARCHIVE_URL:-https://codeload.github.com/${REPO}/tar.gz/refs/heads/${REF}}"
SKIP_PACKAGE_INSTALL="${OHMYVOICE_SKIP_PACKAGE_INSTALL:-0}"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "install-macos.sh only supports macOS." >&2
  exit 1
fi

for cmd in curl tar; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    exit 1
  fi
done

activate_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    return
  fi

  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    return
  fi

  if [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

ensure_homebrew() {
  activate_homebrew
  if command -v brew >/dev/null 2>&1; then
    return
  fi

  echo "Homebrew not found. Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  activate_homebrew

  if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew installation finished, but brew is still not on PATH." >&2
    echo "Open a new terminal, run 'brew --version', then re-run this installer." >&2
    exit 1
  fi
}

install_dependencies() {
  ensure_homebrew

  echo "[1/3] Installing macOS dependencies..."
  brew install node ffmpeg python3
  brew install --cask hammerspoon
}

download_repo() {
  local tmp_dir archive extracted_dir
  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/ohmyvoice-install.XXXXXX")"
  archive="${tmp_dir}/ohmyvoice.tar.gz"
  trap 'rm -rf "${tmp_dir}"' EXIT

  echo "[2/3] Downloading ohmyvoice (${REPO}@${REF})..."
  curl -fsSL "${ARCHIVE_URL}" -o "${archive}"
  tar -xzf "${archive}" -C "${tmp_dir}"

  extracted_dir="$(find "${tmp_dir}" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  if [ -z "${extracted_dir}" ]; then
    echo "Failed to unpack ${ARCHIVE_URL}" >&2
    exit 1
  fi

  rm -rf "${INSTALL_DIR}"
  mkdir -p "$(dirname "${INSTALL_DIR}")"
  mv "${extracted_dir}" "${INSTALL_DIR}"

  trap - EXIT
  rm -rf "${tmp_dir}"
}

run_setup() {
  echo "[3/3] Running ohmyvoice setup..."
  cd "${INSTALL_DIR}"
  bash ./setup-macos.sh

  if [ -d /Applications/Hammerspoon.app ] || [ -d "${HOME}/Applications/Hammerspoon.app" ]; then
    open -a Hammerspoon >/dev/null 2>&1 || true
  fi
}

if [ "${SKIP_PACKAGE_INSTALL}" != "1" ]; then
  install_dependencies
else
  echo "[1/3] Skipping package installation (OHMYVOICE_SKIP_PACKAGE_INSTALL=1)."
fi

download_repo
run_setup

echo ""
echo "ohmyvoice is installed in ${INSTALL_DIR}"
echo "Re-run this command anytime to update."
