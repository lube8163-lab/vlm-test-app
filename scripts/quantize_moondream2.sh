#!/usr/bin/env bash
set -euo pipefail

# Quantize moondream2 text model (F16 -> Q4_K_M) for lower RAM usage.
#
# Usage:
#   bash scripts/quantize_moondream2.sh
# or:
#   INPUT_GGUF=/path/to/moondream2-text-model-f16.gguf \
#   OUTPUT_GGUF=/path/to/moondream2-text-model-q4_k_m.gguf \
#   bash scripts/quantize_moondream2.sh

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LLAMA_DIR="${ROOT_DIR}/third_party/llama.cpp"

INPUT_GGUF="${INPUT_GGUF:-${ROOT_DIR}/Models/moondream2/moondream2-text-model-f16.gguf}"
OUTPUT_GGUF="${OUTPUT_GGUF:-${ROOT_DIR}/Models/moondream2/moondream2-text-model-q4_k_m.gguf}"

if [[ ! -f "${INPUT_GGUF}" ]]; then
  echo "[ERROR] input GGUF not found: ${INPUT_GGUF}"
  exit 1
fi

if [[ ! -d "${LLAMA_DIR}" ]]; then
  echo "[ERROR] llama.cpp not found: ${LLAMA_DIR}"
  exit 1
fi

if ! command -v cmake >/dev/null 2>&1; then
  echo "[ERROR] cmake not found"
  exit 1
fi

HOST_BUILD_DIR="${LLAMA_DIR}/build-host"

cmake -B "${HOST_BUILD_DIR}" -S "${LLAMA_DIR}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DLLAMA_BUILD_TOOLS=ON \
  -DLLAMA_BUILD_TESTS=OFF \
  -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_BUILD_SERVER=OFF

cmake --build "${HOST_BUILD_DIR}" --config Release -j 8 --target llama-quantize

"${HOST_BUILD_DIR}/bin/llama-quantize" "${INPUT_GGUF}" "${OUTPUT_GGUF}" Q4_K_M

echo "[OK] quantized model written:"
echo "  ${OUTPUT_GGUF}"
