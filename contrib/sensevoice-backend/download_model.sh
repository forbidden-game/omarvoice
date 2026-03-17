#!/usr/bin/env bash
# Download the SenseVoice-Small int8 model for sherpa-onnx.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODEL_DIR="${SCRIPT_DIR}/model"

ARCHIVE="sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17.tar.bz2"
URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/${ARCHIVE}"

if [ -f "${MODEL_DIR}/model.int8.onnx" ]; then
  echo "Model already exists at ${MODEL_DIR}/model.int8.onnx"
  exit 0
fi

echo "Downloading SenseVoice-Small model..."
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

curl -L -o "${TMP_DIR}/${ARCHIVE}" "${URL}"
echo "Extracting..."
tar xjf "${TMP_DIR}/${ARCHIVE}" -C "${TMP_DIR}"

mkdir -p "${MODEL_DIR}"
EXTRACTED="${TMP_DIR}/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17"
cp "${EXTRACTED}/model.int8.onnx" "${MODEL_DIR}/"
cp "${EXTRACTED}/tokens.txt" "${MODEL_DIR}/"

echo "Model installed to ${MODEL_DIR}"
echo "  model.int8.onnx  $(du -h "${MODEL_DIR}/model.int8.onnx" | cut -f1)"
echo "  tokens.txt       $(du -h "${MODEL_DIR}/tokens.txt" | cut -f1)"
