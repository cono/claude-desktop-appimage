# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository creates AppImage packages for Claude Desktop on Linux by repurposing the Windows installer. The build process downloads the Windows executable, extracts resources, replaces Windows-specific native modules with Linux stubs, and packages everything into a portable AppImage.

## Key Build Commands

- `./build.sh` - Main build script that creates the AppImage
- `./build.sh --clean no` - Build without cleaning intermediate files
- `./build.sh --debug` - Build with debug mode enabled (verbose output)
- `./build.sh --clean no --debug` - Build with no cleanup and debug mode
- `./update.sh` - Downloads the latest release from GitHub (requires `gh` CLI)

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
1. **Version Detection** (`.github/workflows/build-auto.yml:21-89`) - Downloads AMD64 installer, extracts nupkg, parses version from filename
2. **Parallel Building** - AMD64 builds on `ubuntu-latest`, ARM64 builds on `ubuntu-22.04-arm`
3. **Automated Release** - Creates GitHub release with both architecture AppImages when builds succeed

## Build Architecture

The build process follows these steps:

1. **Architecture Detection** (`build.sh:4-27`) - Detects amd64/arm64 and sets appropriate download URLs
2. **Dependency Installation** (`build.sh:122-158`) - Installs required tools (p7zip, wget, icoutils, imagemagick, nodejs/npm)
3. **Electron/Asar Setup** (`build.sh:163-224`) - Installs local Electron and asar tools in `build/` directory
4. **Resource Extraction** (`build.sh:226-276`) - Downloads Windows installer, extracts nupkg, processes icons
5. **App Modification** (`build.sh:278-363`) - Unpacks app.asar, replaces native module, applies title bar fix
6. **AppImage Packaging** (`scripts/build-appimage.sh`) - Creates AppDir structure and builds final AppImage

## Key Files and Structure

- `build.sh` - Main orchestration script
- `scripts/build-appimage.sh` - AppImage-specific packaging logic
- `build/` - Temporary build directory (cleaned by default)
- `build/electron-app/` - Staging area for app files
- `build/claude-extract/` - Extracted Windows installer content
- `.github/workflows/` - GitHub Actions automation

## Native Module Replacement

The core technique involves replacing `claude-native` (Windows-specific) with a stub implementation that provides the same API but with no-op functions. The stub is created at `build.sh:284-290` and includes keyboard key constants and placeholder functions.

## Title Bar Fix

A critical modification is applied at `build.sh:297-337` where minified JavaScript is patched to enable title bars on Linux by changing conditional logic from `if(!VAR1 && VAR2)` to `if(VAR1 && VAR2)`.

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

- Requires Debian-based Linux distribution for local builds
- Build creates both the AppImage and a corresponding .desktop file
- The `--clean` flag controls whether intermediate build files are preserved
- The `--debug` flag enables verbose output by removing `2>/dev/null` redirections
- Update script uses GitHub CLI to fetch latest releases and handles binary rotation
- GitHub Actions automatically handles version detection and release creation
- Manual workflow dispatch allows forcing builds of existing versions and enabling debug mode