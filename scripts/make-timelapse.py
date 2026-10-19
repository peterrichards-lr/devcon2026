#!/usr/bin/env python3
"""
Turn a screen recording of the Approach 1 run into the clocked time-lapse.

  python3 scripts/make-timelapse.py [RECORDING.mov] [options] [-- CLOCK_OVERLAY_OPTIONS]

  1. Rename the recording to NAME.mov (default approach-1-<commit>-<YYYYMMDD-HHMM>,
     from this checkout's commit and the recording's start time).
  2. Trim the still stretches at either end. The start is the first real change in the
     run window (record-layout.sh's right-hand window), so moving the pointer doesn't
     count; the end is the last change anywhere on screen. PAD_START and PAD_END seconds
     are kept either side, and the start is cut on a whole second. The trimmed copy's
     metadata gets its own start time (the original's plus the cut), so the clock stays
     exact.
  3. Render NAME-timelapse.mp4 with scripts/clock_overlay.py.
  4. Spot check: find the site initializer's Initialized line in `docker logs`, grab the
     frame where it appears, and save it as NAME-clock-check.png. Run this while the
     recorded instance is still up; a later restore replaces its log.

With no RECORDING, it takes the newest "Screen Recording*.mov" on the Desktop.

Options:
  --name NAME          output name stem
  --dest DIR           where the files go (default: the recording's folder)
  --speed N            default 15
  --tz ZONE            default UTC, the zone of Liferay's log timestamps
  --pad-start S        seconds kept before the first change (default 1)
  --pad-end S          seconds kept after the last change (default 2)
  --clock-h PX         height of the clear top-right corner the run window sits below
                       (default 350, as record-layout.sh)
  --no-trim            keep the whole recording
  --no-check           skip the spot check
  --container NAME     the Liferay container for the spot check (default devcon2026)

Anything after -- goes to clock_overlay.py, replacing the default clock options
(--style digital --dual --size 260).

Needs ffmpeg/ffprobe, and Pillow for clock_overlay.py.
"""
import argparse, glob, json, math, os, re, shutil, subprocess, sys
from datetime import datetime, timedelta, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
CLOCK_DEFAULTS = ["--style", "digital", "--dual", "--size", "260"]


def run(cmd, **kw):
    return subprocess.run(cmd, check=True, **kw)


def probe(path):
    out = subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "v:0",
                                   "-show_entries", "stream=width,height:format=duration:format_tags",
                                   "-of", "json", path])
    j = json.loads(out)
    tags = {k.lower(): v for k, v in (j["format"].get("tags") or {}).items()}
    raw = tags.get("com.apple.quicktime.creationdate") or tags.get("creation_time")
    if not raw:
        sys.exit(f"{path} has no creation date in its metadata, so the clock can't be placed.")
    norm = re.sub(r"(\.\d{6})\d+", r"\1", raw.replace("Z", "+00:00"))
    norm = re.sub(r"([+-]\d{2})(\d{2})$", r"\1:\2", norm)
    created = datetime.fromisoformat(norm)
    if created.tzinfo is None:
        created = created.replace(tzinfo=timezone.utc)
    s = j["streams"][0]
    return s["width"], s["height"], float(j["format"]["duration"]), created


def scene_changes(path, vf, threshold):
    """Times (s) where the picture changes by more than `threshold` (ffmpeg scdet)."""
    err = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", path, "-vf",
                          f"{vf}scdet=threshold={threshold}:sc_pass=1", "-an", "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    return [float(t) for t in re.findall(r"lavfi\.scd\.time: ([0-9.]+)", err)]


def iso(dt):
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")


def main():
    ap = argparse.ArgumentParser(description="Rename, trim and clock a recording of the run.")
    ap.add_argument("recording", nargs="?")
    ap.add_argument("--name"); ap.add_argument("--dest")
    ap.add_argument("--speed", type=float, default=15)
    ap.add_argument("--tz", default="UTC")
    ap.add_argument("--pad-start", type=float, default=1.0)
    ap.add_argument("--pad-end", type=float, default=2.0)
    ap.add_argument("--clock-h", type=int, default=350)
    ap.add_argument("--no-trim", action="store_true")
    ap.add_argument("--no-check", action="store_true")
    ap.add_argument("--container", default="devcon2026")
    argv = sys.argv[1:]
    extra = []
    if "--" in argv:
        i = argv.index("--")
        argv, extra = argv[:i], argv[i + 1:]
    a = ap.parse_args(argv)

    rec = a.recording
    if not rec:
        found = sorted(glob.glob(os.path.expanduser("~/Desktop/Screen Recording*.mov")), key=os.path.getmtime)
        if not found:
            sys.exit("No recording given, and no 'Screen Recording*.mov' on the Desktop.")
        rec = found[-1]
    if not os.path.exists(rec):
        sys.exit(f"{rec} not found.")
    w, h, dur, created = probe(rec)

    # 1. Rename.
    if not a.name:
        commit = subprocess.run(["git", "-C", HERE, "rev-parse", "--short", "HEAD"],
                                capture_output=True, text=True).stdout.strip() or "unknown"
        a.name = f"approach-1-{commit}-{created.astimezone().strftime('%Y%m%d-%H%M')}"
    dest = a.dest or os.path.dirname(os.path.abspath(rec))
    os.makedirs(dest, exist_ok=True)
    named = os.path.join(dest, a.name + ".mov")
    if os.path.abspath(rec) != os.path.abspath(named):
        if os.path.exists(named):
            sys.exit(f"{named} already exists; pass another --name.")
        shutil.move(rec, named)
        print(f"renamed  {os.path.basename(rec)} -> {named}")
    rec = named

    # 2. Trim.
    if a.no_trim:
        cut_from, cut_to = 0.0, dur
    else:
        run_window = f"crop={w // 2}:{h - a.clock_h}:{w // 2}:{a.clock_h},"
        starts = scene_changes(rec, run_window, 2)
        ends = scene_changes(rec, "", 0.5)
        # Cut on a whole second: MOV keeps its creation time in whole seconds, so a cut at
        # 19.5 s would put the clock half a second out.
        cut_from = float(max(0, math.floor(starts[0] - a.pad_start))) if starts else 0.0
        cut_to = min(dur, ends[-1] + a.pad_end) if ends else dur
        if cut_to <= cut_from:
            cut_from, cut_to = 0.0, dur
    trimmed = os.path.join(dest, a.name + "-trimmed.mov")
    start_at = created + timedelta(seconds=cut_from)
    print(f"trim     {cut_from:.1f}s to {cut_to:.1f}s of {dur:.1f}s "
          f"(first change in the run window, last change on screen, +{a.pad_start:g}s/+{a.pad_end:g}s)")
    run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", rec,
         "-ss", f"{cut_from:.3f}", "-to", f"{cut_to:.3f}", "-an",
         "-c:v", "libx264", "-crf", "16", "-preset", "fast", "-pix_fmt", "yuv420p",
         "-metadata", f"creation_time={iso(start_at)}", trimmed])

    # 3. Clock.
    timelapse = os.path.join(dest, a.name + "-timelapse.mp4")
    clock = [sys.executable, os.path.join(HERE, "clock_overlay.py"), trimmed, timelapse,
             "--speed", f"{a.speed:g}", "--tz", a.tz] + (extra or CLOCK_DEFAULTS)
    print("clock    " + " ".join(os.path.basename(c) if c.startswith("/") else c for c in clock[1:]))
    run(clock)

    # 4. Spot check.
    if not a.no_check:
        logs = subprocess.run(["docker", "logs", a.container], capture_output=True, text=True)
        events = re.findall(r"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3}) INFO .*Initialized com\.liferay\.site\.initializer",
                            logs.stdout + logs.stderr, re.M)
        events = [datetime.fromisoformat(e + "+00:00") for e in events]
        events = [e for e in events if start_at <= e <= created + timedelta(seconds=cut_to)]
        if not events:
            print("check    skipped: no site initializer 'Initialized' line from this recording in "
                  f"`docker logs {a.container}` (has the instance been restored since?)")
        else:
            event = events[-1]
            at = (event - start_at).total_seconds() / a.speed
            png = os.path.join(dest, a.name + "-clock-check.png")
            run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-ss", f"{at:.2f}",
                 "-i", timelapse, "-frames:v", "1", png])
            print(f"check    Initialized at {event.strftime('%H:%M:%S.%f')[:-3]} UTC should appear at "
                  f"{at:.2f}s: the clock should read {event.strftime('%H:%M:%S')}, give or take a "
                  f"second -> {png}")

    print(f"done     {timelapse}")


if __name__ == "__main__":
    main()
