#!/bin/bash
set -euo pipefail

# --- Architecture Detection ---
echo -e "\033[1;36m--- Architecture Detection ---\033[0m"
echo "⚙️ Detecting system architecture..."
HOST_ARCH=$(dpkg --print-architecture)
echo "Detected host architecture: $HOST_ARCH"
cat /etc/os-release && uname -m && dpkg --print-architecture

# Set variables based on detected architecture
CLAUDE_DOWNLOADS_BASE="https://downloads.claude.ai/releases/win32"
if [ "$HOST_ARCH" = "amd64" ]; then
    CLAUDE_ARCH="x64"
    ARCHITECTURE="amd64"
    echo "Configured for amd64 build."
elif [ "$HOST_ARCH" = "arm64" ]; then
    CLAUDE_ARCH="arm64"
    ARCHITECTURE="arm64"
    echo "Configured for arm64 build."
else
    echo "❌ Unsupported architecture: $HOST_ARCH. This script currently supports amd64 and arm64."
    exit 1
fi
echo "Target Architecture (detected): $ARCHITECTURE"
echo -e "\033[1;36m--- End Architecture Detection ---\033[0m"


if [ ! -f "/etc/debian_version" ]; then
    echo "❌ This script requires a Debian-based Linux distribution"
    exit 1
fi

# Check for root user early, but allow override with --allow-root parameter
# We need to do a simple check here before full argument parsing
ALLOW_ROOT_OVERRIDE=false
for arg in "$@"; do
    if [ "$arg" = "--allow-root" ]; then
        ALLOW_ROOT_OVERRIDE=true
        break
    fi
done

if [ "$EUID" -eq 0 ] && [ "$ALLOW_ROOT_OVERRIDE" = false ]; then
   echo "❌ This script should not be run using sudo or as the root user."
   echo "   It will prompt for sudo password when needed for specific actions."
   echo "   Please run as a normal user."
   echo "   Use --allow-root to override this check for testing purposes."
   exit 1
fi

ORIGINAL_USER=$(whoami)
ORIGINAL_HOME=$(getent passwd "$ORIGINAL_USER" | cut -d: -f6)
if [ -z "$ORIGINAL_HOME" ]; then
    echo "❌ Could not determine home directory for user $ORIGINAL_USER."
    exit 1
fi
echo "Running as user: $ORIGINAL_USER (Home: $ORIGINAL_HOME)"

# Install and configure NVM with Node.js LTS to avoid old Node.js issues
echo -e "\033[1;36m--- NVM and Node.js Setup ---\033[0m"
export NVM_DIR="$ORIGINAL_HOME/.nvm"

if [ -d "$NVM_DIR" ]; then
    echo "Found existing NVM installation for user $ORIGINAL_USER"
else
    echo "NVM not found, installing NVM..."
    if wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash; then
        echo "✓ NVM installation completed"
    else
        echo "❌ Failed to install NVM"
        exit 1
    fi
fi

# Source NVM script to activate it
if [ -s "$NVM_DIR/nvm.sh" ]; then
    echo "Activating NVM..."
    # Temporarily disable unbound variable checking for NVM operations
    set +u
    # shellcheck disable=SC1091
    . "$NVM_DIR/nvm.sh" # This loads nvm
    
    # Install and use Node.js LTS
    echo "Installing Node.js LTS via NVM..."
    if nvm install --lts; then
        echo "✓ Node.js LTS installed successfully"
        nvm use --lts
        echo "Using Node.js version: $(node --version)"
        echo "Using npm version: $(npm --version)"
    else
        echo "❌ Failed to install Node.js LTS via NVM"
        set -u  # Re-enable unbound variable checking
        exit 1
    fi
    # Re-enable unbound variable checking
    set -u
else
    echo "❌ NVM script not found after installation"
    exit 1
fi
echo -e "\033[1;36m--- End NVM and Node.js Setup ---\033[0m"


echo "System Information:"
echo "Distribution: $(grep "PRETTY_NAME" /etc/os-release | cut -d'"' -f2)"
echo "Debian version: $(cat /etc/debian_version)"
echo "Target Architecture: $ARCHITECTURE" 
PACKAGE_NAME="claude-desktop"
PROJECT_ROOT="$(pwd)" WORK_DIR="$PROJECT_ROOT/build" APP_STAGING_DIR="$WORK_DIR/electron-app" VERSION="" 

echo -e "\033[1;36m--- Argument Parsing ---\033[0m"
CLEANUP_ACTION="yes"
DEBUG_MODE="no"
ALLOW_ROOT="no"
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -c|--clean)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "❌ Error: Argument for $1 is missing" >&2
                exit 1
            fi
            CLEANUP_ACTION="$2"
            shift 2 ;;
        -d|--debug)
            DEBUG_MODE="yes"
            shift ;;
        --allow-root)
            ALLOW_ROOT="yes"
            shift ;;
        -h|--help)
            echo "Usage: $0 [--clean yes|no] [--debug] [--allow-root]"
            echo "  --clean: Specify whether to clean intermediate build files (yes or no). Default: yes"
            echo "  --debug: Enable debug mode with verbose output. Default: no"
            echo "  --allow-root: Allow running as root user (for testing only). Default: no"
            exit 0 ;;
        *)
            echo "❌ Unknown option: $1" >&2
            echo "Use -h or --help for usage information." >&2
            exit 1 ;;
    esac
done

# Validate arguments
CLEANUP_ACTION=$(echo "$CLEANUP_ACTION" | tr '[:upper:]' '[:lower:]')
if [[ "$CLEANUP_ACTION" != "yes" && "$CLEANUP_ACTION" != "no" ]]; then
    echo "❌ Invalid cleanup option specified: '$CLEANUP_ACTION'. Must be 'yes' or 'no'." >&2
    exit 1
fi

echo "Cleanup intermediate files: $CLEANUP_ACTION"
echo "Debug mode: $DEBUG_MODE"
echo "Allow root: $ALLOW_ROOT"

PERFORM_CLEANUP=false
if [ "$CLEANUP_ACTION" = "yes" ]; then
    PERFORM_CLEANUP=true
fi
echo -e "\033[1;36m--- End Argument Parsing ---\033[0m"
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "❌ $1 not found"
        return 1
    else
        echo "✓ $1 found"
        return 0
    fi
}

echo "Checking system dependencies (excluding Node.js - handled by NVM)..."
DEPS_TO_INSTALL=""
COMMON_DEPS="p7zip wget wrestool icotool convert desktop-file-validate"
APPIMAGE_DEPS=""
ALL_DEPS_TO_CHECK="$COMMON_DEPS $APPIMAGE_DEPS"

for cmd in $ALL_DEPS_TO_CHECK; do
    if ! check_command "$cmd"; then
        case "$cmd" in
            "p7zip") DEPS_TO_INSTALL="$DEPS_TO_INSTALL p7zip-full" ;;
            "wget") DEPS_TO_INSTALL="$DEPS_TO_INSTALL wget" ;;
            "wrestool"|"icotool") DEPS_TO_INSTALL="$DEPS_TO_INSTALL icoutils" ;;
            "convert") DEPS_TO_INSTALL="$DEPS_TO_INSTALL imagemagick" ;;
            "desktop-file-validate") DEPS_TO_INSTALL="$DEPS_TO_INSTALL desktop-file-utils" ;;
        esac
    fi
done

# Check for npx separately since it's now provided by NVM
if ! check_command "npx"; then
    echo "❌ npx not found. Node.js/npm installation via NVM may have failed."
    exit 1
else
    echo "✓ npx found (provided by NVM Node.js installation)"
fi

if [ -n "$DEPS_TO_INSTALL" ]; then
    echo "System dependencies needed: $DEPS_TO_INSTALL"
    echo "Attempting to install using sudo..."
        if ! sudo -v; then
        echo "❌ Failed to validate sudo credentials. Please ensure you can run sudo."
        exit 1
    fi
        if ! sudo apt update; then
        echo "❌ Failed to run 'sudo apt update'."
        exit 1
    fi
    # Here on purpose no "" to expand the 'list', thus
    # shellcheck disable=SC2086
    if ! sudo apt install -y $DEPS_TO_INSTALL; then
         echo "❌ Failed to install dependencies using 'sudo apt install'."
         exit 1
    fi
    echo "✓ System dependencies installed successfully via sudo."
fi

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
mkdir -p "$APP_STAGING_DIR" 
echo -e "\033[1;36m--- Electron & Asar Handling ---\033[0m"
CHOSEN_ELECTRON_MODULE_PATH="" ASAR_EXEC=""

echo "Ensuring local Electron and Asar installation in $WORK_DIR..."
cd "$WORK_DIR"
if [ ! -f "package.json" ]; then
    echo "Creating temporary package.json in $WORK_DIR for local install..."
    echo '{"name":"claude-desktop-build","version":"0.0.1","private":true}' > package.json
fi

ELECTRON_DIST_PATH="$WORK_DIR/node_modules/electron/dist"
ASAR_BIN_PATH="$WORK_DIR/node_modules/.bin/asar"

INSTALL_NEEDED=false
if [ ! -d "$ELECTRON_DIST_PATH" ]; then
    echo "Electron distribution not found."
    INSTALL_NEEDED=true
fi
if [ ! -f "$ASAR_BIN_PATH" ]; then
    echo "Asar binary not found."
    INSTALL_NEEDED=true
fi

if [ "$INSTALL_NEEDED" = true ]; then
    echo "Installing Electron and Asar locally into $WORK_DIR..."
    if ! npm install --no-save electron @electron/asar; then
        echo "❌ Failed to install Electron and/or Asar locally."
        cd "$PROJECT_ROOT"
        exit 1
    fi
    echo "✓ Electron and Asar installation command finished."

    # npm v11 / Node v24 silently skips the Electron binary download in some CI environments.
    # If the dist directory is still missing, download the binary directly from GitHub releases
    # using the version recorded in the installed package.json.
    if [ ! -d "$ELECTRON_DIST_PATH" ]; then
        echo "⚠️ Electron binary not downloaded by npm postinstall. Falling back to direct download..."
        ELECTRON_PKG_VERSION=$(node -pe "require('./node_modules/electron/package.json').version" 2>/dev/null || echo "")
        if [ -z "$ELECTRON_PKG_VERSION" ]; then
            echo "❌ Could not determine Electron version from installed package.json."
            cd "$PROJECT_ROOT"
            exit 1
        fi
        echo "Electron package version: $ELECTRON_PKG_VERSION"
        if [ "$ARCHITECTURE" = "amd64" ]; then
            ELECTRON_LINUX_ARCH="x64"
        else
            ELECTRON_LINUX_ARCH="arm64"
        fi
        ELECTRON_ZIP="electron-v${ELECTRON_PKG_VERSION}-linux-${ELECTRON_LINUX_ARCH}.zip"
        ELECTRON_RELEASE_URL="https://github.com/electron/electron/releases/download/v${ELECTRON_PKG_VERSION}/${ELECTRON_ZIP}"
        echo "Downloading Electron from: $ELECTRON_RELEASE_URL"
        if ! wget -O "$ELECTRON_ZIP" "$ELECTRON_RELEASE_URL"; then
            echo "❌ Failed to download Electron binary from GitHub releases."
            cd "$PROJECT_ROOT"
            exit 1
        fi
        mkdir -p "$ELECTRON_DIST_PATH"
        if ! 7z x -y "$ELECTRON_ZIP" -o"$ELECTRON_DIST_PATH"; then
            echo "❌ Failed to extract Electron binary."
            cd "$PROJECT_ROOT"
            exit 1
        fi
        rm -f "$ELECTRON_ZIP"
        chmod +x "$ELECTRON_DIST_PATH/electron"
        echo "✓ Electron binary downloaded and extracted successfully."
    fi
else
    echo "✓ Local Electron distribution and Asar binary already present."
fi

if [ -d "$ELECTRON_DIST_PATH" ]; then
    echo "✓ Found Electron distribution directory at $ELECTRON_DIST_PATH."
    CHOSEN_ELECTRON_MODULE_PATH="$(realpath "$WORK_DIR/node_modules/electron")"
    echo "✓ Setting Electron module path for copying to $CHOSEN_ELECTRON_MODULE_PATH."
else
    echo "❌ Failed to find Electron distribution directory at '$ELECTRON_DIST_PATH' after installation attempt."
    echo "   Cannot proceed without the Electron distribution files."
    cd "$PROJECT_ROOT"
    exit 1
fi

if [ -f "$ASAR_BIN_PATH" ]; then
    ASAR_EXEC="$(realpath "$ASAR_BIN_PATH")"
    echo "✓ Found local Asar binary at $ASAR_EXEC."
else
    echo "❌ Failed to find Asar binary at '$ASAR_BIN_PATH' after installation attempt."
    cd "$PROJECT_ROOT"
    exit 1
fi

cd "$PROJECT_ROOT" 
if [ -z "$CHOSEN_ELECTRON_MODULE_PATH" ] || [ ! -d "$CHOSEN_ELECTRON_MODULE_PATH" ]; then
     echo "❌ Critical error: Could not resolve a valid Electron module path to copy."
     exit 1
fi
echo "Using Electron module path: $CHOSEN_ELECTRON_MODULE_PATH"
echo "Using asar executable: $ASAR_EXEC"


echo -e "\033[1;36m--- Download Claude Desktop nupkg ---\033[0m"
echo "📥 Fetching latest version info for $ARCHITECTURE..."
RELEASES_URL="$CLAUDE_DOWNLOADS_BASE/$CLAUDE_ARCH/RELEASES"
RELEASES_CONTENT=$(wget -qO- "$RELEASES_URL")
if [ -z "$RELEASES_CONTENT" ]; then
    echo "❌ Failed to fetch RELEASES file from $RELEASES_URL"
    exit 1
fi

# Get the latest full nupkg entry (last -full.nupkg line)
LATEST_ENTRY=$(echo "$RELEASES_CONTENT" | grep -- "-full.nupkg" | tail -1)
if [ -z "$LATEST_ENTRY" ]; then
    echo "❌ Could not find a -full.nupkg entry in RELEASES file"
    exit 1
fi

NUPKG_SHA1=$(echo "$LATEST_ENTRY" | awk '{print $1}' | tr -d '\r\n' | sed 's/^\xEF\xBB\xBF//')
NUPKG_FILENAME=$(echo "$LATEST_ENTRY" | awk '{print $2}')
VERSION=$(echo "$NUPKG_FILENAME" | LC_ALL=C grep -oP 'AnthropicClaude-\K[0-9]+\.[0-9]+\.[0-9]+(?=-full)')
if [ -z "$VERSION" ]; then
    echo "❌ Could not extract version from nupkg filename: $NUPKG_FILENAME"
    exit 1
fi
echo "✓ Detected Claude version: $VERSION (nupkg: $NUPKG_FILENAME)"

CLAUDE_EXTRACT_DIR="$WORK_DIR/claude-extract"
mkdir -p "$CLAUDE_EXTRACT_DIR"

echo "📥 Downloading $NUPKG_FILENAME..."
NUPKG_DOWNLOAD_URL="$CLAUDE_DOWNLOADS_BASE/$CLAUDE_ARCH/$NUPKG_FILENAME"
NUPKG_PATH="$CLAUDE_EXTRACT_DIR/$NUPKG_FILENAME"
if ! wget -O "$NUPKG_PATH" "$NUPKG_DOWNLOAD_URL"; then
    echo "❌ Failed to download nupkg from $NUPKG_DOWNLOAD_URL"
    exit 1
fi

# Verify SHA1 integrity
echo "Verifying SHA1 checksum..."
ACTUAL_SHA1=$(sha1sum "$NUPKG_PATH" | awk '{print toupper($1)}')
if [ "$ACTUAL_SHA1" != "$NUPKG_SHA1" ]; then
    echo "❌ SHA1 mismatch! Expected: $NUPKG_SHA1, Got: $ACTUAL_SHA1"
    exit 1
fi
echo "✓ SHA1 checksum verified"

echo "📦 Extracting nupkg..."
cd "$CLAUDE_EXTRACT_DIR"
if ! 7z x -y "$NUPKG_FILENAME"; then
    echo "❌ Failed to extract nupkg"
    cd "$PROJECT_ROOT" && exit 1
fi
echo "✓ Resources extracted from nupkg"

EXE_RELATIVE_PATH="lib/net45/claude.exe" # Check if this path is correct for arm64 too
if [ ! -f "$EXE_RELATIVE_PATH" ]; then
    echo "❌ Cannot find claude.exe at expected path within extraction dir: $CLAUDE_EXTRACT_DIR/$EXE_RELATIVE_PATH"
    cd "$PROJECT_ROOT" && exit 1
fi
echo "🎨 Processing icons from $EXE_RELATIVE_PATH..."
if ! wrestool -x -t 14 "$EXE_RELATIVE_PATH" -o claude.ico; then     echo "❌ Failed to extract icons from exe"
    cd "$PROJECT_ROOT" && exit 1
fi

if ! icotool -x claude.ico; then     echo "❌ Failed to convert icons"
    cd "$PROJECT_ROOT" && exit 1
fi
cp claude_*.png "$WORK_DIR/"
echo "✓ Icons processed and copied to $WORK_DIR"

echo "⚙️ Processing app.asar..."
cp "$CLAUDE_EXTRACT_DIR/lib/net45/resources/app.asar" "$APP_STAGING_DIR/"
cp -a "$CLAUDE_EXTRACT_DIR/lib/net45/resources/app.asar.unpacked" "$APP_STAGING_DIR/" 
cd "$APP_STAGING_DIR" 
"$ASAR_EXEC" extract app.asar app.asar.contents

echo "Creating stub native module..."
mkdir -p app.asar.contents/node_modules/claude-native
cat > app.asar.contents/node_modules/claude-native/index.js << 'MODULE_EOF'
// Stub implementation of claude-native using KeyboardKey enum values
const KeyboardKey = { Backspace: 43, Tab: 280, Enter: 261, Shift: 272, Control: 61, Alt: 40, CapsLock: 56, Escape: 85, Space: 276, PageUp: 251, PageDown: 250, End: 83, Home: 154, LeftArrow: 175, UpArrow: 282, RightArrow: 262, DownArrow: 81, Delete: 79, Meta: 187 };
Object.freeze(KeyboardKey);
const AuthRequest = { isAvailable: () => false };
module.exports = { getWindowsVersion: () => "10.0.0", setWindowEffect: () => {}, removeWindowEffect: () => {}, getIsMaximized: () => false, flashFrame: () => {}, clearFlashFrame: () => {}, showNotification: () => {}, setProgressBar: () => {}, clearProgressBar: () => {}, setOverlayIcon: () => {}, clearOverlayIcon: () => {}, getActiveWindowHandle: () => null, focusWindow: () => {}, readCfPrefValue: () => null, readRegistryValues: () => [], getAppInfoForFile: () => null, AuthRequest, KeyboardKey };
MODULE_EOF

mkdir -p app.asar.contents/resources
mkdir -p app.asar.contents/resources/i18n
cp "$CLAUDE_EXTRACT_DIR/lib/net45/resources/Tray"* app.asar.contents/resources/
cp "$CLAUDE_EXTRACT_DIR/lib/net45/resources/"*-*.json app.asar.contents/resources/i18n/

echo "##############################################################"
echo "Patching the minified app bundle for Linux"
echo ""
echo "Claude Desktop ships minified JavaScript built for Windows. Between"
echo "upstream releases the local identifiers, the chunk file names, which"
echo "chunk a given function lands in, and even the quote character used for"
echo "string literals all change. Every patch below therefore anchors only on"
echo "things that survive minification -- icon file names, Statsig gate ids,"
echo "Electron API names -- locates its file by content rather than by name,"
echo "and captures minified identifiers with regex groups instead of"
echo "hardcoding them."
echo ""
echo "Every patch asserts that it actually changed something. A patch that"
echo "quietly matched nothing used to still report success and ship a subtly"
echo "broken AppImage, so an unmatched anchor is now a hard build failure."

VITE_BUILD_DIR="app.asar.contents/.vite/build"

# Quote characters the minifier is known to emit for string literals: releases
# up to 1.24012.11 used double quotes, 1.25927.0 switched to backtick template
# literals. Match every literal through this class so either style works.
JS_QUOTE='["`]'

patch_fail() {
  echo "" >&2
  echo "❌ Bundle patch anchor did not match: $1" >&2
  echo "" >&2
  echo "   Claude Desktop $VERSION has most likely restructured its bundle." >&2
  echo "   Inspect $APP_STAGING_DIR/app.asar.contents and update the patterns" >&2
  echo "   in build.sh. Do not loosen these checks to get a green build: a" >&2
  echo "   patch that silently does nothing ships a broken tray or window." >&2
  exit 1
}

# Count how many times an ERE matches inside a file. grep exits 1 when nothing
# matches, and zero is a meaningful answer for the callers below (they assert
# the count both before and after patching), so it is reported as 0 rather
# than treated as an error.
count_matches() {
  local file="$1" regex="$2" output
  if output=$(grep -oE -- "$regex" "$file"); then
    printf '%s' "$output" | grep -c .
  else
    printf '0'
  fi
}

# Same, for a literal (non-regex) string.
count_literal() {
  local file="$1" literal="$2" output
  if output=$(grep -oF -- "$literal" "$file"); then
    printf '%s' "$output" | grep -c .
  else
    printf '0'
  fi
}

# Locate the one file under .vite/build/ whose contents match an ERE and report
# it in FOUND_FILE. Files are always found by content because code migrates
# between chunks: the tray code lived in index.chunk-*.js up to 1.24012.11 and
# moved into index.js in 1.25927.0, and the context-menu gate now sits in a
# different chunk from the tray code that consumes it.
FOUND_FILE=""
locate_single_file() {
  local description="$1" regex="$2" file
  local -a matches=()
  for file in "$VITE_BUILD_DIR"/*.js; do
    if grep -qE -- "$regex" "$file"; then
      matches+=("$file")
    fi
  done
  if [ "${#matches[@]}" -ne 1 ]; then
    patch_fail "$description (expected exactly 1 matching file, found ${#matches[@]})"
  fi
  FOUND_FILE="${matches[0]}"
  echo "  file: $(basename "$FOUND_FILE")"
}

echo ""
echo "--- Check: upstream still draws its own window controls ---"
# Older builds needed an 'if (!isWindows && isMainWindow) return null;' patch
# in the renderer to get a title bar on Linux. That code is gone -- the app UI
# moved out of app.asar into a separate ion-dist bundle, and the main window is
# now created with titleBarStyle 'hidden' plus a titleBarOverlay, so Electron
# draws usable window controls on Linux without any patching. That patch had in
# fact silently matched nothing since at least 1.24012.11 while still reporting
# success, so it is gone; this asserts the upstream behaviour that replaced it,
# so a release that returns to a Windows-only title bar fails the build instead
# of producing a window that cannot be closed.
locate_single_file "main window titleBarStyle/titleBarOverlay options" \
  "titleBarStyle:${JS_QUOTE}hidden${JS_QUOTE},titleBarOverlay:"
echo "  ✓ main window still uses a hidden title bar with window controls overlay"

echo ""
echo "--- Fix 1/3: tray icon file names ---"
# Electron's nativeImage cannot decode the Windows .ico tray images (they load
# as an empty 0x0 image), so the tray registers with no icon and the system
# tray shows a placeholder. The selector switches on a build-time constant that
# stays "ico" on this Windows build, so redirect the file names to the Linux
# PNGs that ship alongside them (TrayIconLinux*.png), which decode fine.
# Only the file names are matched, so the minifier's quote style is irrelevant.
TRAY_ICON_RE="${JS_QUOTE}Tray-Win32(-Dark)?\.ico${JS_QUOTE}"
locate_single_file "tray icon selector" "$TRAY_ICON_RE"
TRAY_ICON_JS="$FOUND_FILE"

ICON_COUNT=$(count_matches "$TRAY_ICON_JS" "$TRAY_ICON_RE")
if [ "$ICON_COUNT" -ne 2 ]; then
  patch_fail "tray icon selector (expected 2 .ico literals, found $ICON_COUNT)"
fi
# Dark variant first so it isn't partially matched by the non-dark rule.
sed -i -E "s/(${JS_QUOTE})Tray-Win32-Dark\.ico(${JS_QUOTE})/\1TrayIconLinux-Dark.png\2/g; s/(${JS_QUOTE})Tray-Win32\.ico(${JS_QUOTE})/\1TrayIconLinux.png\2/g" "$TRAY_ICON_JS"
ICON_COUNT=$(count_matches "$TRAY_ICON_JS" "$TRAY_ICON_RE")
if [ "$ICON_COUNT" -ne 0 ]; then
  patch_fail "tray icon selector still has $ICON_COUNT .ico literals after patching"
fi
echo "  ✓ redirected Tray-Win32*.ico to TrayIconLinux*.png"

echo ""
echo "--- Fix 2/3: tray left-click restores the main window ---"
# Upstream wires the tray click to the Quick Entry popup, falling back to the
# main window only if the popup fails to show, so on Linux clicking the tray
# never brings the window back. Rewire ONLY the tray click handler. The
# adjacent tray-only '<var>.on("right-click"' is part of the anchor so the
# shared Quick Entry function is left intact (Ctrl+Alt+Space must keep working).
TRAY_CLICK_RE="([A-Za-z0-9_\$]+)\.on\(${JS_QUOTE}click${JS_QUOTE},\(\)=>void ([A-Za-z0-9_\$]+)\(\)\),\1\.on\(${JS_QUOTE}right-click${JS_QUOTE}"
locate_single_file "tray left-click handler" "$TRAY_CLICK_RE"
TRAY_CLICK_JS="$FOUND_FILE"

CLICK_COUNT=$(count_matches "$TRAY_CLICK_JS" "$TRAY_CLICK_RE")
if [ "$CLICK_COUNT" -ne 1 ]; then
  patch_fail "tray left-click handler (expected 1 registration, found $CLICK_COUNT)"
fi

# Derive the main-window reference from the click target's own fallback
# (<mw>&&!<mw>.isDestroyed()&&(<mw>.show(),<mw>.focus())) rather than
# hardcoding it: it was 'exports.mainWindow' up to 1.24012.11 and is a minified
# module reference such as 'u.f' from 1.25927.0 on.
TRAY_MW_RE='([A-Za-z0-9_$]+\.[A-Za-z0-9_$]+)\.isDestroyed\(\)&&\(\1\.show\(\),\1\.focus\(\)\)'
TRAY_MAIN_WINDOW=""
if TRAY_MW_MATCH=$(grep -oE -- "$TRAY_MW_RE" "$TRAY_CLICK_JS"); then
  TRAY_MAIN_WINDOW=$(printf '%s' "$TRAY_MW_MATCH" | head -1 | sed -E 's/\.isDestroyed.*//')
fi
if [ -z "$TRAY_MAIN_WINDOW" ]; then
  patch_fail "main window show/focus expression (needed to rewire the tray click)"
fi
echo "  main window reference: $TRAY_MAIN_WINDOW"

TRAY_CLICK_NEW="()=>void(${TRAY_MAIN_WINDOW}&&!${TRAY_MAIN_WINDOW}.isDestroyed()&&(${TRAY_MAIN_WINDOW}.show(),${TRAY_MAIN_WINDOW}.focus()))"
# '&' is the whole-match reference in a sed replacement, so escape it.
sed -i -E "s/(${JS_QUOTE})click\1,\(\)=>void [A-Za-z0-9_\$]+\(\)(\),[A-Za-z0-9_\$]+\.on\(\1right-click\1)/\1click\1,${TRAY_CLICK_NEW//&/\\&}\2/" "$TRAY_CLICK_JS"

CLICK_COUNT=$(count_matches "$TRAY_CLICK_JS" "$TRAY_CLICK_RE")
if [ "$CLICK_COUNT" -ne 0 ]; then
  patch_fail "tray left-click handler was not rewritten"
fi
CLICK_COUNT=$(count_literal "$TRAY_CLICK_JS" "$TRAY_CLICK_NEW")
if [ "$CLICK_COUNT" -ne 1 ]; then
  patch_fail "expected exactly 1 rewritten tray click handler, found $CLICK_COUNT"
fi
echo "  ✓ tray left-click now shows $TRAY_MAIN_WINDOW directly"

echo ""
echo "--- Fix 3/3: tray context menu ---"
# Upstream gates the native context menu behind a Statsig feature flag (gate id
# 1109029378); when the gate is on it calls Tray.setContextMenu(null) and relies
# on a manual popUpContextMenu on right-click, which does not work with
# StatusNotifierItem hosts on Wayland -> the tray menu is empty. Force that
# gate's accessor to return false so the real menu (Open/Quit/...) is installed
# via setContextMenu. The gate id is a stable source string; the accessor name
# and its callee are minified, and the accessor may live in a different chunk
# from the tray code that calls it, so it is located independently.
# Matching 'return <callee>(<id>)' deliberately excludes the plain
# gate-change listener registration that uses the same id.
TRAY_GATE_RE="return [A-Za-z0-9_\$]+(\.[A-Za-z0-9_\$]+)*\(${JS_QUOTE}1109029378${JS_QUOTE}\)"
locate_single_file "tray context-menu feature gate accessor" "$TRAY_GATE_RE"
TRAY_GATE_JS="$FOUND_FILE"

GATE_COUNT=$(count_matches "$TRAY_GATE_JS" "$TRAY_GATE_RE")
if [ "$GATE_COUNT" -ne 1 ]; then
  patch_fail "tray context-menu gate accessor (expected 1, found $GATE_COUNT)"
fi
sed -i -E "s/${TRAY_GATE_RE}/return !1/" "$TRAY_GATE_JS"
GATE_COUNT=$(count_matches "$TRAY_GATE_JS" "$TRAY_GATE_RE")
if [ "$GATE_COUNT" -ne 0 ]; then
  patch_fail "tray context-menu gate accessor was not patched"
fi
echo "  ✓ forced tray context-menu gate off (native menu enabled)"

echo ""
echo "✓ All bundle patches applied and verified"
echo "##############################################################"

"$ASAR_EXEC" pack app.asar.contents app.asar

mkdir -p "$APP_STAGING_DIR/app.asar.unpacked/node_modules/claude-native"
cat > "$APP_STAGING_DIR/app.asar.unpacked/node_modules/claude-native/index.js" << 'MODULE_EOF'
// Stub implementation of claude-native using KeyboardKey enum values
const KeyboardKey = { Backspace: 43, Tab: 280, Enter: 261, Shift: 272, Control: 61, Alt: 40, CapsLock: 56, Escape: 85, Space: 276, PageUp: 251, PageDown: 250, End: 83, Home: 154, LeftArrow: 175, UpArrow: 282, RightArrow: 262, DownArrow: 81, Delete: 79, Meta: 187 };
Object.freeze(KeyboardKey);
const AuthRequest = { isAvailable: () => false };
module.exports = { getWindowsVersion: () => "10.0.0", setWindowEffect: () => {}, removeWindowEffect: () => {}, getIsMaximized: () => false, flashFrame: () => {}, clearFlashFrame: () => {}, showNotification: () => {}, setProgressBar: () => {}, clearProgressBar: () => {}, setOverlayIcon: () => {}, clearOverlayIcon: () => {}, getActiveWindowHandle: () => null, focusWindow: () => {}, readCfPrefValue: () => null, readRegistryValues: () => [], getAppInfoForFile: () => null, AuthRequest, KeyboardKey };
MODULE_EOF

echo "Copying chosen electron installation to staging area..."
mkdir -p "$APP_STAGING_DIR/node_modules/"
ELECTRON_DIR_NAME=$(basename "$CHOSEN_ELECTRON_MODULE_PATH")
echo "Copying from $CHOSEN_ELECTRON_MODULE_PATH to $APP_STAGING_DIR/node_modules/"
cp -a "$CHOSEN_ELECTRON_MODULE_PATH" "$APP_STAGING_DIR/node_modules/" 
STAGED_ELECTRON_BIN="$APP_STAGING_DIR/node_modules/$ELECTRON_DIR_NAME/dist/electron"
if [ -f "$STAGED_ELECTRON_BIN" ]; then
    echo "Setting executable permission on staged Electron binary: $STAGED_ELECTRON_BIN"
    chmod +x "$STAGED_ELECTRON_BIN"
else
    echo "Warning: Staged Electron binary not found at expected path: $STAGED_ELECTRON_BIN"
fi

echo "✓ app.asar processed and staged in $APP_STAGING_DIR"

cd "$PROJECT_ROOT"

echo -e "\033[1;36m--- Call Packaging Script ---\033[0m"
FINAL_OUTPUT_PATH="" FINAL_DESKTOP_FILE_PATH="" 
echo "📦 Calling AppImage packaging script for $ARCHITECTURE..."
chmod +x scripts/build-appimage.sh
if ! scripts/build-appimage.sh \
    "$VERSION" "$ARCHITECTURE" "$WORK_DIR" "$APP_STAGING_DIR" "$PACKAGE_NAME" "$DEBUG_MODE"; then
    echo "❌ AppImage packaging script failed."
    exit 1
fi
APPIMAGE_FILE=$(find "$WORK_DIR" -maxdepth 1 -name "${PACKAGE_NAME}-${VERSION}-${ARCHITECTURE}.AppImage" | head -n 1)
echo "✓ AppImage Build complete!"
if [ -n "$APPIMAGE_FILE" ] && [ -f "$APPIMAGE_FILE" ]; then
    FINAL_OUTPUT_PATH="./$(basename "$APPIMAGE_FILE")"
    mv "$APPIMAGE_FILE" "$FINAL_OUTPUT_PATH"
    echo "Package created at: $FINAL_OUTPUT_PATH"

    echo -e "\033[1;36m--- Generate .desktop file for AppImage ---\033[0m"
    FINAL_DESKTOP_FILE_PATH="./${PACKAGE_NAME}-appimage.desktop"
    echo "📝 Generating .desktop file for AppImage at $FINAL_DESKTOP_FILE_PATH..."
    cat > "$FINAL_DESKTOP_FILE_PATH" << EOF
[Desktop Entry]
Name=Claude (AppImage)
Comment=Claude Desktop (AppImage Version $VERSION)
Exec=$(basename "$FINAL_OUTPUT_PATH") %u
Icon=claude-desktop
Type=Application
Terminal=false
Categories=Office;Utility;Network;
MimeType=x-scheme-handler/claude;
StartupWMClass=com.anthropic.Claude
X-AppImage-Version=$VERSION
X-AppImage-Name=Claude Desktop (AppImage)
EOF
    echo "✓ .desktop file generated."

else
    echo "Warning: Could not determine final .AppImage file path from $WORK_DIR for ${ARCHITECTURE}."
    FINAL_OUTPUT_PATH="Not Found"
fi

echo "📦 Calling AppImage packaging script for $ARCHITECTURE..."
chmod +x scripts/build-appimage.sh
if ! scripts/build-appimage.sh \
    "$VERSION" "$ARCHITECTURE" "$WORK_DIR" "$APP_STAGING_DIR" "$PACKAGE_NAME" "$DEBUG_MODE"; then
    echo "❌ AppImage packaging script failed."
    exit 1
fi
APPIMAGE_FILE=$(find "$WORK_DIR" -maxdepth 1 -name "${PACKAGE_NAME}-${VERSION}-${ARCHITECTURE}.AppImage" | head -n 1)
echo "✓ AppImage Build complete!"
if [ -n "$APPIMAGE_FILE" ] && [ -f "$APPIMAGE_FILE" ]; then
    FINAL_OUTPUT_PATH="./$(basename "$APPIMAGE_FILE")" 
    mv "$APPIMAGE_FILE" "$FINAL_OUTPUT_PATH"
    echo "Package created at: $FINAL_OUTPUT_PATH"

    echo -e "\033[1;36m--- Generate .desktop file for AppImage ---\033[0m"
    FINAL_DESKTOP_FILE_PATH="./${PACKAGE_NAME}-appimage.desktop"
    echo "📝 Generating .desktop file for AppImage at $FINAL_DESKTOP_FILE_PATH..."
    cat > "$FINAL_DESKTOP_FILE_PATH" << EOF
[Desktop Entry]
Name=Claude (AppImage)
Comment=Claude Desktop (AppImage Version $VERSION)
Exec=$(basename "$FINAL_OUTPUT_PATH") %u
Icon=claude-desktop
Type=Application
Terminal=false
Categories=Office;Utility;Network;
MimeType=x-scheme-handler/claude;
StartupWMClass=com.anthropic.Claude
X-AppImage-Version=$VERSION
X-AppImage-Name=Claude Desktop (AppImage)
EOF
    echo "✓ .desktop file generated."

else
    echo "Warning: Could not determine final .AppImage file path from $WORK_DIR for ${ARCHITECTURE}."
    FINAL_OUTPUT_PATH="Not Found"
fi


echo -e "\033[1;36m--- Cleanup ---\033[0m"
if [ "$PERFORM_CLEANUP" = true ]; then
    echo "🧹 Cleaning up intermediate build files in $WORK_DIR..."
    if rm -rf "$WORK_DIR"; then
        echo "✓ Cleanup complete ($WORK_DIR removed)."
    else
        echo "⚠️ Cleanup command (rm -rf $WORK_DIR) failed."
    fi
else
    echo "Skipping cleanup of intermediate build files in $WORK_DIR."
fi


echo "✅ Build process finished."


echo -e "\n\033[1;34m====== Next Steps ======\033[0m"
if [ "$FINAL_OUTPUT_PATH" != "Not Found" ] && [ -e "$FINAL_OUTPUT_PATH" ]; then
    echo -e "✅ AppImage created at: \033[1;36m$FINAL_OUTPUT_PATH\033[0m"
    echo -e "\n\033[1;33mIMPORTANT:\033[0m This AppImage requires \033[1;36mAppImageLauncher\033[0m for proper desktop integration"
    echo -e "and to handle the \`claude://\` login process correctly."
    echo -e "\n🚀 To install AppImageLauncher:"
    echo -e "   1. Download the appropriate package from:"
    echo -e "      \033[1;34mhttps://github.com/TheAssassin/AppImageLauncher/releases/latest\033[0m"
    echo -e "   2. Install using your distribution's package manager"
    echo -e "   3. Or use your distribution's package repository if available"
    echo -e "\n   After installation, simply double-click \033[1;36m$FINAL_OUTPUT_PATH\033[0m and choose 'Integrate and run'."
else
    echo -e "⚠️ AppImage file not found. Cannot provide usage instructions."
fi
echo -e "\033[1;34m======================\033[0m"
exit 0
