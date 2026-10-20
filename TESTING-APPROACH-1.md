# Testing Approach 1

How to prove Approach 1 end to end on a clean instance, and how to back out when a stage
fails. The steps follow [README.md](README.md#running-approach-1) literally; the scripts
in [`scripts/`](scripts) do the waiting and checking.

A run is **clean** when every stage below passes with no manual permission changes. The
only allowed step after provisioning is the scripted, documented activation of the demo
student (stage 5). Take the stage snapshot from a clean run only.

The commands assume an LDM project called `devcon2026` in `~/ldm-verify/devcon2026`, with
a snapshot `clean-2026q3.5` that holds no Masterclass data, and the admin
`test@liferay.com` / `test`. Every script reads `LIFERAY_URL` and `LIFERAY_ADMIN`, and
`scripts/ldm-provision.sh` also reads `LDM_DIR`, `LDM_PROJECT`, `CLEAN_SNAPSHOT` and `WT`.

## Recording the run

The whole run, from a clean snapshot to the stage snapshot, recorded in one take. It takes
about 7 minutes, almost all of it provisioning (rehearsed on 2026-10-19):

| Stage | Time |
| --- | --- |
| 1. Build | about 25 s |
| 2. Provision | about 5 m 45 s |
| 3. to 6. Checks and the demo student | about 30 s |

### Before you record

1. **Merge what you are recording into 02**, then move the worktree to it. Nothing needs
   rebuilding by hand; stage 1 builds:

   ```bash
   cd ../devcon2026-test
   git fetch upstream
   git checkout --detach upstream/02-aiconversion
   ```

1. **Check the shared search container is running.** A missing `liferay-search-global`
   breaks the restore (stage 0). `ldm-provision.sh` refuses to start without it, but it is
   better found now than on camera:

   ```bash
   docker ps --format '{{.Names}}' | grep liferay-search-global
   ```

1. **Check that Docker's clock agrees with the Mac's.** The log's timestamps come from
   Docker's virtual machine and the time-lapse clock from the Mac, so they only line up if
   the two clocks do. With the instance running:

   ```bash
   python3 -c "import subprocess, time; m = time.time(); d = float(subprocess.check_output(['docker', 'exec', 'devcon2026', 'date', '-u', '+%s.%N'])); print(f'Docker minus Mac: {d - m:+.2f} s')"
   ```

   Anything within about half a second is fine (measured +0.08 s on 2026-10-19, part of it
   the command's own delay). A larger gap means Docker's clock has drifted; restarting
   Docker Desktop resyncs it.

1. **Lay out the screen** (macOS, Terminal.app), from the worktree:

   ```bash
   MENU_BAR=0 scripts/record-layout.sh
   ```

   It finds the 1920x1080 display and opens two windows on it, in a "Recording" profile:
   Menlo 20 pt, dark by default, with titles that say what each window shows. The top-right
   300x350 is left clear for a clock. Running it again replaces both windows.

   | Window | Shows |
   | --- | --- |
   | Liferay server log (live), left | `scripts/follow-logs.sh`: the project's consolidated `ldm logs`, each line keeping its `service \|` prefix, the message coloured by what it says |
   | Approach 1: build, provision and check, right | the worktree, with `scripts/record-approach-1.sh` typed at the prompt, waiting for Enter |

   | Option | Default | Use |
   | --- | --- | --- |
   | `MENU_BAR` | `30` | `0` when the menu bar is hidden; otherwise it keeps clear the menu bar macOS doesn't report on a second display |
   | `SCREEN_NAME` | none | lay out another display by name, for example `Built-in` |
   | `THEME` | `dark` | `light` for a white background |

1. **Set up the screen recording:** the 1920x1080 display, **SDR** (not HDR; the content
   and the playback are SDR, and HDR comes out washed out when converted), 30 fps.

### Recording

Start the screen recording, then press Enter in the right window.

`record-approach-1.sh` runs stages 1 to 6 below in order. Before each stage it shows a
banner and waits for Enter, so you set the pace. Each command is printed as `$ …` before it
runs, with every `--user` password shown as `****`. It passes the group id on by itself,
stops at the first stage that fails, and ends with the time each stage took.

What to expect, and what to say about it:

| Moment | In the log window | In the run window |
| --- | --- | --- |
| Restore | Red `FATAL` lines from `devcon2026-db`: the restore starts from an empty database (`database "lportal" does not exist`) and stops Liferay while it is still connected (`connection to client lost`). Then `container restarted, reconnecting`. Nothing red once Liferay is back up. | `$ ldm restore …`, then `Liferay ready` |
| Deploys | Green `STARTED` for each module and client extension | One `$ cp …` per artifact |
| Site creation | Cyan `Invoking …` handler steps, then bold green `Initialized com.liferay.site.initializer.masterclass.cms` | `handler order ok`, or `RACE` and a second provision (see stage 2) |
| Data batch | Bold green `Successfully deployed batch engine file` for each of the seven files | `batch files deployed: 7` |
| Checks | Quiet | `ok` lines; two `WARN` lines in the student checks are the known self-approve issue |

At the end it asks for a snapshot name. Use `masterclass-02-<short commit>`; Enter skips.
Stage 8, the browser check, stays manual: do it after the snapshot, so the Pending
enrolment it creates is not in it.

`PAUSE=0` runs straight through without stopping; `SNAPSHOT=<name>` takes the snapshot
without asking. To follow the logs without the layout script:

```bash
scripts/follow-logs.sh
```

### Making the time-lapse

One command does it, while the recorded instance is still up:

```bash
python3 scripts/make-timelapse.py
```

It takes the newest `Screen Recording*.mov` on the Desktop (or a file you name), and:

1. renames it `approach-1-<commit>-<YYYYMMDD-HHMM>.mov` (`--name` to choose);
1. trims the still stretches at either end: from a second before the first change in the
   run window (so the pointer moving doesn't count) to two seconds after the last change on
   screen, cutting on a whole second and writing the trimmed file's own start time, so the
   clock stays exact;
1. renders `<name>-timelapse.mp4` with the clock below, at `--speed 15 --tz UTC` and
   `--style digital --dual --size 260` (anything after `--` replaces those clock options);
1. runs the spot check below and saves `<name>-clock-check.png`.

On 2026-10-19 it cut a 6 min 7 s take to 5 min 44 s and rendered 22.6 s at 15x; the
check frame showed 17:52:22 on the clock as the `Initialized` line stamped 17:52:22.802
arrived. The rest of this section is what it does, step by step, for running by hand.

`scripts/clock_overlay.py` speeds the recording up and draws a clock in the corner the
layout left clear. The clock keeps **real** time while the video runs fast, so it races
during provisioning and still lines up with the timestamps in the log window. Run it on
the full, uncut recording, then trim:

```bash
python3 scripts/clock_overlay.py "<recording>.mov" "<recording>-timelapse.mp4" \
	--speed 15 --tz UTC --style digital --dual --size 260
```

This is the form used for the talk: a digital time of day that reads like the log's
timestamps, with an elapsed-time panel under it, so the time-lapse shows both when each
step happened and how long the run has taken. At `--size 260` it is 260 x 222 px, the
largest that fits the clear corner's width.

- **`--tz UTC`**, because Liferay's log timestamps are in UTC. The clock starts at the time
  read from the recording's metadata, converted to `--tz` (default: this Mac's zone). It
  prints that time before rendering; check it against the first log line in the recording.
  Use `--start HH:MM:SS` only if the metadata is missing.
- At `--speed 15`, a 12 minute take becomes about 50 seconds.
- `--style analog|digital|both` chooses the clock, `--dual` adds an elapsed-time panel
  under it, and `--start zero` turns it into a stopwatch.
- `--subsec tenths|ms` adds sub-second digits to the digital elapsed readouts
  (`--subsec-on all` adds them to the time of day too, though its start is only known to the
  second). Each frame covers speed/30 s of real time, so at `--speed 15` even tenths only
  show `.0` and `.5`; the script says so. Sub-seconds suit real-time clips, not the time-lapse.
- **It has to fit the clear corner**: 310 px of height below its 40 px margin, at the
  default `CLOCK_H=350`. At the default `--size 220`, analog with its label is 268 px and
  fits; analog with `--dual` (333 px) or `--style both` (353 px) does not. Use `--size 200`
  with `--dual`, or lay the screen out with a taller corner, such as
  `CLOCK_H=420 scripts/record-layout.sh`, before recording.

**Check the clock against the log.** Pick an event whose exact time the log records, find
the frame where it appears, and compare the clock with the newest log line. The site
initializer's `Initialized` line works well: it appears once, in bold green, near the end
of provisioning. Run this while the recorded instance is still up, since `docker logs` only
covers the current container:

```bash
REC="<recording>.mov"; TL="<recording>-timelapse.mp4"; SPEED=15
EVENT=$(docker logs devcon2026 2>&1 | grep -m1 "Initialized com.liferay.site.initializer" | cut -c1-23)
START=$(ffprobe -v error -show_entries format_tags=creation_time -of default=nw=1:nk=1 "$REC")
AT=$(python3 -c "from datetime import datetime as d; e = d.fromisoformat('$EVENT+00:00'); s = d.fromisoformat('$START'.replace('Z', '+00:00')); print(round((e - s).total_seconds() / $SPEED, 2))")
echo "$EVENT should appear at ${AT}s"
ffmpeg -loglevel error -y -ss "$AT" -i "$TL" -frames:v 1 clock-check.png && open clock-check.png
```

The clock should read the event's second, give or take one, with the `Initialized` line
just appearing at the bottom of the log window. On 2026-10-19 the line stamped 16:46:36.226
appeared between the clock reading 16:46:35 and 16:46:37. If they are further apart,
re-render with `--start HH:MM:SS` set to the corrected start time.

It needs `ffmpeg` (`brew install ffmpeg`) and Pillow (`pip3 install pillow`).

## The one rollback that always works

From stage 2 onwards, provisioning writes things that outlive the site: company scoped
objects, the Space, users, search documents. Deleting the site does not take them back
out, so do not try to repair a failed test run piece by piece. Fix the cause, then go back
to stage 1 and start again from the clean snapshot:

```bash
scripts/ldm-provision.sh
```

It empties `osgi/modules`, restores `clean-2026q3.5`, and deploys everything again. The
per stage notes below say what to fix before you do.

## Stage 0. Preflight

```bash
docker ps --format '{{.Names}}' | grep -E '^(liferay-search-global|devcon2026|devcon2026-db)$'
ls ~/ldm-verify/devcon2026/snapshots
```

**Expect** `liferay-search-global` in the list, and the clean snapshot on disk.

**If it fails**

| Symptom | Do this |
| --- | --- |
| `liferay-search-global` is missing | Start it before anything else. Do **not** run `ldm run` while it is missing: LDM's automatic search volume repair deletes the shared search data of every LDM project on the machine. |
| Someone else is using the instance | Agree who is driving. Two people restoring the same instance within a minute leaves it in neither person's state. |

## Stage 1. Build

Check out the commit under test. A separate worktree keeps your working copy out of it:

```bash
git fetch upstream
git worktree remove --force ../devcon2026-test 2>/dev/null
git worktree add --detach ../devcon2026-test upstream/02-aiconversion
cd ../devcon2026-test

blade gw clean \
	:modules:masterclass-cms-workarounds:jar \
	:modules:masterclass-cms-site-initializer:jar \
	:client-extensions:liferay-masterclassobj-simplerheadlesscallsjs:assemble \
	:client-extensions:liferay-masterclass-custom-css:assemble \
	:client-extensions:masterclass-cms-data-batch:assemble
```

**Expect** `BUILD SUCCESSFUL`, two jars in `modules/*/build/libs/` and three zips in
`client-extensions/*/dist/`.

**If it fails**

| Symptom | Do this |
| --- | --- |
| `Cannot locate tasks that match …` | The command was cut when pasted. Paste it again as the multi line block above. |
| A compile or assemble error | Nothing has been deployed yet, so there is nothing to roll back. Fix the source and build again. |

## Stage 2. Provision

```bash
WT=$PWD scripts/ldm-provision.sh
```

It runs the README deploy order: the workarounds module and the two global client
extensions, then the site initializer, then creates the site, then deploys the data
batch. Each artifact must log `STARTED` before the next one goes in.

It also reads the order the site initializer ran its handlers in. When the collections were
created after the pages (the race in stage 3), it says `RACE` and provisions again from the
restore, up to `MAX_ATTEMPTS` times (default 3), before it deploys the batch or prints the
export line. Stage 3 still checks the result.

**Expect**

- `Initialized com.liferay.site.initializer.masterclass.cms … in N ms`
- `batch files deployed: 7`, and nothing under `Unable to deploy batch`
- under `errors since restore`, only the known start-up and site-creation loggers:
  `HeadlessDisplayTag` and `BaseDisplayTag` (data set tags rendered before their serializer
  is up, a few seconds after Liferay starts) and `RESTClientTemplateContextContributor` (2,
  fragments rendered while the site is being built), and sometimes `ElasticsearchIndexWriter`
  and `BulkDocumentRequestExecutor` (a search delete for an entry that wasn't indexed). Any
  other logger is worth reading;
  see LESSONS-LEARNT.md, "The red in the log is the platform warming up"
- the new site's id, then a line `export MASTERCLASS_GROUP_ID=<id>`. **Paste that line
  into your shell.** The later scripts read it, print which site they are checking, and
  stop if it is not set. The id can change between runs, so paste the new line after every
  provision. Passing the id as the first argument also works.

**If it fails**

| Symptom | Cause | Do this |
| --- | --- | --- |
| `Global search service not running` during the restore | Search was not up when LDM restored. Every `/o/` call then returns 404 and the Space comes up without its folders. | Wait for `liferay-search-global`, then run the script again. Restarting Liferay is not enough. |
| `TIMEOUT waiting for: STARTED …` | The artifact did not start. | Read the log for that bundle. Fix, rebuild, and run the script again. |
| `InitializationException` | The initializer failed and rolled the site back, so no site exists. | Read the exception (`grep -A20 InitializationException` in the log). Fix the tree, rebuild, run again. |
| `Unable to deploy batch …NoSuchGroupException` | The batch ran before the site existed. | Run again; the script keeps the order. |
| `Unable to deploy batch` for any other reason | A data file is wrong. | Fix it, rebuild the batch, run again. A partial import cannot be cleanly removed. |
| `site id: not found` | The site was not created. | Treat as `InitializationException`. |
| `RACE: … ran before addAssetListEntries` | The handler order race. | Nothing: the script provisions again by itself. |
| `gave up after 3 attempts` | The race hit every attempt. | Run the script again, or set `MAX_ATTEMPTS` higher. |

## Stage 3. Collections

```bash
scripts/check-collections.sh
```

**Expect** `ok` on all five pages: `/blog`, `/blog-entry`, `/course`, `/courses`, `/home`.

**If it fails.** `MISSING` means the site initializer's handler order race hit this run
(UPSTREAM-FEEDBACK.md, item 7): the pages were imported before their collections existed.
Nothing in the tree can prevent it. Stage 2 normally catches it from the log and provisions
again; if a run still gets here, go back to stage 2. It usually passes on the next run.
`guest-check.sh` reports the same run as `no display page links found` and `No Results Found`.

## Stage 4. Guest view

```bash
scripts/guest-check.sh
```

It fetches every page as an anonymous visitor, then the course and blog display pages they
link to, then every image, document, stylesheet and script on all of them.

**Expect** `0 failure(s)`. The five member-only pages (account settings, course completions,
course registrations, my learning, notifications) must answer 404 to a visitor, and are
reported as `member-only`.

**If it fails**

| Symptom | Do this |
| --- | --- |
| A public page or display page is not 200 | Check the page's permissions in its `page.json`. Fix the tree, then go back to stage 2. |
| A member-only page answers 200 to Guest | Its `page.json` lost the Guest restriction. Same fix. |
| An image answers 200 with 0 bytes | An empty attachment. Check the batch data for that entry. |
| `No Results Found` or a `[$…$]` token in the HTML | A collection or token did not resolve. Run stage 3; if it passed, check the token's name in the tree. |

## Stage 5. Prepare the demo student

```bash
scripts/demo-prep.sh
```

Users created by a site initializer are inactive by design: `BundleSiteInitializer` sets
each one to inactive after creating it (LPS-184738), so an initializer can't silently
create accounts that can sign in. The script:

1. activates `student.one@liferay.com` and checks it can sign in. This is the one allowed
   post-provision step;
2. as the student, enrols in **Building Enterprise Websites with Liferay** with the register
   button's payload; as admin, approves; as the student, confirms;
3. checks My Learning shows the course.

It is safe to run again: a course that is already Confirmed is kept.

**Expect** `My Learning shows 'Building Enterprise Websites with Liferay'`.

**If it fails**

| Symptom | Cause | Do this |
| --- | --- | --- |
| `no user student.one@liferay.com` | `user-accounts.json` did not run, or used another address. | Check `Invoking addUserAccounts` in the log and the file in the tree. Fix, back to stage 2. |
| `is active but cannot sign in` | Wrong password in `user-accounts.json`, or a password policy blocked it. | Fix the tree, back to stage 2. |
| `the student cannot find MyCourseSession` | Site Member has no VIEW on MyCourseSession. | A grant is missing from `resource-permissions.json`. Fix the tree, back to stage 2. Do not grant it by hand. |
| `the student's enrolment was refused` | No ADD on MyCourseEnrollment, or no VIEW on the linked session (that also returns 403). | Same: fix the grant in the tree. |
| `approve left it …` or `confirm left it …` | An object action failed. | Read the log for the action. Fix the object definition, back to stage 2. |
| `My Learning does not show …` | The user courses fragment or its filter. | Fix the fragment, back to stage 2. |

## Stage 6. Student checks

```bash
scripts/student-check.sh
```

**Expect** `0 failure(s), 2 warning(s)`. The two warnings are a known issue, logged and not
fixed before DevCon: an enrolment's owner can approve it, or set its status, themselves.

The script checks that the student can sign in, read every course object and the
MyCourseSession lookup the register button makes, sees the Confirmed course from stage 5,
and can go through enrol, approve, confirm over REST, but cannot list, read, change or
delete another user's enrolment. It grants nothing, so a missing grant shows up as a
failure, and it removes the enrolments and the test user it creates, even when it fails.

**If it fails**

| Symptom | Do this |
| --- | --- |
| `exists but is Inactive` | Stage 5 did not run, or did not finish. Run it. |
| Any `FAIL` naming a grant, a 401 or a 403 | A permission is missing from the tree. Fix it, back to stage 2. A manual grant would make the run unclean. |
| `student lists other's enrolments` is not 0, or another user's enrolment changed | Something grants VIEW or UPDATE too widely. Fix the tree, back to stage 2. |
| The script was killed part way | Its cleanup may not have run. Delete the user `other.tester@example.com` and any enrolment other than the stage 5 one, then run it again. |

## Stage 7. Snapshot

Only after stages 2 to 6 have all passed on the same run:

```bash
cd ~/ldm-verify/devcon2026
ldm snapshot devcon2026 -n masterclass-02-<short commit> -y
```

**Expect** `Snapshot saved`, with `database.sql` and `search` in the new folder under
`snapshots/`. A snapshot taken while the stack is stopped has no `database.sql`.

**If it fails.** Make sure the stack is running and try again. Nothing on the instance changes.

## Stage 8. Check 3, in a browser

1. Open the site and sign in as `student.one@liferay.com` / `test`.
2. Open a course **other than** Building Enterprise Websites and register for a session.
3. Course Registrations shows the new course as **Pending**.
4. My Learning shows **Building Enterprise Websites with Liferay**.
5. Watch for any prompt on first sign in, such as a password change or terms of use. There
   should be none.

The snapshot was taken before this step, so the Pending enrolment you create here is not
in it.

**If it fails.** Do not use the stage 7 snapshot. Note what you saw, fix the cause, and go
back to stage 1. If you need a working instance in the meantime, restore the previous
fallback (below).

## On stage

```bash
cd ~/ldm-verify/devcon2026
ldm restore devcon2026 -n masterclass-02-<short commit> --up -y
```

Then sign in as the demo student and register for a second course, as in stage 8.

**If the restore fails or the site looks wrong**

| Symptom | Do this |
| --- | --- |
| `Global search service not running` | Start `liferay-search-global`, then restore again. |
| Lists or collections are empty | Check `docker ps` for `liferay-search-global`; if it is there, restore again. |
| Anything else | Restore the previous fallback snapshot and use the recorded backup video. |

## Fallback snapshots

| Snapshot | Contents | Use |
| --- | --- | --- |
| `masterclass-02-<short commit>` | The next clean run of this procedure, taken at the end of the recording | Stage, once it passes stage 8 |
| `masterclass-02-26093eb` | 02 at `26093eb`: every stage passed, browser check included (2026-10-19). Its build is identical to 02 at `d0806f0` apart from build timestamps | Stage fallback until the recorded run replaces it |
| `masterclass-02-7de77b5` | 02 at `7de77b5`: everything except the demo student | Last resort; it has no demo student, so stage 8 cannot be shown |
