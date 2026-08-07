# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository creates AppImage packages for Claude Desktop on Linux by repurposing the Windows installer. The build process downloads the Windows executable, extracts resources, replaces Windows-specific native modules with Linux stubs, and packages everything into a portable AppImage.

## Key Build Commands

- `./build.sh` - Main build script that creates the AppImage (Debian-based host)
- `./build.sh --clean no` - Build without cleaning intermediate files
- `./build.sh --debug` - Build with debug mode enabled (verbose output)
- `./build.sh --clean no --debug` - Build with no cleanup and debug mode
- `make build` - Build the AppImage in Docker (no host deps; output in `./output`)
- `make install` - Download the latest GitHub release and install to `/opt/claude` with desktop integration; prompts to enable a systemd auto-update timer
- `make install-local` - Build locally (if needed) and install that build to `/opt/claude` (development)
- `make uninstall` - Remove `/opt/claude`, the desktop entry, icon, and update timer
- `make update` - Update the installed AppImage to the latest release now
- `make help` - List all Make targets
- `./update.sh` - Downloads the latest release from GitHub (uses `curl`/`wget` + the public API; no `gh`, arch-aware; targets `/opt/claude/claude-desktop` when present, else CWD)

## Automated Release System

The repository uses GitHub Actions for automatic building and releasing:

### Workflows
- **`build-auto.yml`** - Main automated build workflow that:
  - Runs daily at 10:00 UTC to check for new Claude versions
  - Detects Claude version by downloading and extracting the Windows installer
  - Builds AppImages for both AMD64 and ARM64 architectures in parallel
  - Creates GitHub releases automatically when new versions are detected
  - Can be manually triggered with options to:
    - `create_release`: Create GitHub release (default: true)
    - `force_build`: Force build even if version exists (default: false)
    - `debug`: Enable debug mode with verbose output (default: false)

- **`shellcheck.yml`** - Code quality check for shell scripts on push/PR
- **`codespell.yml`** - Spelling check for documentation on push/PR

### Release Process
1. **Version Detection** (`.github/workflows/build-auto.yml:21-89`) - Fetches RELEASES file from downloads.claude.ai, parses latest version
2. **Parallel Building** - AMD64 builds on `ubuntu-latest`, ARM64 builds on `ubuntu-22.04-arm`
3. **Automated Release** - Creates GitHub release with both architecture AppImages when builds succeed

## Build Architecture

The build process follows these steps:

1. **Architecture Detection** (`build.sh:4-27`) - Detects amd64/arm64 and sets appropriate download parameters
2. **Dependency Installation** (`build.sh:122-158`) - Installs required tools (p7zip, wget, icoutils, imagemagick, nodejs/npm)
3. **Electron/Asar Setup** (`build.sh:163-224`) - Installs local Electron and asar tools in `build/` directory
4. **Resource Extraction** (`build.sh:226-276`) - Fetches RELEASES file from downloads.claude.ai, downloads nupkg directly, processes icons
5. **App Modification** (`build.sh:389-600`) - Unpacks app.asar, replaces native module, patches the minified bundle for Linux
6. **AppImage Packaging** (`scripts/build-appimage.sh`) - Creates AppDir structure and builds final AppImage

## Key Files and Structure

- `build.sh` - Main orchestration script
- `scripts/build-appimage.sh` - AppImage-specific packaging logic
- `build/` - Temporary build directory (cleaned by default)
- `build/electron-app/` - Staging area for app files
- `build/claude-extract/` - Extracted Windows installer content
- `.github/workflows/` - GitHub Actions automation

## Native Module Replacement

The core technique involves replacing `claude-native` (Windows-specific) with a stub implementation that provides the same API but with no-op functions. The stub is created at `build.sh:395-403` and includes keyboard key constants and placeholder functions.

## Bundle Patching (`build.sh:410-600`)

Claude Desktop ships minified JavaScript built for Windows, which has to be patched for Linux. Upstream changes its bundling freely between releases: minified identifiers, chunk file names, which chunk a given function lands in, and even the quote character used for string literals (double quotes up to 1.24012.11, backtick template literals from 1.25927.0). The patches are written to survive that:

- **Anchor only on things minification preserves** - icon file names, Statsig gate ids, Electron API names. Never on minified identifiers.
- **Locate files by content, never by name** (`locate_single_file`) - the tray code lived in `index.chunk-*.js` up to 1.24012.11 and moved into `index.js` in 1.25927.0. Each patch resolves its own file, because they no longer all live together (the context-menu gate now sits in a different chunk from the tray code that calls it).
- **Capture minified names with regex groups** rather than hardcoding them - e.g. the main-window reference is derived from the click target's own `show()`/`focus()` fallback (`exports.mainWindow` up to 1.24012.11, `u.f` in 1.25927.0).
- **Match string literals through `$JS_QUOTE`** so either quote style works.

Three fixes are applied, all tray-related:

1. **Tray icon file names** - Electron's `nativeImage` cannot decode the Windows `.ico` tray images (they load as an empty 0x0 image), so the tray shows a placeholder. Redirected to the bundled `TrayIconLinux*.png`.
2. **Tray left-click** - upstream wires the click to Quick Entry, so on Linux clicking the tray never restores the window. Rewired to show the main window directly, anchored on the adjacent tray-only `right-click` registration so the shared Quick Entry function (Ctrl+Alt+Space) stays intact.
3. **Tray context menu** - upstream hides the native menu behind Statsig gate `1109029378` and falls back to a manual `popUpContextMenu`, which does not work with StatusNotifierItem hosts on Wayland. The gate accessor is forced to return false.

There is also a **non-patching assertion** that the main window is still created with `titleBarStyle: hidden` plus a `titleBarOverlay`, which is why no title-bar patch is needed any more. The old `if(!isWindows && isMainWindow)` sed is gone: the app UI moved out of `app.asar` into a separate `ion-dist` bundle, and that patch had been silently matching nothing since at least 1.24012.11 while still reporting success.

### Every patch must assert it changed something

Each patch counts its anchor before and after `sed` and calls `patch_fail` (exit 1) if the count is wrong, including when an anchor becomes ambiguous across several files. This is deliberate: a patch that quietly matches nothing used to report success and ship a subtly broken AppImage. **Do not "fix" a failing build by loosening or skipping these checks** - a failure means upstream restructured, so re-derive the pattern against the new bundle. Note that `set -euo pipefail` makes a bare `VAR=$(grep ...)` abort the script instantly on no match, which is how a missing anchor previously killed the build with no diagnostic at all.

## AppImage Integration

The AppImage includes:
- Desktop integration via bundled .desktop file with `MimeType=x-scheme-handler/claude;`
- AppImageLauncher support for proper system integration
- Wayland detection and appropriate flags in AppRun script
- Logging to `$HOME/claude-desktop-launcher.log`
- `--no-sandbox` flag to avoid Chrome sandbox issues in AppImage context

## Architecture Support

- AMD64 (`dpkg --print-architecture` = "amd64")
- ARM64 (`dpkg --print-architecture` = "arm64")

Each architecture uses different download URLs for the Windows installer but follows the same build process.

## Configuration Location

MCP configuration file: `~/.config/Claude/claude_desktop_config.json`

## Development Notes

- Requires Debian-based Linux distribution for local builds with `./build.sh`; `make build`/`make install` build inside a Docker container (`docker/Dockerfile`, Ubuntu 24.04) so any host with Docker works
- Build creates both the AppImage and a corresponding .desktop file
- The `--clean` flag controls whether intermediate build files are preserved
- The `--debug` flag enables verbose output by removing `2>/dev/null` redirections
- `make install` (`scripts/install.sh`) downloads the latest release (via `update.sh`) and installs to `/opt/claude` with desktop integration; `make install-local` / `install.sh --local` installs a locally-built AppImage from `./output` instead. It can enable a systemd **user** timer (`systemd/claude-update.{service,timer}`) that runs `update.sh` daily
- `update.sh` fetches latest releases via the public GitHub API using `curl`/`wget` (no `gh`), is architecture-aware, and handles binary rotation (`<binary>-old`)
- GitHub Actions automatically handles version detection and release creation
- Manual workflow dispatch allows forcing builds of existing versions and enabling debug mode