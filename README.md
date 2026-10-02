# cardrop

**Plug in a camera or SD card, and cardrop uploads its new files straight to Google Drive (or any
cloud rclone supports), checks every file, and tells you when it's safe to wipe the card.**

For action cameras, drones, dashcams, audio recorders, or any USB drive you fill up and clear
again and again.

```
 ┌──────────────┐   plug in    ┌──────────────┐  stream, no local copy  ┌──────────────┐
 │ Camera / SD  │ ───────────▶ │   cardrop    │ ──────────────────────▶ │ Google Drive │
 └──────────────┘              └──────────────┘                         └──────────────┘
                                      │  verify every file (size + checksum)
                                      ▼
                        🔔 "✅ 212 files verified. Safe to clear the device."
```

## Why not just use Google Drive for desktop?

Drive for desktop only offers **two-way sync**. When you clear your camera, it faithfully deletes
the same files from the cloud. cardrop is deliberately **one-way**:

| | Drive for desktop sync | cardrop |
|---|---|---|
| Clearing the card deletes the cloud copy | Yes | **Never** |
| Needs free space on your Mac | Yes (it caches uploads locally) | **No**, it streams from the card |
| Starts when you plug the device in | Yes | Yes |
| Tells you when it's safe to wipe the card | No | **Yes, after checking every file** |
| Resumes after you unplug partway | Yes | Yes, skipping files already uploaded |
| Works with Dropbox, OneDrive, S3 and others | No | Yes (any [rclone](https://rclone.org) remote) |

## Features

- **One-way and additive.** Files are only ever added to the destination. Nothing there is deleted or overwritten.
- **No local storage.** Files stream straight from the device to the cloud, so a 500 GB card works on a Mac with 20 GB free.
- **Verified.** After uploading, every file is compared with the cloud copy by size and checksum before you're told it's safe to clear the device.
- **Automatic.** Runs whenever a configured device is plugged in, even several at once.
- **Notifications** when an upload starts, is verified, fails, or is interrupted.
- **Pause and resume** at any time. Pausing stops an upload immediately.
- **Keeps the Mac awake** during long uploads.
- **Multiple devices**, each with its own destination folder.

## Requirements

- macOS 13 or later (Apple Silicon or Intel)
- Xcode Command Line Tools: `xcode-select --install`
- [Homebrew](https://brew.sh) and [rclone](https://rclone.org) (`brew install rclone`; the installer offers to do this)
- For Google Drive: your own Google OAuth client ([10-minute setup](docs/google-setup.md))

## Install

```bash
git clone https://github.com/cknm-cmd/cardrop.git
cd cardrop
./install.sh
```

Then:

1. **Connect Google Drive** (after [creating your OAuth client](docs/google-setup.md)):
   ```bash
   cardrop connect gdrive ~/Downloads/client_secret_XXXX.json
   ```
   A browser opens. Pick the Google account the files should go to, and click Allow.

2. **Add your devices.** `cardrop config` opens the device list. Add one line per device:
   ```
   # VOLUME NAME | FOLDER ON DEVICE | DESTINATION
   Insta360 X5   | DCIM             | gdrive:Insta360
   GoPro         | DCIM             | gdrive:GoPro
   ```
   The volume name is what Finder shows when the device is plugged in.

3. **Check everything:**
   ```bash
   cardrop doctor
   ```
   The first time, macOS asks whether **Cardrop** may access removable volumes and send
   notifications. Click **Allow** for both.

## Daily use

1. Plug in the device. You'll see **"⬆️ Uploading N new files"**. To watch it, run `cardrop progress -w`:
   ```
   ⬆️   Insta360 X5 → gdrive:Insta360
       Progress:  38.2 GB / 104.6 GB  (37%)
       Files:     6 / 17 done
       Speed:     5.1 MB/s     Time left: ~3h 37m
       Elapsed:   2h 05m
       Now:       VID_20261001_153054_00_006.insv   62%
   ```
2. Leave it connected. For long uploads, keep the Mac on power or the lid open: cardrop stops idle sleep, but closing the lid on battery still sleeps the Mac.
3. When **"✅ upload verified. Safe to clear the device"** appears, format the card.

If you see **⚠️ incomplete** or **⚠️ disconnected**, don't clear the device. Reconnect it and
cardrop continues, skipping files that are already uploaded.

## Commands

| Command | What it does |
|---|---|
| `cardrop status` | Active or paused, a one-line progress summary, and each device's connection and last result |
| `cardrop progress [-w]` | Live upload progress: size, files, speed, time left, files in flight (`-w` keeps it updating) |
| `cardrop pause` | Stop any upload in progress and skip uploads until resumed (survives restarts) |
| `cardrop resume` | Turn uploads back on; starts immediately if a device is connected |
| `cardrop run` | Check connected devices now |
| `cardrop log [-f]` | Show the recent log (`-f` to follow live) |
| `cardrop config` | Open the device list |
| `cardrop connect <remote> [json]` | Connect a Google Drive rclone remote with your OAuth client |
| `cardrop doctor` | Check rclone, destinations, device access and notifications |
| `cardrop test-notify` | Send a test notification |

### Settings

Optional. Copy `~/.config/cardrop/settings.conf.example` to `settings.conf` and adjust:

| Setting | Default | Meaning |
|---|---|---|
| `TRANSFERS` | `4` | Files uploaded in parallel |
| `CHUNK_SIZE` | `64M` | Google Drive upload chunk; RAM used is about `TRANSFERS × CHUNK_SIZE` |
| `VERIFY` | `checksum` | `checksum` (safest) or `size` (faster) |
| `NOTIFY_ON_START` | `yes` | Notify when an upload starts |

### Other clouds

Any [rclone remote](https://rclone.org/overview/) works as a destination. Set it up with
`rclone config`, then use it in the device list, e.g. `GoPro | DCIM | dropbox:GoPro`.

## How it works

- A launchd agent (`io.github.cknm-cmd.cardrop`) runs whenever **any** volume mounts. It exits
  straight away unless one of your configured devices is connected.
- It runs inside a tiny helper app, **Cardrop.app** (`~/Applications`), so macOS's "Removable Volumes"
  and notification permissions belong to Cardrop rather than to every shell script.
  The app is built only once. Updating cardrop replaces only the scripts, so permissions aren't asked for again.
- Uploads use `rclone copy --ignore-existing`, which only adds files. Verification uses
  `rclone check --one-way` (size + checksum).
- While it runs, rclone serves live stats on `127.0.0.1` (a free port from 5573 to 5599), protected
  by a random password generated for each run. That's what `cardrop progress` reads.
- Hidden files (`.Trashes`, `._*`, `.Spotlight-V100`) are skipped.

| Path | Contents |
|---|---|
| `~/.config/cardrop/devices.conf` | Your device list |
| `~/.config/cardrop/settings.conf` | Optional settings |
| `~/Library/Logs/cardrop.log` | Log (rotates at 5 MB) |
| `~/Library/Application Support/cardrop/` | Installed scripts and state |
| `~/Applications/Cardrop.app` | Helper app |

## FAQ

**Does it need free space on my Mac?** No. rclone reads each file in chunks and sends them
directly. It uses about 256 MB of RAM with the default settings, and no disk space.

**What if I unplug the device partway through?** You'll get a "disconnected" notification. Files
that finished uploading are kept, and unfinished ones are uploaded next time.

**Two files with the same name on different days?** Cameras usually put the date and time in file
names. If a file with the same name already exists at the destination, cardrop never overwrites
it, and verification then flags the mismatch so you don't clear the card.

**Will the Google sign-in expire?** Not if your OAuth app is set to *In production* (see the
[setup guide](docs/google-setup.md)). While it's in *Testing*, Google expires the sign-in after 7 days.

## Uninstall

```bash
./install.sh --uninstall
```

This keeps your device list and log. Your rclone remotes are untouched.

## License

[MIT](LICENSE). cardrop is not affiliated with Google, Insta360, GoPro or DJI. Google Drive is a
trademark of Google LLC.
