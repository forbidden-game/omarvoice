#!/bin/bash
set -euo pipefail

# Environment variables:
# DEVELOPER_ID_APPLICATION  - optional signing identity override
# NOTARY_PROFILE            - optional notarytool keychain profile name

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT_DIR}"

VENV_BIN="${ROOT_DIR}/.venv/bin"
PYTHON="${PYTHON:-${VENV_BIN}/python}"
PYINSTALLER="${PYINSTALLER:-${VENV_BIN}/pyinstaller}"
CREATE_DMG_BIN="${CREATE_DMG:-create-dmg}"
CREATE_DMG_FLAGS="${CREATE_DMG_FLAGS:---skip-jenkins}"
NOTARY_PROFILE="${NOTARY_PROFILE:-ohmyvoice-notary}"
DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:-$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -1)}"

# Extract version from source — no pip install needed
VERSION=$(sed -n 's/^__version__ = "\(.*\)"/\1/p' src/ohmyvoice/__init__.py)
APP_NAME="OhMyVoice"
DMG_NAME="${APP_NAME}-${VERSION}-arm64.dmg"
APP_DIR="dist/${APP_NAME}.app"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd swift
require_cmd xcrun
require_cmd codesign
require_cmd "${CREATE_DMG_BIN}"

if [ ! -x "${PYINSTALLER}" ]; then
  echo "Missing PyInstaller at ${PYINSTALLER}. Run: ${VENV_BIN}/pip install -e \".[dev,dist]\"" >&2
  exit 1
fi

if [ -z "${DEVELOPER_ID_APPLICATION}" ]; then
  echo "Missing Developer ID Application certificate in Keychain." >&2
  exit 1
fi

if ! xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1; then
  echo "Missing notary profile '${NOTARY_PROFILE}'." >&2
  echo "Run: make notary-store-credentials APPLE_ID=... APPLE_TEAM_ID=..." >&2
  exit 1
fi

# Step 1: Build Swift UI
cd ui && swift build -c release && cd ..

# Step 2: PyInstaller
PATH="${VENV_BIN}:$PATH" "${PYINSTALLER}" ohmyvoice.spec --noconfirm

# Step 3: Post-build copy — resources and Swift binary
# PyInstaller datas go to _internal/, we need Contents/Resources/
mkdir -p "${APP_DIR}/Contents/Resources"
cp -R resources/icons  "${APP_DIR}/Contents/Resources/icons"
cp -R resources/sounds "${APP_DIR}/Contents/Resources/sounds" 2>/dev/null || true
cp resources/AppIcon.icns "${APP_DIR}/Contents/Resources/AppIcon.icns" 2>/dev/null || true
cp ui/.build/release/ohmyvoice-ui "${APP_DIR}/Contents/MacOS/"
rm -rf "${APP_DIR}/Contents/_CodeSignature"

# Step 3b: Copy mlx Metal shaders (not picked up by PyInstaller)
MLX_METALLIB=$(PATH="${VENV_BIN}:$PATH" "${PYTHON}" -c 'from pathlib import Path; import mlx; print(next((str(p) for base in getattr(mlx, "__path__", []) for p in [Path(base) / "lib" / "mlx.metallib"] if p.exists()), ""))')
if [ -f "$MLX_METALLIB" ]; then
  mkdir -p "${APP_DIR}/Contents/Frameworks/mlx/lib"
  cp "$MLX_METALLIB" "${APP_DIR}/Contents/Frameworks/mlx/lib/"
fi

# Step 4: Pre-flight check — @2x icons
for state in idle recording processing done; do
  if [ ! -f "${APP_DIR}/Contents/Resources/icons/mic_${state}@2x.png" ]; then
    echo "WARNING: missing mic_${state}@2x.png — Retina displays will show blurry icons"
  fi
done

# Step 5: Inside-out code signing
# Sign all Mach-O binaries in Frameworks/ first, then executables, then outer bundle
# 5a: Frameworks/ — all .so, .dylib, and executable Mach-O files
find "${APP_DIR}/Contents/Frameworks" -type f \( -name '*.dylib' -o -name '*.so' -o -name '*.metallib' -o -perm +111 \) -print0 | while IFS= read -r -d '' bin; do
  if [ "${bin##*.}" = "metallib" ] || file "$bin" | grep -q "Mach-O"; then
    codesign --force --timestamp --options runtime --sign "${DEVELOPER_ID_APPLICATION}" "$bin"
  fi
done

# 5b: Swift UI binary (no special entitlements needed)
codesign --force --timestamp --options runtime \
  --sign "${DEVELOPER_ID_APPLICATION}" \
  "${APP_DIR}/Contents/MacOS/ohmyvoice-ui"

# 5c: Python main executable (needs entitlements for MLX JIT)
codesign --force --timestamp --options runtime \
  --sign "${DEVELOPER_ID_APPLICATION}" \
  --entitlements entitlements.plist \
  "${APP_DIR}/Contents/MacOS/ohmyvoice"

# 5d: Outer bundle
codesign --force --timestamp --options runtime \
  --sign "${DEVELOPER_ID_APPLICATION}" \
  --entitlements entitlements.plist \
  "${APP_DIR}"
codesign --verify --deep --strict "${APP_DIR}"

# Step 6: Notarize (notarytool needs zip/dmg/pkg, not bare .app)
ditto -c -k --keepParent "${APP_DIR}" "dist/${APP_NAME}.zip"
xcrun notarytool submit "dist/${APP_NAME}.zip" \
  --keychain-profile "${NOTARY_PROFILE}" \
  --wait
rm "dist/${APP_NAME}.zip"

# Step 7: Staple
xcrun stapler staple "${APP_DIR}"
xcrun stapler validate "${APP_DIR}"

# Step 8: Create DMG
rm -f "dist/${DMG_NAME}"
"${CREATE_DMG_BIN}" ${CREATE_DMG_FLAGS} \
  --volname "${APP_NAME}" \
  --window-size 600 400 \
  --icon-size 128 \
  --icon "${APP_NAME}.app" 150 200 \
  --app-drop-link 450 200 \
  "dist/${DMG_NAME}" \
  "${APP_DIR}"

# Step 9: Sign and notarize DMG
codesign --force --timestamp --sign "${DEVELOPER_ID_APPLICATION}" "dist/${DMG_NAME}"
xcrun notarytool submit "dist/${DMG_NAME}" \
  --keychain-profile "${NOTARY_PROFILE}" \
  --wait
xcrun stapler staple "dist/${DMG_NAME}"
xcrun stapler validate "dist/${DMG_NAME}"

echo "Done! Output: dist/${DMG_NAME}"
