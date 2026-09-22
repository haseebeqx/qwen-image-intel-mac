#!/usr/bin/env bash
set -euo pipefail

RELEASE_REPOSITORY="${QWEN_RELEASE_REPOSITORY:-haseebeqx/qwen-image-intel-mac}"
INSTALL_VERSION="${QWEN_INSTALL_VERSION:-latest}"
INSTALL_DIR="${QWEN_INSTALL_DIR:-${HOME}/.local/share/qwen-image-intel-mac}"
ASSET_NAME="qwen-image-intel-mac-x86_64.tar.gz"

if [[ "$(uname -s)" != Darwin || "$(uname -m)" != x86_64 ]]; then
    echo "error: the prebuilt release requires an Intel Mac" >&2
    exit 1
fi
command -v curl >/dev/null 2>&1 || { echo "error: curl is required to install qwen-image" >&2; exit 1; }
command -v shasum >/dev/null 2>&1 || { echo "error: shasum is required to verify the download" >&2; exit 1; }

if [[ "$INSTALL_VERSION" == latest ]]; then
    release_base="https://github.com/$RELEASE_REPOSITORY/releases/latest/download"
else
    release_base="https://github.com/$RELEASE_REPOSITORY/releases/download/$INSTALL_VERSION"
fi
archive_url="${QWEN_RELEASE_URL:-$release_base/$ASSET_NAME}"
checksum_url="${QWEN_RELEASE_CHECKSUM_URL:-$archive_url.sha256}"

if [[ -e "$INSTALL_DIR" || -L "$INSTALL_DIR" ]]; then
    if [[ ! -d "$INSTALL_DIR" || ( ! -f "$INSTALL_DIR/.qwen-image-release" && ! -d "$INSTALL_DIR/.git" ) ]]; then
        echo "error: $INSTALL_DIR already exists but is not a qwen-image installation" >&2
        echo "Remove it or choose another location with QWEN_INSTALL_DIR." >&2
        exit 1
    fi
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
archive="$tmp/$ASSET_NAME"
checksum="$tmp/$ASSET_NAME.sha256"

echo "Downloading qwen-image release ($INSTALL_VERSION)..."
curl -fL --retry 3 --output "$archive" "$archive_url"
curl -fL --retry 3 --output "$checksum" "$checksum_url"
expected="$(awk 'NR == 1 { print $1 }' "$checksum")"
actual="$(shasum -a 256 "$archive" | awk '{ print $1 }')"
if [[ ! "$expected" =~ ^[[:xdigit:]]{64}$ || "$actual" != "$expected" ]]; then
    echo "error: release checksum verification failed" >&2
    exit 1
fi

stage="$tmp/release"
mkdir -p "$stage"
tar -xzf "$archive" -C "$stage"
[[ -f "$stage/.qwen-image-release" && -x "$stage/install.sh" && -x "$stage/build/bin/sd-cli" ]] || {
    echo "error: release archive is incomplete" >&2
    exit 1
}

mkdir -p "$INSTALL_DIR"
cp -R "$stage"/. "$INSTALL_DIR"/
exec "$INSTALL_DIR/install.sh" --skip-build "$@"
