#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

SOURCE="$TMP/source"
DEST="$TMP/install dir"
RESULT="$TMP/arguments"
ASSET="$TMP/qwen-image-intel-mac-x86_64.tar.gz"
mkdir -p "$SOURCE/build/bin" "$SOURCE/scripts" "$TMP/bin"
cat >"$SOURCE/install.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$RESULT"
EOF
printf '#!/usr/bin/env bash\n' >"$SOURCE/build/bin/sd-cli"
printf 'test\n' >"$SOURCE/.qwen-image-release"
chmod +x "$SOURCE/install.sh" "$SOURCE/build/bin/sd-cli"
tar -C "$SOURCE" -czf "$ASSET" .
shasum -a 256 "$ASSET" >"$ASSET.sha256"

# Make the platform check deterministic when these tests run on Linux CI.
cat >"$TMP/bin/uname" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == -s ]]; then echo Darwin; elif [[ "${1:-}" == -m ]]; then echo x86_64; else echo Darwin; fi
EOF
chmod +x "$TMP/bin/uname"

RESULT="$RESULT" PATH="$TMP/bin:$PATH" QWEN_INSTALL_DIR="$DEST" \
QWEN_RELEASE_URL="file://$ASSET" QWEN_RELEASE_CHECKSUM_URL="file://$ASSET.sha256" \
    "$ROOT/web-install.sh"

grep -qx -- '--skip-build' "$RESULT"
[[ "$(wc -l <"$RESULT" | tr -d ' ')" == 1 ]]
[[ -x "$DEST/install.sh" ]]
[[ -x "$DEST/build/bin/sd-cli" ]]

# A repeated invocation updates the release in place and preserves unrelated data.
touch "$DEST/preserved-model"
RESULT="$RESULT" PATH="$TMP/bin:$PATH" QWEN_INSTALL_DIR="$DEST" \
QWEN_RELEASE_URL="file://$ASSET" QWEN_RELEASE_CHECKSUM_URL="file://$ASSET.sha256" \
    "$ROOT/web-install.sh"

grep -qx -- '--skip-build' "$RESULT"
[[ "$(wc -l <"$RESULT" | tr -d ' ')" == 1 ]]
[[ -f "$DEST/preserved-model" ]]

echo "web installer tests passed"
