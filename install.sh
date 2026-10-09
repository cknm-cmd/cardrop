#!/bin/bash
# cardrop installer.
#   ./install.sh                   install or update
#   ./install.sh --rebuild-helper  also recompile Cardrop.app (macOS will ask for permissions again)
#   ./install.sh --uninstall       remove cardrop (keeps your device list and log)
set -eo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
. "$REPO/libexec/common.sh"

[ "$(uname)" = "Darwin" ] || { echo "cardrop only runs on macOS."; exit 1; }

BIN_LINKS=(/opt/homebrew/bin/cardrop /usr/local/bin/cardrop "$HOME/.local/bin/cardrop")

launchctl bootout "gui/$(id -u)/$CARDROP_LABEL" 2>/dev/null || true

if [ "${1:-}" = "--uninstall" ]; then
    rm -f "$PLIST"
    rm -rf "$APP_PATH"
    for link in "${BIN_LINKS[@]}"; do [ -L "$link" ] && rm -f "$link"; done
    rm -rf "$SUPPORT_DIR"
    echo "cardrop removed."
    echo "Kept your device list ($CONFIG_DIR) and log ($LOG_FILE). Delete them by hand if you like."
    exit 0
fi

echo "Installing cardrop $CARDROP_VERSION"

# 1. Requirements
if ! command -v swiftc >/dev/null; then
    echo "The Xcode Command Line Tools are needed to build the helper app. Install them with:"
    echo "    xcode-select --install"
    exit 1
fi
if ! command -v rclone >/dev/null; then
    if command -v brew >/dev/null; then
        read -r -p "rclone isn't installed. Install it with Homebrew now? [Y/n] " answer
        if [[ "${answer:-Y}" =~ ^[Yy] ]]; then brew install rclone; else echo "cardrop needs rclone."; exit 1; fi
    else
        echo "cardrop needs rclone. Install Homebrew (https://brew.sh), then: brew install rclone"
        exit 1
    fi
fi

# 2. Cardrop.app: built only once, because re-signing it makes macOS ask for permissions again.
if [ ! -x "$HELPER" ] || [ "${1:-}" = "--rebuild-helper" ]; then
    echo "Building Cardrop.app..."
    rm -rf "$APP_PATH"
    mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
    swiftc -O -target "$(uname -m)-apple-macos13.0" "$REPO/helper/CardropHelper.swift" -o "$HELPER"
    cp "$REPO/assets/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
    cat > "$APP_PATH/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>cardrop-helper</string>
    <key>CFBundleIdentifier</key><string>$CARDROP_LABEL</string>
    <key>CFBundleName</key><string>Cardrop</string>
    <key>CFBundleDisplayName</key><string>Cardrop</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$CARDROP_VERSION</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSRemovableVolumesUsageDescription</key><string>Cardrop reads new files from your camera or SD card to upload them.</string>
</dict>
</plist>
EOF
    codesign --force --sign - "$APP_PATH" 2>/dev/null
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_PATH"
fi

# 3. Scripts (outside the app, so updating them doesn't touch its permissions)
mkdir -p "$SUPPORT_DIR" "$DEVICE_STATE_DIR"
cp "$REPO/libexec/common.sh" "$REPO/libexec/cardrop-run.sh" "$REPO/libexec/progress.py" "$REPO/bin/cardrop" "$SUPPORT_DIR/"
cp "$REPO/config/devices.conf.example" "$REPO/config/settings.conf.example" "$SUPPORT_DIR/"
chmod +x "$SUPPORT_DIR/cardrop" "$SUPPORT_DIR/cardrop-run.sh"

# 4. The `cardrop` command
LINKED=""
for link in "${BIN_LINKS[@]}"; do
    dir=$(dirname "$link")
    if [ "$dir" = "$HOME/.local/bin" ]; then mkdir -p "$dir"; fi
    if [ -d "$dir" ] && [ -w "$dir" ]; then
        ln -sf "$SUPPORT_DIR/cardrop" "$link"
        LINKED="$link"
        break
    fi
done

# 5. Config (never overwritten)
mkdir -p "$CONFIG_DIR"
[ -f "$DEVICES_FILE" ] || cp "$REPO/config/devices.conf.example" "$DEVICES_FILE"
cp "$REPO/config/settings.conf.example" "$CONFIG_DIR/settings.conf.example"

# 6. Background job: runs whenever any volume mounts
mkdir -p "$(dirname "$PLIST")"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$CARDROP_LABEL</string>
    <key>ProgramArguments</key>
    <array><string>$HELPER</string></array>
    <key>StartOnMount</key><true/>
    <key>WatchPaths</key>
    <array><string>/Volumes</string></array>
    <key>RunAtLoad</key><true/>
    <key>ProcessType</key><string>Background</string>
</dict>
</plist>
EOF
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo
echo "✅ cardrop is installed."
if [ -n "$LINKED" ]; then
    echo "   Command: $LINKED"
    case ":$PATH:" in *":$(dirname "$LINKED"):"*) ;; *) echo "   (Add $(dirname "$LINKED") to your PATH to use the cardrop command.)" ;; esac
fi
echo
echo "Next steps:"
echo "  1. Connect Google Drive:   cardrop connect gdrive ~/Downloads/client_secret_XXXX.json"
echo "                             (see docs/google-setup.md for creating that file)"
echo "  2. Add your devices:       cardrop config"
echo "  3. Check everything:       cardrop doctor"
