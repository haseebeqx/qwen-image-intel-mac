#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
interrupt_wrapper=""
live_wrapper=""
interrupt_pids=""
cleanup() {
    [[ -z "$live_wrapper" ]] || kill -KILL "$live_wrapper" 2>/dev/null || true
    [[ -z "$interrupt_wrapper" ]] || kill -KILL "$interrupt_wrapper" 2>/dev/null || true
    for pid in $interrupt_pids; do kill -KILL "$pid" 2>/dev/null || true; done
    rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/models"
for f in qwen_image_2.1-Q2_K.gguf Qwen3VL-8B-Instruct-Q4_K_M.gguf qwen_image_2.1_vae_bf16.safetensors; do printf x >"$TMP/models/$f"; done
cat >"$TMP/sd-cli" <<'EOF'
#!/bin/sh
echo "noisy engine details"
if [ -n "${QWEN_TEST_ENV_FILE:-}" ]; then
    printf '%s\n' "${GGML_METAL_N_CB:-unset}" >"$QWEN_TEST_ENV_FILE"
fi
if [ "${QWEN_TEST_HANG:-0}" = 1 ]; then
    trap '' INT TERM
    sleep 300 &
    printf '%s %s\n' "$$" "$!" >"$QWEN_TEST_PID_FILE"
    wait
fi
if [ "${QWEN_TEST_PROGRESS:-0}" = 1 ]; then
    printf '[INFO   ] request.cpp - sampling using Euler method\n'
    printf '\r  |=========================                         | 1/2 - 1.00s/it\033[K'
    if [ "${QWEN_TEST_LIVE_PROGRESS:-0}" = 1 ]; then sleep 1; fi
    printf '\r  |==================================================| 2/2 - 1.00s/it\033[K\n'
    printf '[INFO   ] image.cpp - decoding 1 latents\n'
    printf '\r  |==================================================| 1/1 - 1.00s/it\033[K\n'
fi
exit 0
EOF
chmod +x "$TMP/sd-cli"
mkdir -p "$TMP/bin"
cat >"$TMP/bin/system_profiler" <<'EOF'
#!/bin/sh
cat <<PROFILE
Graphics/Displays:

    AMD Radeon Pro 5500M:

      Chipset Model: AMD Radeon Pro 5500M
      VRAM (Total): ${TEST_VRAM_GB:-8} GB
      Metal Support: Metal 3
PROFILE
EOF
chmod +x "$TMP/bin/system_profiler"

run=(env QWEN_ENGINE="$TMP/sd-cli" QWEN_MODEL_DIR="$TMP/models" "$ROOT/qwen-image")

"$ROOT/qwen-image" --help >/dev/null
# Release bundles carry their tag in a marker file; version checks must not need
# the engine or models.
version_dir="$TMP/version-bundle"
mkdir -p "$version_dir"
cp "$ROOT/qwen-image" "$version_dir/qwen-image"
printf 'v9.8.7\n' >"$version_dir/.qwen-image-release"
[[ "$(QWEN_MODEL_DOWNLOADER=/usr/bin/false "$version_dir/qwen-image" --version)" == 'qwen-image v9.8.7' ]]
[[ "$(QWEN_MODEL_DOWNLOADER=/usr/bin/false "$version_dir/qwen-image" -V)" == 'qwen-image v9.8.7' ]]
# Help must remain side-effect free, while the first real run lazily fetches models.
empty_models="$TMP/lazy-models"
if ! env QWEN_MODEL_DIR="$empty_models" QWEN_MODEL_DOWNLOADER=/usr/bin/false "$ROOT/qwen-image" --help >/dev/null; then
    echo "help unexpectedly attempted a model download" >&2; exit 1
fi
cat >"$TMP/model-downloader" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$QWEN_TEST_DOWNLOAD_LOG"
model_dir=""
editing=0
while (($#)); do
    case "$1" in
        --model-dir) model_dir="$2"; shift 2 ;;
        --editing) editing=1; shift ;;
        *) shift ;;
    esac
done
mkdir -p "$model_dir"
for name in qwen_image_2.1-Q2_K.gguf Qwen3VL-8B-Instruct-Q4_K_M.gguf qwen_image_2.1_vae_bf16.safetensors; do
    printf x >"$model_dir/$name"
done
if (( editing )); then printf x >"$model_dir/mmproj-Qwen3VL-8B-Instruct-Q8_0.gguf"; fi
EOF
chmod +x "$TMP/model-downloader"
lazy_output="$(env QWEN_ENGINE="$TMP/sd-cli" QWEN_MODEL_DIR="$empty_models" \
    QWEN_MODEL_DOWNLOADER="$TMP/model-downloader" QWEN_TEST_DOWNLOAD_LOG="$TMP/download.log" \
    "$ROOT/qwen-image" 'lazy download' --dry-run)"
grep -q -- 'Required models are missing' <<<"$lazy_output"
grep -q -- "--accept-license --model-dir $empty_models" "$TMP/download.log"
for name in qwen_image_2.1-Q2_K.gguf Qwen3VL-8B-Instruct-Q4_K_M.gguf qwen_image_2.1_vae_bf16.safetensors; do
    [[ -s "$empty_models/$name" ]]
done

default_models="$TMP/home/.qwen-image"
env HOME="$TMP/home" QWEN_ENGINE="$TMP/sd-cli" \
    QWEN_MODEL_DOWNLOADER="$TMP/model-downloader" QWEN_TEST_DOWNLOAD_LOG="$TMP/default-download.log" \
    "$ROOT/qwen-image" 'default model directory' --dry-run >/dev/null
grep -qx -- "--accept-license --model-dir $default_models" "$TMP/default-download.log"
[[ -s "$default_models/qwen_image_2.1-Q2_K.gguf" ]]
# Installed commands are symlinks; the wrapper must still resolve the project root.
ln -s "$ROOT/qwen-image" "$TMP/qwen-image"
symlink_output="$(env QWEN_ENGINE="$TMP/sd-cli" QWEN_MODEL_DIR="$TMP/models" "$TMP/qwen-image" 'symlink test' --dry-run)"
grep -q -- "$ROOT/outputs/qwen-" <<<"$symlink_output"
output="$("${run[@]}" 'a test prompt' --dry-run --width 512 --height 512 --output "$TMP/out.png")"
grep -q -- '--diffusion-model' <<<"$output"
grep -q -- 'diffusion=MTL0' <<<"$output"
grep -q -- 'te=CPU' <<<"$output"
grep -q -- '--diffusion-fa' <<<"$output"
grep -q -- '--log-level info' <<<"$output"

compact_output="$("${run[@]}" 'compact output' --output "$TMP/compact.png")"
grep -q -- 'Generating 512x512 image (20 steps)' <<<"$compact_output"
grep -q -- "Saved: $TMP/compact.png" <<<"$compact_output"
if grep -q -- 'noisy engine details\|Engine command:' <<<"$compact_output"; then
    echo "compact output leaked engine details" >&2; exit 1
fi
progress_output="$(QWEN_TEST_PROGRESS=1 "${run[@]}" 'progress output' --steps 2 --output "$TMP/progress.png")"
grep -q -- 'Loading text encoder' <<<"$progress_output"
grep -q -- '2/2' <<<"$progress_output"
grep -q -- 'Decoding image' <<<"$progress_output"
# Progress must reach the wrapper's output while the engine is still running,
# rather than being block-buffered until the pipeline closes.
QWEN_TEST_PROGRESS=1 QWEN_TEST_LIVE_PROGRESS=1 \
    "${run[@]}" 'live progress' --steps 2 --output "$TMP/live.png" >"$TMP/live.log" &
live_wrapper=$!
for _ in {1..200}; do
    grep -q -- '1/2' "$TMP/live.log" && break
    sleep 0.02
done
if ! grep -q -- '1/2' "$TMP/live.log"; then
    echo "progress was not emitted while generation was running" >&2
    exit 1
fi
wait "$live_wrapper"
live_wrapper=""
verbose_output="$("${run[@]}" 'verbose output' --verbose --output "$TMP/verbose.png")"
grep -q -- 'Engine command:' <<<"$verbose_output"
grep -q -- 'noisy engine details' <<<"$verbose_output"
grep -q -- '--verbose' <<<"$verbose_output"
QWEN_TEST_ENV_FILE="$TMP/metal-n-cb" "${run[@]}" 'Metal scheduling' --output "$TMP/env.png" >/dev/null
grep -qx -- '32' "$TMP/metal-n-cb"
GGML_METAL_N_CB=4 QWEN_TEST_ENV_FILE="$TMP/metal-n-cb-override" \
    "${run[@]}" 'Metal scheduling override' --output "$TMP/env-override.png" >/dev/null
grep -qx -- '4' "$TMP/metal-n-cb-override"

# SIGINT and SIGTERM share the same descendant-tree shutdown path. Exercise it
# with an engine and worker that ignore polite signals, ensuring neither survives.
QWEN_TEST_HANG=1 QWEN_TEST_PID_FILE="$TMP/engine-pids" \
    "${run[@]}" 'interrupt test' --output "$TMP/interrupted.png" >"$TMP/interrupt.log" 2>&1 &
interrupt_wrapper=$!
for _ in {1..100}; do
    [[ -s "$TMP/engine-pids" ]] && break
    sleep 0.02
done
[[ -s "$TMP/engine-pids" ]] || { echo "interrupt test engine did not start" >&2; exit 1; }
interrupt_pids="$(<"$TMP/engine-pids")"
kill -TERM "$interrupt_wrapper"
if wait "$interrupt_wrapper"; then
    interrupt_status=0
else
    interrupt_status=$?
fi
interrupt_wrapper=""
[[ "$interrupt_status" == 143 ]] || { echo "expected interrupted wrapper to exit 143, got $interrupt_status" >&2; exit 1; }
for _ in {1..50}; do
    survivors=""
    for pid in $interrupt_pids; do kill -0 "$pid" 2>/dev/null && survivors+=" $pid"; done
    [[ -z "$survivors" ]] && break
    sleep 0.02
done
[[ -z "$survivors" ]] || { echo "generation processes survived shutdown:$survivors" >&2; exit 1; }
interrupt_pids=""

# Cover the discrete VRAM capacities available across Intel Mac configurations.
for profile in '4 3.0' '8 7.0' '16 15.0' '32 31.0'; do
    read -r installed expected <<<"$profile"
    auto_vram_output="$(TEST_VRAM_GB="$installed" PATH="$TMP/bin:$PATH" "${run[@]}" "$installed GB GPU" --dry-run)"
    grep -q -- "--max-vram MTL0=$expected" <<<"$auto_vram_output"
done
explicit_vram_output="$(PATH="$TMP/bin:$PATH" "${run[@]}" prompt --dry-run --vram 5.5)"
grep -q -- '--max-vram MTL0=5.5' <<<"$explicit_vram_output"
if "${run[@]}" prompt --dry-run --vram nope >/dev/null 2>&1; then
    echo "expected invalid VRAM budget to fail" >&2; exit 1
fi

fast_output="$("${run[@]}" 'a fast prompt' --dry-run --fast)"
grep -q -- '--width 256 --height 256' <<<"$fast_output"
grep -q -- '--steps 12' <<<"$fast_output"
grep -q -- '--cfg-scale 6.0' <<<"$fast_output"
if grep -q -- '--cache-mode' <<<"$fast_output"; then
    echo "fast profile must not skip denoising steps" >&2; exit 1
fi

# Explicit values override the fast profile even when --fast appears later.
fast_override="$("${run[@]}" prompt --dry-run --width 384 --steps 12 --cfg 2 --fast)"
grep -q -- '--width 384 --height 256' <<<"$fast_override"
grep -q -- '--steps 12' <<<"$fast_override"
grep -q -- '--cfg-scale 2' <<<"$fast_override"

if "${run[@]}" prompt --dry-run --width 500 >/dev/null 2>&1; then
    echo "expected invalid dimensions to fail" >&2; exit 1
fi
if "${run[@]}" prompt --dry-run --reference "$TMP/nope.png" >/dev/null 2>&1; then
    echo "expected missing reference to fail" >&2; exit 1
fi

echo "wrapper tests passed"
