"""Formats rclone's live stats (core/stats JSON on stdin) for `cardrop progress` and `cardrop status`.

Usage: progress.py full|line <phase> <volume> <destination> <expected files> <started epoch>
"""
import json
import sys
import time


def size(n):
    n = float(n or 0)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1000 or unit == "TB":
            return f"{n:.0f} {unit}" if unit in ("B", "KB") else f"{n:.1f} {unit}"
        n /= 1000


def duration(seconds):
    if seconds is None or seconds < 0:
        return "calculating..."
    seconds = int(seconds)
    h, rest = divmod(seconds, 3600)
    m = rest // 60
    if h:
        return f"{h}h {m:02d}m"
    return f"{m}m" if m else "under a minute"


def main():
    mode, phase, volume, dest, expected, started = sys.argv[1:7]
    expected = int(expected or 0)
    elapsed = time.time() - int(started or time.time())
    try:
        stats = json.load(sys.stdin)
    except ValueError:
        print("starting..." if mode == "line" else f"Starting up ({phase} {volume})...")
        return

    if phase == "verifying":
        checked = stats.get("checks", 0)
        total = max(expected, stats.get("totalChecks", 0))
        if mode == "line":
            print(f"verifying {checked}/{total} files")
            return
        print(f"🔍  Verifying {volume} against {dest}")
        print(f"    Checked:   {checked} / {total} files")
        print(f"    Elapsed:   {duration(elapsed)}")
        for name in stats.get("checking", [])[:4]:
            print(f"    Now:       {name}")
        return

    done_bytes = stats.get("bytes", 0)
    total_bytes = max(stats.get("totalBytes", 0), done_bytes)
    speed = stats.get("speed", 0)
    eta = stats.get("eta")
    if eta is None and speed:
        eta = (total_bytes - done_bytes) / speed
    percent = 100 * done_bytes / total_bytes if total_bytes else 0
    files_done = stats.get("transfers", 0)
    files_total = max(expected, stats.get("totalTransfers", 0))

    if mode == "line":
        print(f"{percent:.0f}% · {size(done_bytes)} / {size(total_bytes)} · "
              f"{files_done}/{files_total} files · {duration(eta)} left")
        return

    print(f"⬆️   {volume} → {dest}")
    print(f"    Progress:  {size(done_bytes)} / {size(total_bytes)}  ({percent:.0f}%)")
    print(f"    Files:     {files_done} / {files_total} done")
    left = duration(eta)
    print(f"    Speed:     {size(speed)}/s     Time left: {'~' + left if left[0].isdigit() else left}")
    print(f"    Elapsed:   {duration(elapsed)}")
    transferring = sorted(stats.get("transferring", []), key=lambda t: -t.get("percentage", 0))
    for i, item in enumerate(transferring[:4]):
        label = "Now:" if i == 0 else ""
        print(f"    {label:<10} {item.get('name', '?')}   {item.get('percentage', 0)}%")


if __name__ == "__main__":
    main()
