#!/usr/bin/env bash
set -euo pipefail

MODEL_DIR="${QWEN_MODEL_DIR:-$HOME/.qwen-image}"
accepted=0
editing=0

usage() {
    echo "Usage: $0 --accept-license [--editing] [--model-dir PATH]"
}
while (($#)); do
    case "$1" in
        --accept-license) accepted=1; shift ;;
        --editing) editing=1; shift ;;
        --model-dir) [[ $# -ge 2 ]] || { usage; exit 2; }; MODEL_DIR="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown option $1" >&2; usage; exit 2 ;;
    esac
done

if (( ! accepted )); then
    cat >&2 <<'EOF'
error: model download requires --accept-license.
Read the Qwen Research License Agreement first:
https://huggingface.co/Qwen/Qwen-Image-2.1/blob/main/LICENSE
EOF
    exit 2
fi

mkdir -p "$MODEL_DIR"
headers=()
[[ -n "${HF_TOKEN:-}" ]] && headers=(-H "Authorization: Bearer $HF_TOKEN")

download() {
    local url="$1" name="$2" expected="$3" actual=0
    local path="$MODEL_DIR/$name"
    if [[ -f "$path" ]]; then actual="$(stat -f %z "$path")"; fi
    if (( actual == expected )); then
        echo "Already complete: $name"
        return
    fi
    echo "Downloading $name ($((expected / 1000 / 1000)) MB)..."
    curl --fail --location --retry 6 --retry-all-errors --continue-at - \
        "${headers[@]}" --output "$path" "$url"
    actual="$(stat -f %z "$path")"
    if (( actual != expected )); then
        echo "error: $name has $actual bytes; expected $expected" >&2
        echo "Remove the file and retry if the remote artifact changed." >&2
        exit 1
    fi
}

download \
  "https://huggingface.co/leejet/Qwen-Image-2.1-GGUF/resolve/main/qwen_image_2.1-Q2_K.gguf?download=true" \
  "qwen_image_2.1-Q2_K.gguf" 2561716256

download \
  "https://huggingface.co/Qwen/Qwen3-VL-8B-Instruct-GGUF/resolve/main/Qwen3VL-8B-Instruct-Q4_K_M.gguf?download=true" \
  "Qwen3VL-8B-Instruct-Q4_K_M.gguf" 5027784800

download \
  "https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/vae/qwen_image_2.1_vae_bf16.safetensors?download=true" \
  "qwen_image_2.1_vae_bf16.safetensors" 675509688

if (( editing )); then
    download \
      "https://huggingface.co/Qwen/Qwen3-VL-8B-Instruct-GGUF/resolve/main/mmproj-Qwen3VL-8B-Instruct-Q8_0.gguf?download=true" \
      "mmproj-Qwen3VL-8B-Instruct-Q8_0.gguf" 752289728
fi

echo
echo "Models ready in: $MODEL_DIR"
