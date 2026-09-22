#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/models"
for f in qwen_image_2.1-Q2_K.gguf Qwen3VL-8B-Instruct-Q4_K_M.gguf qwen_image_2.1_vae_bf16.safetensors; do printf x >"$TMP/models/$f"; done
cat >"$TMP/sd-cli" <<'EOF'
#!/bin/sh
echo "noisy engine details"
if [ "${QWEN_TEST_PROGRESS:-0}" = 1 ]; then
    printf '[INFO   ] request.cpp - sampling using Euler method\n'
    printf '\r  |=========================                         | 1/2 - 1.00s/it\033[K'
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
verbose_output="$("${run[@]}" 'verbose output' --verbose --output "$TMP/verbose.png")"
grep -q -- 'Engine command:' <<<"$verbose_output"
grep -q -- 'noisy engine details' <<<"$verbose_output"
grep -q -- '--verbose' <<<"$verbose_output"

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
