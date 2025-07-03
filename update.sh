#!/bin/bash

set -e

REPO="cono/claude-desktop-appimage"
BINARY_NAME="claude-desktop"
TEMP_DIR=$(mktemp -d -t claude-update-XXXXXX)

echo "Fetching latest release version from $REPO..."

# Get the latest release tag
LATEST_VERSION=$(gh release view --repo "$REPO" --json tagName --jq '.tagName')

if [ -z "$LATEST_VERSION" ]; then
    echo "Error: Could not fetch latest release version"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "Latest version: $LATEST_VERSION"

# Check existing binary hash if it exists
EXISTING_HASH=""
if [ -f "$BINARY_NAME" ]; then
    EXISTING_HASH=$(sha256sum "$BINARY_NAME" | cut -d' ' -f1)
    echo "Existing binary hash: $EXISTING_HASH"
fi

# Download only the amd64 AppImage
echo "Downloading amd64 AppImage..."
cd "$TEMP_DIR"
gh release download "$LATEST_VERSION" --repo "$REPO" --pattern "*amd64*.AppImage" --clobber

DOWNLOADED_FILE=$(find . -name "*.AppImage" | head -1)

if [ -z "$DOWNLOADED_FILE" ]; then
    echo "Error: No amd64 AppImage file found in the release"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "Downloaded: $DOWNLOADED_FILE"

# Check hash of downloaded file
DOWNLOADED_HASH=$(sha256sum "$DOWNLOADED_FILE" | cut -d' ' -f1)
echo "Downloaded binary hash: $DOWNLOADED_HASH"

cd - > /dev/null

# Compare hashes and skip update if they match
if [ -n "$EXISTING_HASH" ] && [ "$EXISTING_HASH" = "$DOWNLOADED_HASH" ]; then
    echo "Binary is already up to date (hashes match)"
    rm -rf "$TEMP_DIR"
    exit 0
fi

echo "Rotating binaries..."
if [ -f "$BINARY_NAME" ]; then
    if [ -f "$BINARY_NAME-old" ]; then
        rm "$BINARY_NAME-old"
        echo "Removed old backup"
    fi
    mv "$BINARY_NAME" "$BINARY_NAME-old"
    echo "Moved current binary to backup"
fi

mv "$TEMP_DIR/$DOWNLOADED_FILE" "$BINARY_NAME"
chmod +x "$BINARY_NAME"

rm -rf "$TEMP_DIR"

echo "Update completed successfully!"
echo "Current binary: $BINARY_NAME"
echo "Previous backup: $BINARY_NAME-old"
echo "Version: $LATEST_VERSION"