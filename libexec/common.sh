# Shared paths, settings and helpers for cardrop. Sourced by the CLI, the worker and the installer.

CARDROP_VERSION="1.2.0"
CARDROP_LABEL="io.github.cknm-cmd.cardrop"

CONFIG_DIR="$HOME/.config/cardrop"
DEVICES_FILE="$CONFIG_DIR/devices.conf"
SETTINGS_FILE="$CONFIG_DIR/settings.conf"

SUPPORT_DIR="$HOME/Library/Application Support/cardrop"
DEVICE_STATE_DIR="$SUPPORT_DIR/devices"
LOCK_FILE="$SUPPORT_DIR/lock"
PAUSED_FILE="$SUPPORT_DIR/paused"
PROBE_REQUEST="$SUPPORT_DIR/probe-request"
PROBE_RESULT="$SUPPORT_DIR/probe-result"
CURRENT_FILE="$SUPPORT_DIR/current"   # live upload info for `cardrop progress` (mode 600)

LOG_FILE="$HOME/Library/Logs/cardrop.log"
APP_PATH="$HOME/Applications/Cardrop.app"
HELPER="$APP_PATH/Contents/MacOS/cardrop-helper"
PLIST="$HOME/Library/LaunchAgents/$CARDROP_LABEL.plist"

# launchd starts jobs with a minimal PATH; make Homebrew (Apple Silicon and Intel) visible.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# Defaults. Override any of these in ~/.config/cardrop/settings.conf.
TRANSFERS=4          # files uploaded in parallel
CHUNK_SIZE=64M       # Google Drive upload chunk size; RAM used is about TRANSFERS x CHUNK_SIZE
VERIFY=checksum      # checksum (safest) or size (faster)
NOTIFY_ON_START=yes  # notify when an upload starts
[ -f "$SETTINGS_FILE" ] && . "$SETTINGS_FILE"

# Skip hidden files and folders: macOS metadata, ._ files, .Trashes, .Spotlight-V100 and so on.
FILTERS=(--exclude ".*" --exclude ".*/**")

trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# Prints one "volume|folder|destination" line per device configured in devices.conf.
list_devices() {
    [ -f "$DEVICES_FILE" ] || return 0
    local line vol src dst
    while IFS= read -r line || [ -n "$line" ]; do
        [[ "$(trim "$line")" == \#* || -z "$(trim "$line")" ]] && continue
        IFS='|' read -r vol src dst <<< "$line"
        vol=$(trim "$vol")
        src=$(trim "$src")
        dst=$(trim "$dst")
        if [ -z "$vol" ] || [ -z "$dst" ]; then
            echo "cardrop: ignoring malformed line in devices.conf: $line" >&2
            continue
        fi
        printf '%s|%s|%s\n' "$vol" "${src:-.}" "$dst"
    done < "$DEVICES_FILE"
}

# Loads configured devices into the DEVICES array.
load_devices() {
    DEVICES=()
    local line
    while IFS= read -r line; do DEVICES+=("$line"); done < <(list_devices)
}

source_path() {  # volume, folder
    if [ "$2" = "." ]; then echo "/Volumes/$1"; else echo "/Volumes/$1/$2"; fi
}

device_slug() {  # volume name -> safe file name
    printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'
}

# Identifies the current connection of a mounted volume (macOS assigns a device number per mount).
connection_id() {
    stat -f %d "/Volumes/$1" 2>/dev/null
}

# `cardrop cancel` marks a device as skipped until it's unplugged.
cancel_marker() {
    echo "$DEVICE_STATE_DIR/$(device_slug "$1").cancelled"
}

is_cancelled() {  # volume
    local marker
    marker=$(cancel_marker "$1")
    [ -f "$marker" ] && [ "$(cat "$marker")" = "$(connection_id "$1")" ]
}

running_pid() {
    [ -f "$LOCK_FILE" ] && kill -0 "$(cat "$LOCK_FILE")" 2>/dev/null && cat "$LOCK_FILE"
}
