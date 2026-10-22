#!/usr/bin/env python3
"""
Superimpose a clock on a screen recording and speed it up into a time-lapse.

The clock keeps real time while the video plays fast, so the audience sees the time
race by during the provisioning.

Usage:
  python3 clock_overlay.py INPUT.mov OUTPUT.mp4 --speed 15

  --start   Clock time at the first frame of INPUT. One of:
              auto      (default; alias: current) time of day the recording started,
                        read from its metadata (QuickTime's creation date)
              HH:MM:SS  a time you set, e.g. from the first log line
              elapsed   (alias: zero) stopwatch from 00:00
  --tz      Time zone the clock shows when --start auto, e.g. UTC or Europe/London.
            Default: this computer's zone. Match whatever zone the log timestamps use.
  --speed   Speed-up factor (15 = 15x faster). Default 15.
  --style   analog | digital | both. Default analog.
  --dual    Also show elapsed time since the start of the recording, in a panel
            under the clock (real time on the clock, elapsed below).
  --subsec  none | tenths | ms. Sub-second digits on the digital readouts (default none).
            Each output frame covers speed/30 s of real time, so at 15x the digits can
            only show .000/.500: use tenths (or none) for --speed 3 and above.
  --subsec-on  elapsed | all. Which readouts get them (default elapsed: the --dual
            panel, and the readout when --start zero). all adds the time of day too,
            whose start is only known to the second.
  --size    Clock width in pixels. Default 220.
  --pos     Corner: tr, tl, br, bl. Default tr (top right).
  --label   Text under the clock. Default "<speed>x speed". Use "" for none.

Needs: ffmpeg/ffprobe on PATH, Python 3 with Pillow (pip3 install pillow).
"""
import argparse, json, math, os, subprocess, sys
from datetime import datetime, timezone
from PIL import Image, ImageDraw, ImageFont

FPS = 30
SS = 3  # supersampling for smooth edges


def probe(path):
    out = subprocess.check_output([
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "stream=width,height:stream_tags:format=duration:format_tags",
        "-of", "json", path])
    j = json.loads(out)
    s = j["streams"][0]
    tags = {}
    tags.update({k.lower(): v for k, v in (s.get("tags") or {}).items()})
    tags.update({k.lower(): v for k, v in (j["format"].get("tags") or {}).items()})
    return s["width"], s["height"], float(j["format"]["duration"]), tags


def start_from_metadata(tags, tz_name):
    """Return (seconds past midnight, source) from the recording's creation date."""
    raw = tags.get("com.apple.quicktime.creationdate") or tags.get("creation_time")
    src = "com.apple.quicktime.creationdate" if "com.apple.quicktime.creationdate" in tags else "creation_time"
    if not raw:
        sys.exit("No creation date in the file's metadata. Pass --start HH:MM:SS "
                 "(read it off the first log line) or --start elapsed.")
    import re
    norm = raw.replace("Z", "+00:00")
    norm = re.sub(r"([+-]\d{2})(\d{2})$", r"\1:\2", norm)        # +0100 -> +01:00 (Python < 3.11)
    norm = re.sub(r"(\.\d{6})\d+", r"\1", norm)                     # trim extra fraction digits
    dt = datetime.fromisoformat(norm)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    if tz_name and tz_name.upper() == "UTC":
        dt = dt.astimezone(timezone.utc)  # no time zone database needed (Windows has none)
    elif tz_name:
        from zoneinfo import ZoneInfo  # on Windows, needs: pip install tzdata
        dt = dt.astimezone(ZoneInfo(tz_name))
    else:
        dt = dt.astimezone()  # this computer's zone
    return dt.hour * 3600 + dt.minute * 60 + dt.second + dt.microsecond / 1e6, f"{src} = {raw} -> {dt.strftime('%H:%M:%S %Z')}"


def load_font(px, mono=False):
    win = os.path.join(os.environ.get("WINDIR", r"C:\Windows"), "Fonts")
    names = (("/System/Library/Fonts/Menlo.ttc", "/System/Library/Fonts/SFNSMono.ttf",
              "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf",
              os.path.join(win, "consolab.ttf"), os.path.join(win, "consola.ttf")) if mono else
             ("/System/Library/Fonts/Helvetica.ttc", "/System/Library/Fonts/SFNS.ttf",
              "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
              os.path.join(win, "arialbd.ttf"), os.path.join(win, "segoeuib.ttf")))
    for f in names:
        try:
            return ImageFont.truetype(f, px)
        except OSError:
            pass
    # Pillow's own font, at the size asked for (without a size it is a fixed 10 px)
    return ImageFont.load_default(px)


SUBSEC_DIGITS = {"none": 0, "tenths": 1, "ms": 3}


def fmt_time(t, elapsed, long_run, subsec="none"):
    ms_total = int(round(t * 1000))          # round once, so .9999 can't show as .10
    t, frac = ms_total // 1000, ms_total % 1000
    h, m, sec = t // 3600, (t // 60) % 60, t % 60
    if elapsed and not long_run:
        out = "%02d:%02d" % (m, sec)
    else:
        out = "%02d:%02d:%02d" % (h % 24 if not elapsed else h, m, sec)
    digits = SUBSEC_DIGITS[subsec]
    if digits:
        out += "." + ("%03d" % frac)[:digits]
    return out


def fmt_sample(elapsed, long_run, subsec):
    """The widest string a readout will show, for fitting its font."""
    base = "00:00" if (elapsed and not long_run) else "00:00:00"
    digits = SUBSEC_DIGITS[subsec]
    return base + ("." + "0" * digits if digits else "")


class Clock:
    def __init__(self, size, style, label, elapsed, long_run, dual=False, start=0,
                 subsec="none", subsec_on="elapsed"):
        self.size, self.style, self.label = size, style, label
        # Sub-seconds on the main readout when it shows elapsed time, or when asked for all;
        # on the --dual panel whenever they are on at all.
        self.main_subsec = subsec if (elapsed or subsec_on == "all") else "none"
        self.dual_subsec = subsec
        self.elapsed, self.long_run = elapsed, long_run
        self.dual, self.start = dual and not elapsed, start
        self.dual_h = int(size * 0.26) if self.dual else 0
        self.analog_h = size if style in ("analog", "both") else 0
        self.digital_h = int(size * 0.34) if style in ("digital", "both") else 0
        self.label_h = int(size * 0.22) if label else 0
        self.gap = int(size * 0.05) if (self.analog_h and self.digital_h) else 0
        self.gap2 = int(size * 0.04) if self.dual else 0
        self.w = size
        self.h = self.analog_h + self.gap + self.digital_h + self.gap2 + self.dual_h + self.label_h
        self.capfont = load_font(int(size * 0.075) * SS)
        self.font = load_font(int(size * 0.13) * SS)
        sample = fmt_sample(elapsed, long_run, self.main_subsec)
        px = int(size * 0.30) * SS
        f = load_font(px, mono=True)
        while f.getlength(sample) > (size - 24) * SS and px > 10:
            px -= SS
            f = load_font(px, mono=True)
        self.dfont = f
        e_sample = fmt_sample(True, long_run, self.dual_subsec)
        # The elapsed time sits right of its "ELAPSED" caption: fit it to the space left,
        # 10 px margins either side and an 8 px gap, so wider sub-second text can't collide.
        e_room = (size - 28) * SS - self.capfont.getlength("ELAPSED")
        epx = int(size * 0.17) * SS
        ef = load_font(epx, mono=True)
        while ef.getlength(e_sample) > e_room and epx > 10:
            epx -= SS
            ef = load_font(epx, mono=True)
        self.efont = ef

    def render(self, seconds):
        W, H = self.w * SS, self.h * SS
        im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        y = 0
        if self.analog_h:
            self._analog(d, seconds, W)
            y += self.analog_h * SS + self.gap * SS
        if self.digital_h:
            dh = self.digital_h * SS
            d.rounded_rectangle([2 * SS, y, W - 2 * SS, y + dh], radius=dh * 0.25,
                                fill=(15, 18, 28, 215), outline=(255, 255, 255, 235), width=3 * SS)
            txt = fmt_time(seconds, self.elapsed, self.long_run, self.main_subsec)
            bb = d.textbbox((0, 0), txt, font=self.dfont)
            d.text(((W - (bb[2] - bb[0])) / 2 - bb[0], y + (dh - (bb[3] - bb[1])) / 2 - bb[1]),
                   txt, font=self.dfont, fill=(255, 255, 255, 255))
            y += dh
        if self.dual:
            y += self.gap2 * SS
            eh = self.dual_h * SS
            d.rounded_rectangle([2 * SS, y, W - 2 * SS, y + eh], radius=eh * 0.25,
                                fill=(255, 140, 40, 60), outline=(255, 140, 40, 235), width=3 * SS)
            cap = "ELAPSED"
            cb = d.textbbox((0, 0), cap, font=self.capfont)
            d.text((10 * SS - cb[0], y + (eh - (cb[3] - cb[1])) / 2 - cb[1]), cap,
                   font=self.capfont, fill=(255, 190, 120, 255))
            txt = fmt_time(max(0, seconds - self.start), True, self.long_run, self.dual_subsec)
            tb = d.textbbox((0, 0), txt, font=self.efont)
            d.text((W - 10 * SS - (tb[2] - tb[0]) - tb[0], y + (eh - (tb[3] - tb[1])) / 2 - tb[1]),
                   txt, font=self.efont, fill=(255, 255, 255, 255))
            y += eh
        if self.label:
            tw = d.textlength(self.label, font=self.font)
            d.text(((W - tw) / 2, y + 3 * SS), self.label, font=self.font, fill=(255, 255, 255, 235),
                   stroke_width=2 * SS, stroke_fill=(0, 0, 0, 200))
        return im.resize((self.w, self.h), Image.LANCZOS)

    def _analog(self, d, seconds, W):
        c = W / 2
        r = W / 2 - 4 * SS
        d.ellipse([c - r, c - r, c + r, c + r], fill=(15, 18, 28, 215),
                  outline=(255, 255, 255, 235), width=4 * SS)
        for i in range(60):
            a = math.radians(i * 6)
            major = i % 5 == 0
            r1 = r * (0.80 if major else 0.88)
            d.line([c + r1 * math.sin(a), c - r1 * math.cos(a),
                    c + r * 0.94 * math.sin(a), c - r * 0.94 * math.cos(a)],
                   fill=(255, 255, 255, 235 if major else 150), width=(5 if major else 2) * SS)

        def hand(angle_deg, length, width, colour, tail=0.0):
            a = math.radians(angle_deg)
            d.line([c - tail * r * math.sin(a), c + tail * r * math.cos(a),
                    c + length * r * math.sin(a), c - length * r * math.cos(a)],
                   fill=colour, width=int(width * SS))

        if not self.elapsed:  # a stopwatch has no hour hand
            hand((seconds / 3600) % 12 * 30, 0.50, 9, (255, 255, 255, 255))
        hand((seconds / 60) % 60 * 6, 0.74, 6, (255, 255, 255, 255))
        hand(seconds % 60 * 6, 0.84, 2.5, (255, 140, 40, 255), tail=0.15)
        d.ellipse([c - 7 * SS, c - 7 * SS, c + 7 * SS, c + 7 * SS], fill=(255, 140, 40, 255))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("input"); ap.add_argument("output")
    ap.add_argument("--start", default="auto", help="auto|current | HH:MM[:SS] | elapsed|zero")
    ap.add_argument("--style", default="analog", choices=["analog", "digital", "both"])
    ap.add_argument("--dual", action="store_true", help="also show elapsed time below the clock")
    ap.add_argument("--subsec", default="none", choices=["none", "tenths", "ms"],
                    help="sub-second digits on the digital readouts")
    ap.add_argument("--subsec-on", default="elapsed", choices=["elapsed", "all"],
                    help="readouts that get them: elapsed (default) or all, adding the time of day")
    ap.add_argument("--tz", help="time zone for --start auto, e.g. UTC")
    ap.add_argument("--speed", type=float, default=15)
    ap.add_argument("--size", type=int, default=220)
    ap.add_argument("--pos", default="tr", choices=["tr", "tl", "br", "bl"])
    ap.add_argument("--label")
    a = ap.parse_args()

    w, h, dur, tags = probe(a.input)
    a.start = {"current": "auto", "zero": "elapsed"}.get(a.start, a.start)
    if a.start == "elapsed":
        start, how = 0, "elapsed time from 00:00"
    elif a.start == "auto":
        start, how = start_from_metadata(tags, a.tz)
    else:
        p = [int(x) for x in a.start.split(":")] + [0, 0]
        start, how = p[0] * 3600 + p[1] * 60 + p[2], "given with --start"
    hms = lambda t: "%02d:%02d:%02d" % (int(t // 3600) % 24, int(t // 60) % 60, int(t) % 60)
    print(f"Clock starts at {hms(start)} ({how}), ends at {hms(start + dur)}.\n"
          f"Check the start against the first log line in the recording.", file=sys.stderr)
    label = f"{a.speed:g}\u00d7 speed" if a.label is None else a.label
    elapsed = a.start == "elapsed"
    if a.dual and elapsed:
        print("--dual ignored: --start zero already shows elapsed time.", file=sys.stderr)
    shows_digital = a.style in ("digital", "both") or (a.dual and not elapsed)
    if a.subsec != "none":
        if not shows_digital:
            print(f"--subsec {a.subsec} has no effect: it applies to digital readouts only "
                  "(use --style digital|both, or --dual).", file=sys.stderr)
        if a.subsec_on == "all" and not elapsed:
            print(f"--subsec-on all: the time of day's start ({how}) is only known to the "
                  "second, so its sub-second digits are not accurate.", file=sys.stderr)
        step = a.speed / FPS                      # real seconds per output frame
        # ms stops meaning more than tenths once a frame covers 0.1 s (3x); tenths stop
        # meaning anything once a frame covers more than 0.1 s.
        coarse = step >= 0.1 if a.subsec == "ms" else step > 0.1
        if coarse:
            shown = sorted({fmt_time(i * step, True, False, a.subsec).split(".")[1]
                            for i in range(int(round(10 / step)) + 1)})
            more = "" if len(shown) <= 10 else f" … ({len(shown)} values)"
            print(f"--subsec {a.subsec} at {a.speed:g}x: each frame covers {step:.3f} s of real "
                  f"time, so the digits only show ." + "/.".join(shown[:10]) + more + ".",
                  file=sys.stderr)
            if a.subsec == "ms":
                print("Use --subsec tenths at --speed 3 and above.", file=sys.stderr)
            elif step >= 0.5:
                print("At this speed, --subsec none reads better.", file=sys.stderr)
    clock = Clock(a.size, a.style, label, elapsed, long_run=(dur >= 3600), dual=a.dual, start=start,
                  subsec=a.subsec, subsec_on=a.subsec_on)
    cw, ch = clock.w, clock.h
    m = 40
    x = {"tr": w - cw - m, "br": w - cw - m, "tl": m, "bl": m}[a.pos]
    y = {"tr": m, "tl": m, "br": h - ch - m, "bl": h - ch - m}[a.pos]

    out_dur = dur / a.speed
    n = int(out_dur * FPS)
    print(f"{dur:.0f}s in -> {out_dur:.1f}s out at {a.speed:g}x, {n} frames", file=sys.stderr)

    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-stats",
           "-i", a.input,
           "-f", "rawvideo", "-pix_fmt", "rgba", "-s", f"{cw}x{ch}", "-r", str(FPS), "-i", "-",
           "-filter_complex",
           f"[0:v]setpts=PTS/{a.speed},fps={FPS}[v];[v][1:v]overlay={x}:{y}:shortest=1,format=yuv420p",
           "-an", "-c:v", "libx264", "-crf", "18", "-preset", "medium",
           "-movflags", "+faststart", a.output]
    ff = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    try:
        for i in range(n):
            real = start + (i / FPS) * a.speed
            ff.stdin.write(clock.render(real).tobytes())
        ff.stdin.close()
    except BrokenPipeError:
        # n is an estimate; the sped up video can end a few frames sooner, and ffmpeg
        # (overlay shortest=1) stops reading when it does. The output is complete.
        pass
    sys.exit(ff.wait())


if __name__ == "__main__":
    main()
