#!/usr/bin/env bash
set -euo pipefail

# Build llama.cpp static libs for iOS (iphoneos + iphonesimulator)
# and place them under vlm_test/vendor/llama.
#
# Prereqs:
#   brew install cmake ninja
#   git clone https://github.com/ggml-org/llama.cpp third_party/llama.cpp
#
# Usage:
#   bash scripts/build_llama_ios_libs.sh

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LLAMA_DIR="${ROOT_DIR}/third_party/llama.cpp"

if [[ ! -d "${LLAMA_DIR}" ]]; then
  echo "[ERROR] llama.cpp not found: ${LLAMA_DIR}"
  exit 1
fi

for cmd in cmake ninja xcrun libtool lipo; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[ERROR] missing command: $cmd"
    exit 1
  fi
done

C_COMPILER="$(xcrun --find clang)"
CXX_COMPILER="$(xcrun --find clang++)"

build_one() {
  local out_dir="$1"
  local sysroot="$2"
  local arch="$3"

  rm -rf "$out_dir"

  cmake -B "$out_dir" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$sysroot" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=16.4 \
    -DCMAKE_OSX_ARCHITECTURES="$arch" \
    -DCMAKE_C_COMPILER="$C_COMPILER" \
    -DCMAKE_CXX_COMPILER="$CXX_COMPILER" \
    -DBUILD_SHARED_LIBS=OFF \
    -DLLAMA_BUILD_EXAMPLES=OFF \
    -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_SERVER=OFF \
    -DLLAMA_BUILD_TOOLS=ON \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON \
    -DLLAMA_OPENSSL=OFF \
    -S "$LLAMA_DIR"

  cmake --build "$out_dir" --config Release -j 8
}

SIM_ARM64_BUILD="/tmp/llama_ios_sim_arm64_static"
SIM_X86_BUILD="/tmp/llama_ios_sim_x86_static"
DEVICE_BUILD="/tmp/llama_ios_device_static"

build_one "$SIM_ARM64_BUILD" iphonesimulator arm64
build_one "$SIM_X86_BUILD" iphonesimulator x86_64
build_one "$DEVICE_BUILD" iphoneos arm64

combine_static() {
  local base_dir="$1"
  local out_lib="$2"

  libtool -static -o "$out_lib" \
    "$base_dir/src/libllama.a" \
    "$base_dir/tools/mtmd/libmtmd.a" \
    "$base_dir/ggml/src/libggml.a" \
    "$base_dir/ggml/src/libggml-base.a" \
    "$base_dir/ggml/src/libggml-cpu.a" \
    "$base_dir/ggml/src/ggml-metal/libggml-metal.a" \
    "$base_dir/ggml/src/ggml-blas/libggml-blas.a"
}

ARTIFACTS_DIR="${ROOT_DIR}/third_party/llama_artifacts"
mkdir -p "$ARTIFACTS_DIR"

SIM_ARM64_LIB="${ARTIFACTS_DIR}/libllama-ios-sim-arm64.a"
SIM_X86_LIB="${ARTIFACTS_DIR}/libllama-ios-sim-x86_64.a"
SIM_FAT_LIB="${ARTIFACTS_DIR}/libllama-ios-sim.a"
DEVICE_LIB="${ARTIFACTS_DIR}/libllama-ios-device.a"

combine_static "$SIM_ARM64_BUILD" "$SIM_ARM64_LIB"
combine_static "$SIM_X86_BUILD" "$SIM_X86_LIB"
combine_static "$DEVICE_BUILD" "$DEVICE_LIB"

lipo -create "$SIM_ARM64_LIB" "$SIM_X86_LIB" -output "$SIM_FAT_LIB"

VENDOR_DIR="${ROOT_DIR}/vlm_test/vendor/llama"
mkdir -p "$VENDOR_DIR/include" "$VENDOR_DIR/iphonesimulator" "$VENDOR_DIR/iphoneos"

cp "$LLAMA_DIR/include/llama.h" "$VENDOR_DIR/include/"
cp "$LLAMA_DIR/ggml/include/"*.h "$VENDOR_DIR/include/"
cp "$LLAMA_DIR/tools/mtmd/mtmd.h" "$VENDOR_DIR/include/"
cp "$LLAMA_DIR/tools/mtmd/mtmd-helper.h" "$VENDOR_DIR/include/"
cp "$SIM_FAT_LIB" "$VENDOR_DIR/iphonesimulator/libllama.a"
cp "$DEVICE_LIB" "$VENDOR_DIR/iphoneos/libllama.a"

echo "[OK] Updated vendor libs:"
echo "  - ${VENDOR_DIR}/iphonesimulator/libllama.a"
echo "  - ${VENDOR_DIR}/iphoneos/libllama.a"
