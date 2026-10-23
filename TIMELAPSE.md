# Clocked time-lapse

Two scripts turn a screen recording of a long run into a 15x time-lapse with a clock that
keeps real time and matches Liferay's log timestamps. On 19 October they turned a 6 min 7 s
Approach 1 take into 22.6 s, with the clock on the site initializer's `Initialized` line to
the second.

This guide covers macOS and Windows, and ends with a prompt for an AI session.
[TESTING-APPROACH-1.md](TESTING-APPROACH-1.md) ("Recording the run") has the Approach 1
procedure in full.

## What you need

A checkout of `02-aiconversion` at `1516efe` or later. Older checkouts render the clock with
a tiny font on Windows.

| Script | What it does | Platform |
| --- | --- | --- |
| `scripts/clock_overlay.py` | Speeds a recording up and draws a real-time clock in one corner | Any: Python 3, ffmpeg, Pillow |
| `scripts/make-timelapse.py` | One command: renames, trims the still ends, runs `clock_overlay.py`, saves a check frame | Any; the check reads `docker logs` |
| `scripts/record-layout.sh` | Lays out two Terminal windows (log left, run right) and leaves the top-right corner clear for the clock | macOS only: Terminal.app, zsh |
| `scripts/follow-logs.sh` | The coloured Liferay log for the left window, reconnecting when a restore restarts the container | Any, with LDM; Git Bash or WSL on Windows |

Install ffmpeg (`brew install ffmpeg` on macOS, `winget install Gyan.FFmpeg` on Windows) and
Pillow (`pip3 install pillow`, or `pip install pillow` on Windows).

The clock is placed from the time stored in the recording file. macOS screen recording
(Cmd+Shift+5) writes it; Windows recorders may not, so check first (see "On Windows").

## Approach 1, the way we did it

1. Check Docker's clock against the computer's (see "Getting the clock right"). Anything
   within half a second is fine.
1. Lay out the screen: `MENU_BAR=0 scripts/record-layout.sh`. It finds the 1920x1080
   display, opens the log on the left and the run on the right, and keeps the top-right
   300 x 350 px clear.
1. Start the screen recording on that display, in SDR at 30 fps.
1. Press Enter in the right window. It runs `scripts/record-approach-1.sh`: build,
   provision, checks, snapshot.
1. Stop the recording when the run ends.
1. While that instance is still up, run `python3 scripts/make-timelapse.py`.

`make-timelapse.py` takes the newest `Screen Recording*.mov` on the Desktop, or a file you
name, and writes three files next to it:

| File | What it is |
| --- | --- |
| `approach-1-<commit>-<date>.mov` | The original, renamed |
| `…-timelapse.mp4` | Trimmed, 15x, with a digital UTC clock and an elapsed panel |
| `…-clock-check.png` | The frame where the site initializer's `Initialized` line appears; the clock should read that line's second |

It trims from a second before the first change in the right-hand window (so moving the
pointer doesn't count) to two seconds after the last change on screen. Useful options:
`--name`, `--dest`, `--speed`, `--no-trim`, `--no-check`; anything after `--` replaces the
clock options.

## Any other recording (Approach 2)

`make-timelapse.py` assumes Approach 1 in three places:

- **Trim:** it looks for the first change in the right half of the screen, below the clear
  corner. With another layout, pass `--no-trim` and trim yourself.
- **Name:** it defaults to `approach-1-…`. Pass `--name approach-2-…`.
- **Check:** it looks for the site initializer's `Initialized` line. Pass `--no-check`, and
  check by hand against a line your own run logs.

So for Approach 2:

```bash
python3 scripts/make-timelapse.py <recording> \
	--name approach-2-<commit> --no-trim --no-check
```

Or the clock alone, on any recording:

```bash
python3 scripts/clock_overlay.py <recording> <recording>-timelapse.mp4 \
	--speed 15 --tz UTC --style digital --dual --size 260
```

That is the talk's look: time of day on top, elapsed time underneath, 260 x 222 px. Other
options: `--style analog|both`, `--start elapsed` for a stopwatch, `--start HH:MM:SS` when
the file has no start time, `--pos tl|tr|bl|br`, `--label ""`.

The backup video of a live step, such as the enrolment, stays real time with no clock (the
2026-10-19 decision in [LESSONS-LEARNT.md](LESSONS-LEARNT.md)).

## On Windows

The two Python scripts run on Windows from `1516efe`. The rest needs these changes:

| What | On Windows |
| --- | --- |
| Python | Run the scripts with `python`, not `python3` |
| `record-layout.sh` | macOS only. Lay the screen out by hand: log on the left, the run on the right, the top-right 300 x 350 px left clear for the clock |
| `.sh` scripts | Run them in Git Bash or WSL |
| Recording | Snipping Tool, Xbox Game Bar or OBS, in SDR at 30 fps. Pass the file's path: the default looks for a macOS `Screen Recording*.mov` on the Desktop |
| Start time | The clock is placed from the file's `creation_time`, which Windows recorders may not write. Check it first (below) |
| `--tz` | `UTC` works as it is. Any other zone needs `pip install tzdata` |

Check that the recording knows when it started:

```bash
ffprobe -v error -show_entries format_tags=creation_time -of default=nw=1:nk=1 recording.mp4
```

No output means no start time. Stamp one on, in UTC, from when you pressed record. OBS names
its files with the local start time, to the second:

```bash
ffmpeg -i recording.mp4 -c copy -metadata creation_time=2026-10-22T09:15:30Z stamped.mp4
```

Then use `stamped.mp4`, and check the clock against a log line afterwards: a start time
typed by hand is only as good as where you read it.

## Getting the clock right

The audience will compare the clock with the log. These are the things that pulled them
apart for us:

| Trap | What we saw | What to do |
| --- | --- | --- |
| Time zone | The clock started in the Mac's zone (BST), an hour off the log | `--tz UTC`: Liferay logs in UTC |
| Whole seconds | MOV stores its start time in whole seconds; a cut at 19.5 s put the clock half a second out | Cut on a whole second; `make-timelapse.py` does |
| Docker skew | The log is stamped by Docker's VM, the clock by the computer: +0.05 to +0.08 s apart | Check before each take (below); within half a second is fine |
| HDR | HDR recordings come out washed out when converted | Record in SDR, 30 fps |
| Clear corner | Analog with `--dual` (333 px) or `--style both` (353 px) is taller than the 310 px the corner leaves | Digital `--dual` at `--size 260`, or `CLOCK_H=420 scripts/record-layout.sh` |

The skew check, with the instance running (`python` on Windows; the command works as it is
in PowerShell):

```bash
python3 -c "import subprocess, time; m = time.time(); d = float(subprocess.check_output(['docker', 'exec', 'devcon2026', 'date', '-u', '+%s.%N'])); print(f'Docker minus computer: {d - m:+.2f} s')"
```

Change `devcon2026` to your Liferay container's name.

Always check the result against an event: pick a log line with a known time, work out the
frame where it must appear (seconds since the recording started, divided by the speed), and
look:

```bash
ffmpeg -loglevel error -y -ss <seconds> -i <timelapse>.mp4 -frames:v 1 clock-check.png
```

The clock should read that line's second, give or take one. `docker logs` only covers the
current container, so do this before the next restore.

## A prompt for an AI session

Paste this into an AI session started in your checkout, and fill in the lines in angle
brackets:

```text
I want a clocked time-lapse of a screen recording, the way Peter made the Approach 1 one
for DevCon 2026. Pull 02-aiconversion first, then follow TIMELAPSE.md in this checkout,
and read scripts/clock_overlay.py and scripts/make-timelapse.py (their header comments
are their documentation).

I'm on <Windows / macOS>.
What I'm recording: <Approach 2 / Approach 1 / something else>, on the Liferay
container <name>.
The recording: <path, or "not recorded yet">.

Take me through it: check the tools, check the clock skew if I haven't recorded yet,
make the time-lapse, check the clock against one log line by extracting that frame and
looking at it, and tell me where the files are. Don't change the scripts; if one doesn't
fit what I'm doing, tell me what you'd change and wait for me.
```
