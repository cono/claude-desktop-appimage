#!/usr/bin/env bash
#
# Update the installed Claude Desktop AppImage to the latest GitHub release.
#
# Dependency-light: uses curl or wget against the *public* GitHub API (no `gh`,
# no authentication). This is the single updater used by:
#   - a manual run (`./update.sh`, or `wget .../update.sh && ./update.sh`)
#   - `make update`
#   - the optional systemd user timer installed by `make install`
#     (installed as /opt/claude/update.sh)
#
# Target binary resolution (first match wins):
#   1. $CLAUDE_BIN, if set
#   2. /opt/claude/claude-desktop, if /opt/claude exists (the `make install` layout)
#   3. ./claude-desktop, in the current directory (legacy behaviour)
#
set -euo pipefail

REPO="cono/claude-desktop-appimage"

# --- Resolve target binary -------------------------------------------------
if [ -n "${CLAUDE_BIN:-}" ]; then
    BIN="$CLAUDE_BIN"
elif [ -d /opt/claude ]; then
    BIN="/opt/claude/claude-desktop"
else
    BIN="./claude-desktop"
fi

# --- Detect architecture ---------------------------------------------------
case "$(uname -m)" in
    x86_64 | amd64) ARCH="amd64" ;;
    aarch64 | arm64) ARCH="arm64" ;;
    *) echo "❌ Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

# --- HTTP helpers (curl preferred, wget fallback) --------------------------
fetch() { # url -> stdout
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "$1"
    else
        echo "❌ Need either curl or wget installed." >&2; exit 1
    fi
}
download() { # url dest
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$1" -o "$2"
    else
        wget -qO "$2" "$1"
    fi
}

# --- Find the latest release asset for this architecture -------------------
echo "🔎 Checking latest release of $REPO ($ARCH)…"
API="https://api.github.com/repos/$REPO/releases/latest"
ASSET_URL=$(fetch "$API" \
    | grep -oE '"browser_download_url": *"[^"]+"' \
    | sed -E 's/.*"(https[^"]+)"$/\1/' \
    | grep -iE "${ARCH}\.AppImage$" \
    | head -n1)

if [ -z "$ASSET_URL" ]; then
    echo "❌ Could not find a ${ARCH} AppImage in the latest release of $REPO." >&2
    exit 1
fi
# Derive the version from the asset filename (claude-desktop-<version>-<arch>.AppImage)
VERSION=$(basename "$ASSET_URL" | sed -E 's/^claude-desktop-(.+)-(amd64|arm64)\.AppImage$/\1/')
echo "   Latest release: ${VERSION:-unknown} ($ARCH)"
echo "   Asset: $ASSET_URL"

# --- Download to a temp file, compare, then swap ---------------------------
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
echo "⬇️  Downloading…"
download "$ASSET_URL" "$TMP"
chmod +x "$TMP"

if [ -f "$BIN" ] && cmp -s "$TMP" "$BIN"; then
    echo "✓ Already up to date (${VERSION:-unknown}): $BIN"
    exit 0
fi

mkdir -p "$(dirname "$BIN")"
if [ -f "$BIN" ]; then
    cp -f "$BIN" "$BIN-old"
    echo "↩️  Backed up previous binary to $BIN-old"
fi
mv -f "$TMP" "$BIN"
trap - EXIT
echo "✅ Updated to ${VERSION:-unknown}: $BIN"
