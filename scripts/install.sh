#!/usr/bin/env bash
#
# Install Claude Desktop into /opt/claude and wire up desktop integration on
# the host, so the app gets a proper menu entry, the correct window/taskbar
# icon, and the claude:// URL handler — on ANY setup, without depending on
# AppImageLauncher/appimaged.
#
# By default it DOWNLOADS the latest AppImage from GitHub releases (no local
# build, no Docker needed). Use --local to install a locally-built AppImage
# instead (for development).
#
# What it does:
#   - creates /opt/claude (owned by the invoking user; needs sudo once)
#   - installs the AppImage as /opt/claude/claude-desktop
#       * download mode: via update.sh (latest release, rotates a backup)
#       * --local mode:  copies a local build (rotating a backup)
#   - installs the app icon into the hicolor theme
#   - writes ~/.local/share/applications/com.anthropic.Claude.desktop
#     (filename == the Wayland app_id Electron uses, so GNOME matches the window)
#   - registers the claude:// scheme handler and refreshes caches
#   - optionally installs a systemd user timer for daily auto-updates
#
# Usage:
#   scripts/install.sh                 # download the latest GitHub release and install
#   scripts/install.sh --local         # install the newest AppImage in ./output
#   scripts/install.sh --local PATH    # install a specific local AppImage
#   scripts/install.sh --uninstall     # remove everything this installs
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

APP_ID="com.anthropic.Claude"          # == Wayland app_id Electron derives from desktopName
INSTALL_DIR="/opt/claude"
BIN="$INSTALL_DIR/claude-desktop"
UPDATER="$INSTALL_DIR/update.sh"

APPS_DIR="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
DESKTOP_FILE="$APPS_DIR/$APP_ID.desktop"
ICON_FILE="$ICON_DIR/$APP_ID.png"

UNIT_DIR="$HOME/.config/systemd/user"
TIMER="claude-update.timer"
SERVICE="claude-update.service"

refresh_caches() {
    gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true
    update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--uninstall" ]; then
    echo "🧹 Uninstalling Claude Desktop…"

    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user disable --now "$TIMER" >/dev/null 2>&1 || true
        rm -f "$UNIT_DIR/$TIMER" "$UNIT_DIR/$SERVICE"
        systemctl --user daemon-reload >/dev/null 2>&1 || true
        echo "✓ Removed auto-update timer (if present)"
    fi

    rm -f "$DESKTOP_FILE" "$ICON_FILE"
    refresh_caches
    echo "✓ Removed desktop entry and icon"

    if [ -d "$INSTALL_DIR" ]; then
        rm -rf "$INSTALL_DIR" 2>/dev/null || sudo rm -rf "$INSTALL_DIR"
        echo "✓ Removed $INSTALL_DIR"
    fi

    echo "✅ Uninstalled. (User config in ~/.config/Claude was left untouched.)"
    exit 0
fi

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
# 0) Parse mode: download the latest release (default) or install a local build.
MODE="download"
LOCAL_PATH=""
case "${1:-}" in
    "")      MODE="download" ;;
    --local) MODE="local"; LOCAL_PATH="${2:-}" ;;
    -*)      echo "❌ Unknown option: $1" >&2; exit 1 ;;
    *)       MODE="local"; LOCAL_PATH="$1" ;;
esac

# 1) Create /opt/claude owned by the current user (needs sudo for /opt).
if [ ! -d "$INSTALL_DIR" ]; then
    echo "🔐 Creating $INSTALL_DIR (sudo required)…"
    sudo mkdir -p "$INSTALL_DIR"
    sudo chown "$USER:$(id -gn)" "$INSTALL_DIR"
elif [ ! -w "$INSTALL_DIR" ]; then
    echo "🔐 Taking ownership of $INSTALL_DIR (sudo required)…"
    sudo chown "$USER:$(id -gn)" "$INSTALL_DIR"
fi

# 2) Put the binary in place.
if [ "$MODE" = "download" ]; then
    echo "⬇️  Downloading the latest Claude Desktop release from GitHub…"
    # update.sh downloads the right-arch AppImage into $CLAUDE_BIN and rotates
    # a "<binary>-old" backup. It exits 0 (no-op) if already up to date.
    CLAUDE_BIN="$BIN" bash "$REPO_ROOT/update.sh"
else
    if [ -z "$LOCAL_PATH" ]; then
        LOCAL_PATH=$(find "$REPO_ROOT/output" -maxdepth 1 -name 'claude-desktop-*.AppImage' -printf '%T@ %p\n' 2>/dev/null \
            | sort -rn | head -n1 | cut -d' ' -f2-)
    fi
    if [ -z "$LOCAL_PATH" ] || [ ! -f "$LOCAL_PATH" ]; then
        echo "❌ No local AppImage found to install." >&2
        echo "   Build one first with 'make build', or pass a path:" >&2
        echo "     scripts/install.sh --local /path/to/claude-desktop-<ver>-<arch>.AppImage" >&2
        exit 1
    fi
    echo "📦 Installing local build: $LOCAL_PATH"
    if [ -f "$BIN" ]; then
        cp -f "$BIN" "$BIN-old"
        echo "↩️  Backed up previous binary to $BIN-old"
    fi
    cp -f "$LOCAL_PATH" "$BIN"
    chmod +x "$BIN"
fi
echo "✓ Binary installed at $BIN"

# 3) Install the icon (extract the AppImage's .DirIcon, a 256x256 PNG).
echo "🎨 Installing icon…"
mkdir -p "$ICON_DIR"
TMPX="$(mktemp -d)"
(
    cd "$TMPX"
    APPIMAGE_EXTRACT_AND_RUN=1 "$BIN" --appimage-extract .DirIcon >/dev/null 2>&1 || true
)
if [ -f "$TMPX/squashfs-root/.DirIcon" ]; then
    cp -f "$TMPX/squashfs-root/.DirIcon" "$ICON_FILE"
    echo "✓ Icon installed at $ICON_FILE"
else
    echo "⚠️  Could not extract icon from the AppImage; menu icon may be generic." >&2
fi
rm -rf "$TMPX"

# 4) Desktop entry. The filename equals the Wayland app_id so GNOME matches the
#    window to it (StartupWMClass covers X11 / older matchers too).
echo "📝 Writing desktop entry…"
mkdir -p "$APPS_DIR"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=Claude
Comment=Claude Desktop for Linux
Exec=$BIN --gtk-version=3 %u
Icon=$APP_ID
Type=Application
Terminal=false
Categories=Network;Utility;
MimeType=x-scheme-handler/claude;
StartupWMClass=$APP_ID
EOF
echo "✓ Desktop entry at $DESKTOP_FILE"

# 5) Refresh caches and register the claude:// handler.
refresh_caches
xdg-mime default "$APP_ID.desktop" x-scheme-handler/claude >/dev/null 2>&1 || true
echo "✓ Caches refreshed and claude:// handler registered"

# 6) Optional: systemd user timer for daily auto-updates.
install_timer() {
    cp -f "$REPO_ROOT/update.sh" "$UPDATER"
    chmod +x "$UPDATER"
    mkdir -p "$UNIT_DIR"
    cp -f "$REPO_ROOT/systemd/$SERVICE" "$UNIT_DIR/"
    cp -f "$REPO_ROOT/systemd/$TIMER" "$UNIT_DIR/"
    systemctl --user daemon-reload
    systemctl --user enable --now "$TIMER"
    echo "✓ Auto-update timer enabled (daily)."
    echo "   Status:  systemctl --user list-timers 'claude-*'"
    echo "   Run now: systemctl --user start $SERVICE"
    echo "   Logs:    journalctl --user -u $SERVICE            # add -f to follow, -e to jump to newest"
    echo "   History: journalctl --user -u $SERVICE | grep -E 'Updated to|up to date'   # which version landed when"
    echo "   Disable: systemctl --user disable --now $TIMER"
}

if command -v systemctl >/dev/null 2>&1 && [ -t 0 ]; then
    read -r -p "Install a systemd timer to auto-update Claude daily? [y/N] " reply
    case "${reply:-N}" in
        [yY]*) install_timer ;;
        *) echo "↷ Skipped auto-update timer. Update manually anytime with 'make update'." ;;
    esac
elif command -v systemctl >/dev/null 2>&1; then
    echo "↷ Non-interactive shell; skipping auto-update timer prompt."
    echo "   Enable later by re-running 'make install' in a terminal."
else
    echo "↷ systemd not detected; auto-update timer unavailable. Use 'make update' manually."
fi

echo "✅ Done. Launch Claude from your application menu, or run: $BIN"
