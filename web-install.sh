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
replacement=""
backup=""
old_moved=0
cleanup() {
    status=$?
    set +e
    if (( old_moved )); then
        rm -rf "$INSTALL_DIR"
        mv "$backup" "$INSTALL_DIR"
    fi
    [[ -z "$replacement" ]] || rm -rf "$replacement"
    rm -rf "$tmp"
    return "$status"
}
trap cleanup EXIT
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

# Build the replacement beside the destination so the final moves stay on the
# same filesystem. Replacing the directory, rather than copying over it, also
# removes files that no longer belong to the release.
install_parent="$(dirname "$INSTALL_DIR")"
mkdir -p "$install_parent"
replacement="$(mktemp -d "$install_parent/.qwen-image-install.XXXXXX")"
cp -R "$stage"/. "$replacement"/

if [[ -e "$INSTALL_DIR" || -L "$INSTALL_DIR" ]]; then
    backup="$(mktemp -d "$install_parent/.qwen-image-backup.XXXXXX")"
    rmdir "$backup"
    mv "$INSTALL_DIR" "$backup"
    old_moved=1
fi
mv "$replacement" "$INSTALL_DIR"
replacement=""

if (( old_moved )); then
    rm -rf "$backup"
    backup=""
    old_moved=0
fi

exec "$INSTALL_DIR/install.sh" --skip-build "$@"
