#!/bin/bash
# cardrop worker. launchd runs it (through Cardrop.app) every time a volume mounts.
# For each configured device that is connected: upload new files one-way, verify them, notify.
# Nothing at the destination is ever deleted or overwritten.

. "$(dirname "$0")/common.sh"

mkdir -p "$DEVICE_STATE_DIR" "$(dirname "$LOG_FILE")"
if [ -f "$LOG_FILE" ] && [ "$(stat -f %z "$LOG_FILE")" -gt 5000000 ]; then mv -f "$LOG_FILE" "$LOG_FILE.old"; fi
exec >>"$LOG_FILE" 2>&1

log() { echo "$(date '+%Y-%m-%d %H:%M:%S')  $*"; }
notify() { "$HELPER" notify "$1" "$2" "${3:-Glass}" || true; }   # title, message, sound
record() { echo "$(date '+%Y-%m-%d %H:%M')  $2" > "$DEVICE_STATE_DIR/$1.last"; }  # slug, result

load_devices

# `cardrop doctor` asks for an access check that runs under Cardrop.app's permissions.
if [ -f "$PROBE_REQUEST" ]; then
    rm -f "$PROBE_REQUEST"
    for device in "${DEVICES[@]}"; do
        IFS='|' read -r vol src dst <<< "$device"
        path=$(source_path "$vol" "$src")
        if [ ! -d "/Volumes/$vol" ]; then echo "$vol|not connected"
        elif [ ! -d "$path" ]; then echo "$vol|folder '$src' not found"
        elif ls "$path" >/dev/null 2>&1; then echo "$vol|ok"
        else echo "$vol|denied"
        fi
    done > "$PROBE_RESULT.tmp"
    mv -f "$PROBE_RESULT.tmp" "$PROBE_RESULT"
    exit 0
fi

# A cancel only lasts while the device stays plugged in: forget it once the device is gone.
# (launchd also runs this worker when /Volumes changes, so unplugging triggers this cleanup.)
for device in "${DEVICES[@]}"; do
    IFS='|' read -r vol _ _ <<< "$device"
    marker=$(cancel_marker "$vol")
    if [ -f "$marker" ] && { [ ! -d "/Volumes/$vol" ] || ! is_cancelled "$vol"; }; then
        rm -f "$marker"
    fi
done

# launchd fires for every volume that mounts; stay silent unless a configured device is present.
connected=0
for device in "${DEVICES[@]}"; do
    IFS='|' read -r vol _ _ <<< "$device"
    [ -d "/Volumes/$vol" ] && connected=1
done
[ "$connected" -eq 1 ] || exit 0

if [ -f "$PAUSED_FILE" ]; then
    log "Device connected, but cardrop is paused (run 'cardrop resume')."
    exit 0
fi

# One run at a time.
if running_pid >/dev/null; then exit 0; fi
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE" "$CURRENT_FILE"' EXIT

RCLONE=$(command -v rclone)
if [ -z "$RCLONE" ]; then
    log "rclone not found."
    notify "⚠️ cardrop needs rclone" "Install it with: brew install rclone" Basso
    exit 1
fi

PROCESSED=" "   # "slug:fingerprint" pairs handled during this run

# True (and logged) if the user paused cardrop or cancelled this device while it was working.
stopped_by_user() {  # volume, slug
    if [ -f "$PAUSED_FILE" ]; then
        log "$1: stopped because cardrop was paused. Files already uploaded are kept."
        record "$2" "⏸ paused before finishing"
        return 0
    fi
    if is_cancelled "$1"; then
        log "$1: cancelled. Files already uploaded are kept; it won't upload again until reconnected."
        record "$2" "✖ cancelled (uploads again next time it's plugged in)"
        return 0
    fi
    return 1
}

# rclone serves live stats on localhost while it runs, so `cardrop progress` can read them.
# A free port and a one-off password are chosen per run and kept in $CURRENT_FILE (mode 600).
RC_PORT=""
for port in $(seq 5573 5599); do
    if ! nc -z 127.0.0.1 "$port" 2>/dev/null; then RC_PORT=$port; break; fi
done
RC_PASS=$(openssl rand -hex 16)
RC_FLAGS=()
[ -n "$RC_PORT" ] && RC_FLAGS=(--rc --rc-addr "127.0.0.1:$RC_PORT" --rc-user cardrop --rc-pass "$RC_PASS")

set_current() {  # phase, volume, destination, pending
    (umask 077; printf '%s\n' "$1" "$2" "$3" "$4" "$RC_PORT" "$RC_PASS" "$(date +%s)" > "$CURRENT_FILE")
}

# Returns 0 if it did any work (uploaded or verified), 1 if there was nothing to do.
process_device() {
    local vol="$1" src_rel="$2" dst="$3"
    local src slug state listing total fingerprint dry pending out status matched
    src=$(source_path "$vol" "$src_rel")
    slug=$(device_slug "$vol")
    state="$DEVICE_STATE_DIR/$slug.verified"

    [ -d "/Volumes/$vol" ] || return 1
    is_cancelled "$vol" && return 1
    if [ ! -d "$src" ]; then
        log "$vol: folder '$src_rel' not found on the device. Skipping."
        return 1
    fi
    if ! ls "$src" >/dev/null 2>&1; then
        log "$vol: macOS blocked access to the device."
        record "$slug" "⚠️ no permission to read the device"
        notify "⚠️ cardrop can't read $vol" "Allow Cardrop in System Settings → Privacy & Security → Files & Folders → Removable Volumes." Basso
        return 1
    fi

    listing=$(cd "$src" && find . -type f -not -path '*/.*' -exec stat -f '%N %z %m' {} + 2>/dev/null | sort)
    [ -n "$listing" ] || return 1
    total=$(printf '%s\n' "$listing" | wc -l | tr -d ' ')
    fingerprint=$(printf '%s' "$listing" | shasum | cut -c1-16)

    [[ "$PROCESSED" == *" $slug:$fingerprint "* ]] && return 1
    PROCESSED="$PROCESSED$slug:$fingerprint "

    dry=$("$RCLONE" copy "$src" "$dst" --ignore-existing "${FILTERS[@]}" --dry-run 2>&1)
    if [ $? -ne 0 ]; then
        stopped_by_user "$vol" "$slug" && return 1
        log "$vol: can't reach $dst"
        printf '%s\n' "$dry" | tail -5
        record "$slug" "⚠️ couldn't reach $dst"
        notify "⚠️ $vol: can't reach the destination" "Check your internet connection, then run 'cardrop doctor'. Don't clear the device." Basso
        return 1
    fi
    pending=$(printf '%s\n' "$dry" | grep -c "Skipped copy")

    # Same files as last time and all already uploaded: nothing to say.
    if [ "$pending" -eq 0 ] && [ "$(cat "$state" 2>/dev/null)" = "$fingerprint" ]; then return 1; fi

    log "=== $vol: $total files, $pending new -> $dst ==="
    if [ "$pending" -gt 0 ]; then
        [ "$NOTIFY_ON_START" = "yes" ] && notify "⬆️ $vol: uploading $pending new files" "Keep it connected until you see ✅. Progress: cardrop progress" Pop
        set_current uploading "$vol" "$dst" "$pending"
        # caffeinate stops the Mac idle-sleeping during long uploads.
        caffeinate -i "$RCLONE" copy "$src" "$dst" \
            --ignore-existing "${FILTERS[@]}" "${RC_FLAGS[@]}" \
            --transfers "$TRANSFERS" --drive-chunk-size "$CHUNK_SIZE" \
            --retries 5 --low-level-retries 20 \
            --stats 5m --stats-one-line -v
        log "$vol: upload finished (status $?)."
    fi

    stopped_by_user "$vol" "$slug" && return 1
    if [ ! -d "$src" ]; then
        log "$vol: disconnected before the upload finished."
        record "$slug" "⚠️ disconnected before finishing"
        notify "⚠️ $vol disconnected" "The upload didn't finish. Plug it back in to resume. Don't clear it yet." Basso
        return 1
    fi

    log "$vol: verifying against $dst ($VERIFY)..."
    local verify_flags=()
    [ "$VERIFY" = "size" ] && verify_flags=(--size-only)
    set_current verifying "$vol" "$dst" "$total"
    out=$(caffeinate -i "$RCLONE" check "$src" "$dst" --one-way "${FILTERS[@]}" "${verify_flags[@]}" "${RC_FLAGS[@]}" 2>&1)
    status=$?
    rm -f "$CURRENT_FILE"
    printf '%s\n' "$out"

    stopped_by_user "$vol" "$slug" && return 1

    matched=$(printf '%s\n' "$out" | sed -nE 's/.* ([0-9]+) matching files.*/\1/p' | tail -1)
    if [ "$status" -eq 0 ]; then
        echo "$fingerprint" > "$state"
        log "$vol: VERIFIED ${matched:-$total} files."
        record "$slug" "✅ verified ${matched:-$total} files"
        notify "✅ $vol: upload verified" "${matched:-$total} files are safely in $dst. Safe to clear the device." Glass
    else
        log "$vol: VERIFY FAILED (status $status)."
        record "$slug" "⚠️ verification failed"
        notify "⚠️ $vol: upload incomplete" "Some files didn't verify. Don't clear the device. Reconnect it to retry." Basso
    fi
    return 0
}

# Keep passing over all devices until nothing is left to do, so a device that is
# plugged in while another one is uploading still gets picked up.
for pass in 1 2 3 4 5; do
    worked=0
    for device in "${DEVICES[@]}"; do
        [ -f "$PAUSED_FILE" ] && break 2
        IFS='|' read -r vol src dst <<< "$device"
        process_device "$vol" "$src" "$dst" && worked=1
    done
    [ "$worked" -eq 1 ] || break
done
