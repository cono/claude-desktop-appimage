#!/usr/bin/env bash
#
# Install a locally-built Claude Desktop AppImage into /opt/claude and wire up
# desktop integration on the host, so the app gets a proper menu entry, the
# correct window/taskbar icon, and the claude:// URL handler — on ANY setup,
# without depending on AppImageLauncher/appimaged.
#
# What it does:
#   - creates /opt/claude (owned by the invoking user; needs sudo once)
#   - installs the AppImage as /opt/claude/claude-desktop (rotating a backup)
#   - installs the app icon into the hicolor theme
#   - writes ~/.local/share/applications/com.anthropic.Claude.desktop
#     (filename == the Wayland app_id Electron uses, so GNOME matches the window)
#   - registers the claude:// scheme handler and refreshes caches
#   - optionally installs a systemd user timer for daily auto-updates
#
# Usage:
#   scripts/install.sh [PATH_TO_APPIMAGE]     # install (auto-detects output/ if omitted)
#   scripts/install.sh --uninstall            # remove everything this installs
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
# 1) Locate the AppImage to install.
APPIMAGE="${1:-}"
if [ -z "$APPIMAGE" ]; then
    APPIMAGE=$(ls -t "$REPO_ROOT"/output/claude-desktop-*.AppImage 2>/dev/null | head -n1 || true)
fi
if [ -z "$APPIMAGE" ] || [ ! -f "$APPIMAGE" ]; then
    echo "❌ No AppImage found to install." >&2
    echo "   Build one first with 'make build', or pass a path:" >&2
    echo "     scripts/install.sh /path/to/claude-desktop-<ver>-<arch>.AppImage" >&2
    exit 1
fi
echo "📦 Installing: $APPIMAGE"

# 2) Create /opt/claude owned by the current user (needs sudo for /opt).
if [ ! -d "$INSTALL_DIR" ]; then
    echo "🔐 Creating $INSTALL_DIR (sudo required)…"
    sudo mkdir -p "$INSTALL_DIR"
    sudo chown "$USER:$(id -gn)" "$INSTALL_DIR"
elif [ ! -w "$INSTALL_DIR" ]; then
    echo "🔐 Taking ownership of $INSTALL_DIR (sudo required)…"
    sudo chown "$USER:$(id -gn)" "$INSTALL_DIR"
fi

# 3) Install the binary (rotate a backup).
if [ -f "$BIN" ]; then
    cp -f "$BIN" "$BIN-old"
    echo "↩️  Backed up previous binary to $BIN-old"
fi
cp -f "$APPIMAGE" "$BIN"
chmod +x "$BIN"
echo "✓ Installed binary at $BIN"

# 4) Install the icon (extract the AppImage's .DirIcon, a 256x256 PNG).
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

# 5) Desktop entry. The filename equals the Wayland app_id so GNOME matches the
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

# 6) Refresh caches and register the claude:// handler.
refresh_caches
xdg-mime default "$APP_ID.desktop" x-scheme-handler/claude >/dev/null 2>&1 || true
echo "✓ Caches refreshed and claude:// handler registered"

# 7) Optional: systemd user timer for daily auto-updates.
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
    echo "   Disable: systemctl --user disable --now $TIMER"
}

if command -v systemctl >/dev/null 2>&1 && [ -t 0 ]; then
    read -r -p "Install a systemd timer to auto-update Claude daily? [y/N] " ans
    case "${ans:-N}" in
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
