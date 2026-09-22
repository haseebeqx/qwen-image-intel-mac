#!/usr/bin/env bash
set -euo pipefail

REPOSITORY="${QWEN_REPOSITORY:-https://github.com/haseebeqx/qwen-image-intel-mac.git}"
INSTALL_REF="${QWEN_INSTALL_REF:-main}"
INSTALL_DIR="${QWEN_INSTALL_DIR:-${HOME}/.local/share/qwen-image-intel-mac}"

if ! command -v git >/dev/null 2>&1; then
    echo "error: Git is required to install qwen-image" >&2
    exit 1
fi

if [[ -e "$INSTALL_DIR" || -L "$INSTALL_DIR" ]]; then
    if [[ ! -d "$INSTALL_DIR/.git" || ! -x "$INSTALL_DIR/install.sh" ]]; then
        echo "error: $INSTALL_DIR already exists but is not a qwen-image checkout" >&2
        echo "Remove it or choose another location with QWEN_INSTALL_DIR." >&2
        exit 1
    fi

    origin="$(git -C "$INSTALL_DIR" remote get-url origin 2>/dev/null || true)"
    if [[ "$origin" != "$REPOSITORY" ]]; then
        echo "error: $INSTALL_DIR has an unexpected Git origin: ${origin:-<none>}" >&2
        echo "Expected: $REPOSITORY" >&2
        exit 1
    fi
    echo "Using existing checkout: $INSTALL_DIR"
else
    mkdir -p "$(dirname "$INSTALL_DIR")"
    echo "Cloning qwen-image-intel-mac into $INSTALL_DIR"
    git clone --depth 1 --branch "$INSTALL_REF" -- "$REPOSITORY" "$INSTALL_DIR"
fi

exec "$INSTALL_DIR/install.sh" "$@"
