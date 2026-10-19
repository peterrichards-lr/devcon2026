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

**Expect**

- `Initialized com.liferay.site.initializer.masterclass.cms … in N ms`
- `batch files deployed: 7`, and nothing under `Unable to deploy batch`
- nothing under `errors since restore`
- a site id on the last line. Every later stage takes it as `<groupId>`, and it can change
  between runs.

**If it fails**

| Symptom | Cause | Do this |
| --- | --- | --- |
| `Global search service not running` during the restore | Search was not up when LDM restored. Every `/o/` call then returns 404 and the Space comes up without its folders. | Wait for `liferay-search-global`, then run the script again. Restarting Liferay is not enough. |
| `TIMEOUT waiting for: STARTED …` | The artifact did not start. | Read the log for that bundle. Fix, rebuild, and run the script again. |
| `InitializationException` | The initializer failed and rolled the site back, so no site exists. | Read the exception (`grep -A20 InitializationException` in the log). Fix the tree, rebuild, run again. |
| `Unable to deploy batch …NoSuchGroupException` | The batch ran before the site existed. | Run again; the script keeps the order. |
| `Unable to deploy batch` for any other reason | A data file is wrong. | Fix it, rebuild the batch, run again. A partial import cannot be cleanly removed. |
| `site id: not found` | The site was not created. | Treat as `InitializationException`. |

## Stage 3. Collections

```bash
scripts/check-collections.sh <groupId>
```

**Expect** `ok` on all five pages: `/blog`, `/blog-entry`, `/course`, `/courses`, `/home`.

**If it fails.** `MISSING` means the site initializer's handler order race hit this run
(UPSTREAM-FEEDBACK.md, item 7): the pages were imported before their collections existed.
Nothing in the tree can prevent it. Go back to stage 2 and provision again; it usually
passes on the next run.

## Stage 4. Guest view

```bash
scripts/guest-check.sh <groupId>
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
scripts/demo-prep.sh <groupId>
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
scripts/student-check.sh <groupId>
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
| `masterclass-02-<short commit>` | The latest clean run of this procedure | Stage, recording |
| `masterclass-02-7de77b5` | 02 at `7de77b5`: everything except the demo student | Last resort; it has no demo student, so stage 8 cannot be shown |
