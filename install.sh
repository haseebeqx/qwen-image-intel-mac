#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
ACCEPT_LICENSE=0
EDITING=0
BUILD=1
DOWNLOAD=1
FORCE=0

usage() {
    cat <<'EOF'
Usage: ./install.sh --accept-license [options]

Builds the pinned engine, downloads the model files, and installs a qwen-image
command that points to this checkout.

Options:
  --accept-license   confirm acceptance of the Qwen model license (required
                     unless --skip-models is used)
  --editing          also download the image-editing vision projector
  --bin-dir PATH     command install directory (default: ~/.local/bin)
  --skip-build       do not build stable-diffusion.cpp
  --skip-models      do not download model files
  --force            replace an existing qwen-image command in --bin-dir
  -h, --help         show this help
EOF
}

while (($#)); do
    case "$1" in
        --accept-license) ACCEPT_LICENSE=1; shift ;;
        --editing) EDITING=1; shift ;;
        --bin-dir) [[ $# -ge 2 ]] || { echo "error: --bin-dir needs a value" >&2; exit 2; }; BIN_DIR="$2"; shift 2 ;;
        --skip-build) BUILD=0; shift ;;
        --skip-models) DOWNLOAD=0; shift ;;
        --force) FORCE=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown option $1" >&2; usage >&2; exit 2 ;;
    esac
done

if (( DOWNLOAD && ! ACCEPT_LICENSE )); then
    cat >&2 <<'EOF'
error: --accept-license is required before model files can be downloaded.
Read the Qwen Research License Agreement first:
https://huggingface.co/Qwen/Qwen-Image-2.1/blob/main/LICENSE

Use --skip-models if you only want to build and install the command.
EOF
    exit 2
fi

DEST="$BIN_DIR/qwen-image"
if [[ -d "$DEST" && ! -L "$DEST" ]]; then
    echo "error: $DEST is a directory and cannot be replaced" >&2
    exit 1
fi
if [[ -e "$DEST" || -L "$DEST" ]]; then
    if (( ! FORCE )) && [[ "$(readlink "$DEST" 2>/dev/null || true)" != "$ROOT/qwen-image" ]]; then
        echo "error: $DEST already exists (use --force to replace it)" >&2
        exit 1
    fi
fi

"$ROOT/scripts/doctor.sh"
(( BUILD )) && "$ROOT/scripts/build.sh"
if (( DOWNLOAD )); then
    download_args=(--accept-license)
    (( EDITING )) && download_args+=(--editing)
    "$ROOT/scripts/download-models.sh" "${download_args[@]}"
fi

mkdir -p "$BIN_DIR"
rm -f "$DEST"
ln -s "$ROOT/qwen-image" "$DEST"

echo
echo "Installed command: $DEST"
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    shell_name="$(basename "${SHELL:-sh}")"
    echo "Add this directory to PATH (for example, in ~/.${shell_name}rc):"
    printf '  export PATH="%s:$PATH"\n' "$BIN_DIR"
fi
echo "Keep this checkout at: $ROOT"
echo 'Try: qwen-image --help'
