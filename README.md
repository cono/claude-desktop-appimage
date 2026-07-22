## Feedback

Please check the [Releases page](https://github.com/cono/claude-desktop-appimage/releases) for the latest builds. Feedback on the packages and the build process is greatly appreciated! Please open an issue if you encounter any problems.

---


***THIS IS AN UNOFFICIAL BUILD SCRIPT (produces only an .AppImage)!***

If you run into an issue with this build script, make an issue here. Don't bug Anthropic about it - they already have enough on their plates.

# Claude Desktop for Linux

This project was inspired by [k3d3's claude-desktop-linux-flake](https://github.com/k3d3/claude-desktop-linux-flake) and their [Reddit post](https://www.reddit.com/r/ClaudeAI/comments/1hgsmpq/i_successfully_ran_claude_desktop_natively_on/) about running Claude Desktop natively on Linux. Their work provided valuable insights into the application's structure and the native bindings implementation.

Supports MCP!

Location of the MCP-configuration file is: `~/.config/Claude/claude_desktop_config.json`

![image](https://github.com/user-attachments/assets/93080028-6f71-48bd-8e59-5149d148cd45)

Supports the Ctrl+Alt+Space popup!
![image](https://github.com/user-attachments/assets/1deb4604-4c06-4e4b-b63f-7f6ef9ef28c1)

Supports the Tray menu! (Screenshot of running on KDE)
![image](https://github.com/user-attachments/assets/ba209824-8afb-437c-a944-b53fd9ecd559)

# Installation

This project uses GitHub Actions to automatically build Claude Desktop AppImages for both AMD64 and ARM64 architectures. **No local building is required** - simply download the pre-built AppImages from the releases page.

## Download Pre-built AppImages

1. Go to the [Releases page](https://github.com/cono/claude-desktop-appimage/releases)
2. Download the appropriate AppImage for your architecture:
   - `claude-desktop-*-amd64.AppImage` for x86_64 systems
   - `claude-desktop-*-arm64.AppImage` for ARM64 systems

## Automatic Updates

The included `update.sh` script downloads the latest release AppImage and swaps
it in. It only needs `curl` (or `wget`) — no GitHub CLI or authentication — and
picks the right architecture (amd64/arm64) automatically.

```bash
# Download and run the update script
wget https://raw.githubusercontent.com/cono/claude-desktop-appimage/main/update.sh
chmod +x update.sh
./update.sh
```

The script will:
- Check the latest release via the public GitHub API
- Download the AppImage for your architecture
- Compare the files to avoid unnecessary swaps
- Back up the current binary as `<binary>-old`
- Make the new binary executable

**Where it updates:** `$CLAUDE_BIN` if set, otherwise `/opt/claude/claude-desktop`
if that directory exists (the [`make install`](#recommended-make-install) layout),
otherwise `./claude-desktop` in the current directory.

**Hands-off updates:** if you installed with `make install`, you were offered a
**systemd user timer** that runs this script daily. Manage it with:

```bash
systemctl --user list-timers 'claude-*'   # see the schedule
systemctl --user start claude-update       # update right now
systemctl --user disable --now claude-update.timer  # stop auto-updates
```

## Local Building (Optional)

If you want to build locally (for development, or to install with full desktop
integration), clone the repo first:

```bash
git clone https://github.com/cono/claude-desktop-appimage.git
cd claude-desktop-appimage
```

### Recommended: `make install`

The easiest way to build **and** integrate on the local machine. It builds the
AppImage in Docker, then sets everything up so the app behaves like a native
install — correct menu entry and window/taskbar icon, working `claude://` login
handler, and (optionally) automatic updates.

```bash
make install
```

This will:
- Build the AppImage in Docker if one isn't already in `./output` (`make build`).
- Create `/opt/claude` owned by your user (asks for `sudo` once for the `/opt` dir).
- Install the AppImage as `/opt/claude/claude-desktop` (backing up any previous
  copy as `claude-desktop-old`).
- Install the app icon into your icon theme and write
  `~/.local/share/applications/com.anthropic.Claude.desktop` (its name matches the
  Wayland `app_id` so your compositor shows the right icon), then register the
  `claude://` handler.
- **Prompt** whether to install a **systemd user timer** that auto-updates the
  AppImage daily (see [Automatic Updates](#automatic-updates)).

Remove everything it installed (config in `~/.config/Claude` is kept):

```bash
make uninstall
```

> **Requirements:** Docker (for the build) and a Linux desktop with the usual
> freedesktop tools. `make install` needs `sudo` only to create `/opt/claude`.
> Run `make help` to list all targets.

### Manual build

Prefer to drive the build yourself:

```bash
# Build the AppImage directly on a Debian-based host (installs build deps)
./build.sh

# ...or build in Docker without installing host deps
make build            # result in ./output
```

`build.sh` will download and extract resources from the Windows version, replace
the platform-specific native module, apply the Linux fixes, and produce the
`.AppImage` (plus a matching `.desktop` file).

**Heads-up:** a bare AppImage installs nothing by itself — running it launches the
app but adds no menu entry or icon, and `claude://` login **will not work** until a
`.desktop` file is registered. Use `make install` above, a tool like
[AppImageLauncher](https://github.com/TheAssassin/AppImageLauncher), or set it up
manually:

1.  **Make the AppImage executable:** `chmod +x ./FILENAME.AppImage`
2.  **Run it:** `./FILENAME.AppImage`
3.  **Integrate manually:** move the `.AppImage` somewhere stable (e.g. `/opt` or
    `~/Applications`) and copy the generated `claude-desktop-appimage.desktop` to
    `~/.local/share/applications/`, editing its `Exec=` line to point at the
    AppImage's location. Then run `update-desktop-database ~/.local/share/applications`.

#### --no-sandbox

The AppImage script runs with electron's --no-sandbox flag. AppImage's don't have their own sandbox. chome-sandbox, which is used by electron, needs to escalate root privileges briefly in order to setup the sandbox. When you pack an AppImage, chrome-sandbox loses any assigned ownership and executes with user permissions. There's also an issue with [unprivileged namespaces](https://www.reddit.com/r/debian/comments/hkyeft/comment/fww5xb1) being set differently on different distributions.

**Alternatives to --no-sandbox**
 - Run claude-desktop as root
   - Doesn't feel warm and fuzzy.
 - Install chrome-sandbox outside of the AppImage(or leverage an existing install), set it with the right permissions, and reference it.
   - Counter-intuitive to the "batteries included" mindset of AppImages
 - Run it with --no-sandbox, but then wrap the whole thing inside another sandbox like bubblewrap
   - Not "batteries included", and configuring in such a way that it runs everywhere is beyond my immediate capabilities.

I'd love a better suggestion. Feel free to submit a PR or start a discussion if I missed something obvious.

# Uninstallation

## Installed with `make install`

From the cloned repository:

```bash
make uninstall
```

This removes `/opt/claude`, the desktop entry, the installed icon, and the
auto-update systemd timer. Your configuration in `~/.config/Claude` is kept
(see below to remove it too).

## AppImage (.AppImage)

If you set it up manually:
1.  Delete the `.AppImage` file.
2.  Delete the associated `.desktop` file (e.g., `claude-desktop-appimage.desktop` from where you placed it, like `~/.local/share/applications/`).
3.  If you used AppImageLauncher, it might offer an option to un-integrate the AppImage.

## Configuration Files (Both Formats)

To remove user-specific configuration files (including MCP settings), regardless of installation method:

```bash
rm -rf ~/.config/Claude
```

# Troubleshooting

Aside from the install logs, runtime logs can be found in (`$HOME/claude-desktop-launcher.log`).

If your window isn't scaling correctly the first time or two you open the application, right click on the claude-desktop panel (taskbar) icon and quit. When doing a safe shutdown like this, the application saves some states to the .config/claude folder which will resolve the issue moving forward. Force quitting the application will not trigger the updates.

# How it works (Debian/Ubuntu Build)

Claude Desktop is an Electron application packaged as a Windows executable. Our build script performs several key operations to make it work on Linux:

1.  Downloads and extracts the Windows installer
2.  Unpacks the `app.asar` archive containing the application code
3.  Replaces the Windows-specific native module with a Linux-compatible stub implementation
4.  Repackages everything into the user's chosen format:
    *   **AppImage (.AppImage):** Creates a self-contained executable using `appimagetool`.

The process works because Claude Desktop is largely cross-platform, with only one platform-specific component that needs replacement.

## Build Process Details

The main build script (`build.sh`) orchestrates the process:

1. Checks for a Debian-based system and required dependencies
2. Parses the `--clean` flag to determine cleanup behavior.
3. Downloads the official Windows installer
4. Extracts the application resources
5. Processes icons for Linux desktop integration
6. Unpacks and modifies the app.asar:
   - Replaces the native mapping module with our Linux version
   - Preserves all other functionality
7. Calls the packaging script (`scripts/build-appimage.sh`) to create the final AppImage.
   *   **For .AppImage:** Creates an AppDir, bundles Electron, generates an `AppRun` script and `.desktop` file, and uses `appimagetool` to create the final `.AppImage`.

## Updating the Build Script

When a new version of Claude Desktop is released, the script attempts to automatically detect the correct download URL based on your system architecture (amd64 or arm64). If the download URLs change significantly in the future, you may need to update the `CLAUDE_DOWNLOAD_URL` variables near the top of `build.sh`. The script should handle the rest of the build process automatically.

# k3d3's Original NixOS Implementation

For NixOS users, please refer to [k3d3's claude-desktop-linux-flake](https://github.com/k3d3/claude-desktop-linux-flake) repository. Their implementation is specifically designed for NixOS and provides the original Nix flake that inspired this project. Go check their repo out if you want some more details about the core process behind this.

# Emsi's Alternative Debian Implementation

Emsi has put together a fork of this repo at [https://github.com/emsi/claude-desktop](https://github.com/emsi/claude-desktop). Aside from approaching the problem much more intelligently than I, his repo collection is full of goodies such as [https://github.com/emsi/MyManus](https://github.com/emsi/MyManus). This repo (aaddrick/claude-desktop-debian) currently relies on his title bar fix to keep the main title bar visible.

# License

The build scripts in this repository, are dual-licensed under the terms of the MIT license and the Apache License (Version 2.0).

See [LICENSE-MIT](LICENSE-MIT) and [LICENSE-APACHE](LICENSE-APACHE) for details.

The Claude Desktop application, not included in this repository, is likely covered by [Anthropic's Consumer Terms](https://www.anthropic.com/legal/consumer-terms).

## Contribution

Unless you explicitly state otherwise, any contribution intentionally submitted
for inclusion in the work by you, as defined in the Apache-2.0 license, shall be dual licensed as above, without any
additional terms or conditions.
