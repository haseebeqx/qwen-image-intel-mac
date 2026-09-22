#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=engine-version.sh
source "$ROOT/scripts/engine-version.sh"
SRC="$ROOT/vendor/stable-diffusion.cpp"
BUILD="$ROOT/build"

for tool in git cmake xcrun; do
    command -v "$tool" >/dev/null || { echo "error: missing $tool" >&2; exit 1; }
done
[[ "$(uname -s)" == Darwin ]] || { echo "error: this build targets macOS" >&2; exit 1; }

mkdir -p "$ROOT/vendor"
if [[ ! -e "$SRC" ]]; then
    echo "Cloning stable-diffusion.cpp..."
    git clone --filter=blob:none "$SD_CPP_REPOSITORY" "$SRC"
elif [[ ! -d "$SRC/.git" ]]; then
    echo "error: $SRC exists but is not a Git checkout; remove it and retry" >&2
    exit 1
fi

echo "Checking out pinned engine $SD_CPP_COMMIT..."
git -C "$SRC" fetch --depth 1 origin "$SD_CPP_COMMIT"
git -C "$SRC" checkout --detach "$SD_CPP_COMMIT"
git -C "$SRC" submodule sync --recursive
git -C "$SRC" submodule update --init --recursive --depth 1

cmake -S "$SRC" -B "$BUILD" \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON \
    -DSD_BUILD_SHARED_LIBS=OFF \
    -DSD_BUILD_EXAMPLES=ON

jobs="$(sysctl -n hw.physicalcpu 2>/dev/null || echo 4)"
cmake --build "$BUILD" --config Release --parallel "$jobs"

[[ -x "$BUILD/bin/sd-cli" ]] || { echo "error: build completed without sd-cli" >&2; exit 1; }
echo
echo "Built: $BUILD/bin/sd-cli"
"$BUILD/bin/sd-cli" --list-devices
