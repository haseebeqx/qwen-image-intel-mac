#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

SOURCE="$TMP/source"
DEST="$TMP/install dir"
RESULT="$TMP/arguments"
mkdir -p "$SOURCE"
cat >"$SOURCE/install.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$RESULT"
EOF
chmod +x "$SOURCE/install.sh"
git -C "$SOURCE" init -q -b main
git -C "$SOURCE" config user.name test
git -C "$SOURCE" config user.email test@example.invalid
git -C "$SOURCE" add install.sh
git -C "$SOURCE" commit -qm initial

RESULT="$RESULT" QWEN_REPOSITORY="$SOURCE" QWEN_INSTALL_DIR="$DEST" \
    "$ROOT/web-install.sh" --accept-license --skip-build

grep -qx -- '--accept-license' "$RESULT"
grep -qx -- '--skip-build' "$RESULT"
[[ -x "$DEST/install.sh" ]]

# A repeated invocation reuses the checkout without cloning over it.
RESULT="$RESULT" QWEN_REPOSITORY="$SOURCE" QWEN_INSTALL_DIR="$DEST" \
    "$ROOT/web-install.sh" --skip-models
grep -qx -- '--skip-models' "$RESULT"

echo "web installer tests passed"
