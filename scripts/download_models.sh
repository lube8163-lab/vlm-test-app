#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   bash scripts/download_models.sh
# Optional env:
#   MODELS_DIR=/abs/path/to/Models
#   QWEN_REPO=Qwen/Qwen3.5-0.8B
#   QWEN_REVISION=main
#   QWEN_GGUF_REPO=unsloth/Qwen3.5-0.8B-GGUF   # optional
#   QWEN_GGUF_GLOB='*Q4_K_M*.gguf'
#   QWEN_VL_GGUF_REPO=unsloth/Qwen3.5-0.8B-GGUF # optional (GGUF + mmproj)
#   QWEN_VL_GGUF_GLOB='*Q4_K_M*.gguf'
#   QWEN_VL_MMPROJ_FILE='mmproj-F16.gguf'
#   MOONDREAM_REPO=vikhyatk/moondream2
#   MOONDREAM_REVISION=2025-06-21

HF_CMD=""
if command -v hf >/dev/null 2>&1; then
  HF_CMD="hf"
elif command -v huggingface-cli >/dev/null 2>&1; then
  HF_CMD="huggingface-cli"
else
  echo "[ERROR] hf / huggingface-cli が見つかりません。"
  echo "pip install -U \"huggingface_hub[cli]\" を実行してください。"
  exit 1
fi

MODELS_DIR="${MODELS_DIR:-$(pwd)/Models}"
QWEN_REPO="${QWEN_REPO:-Qwen/Qwen3.5-0.8B}"
QWEN_REVISION="${QWEN_REVISION:-main}"
QWEN_GGUF_REPO="${QWEN_GGUF_REPO:-}"
QWEN_GGUF_GLOB="${QWEN_GGUF_GLOB:-*Q4_K_M*.gguf}"
QWEN_VL_GGUF_REPO="${QWEN_VL_GGUF_REPO:-}"
QWEN_VL_GGUF_GLOB="${QWEN_VL_GGUF_GLOB:-*Q4_K_M*.gguf}"
QWEN_VL_MMPROJ_FILE="${QWEN_VL_MMPROJ_FILE:-mmproj-F16.gguf}"
MOONDREAM_REPO="${MOONDREAM_REPO:-vikhyatk/moondream2}"
MOONDREAM_REVISION="${MOONDREAM_REVISION:-2025-06-21}"

mkdir -p "${MODELS_DIR}/qwen3_5_0_8b" \
  "${MODELS_DIR}/moondream2" \
  "${MODELS_DIR}/qwen3_5_0_8b_gguf" \
  "${MODELS_DIR}/qwen3_5_vl_0_8b_gguf"

echo "[1/3] Download Qwen3.5-0.8B (Transformers weights)..."
if [[ "${HF_CMD}" == "hf" ]]; then
  hf download "${QWEN_REPO}" \
    --revision "${QWEN_REVISION}" \
    --repo-type model \
    --local-dir "${MODELS_DIR}/qwen3_5_0_8b"
else
  huggingface-cli snapshot-download "${QWEN_REPO}" \
    --revision "${QWEN_REVISION}" \
    --local-dir "${MODELS_DIR}/qwen3_5_0_8b" \
    --resume-download
fi

echo "[2/3] Download moondream2 source model (Transformers weights)..."
if [[ "${HF_CMD}" == "hf" ]]; then
  hf download "${MOONDREAM_REPO}" \
    --revision "${MOONDREAM_REVISION}" \
    --repo-type model \
    --local-dir "${MODELS_DIR}/moondream2"
else
  huggingface-cli snapshot-download "${MOONDREAM_REPO}" \
    --revision "${MOONDREAM_REVISION}" \
    --local-dir "${MODELS_DIR}/moondream2" \
    --resume-download
fi

echo "[3/3] Optional GGUF for Qwen3.5-0.8B..."
if [[ -n "${QWEN_GGUF_REPO}" ]]; then
  if [[ "${HF_CMD}" == "hf" ]]; then
    hf download "${QWEN_GGUF_REPO}" \
      --repo-type model \
      --local-dir "${MODELS_DIR}/qwen3_5_0_8b_gguf" \
      --include "${QWEN_GGUF_GLOB}"
  else
    huggingface-cli download "${QWEN_GGUF_REPO}" \
      --local-dir "${MODELS_DIR}/qwen3_5_0_8b_gguf" \
      --include "${QWEN_GGUF_GLOB}" \
      --resume-download
  fi
else
  echo "Skip: QWEN_GGUF_REPO is empty."
  echo "      必要なら例: QWEN_GGUF_REPO=unsloth/Qwen3.5-0.8B-GGUF"
fi

echo "[4/4] Optional GGUF + mmproj for Qwen3.5-VL-0.8B..."
if [[ -n "${QWEN_VL_GGUF_REPO}" ]]; then
  if [[ "${HF_CMD}" == "hf" ]]; then
    hf download "${QWEN_VL_GGUF_REPO}" \
      --repo-type model \
      --local-dir "${MODELS_DIR}/qwen3_5_vl_0_8b_gguf" \
      --include "${QWEN_VL_GGUF_GLOB}" \
      --include "${QWEN_VL_MMPROJ_FILE}"
  else
    huggingface-cli download "${QWEN_VL_GGUF_REPO}" \
      --local-dir "${MODELS_DIR}/qwen3_5_vl_0_8b_gguf" \
      --include "${QWEN_VL_GGUF_GLOB}" \
      --include "${QWEN_VL_MMPROJ_FILE}" \
      --resume-download
  fi
else
  echo "Skip: QWEN_VL_GGUF_REPO is empty."
  echo "      必要なら例: QWEN_VL_GGUF_REPO=unsloth/Qwen3.5-0.8B-GGUF"
fi

echo "Done."
echo "- Qwen (HF): ${MODELS_DIR}/qwen3_5_0_8b"
echo "- Qwen (GGUF optional): ${MODELS_DIR}/qwen3_5_0_8b_gguf"
echo "- Qwen3.5-VL (GGUF+mmproj optional): ${MODELS_DIR}/qwen3_5_vl_0_8b_gguf"
echo "- moondream2 path: ${MODELS_DIR}/moondream2"
