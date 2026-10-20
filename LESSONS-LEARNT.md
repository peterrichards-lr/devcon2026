# Lessons Learnt

Raw material for the DevCon 2026 talk. Each entry is something that happened while moving
the Masterclass LMS from web content to the objects based CMS, what it taught us, and how
it might land on a slide.

The talk has two use cases, so the entries are split by approach. Within each approach,
newest first. Add a new entry at the top of the approach it belongs to; tidy it when the
slides are planned.

Every entry should say **what happened**, **the lesson**, and **the evidence** (an issue,
PR, commit, or measurement), so a claim on a slide can be traced back to something real.

## The two approaches

| | Approach 1: site initializer to site initializer | Approach 2: live site, migrated in place |
| --- | --- | --- |
| Use case | 1 (first 20 minutes) | 2 (second 20 minutes) |
| Starting point | The 2024 Masterclass site initializer: web content, DDM structures and templates | A running DXP site on the old CMS and DAM: web content and Documents and Media |
| End point | A new initializer on the new CMS: a Space, content structures, objects, plus a batch client extension for the data | The same site, now on the new CMS and Spaces |
| How | AI rewrites the initializer tree; the site is recreated from it | AI calls the Headless APIs and MCP against the live site; no initializer involved |
| Lessons | [Approach 1](#approach-1-site-initializer-to-site-initializer) | [Approach 2](#approach-2-live-site-migrated-in-place) |

## Decisions

Calls made along the way that shape what is shown on stage. Newest first; each says who
agreed it and where the change landed.

| Date | Decision | Why | Where |
| --- | --- | --- | --- |
| 2026-10-20 | The demo student stays activated by `demo-prep.sh`, not by the workarounds module | The initializer creates users inactive on purpose (LPS-184738), so it can't silently create accounts that can sign in; activating them automatically in a module would undo that quietly. A visible, scripted exception keeps it honest, and the script is needed anyway for the prepared enrolment. The time-lapse was also already recorded with this flow. Peter | `scripts/demo-prep.sh` |
| 2026-10-20 | Prevent a student registering twice for the same session with a composite key rule, in the workarounds module | Rafa built this live in 2024; the site initializer can't declare it (item 8). Rafa asked whether one OSGi module could replace the script altogether. It can't sensibly (see the row above), so the line is drawn by purpose: fixes to the data model go in the module, where they apply to every site created from the tree; steps taken only for the stage stay in the script. Peter and Rafa | #100 (in progress) |
| 2026-10-19 | The time-lapse runs at 15x with a digital UTC clock and an elapsed panel; the backup video of the live enrolment stays real time, with no clock | The clock matches the log timestamps, so the audience can see both when each step happened and how long it took. A live action should play at its real pace | #98, #99 |
| 2026-10-19 | The recorded take is the stage fallback: snapshot `masterclass-02-b0684c3`, tagged `devcon-approach-1` | Every stage passed, the browser check included. Later 02 commits only add the time-lapse tooling | tags, `TESTING-APPROACH-1.md` |
| 2026-10-19 | Master becomes the converted site; the before state is kept as the tag `devcon-start` | People will look at master. A tag keeps the starting point one checkout away | #92, #96 |
| 2026-10-19 | Leave the database's red `FATAL` lines during the restore red, and explain them | They are real: the restore starts the database from empty and stops Liferay while it is connected. Nothing red appears after Liferay is back up | narration |
| 2026-10-19 | Students approving or completing their own enrolment is a known issue, logged and not fixed before DevCon | The stage flow doesn't depend on it; `student-check.sh` reports it as a warning | entry below |
| 2026-10-19 | Only scripted, documented steps after provisioning: activating the demo student. Any manual permission change makes a run unclean | Everything on stage has to come from the tree, the batch or a script in the repo | #88, `TESTING-APPROACH-1.md` |
| 2026-10-19 | Give the demo student a Confirmed course by running the real flow (enrol, admin approves, student confirms) before the snapshot, rather than seeding one | An enrolment created by the initializer or batch is owned by the admin, and students only see enrolments they own | #88 |
| 2026-10-19 | Pending stays the real behaviour. On stage the student registers for a second course and shows it Pending on Course Registrations; no demo-only shortcut to Confirmed | Peter and Rafa | #88 |
| 2026-10-19 | The demo student is created by the site initializer, as a Site Member, with no custom role | All of it must come from the tree, so a clean provision is stage ready. Rafa | #86 |
| 2026-10-19 | Demo 1 shows an already provisioned site plus a short time-lapse of the provisioning; nothing is provisioned live. Guest self registration is out of scope | Provisioning takes 6 to 11 minutes and can hit the collection race. Peter and Rafa | `TESTING-APPROACH-1.md` |
| 2026-10-16 | Two use cases, 20 minutes each: Approach 1 (initializer to initializer) and Approach 2 (live site migrated in place) | Peter and Rafa, after the 2026-10-14 meeting | the table above |

---

# Approach 1: site initializer to site initializer

## 2026-10-19 — A clock you can trust next to the log

**What happened.** The time-lapse of provisioning carries a clock, so the audience sees how
long each step really took while the video runs at 15x. It has to agree with the log
window's timestamps, or the first sharp-eyed viewer stops trusting both. Three things could
pull them apart, and one did:

- **Time zone.** The clock started from the recording's metadata in the Mac's zone (BST),
  while Liferay logs in UTC: an hour out. `--tz UTC` fixed it.
- **Precision.** MOV stores its creation time in whole seconds. Trimming the recording at
  19.5 s and writing the new start back came out as `.000`, half a second out, so the trim
  now cuts on a whole second.
- **Clock skew.** The log is stamped by Docker's virtual machine, the clock by the Mac. They
  were +0.05 to +0.08 s apart: fine, but now checked before every take.

**Evidence.** A frame where the site initializer's `Initialized` line (16:46:36.226) arrives
shows the clock moving from 16:46:35 to 16:46:37, and the recorded take's check frame shows
17:52:22 as the line stamped 17:52:22.802 arrives. `scripts/clock_overlay.py` (Peter's) and
`scripts/make-timelapse.py`, #98 and #99.

### Lessons

1. **Put a timestamp next to a timestamp only if you have checked they agree.** A clock that
   is an hour or half a second out undermines every log line on screen.
   *Slide angle: Two clocks on one screen will be compared; make sure they agree.*

1. **Check against an event, not a feeling.** The spot check takes one log line with a
   known time, works out the frame where it must appear, and looks.

---

## 2026-10-19 — The red in the log is the platform warming up

**What happened.** Every provisioning run shows red in the log window, and on a recording it
looks alarming. Each one was traced:

| When | What | Why it is harmless |
| --- | --- | --- |
| The restore | The database logs `FATAL` (`database "lportal" does not exist`, `the database system is shutting down`, `connection to client lost`) | The restore starts Postgres from empty, runs a temporary server to load the snapshot, and stops Liferay while it is still connected. The wording varies by run; the cause doesn't |
| About 40 s after Liferay starts | Data set display tags throw `NullPointerException` (`fdsSerializer` is null), 6 to 21 pairs | A reindex task renders a data set component before its serializer service is up: a start-up race, before anything of ours is deployed |
| Site creation | 2 `RESTClientTemplateContextContributor` `SecurityException`s | Fragment templates that call `restClient` render while the site is being built, with no user who has access |
| Site creation | One search index delete fails | The entry wasn't in the index |

Nothing red appears once the site is up, and the checks after provisioning all pass.

**Evidence.** `docker logs` of the 2026-10-19 runs; the timings above are from the takes at
16:43 and 17:47 UTC.

### Lessons

1. **A clean log is not the success criterion; the checks are.** Explain the red rather than
   hide it. Hiding it reads as hiding something.
   *Slide angle: The red lines are the restore at work. Watch what the checks say.*

---

## 2026-10-19 — A check that could never fail

**What happened.** `ldm-provision.sh` ends with "errors since restore", listing every
`ERROR` logged during the run. It printed nothing on every rehearsal, yet the log had
dozens. It counted the log's lines before the restore and printed only what came after that
line number, but the restore starts a new, shorter log file, so it was always reading past
the end.

**Evidence.** The 2026-10-19 rehearsals: the section empty each time, while `docker logs`
showed the data set exceptions above. A fix is in progress, in its own PR.

### Lessons

1. **Test a check by making it fail.** A check that has never shown a failure is a guess.
   *Slide angle: Green because it works, or green because it can't see?*

---

## 2026-10-19 — Two branches, one silent deletion

**What happened.** Master was kept as the "before" state, so in October a change that
landed there by mistake was reverted (#16). Merging 02 into master after the conversion
would have deleted four files Approach 1 needs (the enrolment object, its status picklist
and both enrolment relationships) and restored five old batch files, **with no conflict**:
git applies a revert's deletion wherever the other side hasn't touched the file since. The
trial merge in a scratch worktree showed it before anything reached master.

**What we did.** Carried everything that only master had into 02 first (#92), then merged
with master taking 02's tree exactly (#96). All 112 files master lost were traced to the
02 commit that removed them on purpose. `devcon-start` keeps the before state.

**Evidence.** #92, #96, and "A clean merge can delete the whole conversion" under "Earlier,
from `.agent-state.md`" below, which saw the same trap in the other direction.

### Lessons

1. **A merge without conflicts is not a merge without changes.** Compare the result's tree
   with what you meant, file by file.
   *Slide angle: The most dangerous merge is the one that just works.*

---

## 2026-10-19 — The collection race, measured

**What happened.** The race from 2026-10-16 (collections created after the pages that use
them) hit **3 of 12** site creations on 19 October, including one recorded take. The site
initializer still reports success when it happens. `ldm-provision.sh` now reads the handler
order from the log and, when the collections lost the race, provisions again by itself, up
to three times. On the recorded take it printed `RACE … provisioning again`, and the second
attempt passed every check.

**Evidence.** #90; `scripts/check-collections.sh` and the run logs of 19 October;
UPSTREAM-FEEDBACK.md item 7 (LPD-110315).

### Lessons

1. **Count an intermittent failure before you call it rare.** One in four is not rare on a
   stage.
   *Slide angle: The safeguard caught it on camera.*

---

## 2026-10-19 — Known issue: students can approve or complete their own enrolment

**What happened.** An enrolment's owner gets every action on it: update, delete, and every
standalone object action. So a student can run `approveACourse` on their own Pending
enrolment (204, now Approved), or PATCH its status straight to Completed (200). Pending
stops nothing.

**Decision.** Logged, not fixed before DevCon. The stage flow doesn't depend on it, and
`student-check.sh` reports both as warnings rather than failures. Possible fixes, not yet
evaluated: limit the Owner role's permissions on the object's actions, a validation rule on
status changes, or approval through a workflow.

**Evidence.** Tested as a site member on 02 at `7de77b5`, 2026-10-19; the two `WARN` lines in
every `student-check.sh` run since.

### Lessons

1. **Pending is only a gate if the owner can't open it.** Check who can run each standalone
   action, not just who can create the entry.

---

## 2026-10-19 — The register button only worked for admins

**What happened.** Testing as an ordinary signed in member, not as admin, the register
button failed twice over:

1. It first looks the session up in MyCourseSession, and members had no VIEW on it: the
   lookup returned 0 of 12, and the button said "not linked".
1. Its enrolment links that session, and linking needs VIEW on the related entry: the POST
   returned **403**. The same POST without the session link returned 200.

REST tests run as admin had passed throughout. Separately, an enrolment created by an
admin was invisible to the student it was for (404), because students only see enrolments
they own. That ruled out seeding a Confirmed enrolment from the initializer or batch.

**What we did.** #84 let signed in users enrol (ADD on MyCourseEnrollment for the User
role); #86 moved the grants to Site Member and added VIEW on MyCourseSession. And
`demo-prep.sh` gives the demo student a Confirmed course through the real flow, so the
student owns it (#88).

**Evidence.** #84, #86, #88; the two-user and student checks in `scripts/student-check.sh`.

### Lessons

1. **Test as the user who will click it.** Admin passes every permission check, so admin
   tests prove nothing about permissions.
   *Slide angle: It works on my admin account.*

1. **A relationship is also a read.** Linking an entry to another needs VIEW on the other.

---

## 2026-10-19 — The demo student who couldn't sign in

**What happened.** The site initializer created the demo student, added it to the site, and
left it **Inactive**: signing in returned 401. The same JSON sent to the user API directly
created an active user, so it looked like a bug. Then it was put down to an internal
security request. The portal source settled it: `BundleSiteInitializer._addUserAccounts`
sets every user it creates to inactive on purpose, so an initializer can't silently create
accounts that can sign in (LPS-184738, 2023-12-26).

**What we did.** `demo-prep.sh` activates the student as its first, scripted, documented step
after provisioning, and the README says why.

**Evidence.** #88; `000dba9c42` in liferay-portal (LPS-184738).

### Lessons

1. **Read the source before you name a cause.** It turned "bug" and "someone asked for it"
   into one line of platform code with a ticket.
   *Slide angle: The platform did exactly what it was told. It just wasn't us who told it.*

---

## 2026-10-19 — No feature flags needed for Approach 1

**What happened.** The README had to say which feature flags to enable. The LDM instance had
two on (`LPD-35443`, `LPS-178052`) with nothing recording whether Approach 1 needed them. A
clean run with both switched off created the site, loaded the data and rendered every page.

**Evidence.** #85; two clean runs of 02 at `7de77b5`, one with LDM's default flags and one
with both off. (Approach 2's page specification edits do need `LPD-74328`; see the
2026-10-15 entry under Approach 2.)

### Lessons

1. **Test the minimum, don't inherit it.** "These flags are on" is not "these flags are
   needed".

---

## 2026-10-16 — Correction: collection classPK is not string vs number, it is handler order

**What happened.** The 2026-10-14 entry below concluded that display page templates need a
numeric `classPK` (`"[#ASSET_LIST_ENTRY_ID:…#]"`) and content pages a string one
(`"[$ASSET_LIST_ENTRY_ID:…$]"`). Two clean creations of the tree on LDM (2026.q3.5) and the
portal source say otherwise:

| Run | Template token | Handler order in the log | Blog DPT "More like this" collection |
| --- | --- | --- | --- |
| 14 Oct, #60 tree | `[$…$]` | `addLayoutPageTemplates` before `addAssetListEntries` | absent |
| 15 Oct, current 02 | `[#…#]` | `addAssetListEntries` before `addLayoutPageTemplates` | present |

The token form changed, and so did the order. Only the order matters.

**Root cause.** Content pages and display page templates go through the same
`CollectionLayoutStructureItemImporter`, which reads `classPK` with `String.valueOf(…)`, so a
string and a number are treated the same. The failure is that the token has not been registered
yet: `addAssetListEntries` registers `ASSET_LIST_ENTRY_ID`, and neither `addLayoutPageTemplates`
nor `addOrUpdateLayoutsContent` depends on it. `BundleSiteInitializer` orders its handlers by
iterating a `HashMap` keyed on objects with identity hash codes, so the order can change on every
site creation. When the pages win, the literal token fails to parse and the collection is
silently dropped. The same can happen to content pages, which is the likely explanation for
numeric tokens "breaking" them in #63.

**Evidence.** The two runs above; `_createRMap` and its run loop in `BundleSiteInitializer`;
`CollectionLayoutStructureItemImporter._getCollectionJSONObject`. The course display page
template, whose collection uses a provider class name with no tree scoped token, kept its
collection on both runs.

### Lessons

1. **A fix that works once is a hypothesis.** The `[#…#]` change was followed by a working run,
   which looked like proof. One more clean run with the order reversed would have shown the
   result followed the order, not the token.
   *Slide angle: It worked after my change is not the same as it worked because of my change.*

1. **An intermittent bug can be on stage.** Any site creation, including the one in the demo, can
   come up with empty collections. Check the collections after every creation, and keep a
   pre-provisioned instance as the fallback.
   *Slide angle: Rehearse the failure, not just the happy path.*

1. **Correct the rules, not just the code.** The wrong rule had already been written into the
   agents' portability card, where every future migration would have followed it. The card now
   describes the race instead.
   *Slide angle: A wrong rule taught to the agent is worse than no rule.*

---

## 2026-10-14 — The dual personality of collection classPK: string in pages, number in templates

> **Superseded by the 2026-10-16 correction above.** The root cause below is wrong: the token
> form does not matter, the order the initializer runs its handlers does.

**What happened.** While standardizing collection displays across the site initializer,
collections exhibited contradictory behavior between Content Pages and Display Page Templates:
- In the Blog Display Page Template (`layout-page-templates/display-page-templates/blog-entry`),
  the "More like this" Collection Display failed to map. Changing its `classPK` from
  `"[$ASSET_LIST_ENTRY_ID:BLOG-ENTRIES$]"` to `"[#ASSET_LIST_ENTRY_ID:BLOG-ENTRIES#]"` (which
  resolves to raw number `76456` without quotes) fixed the DPT.
- However, applying that same numeric syntax `[#...#]` to Content Pages (`layouts/1_home`,
  `layouts/courses`, `layouts/blog`, `layouts/my-learning`) broke all collections across the
  entire site, leaving `collectionSettings: {}` empty.
- Content Pages require the string token syntax `"[$ASSET_LIST_ENTRY_ID:...$]"`, while Display
  Page Templates require numeric syntax `"[#ASSET_LIST_ENTRY_ID:...#]"`.

**Root cause.** Two independent importers in Liferay Portal process `page-definition.json`:
- `LayoutPageTemplateEntry` importer (DPTs) strictly requires a JSON number for `classPK`.
  Passing a string causes validation failure, silently dropping the collection reference.
- `BundleSiteInitializer` / `LayoutStructureItemImporter` (Content Pages) expects a JSON String
  for `classPK` inside `CollectionDisplay`. Passing a raw number fails type binding and leaves
  `collectionSettings` empty.
Neither importer logs a warning or error — both log successful initialization.

**Evidence.** PR #62, PR #63.

### Lessons

1. **Same JSON schema, different parser.** Even though Content Pages and Display Page Templates
   both use `page-definition.json`, they are deserialized by different portal components with
   conflicting type expectations for the exact same attribute (`classPK`).
   *Slide angle: Same JSON, different parser: the hidden strictness between Content Pages and Templates.*

1. **Silent drops without errors.** Neither parser logs an error when discarding an unmapped
   collection reference. The console logs `Initialized com.liferay.site.initializer... in 5902 ms`
   with 0 errors while the UI renders empty containers.
   *Slide angle: The silence of the parsers: when 0 errors = missing features.*

1. **Teach the agents the divergence.** Documenting this in `rules/site-initializer-portability.md`
   ensures agents and developers use `[$...$]` for `layouts/` and `[#...#]` for `layout-page-templates/`.
   *Slide angle: Why domain rules matter for AI-assisted migrations.*

---

## 2026-10-13 — The guard that would have broken working code

**What happened.** Applying a brief on agent-repo practice, we turned the portability
audit in the `migrate-cms-to-objects` skill into blocking guards. The skill's card said
`[#…#]` is "literal, never substituted", and its checklist made any use an error. 02 had
five, so the first draft of the guard failed the tree. Before writing it, we checked the
portal source. `SiteInitializerUtil.replace` has run a `"[#…#]"` pass since LRSD-5177
(2024), with the double quotes as part of the delimiter, so it substitutes an unquoted
number. All five uses were correct. The extender's own test bundles use the form for
`classPK` and `imageId`.

The same pass found that `.agents/rules/site-initializer-portability.md` was a symlink
committed as a 75 byte text file, on 02, 03 and master. That is the failure that once made a
week of evals measure nothing (#24). Claude and Gemini read the card through their own
links, so only an agent reading `.agents/` directly got a path instead of the card.

A third finding came from asking Gemini directly: it had never read `.gemini/GEMINI.md`.
Version 0.46 only reads `GEMINI.md` from the working directory up to the git root, so
Gemini sessions here started without the workspace rules, and the copy they would have
read had drifted anyway.

Fixed in rlluis/devcon2026#50 (card, symlink, guards with a GitHub Action) and #51 (a
root `GEMINI.md` that imports the rules).

### Lessons

1. **A skill can be confidently wrong, and automation multiplies it.** As prose, the
   card's mistake cost a reader a moment of doubt. As a blocking guard, it would have
   failed correct code on every push, with a message citing the card as the reason.
   Check the source before turning documentation into enforcement.
   *Slide angle: the instructions needed a code review too.*

1. **Prove a check both ways.** Every guard has a test that plants the violation, and the
   check was run against 02 from before the fix to confirm it caught the real symlink.
   The `[#` guard checks the rule as the code applies it (`[#…#]` outside a whole quoted
   string), not as the card stated it.

1. **Ask the tool what it loaded.** The Gemini file looked right, sat where a reader
   would expect, and was never read. One `gemini --debug` prompt showed which files it
   loaded and which heading it quoted, before and after.

1. **Symlink failures recur.** Two instances within a week, both silent, both on files
   agents depend on. That is now a guard, not a reminder.

---

## 2026-10-13 — The bridge entry that arrived empty

**What happened.** Enrolment lives in our own objects (MyCourseSession, MyCourseEnrollment),
but a CMS object in a Space cannot be related to them. Rafa bridged the gap with an
`onAfterAdd` action on ElearningSession that creates a MyCourseSession, meant to copy the
session's `id`, `startDate` and `endDate`. Only the `id` ever arrived.

**Root cause, as Rafa found it.** ElearningSession has `enableObjectEntryDraft` and
`enableObjectEntryVersioning` on, as all five of our Space scoped objects do. Creating an entry first saves a
draft shell, and `onAfterAdd` fires on that shell, when only the generated `id` exists. The
author's values come later, with an update. And `onAfterUpdate` cannot fill them in
elsewhere: `add-object-entry` there makes a new bridge record on every save, and
`update-object-entry` has no way to find the MyCourseSession whose `courseSessionID` matches
the session.

**What we did.** Rafa weighed a Groovy action on update against storing only the ID, and
chose the ID. The bridge now holds just `courseSessionID`, and the registrations fragment
reads the dates from ElearningSession itself, so the CMS object is the only source of truth
for them (rlluis/devcon2026 `ba649c7`). On a clean provision, 12 sessions created 12 bridge
entries with matching IDs, and an ordinary signed in user could read the dates.

### Lessons

1. **Drafts change what "after add" means.** On a draft enabled object, `onAfterAdd`
   happens before the author has typed anything. Any action that copies field values
   needs a trigger that fires on publish.

1. **When the platform cannot sync a value, stop copying it.** Storing the reference
   and reading through it removed the sync problem altogether, with no code to maintain.
   *Slide angle: the least code answer was a smaller data model, not a script.*

1. **This is product feedback, not just a workaround.** Rafa is filing it as a bug (an
   `onAfterPublish` trigger, or deferring `onAfterAdd` until the entry leaves draft) and
   a feature request (`update-object-entry` that finds its target by a field match). Add
   the links here when they exist; they count toward the bugs and FRs slide.

---

## 2026-10-09 — The images only the author could see

**What happened.** Rafa's info templates mapped course images, PDFs and video
correctly when signed in, and not at all on a second machine or as a visitor. An AI
diagnosis called it a race condition in the site initializer and concluded it could
not be fixed. It was three separate problems, none of them a race.

**Root causes.**
- *Not a race.* The dependency graph orders the templates before the display pages
  through an indirect dependency the diagnosis missed, and the steps run one at a time.
  A clean first run proved it: every mapping resolved to a real template ID.
- *Guests were refused, silently, twice.* The templates fetched documents over REST as
  the visitor, which the Service Access Policy blocks; `!{}` turned the error into empty
  output. Under that, every attachment download was 404 for a guest, because the file
  is owned by the CMS Basic Document that uploaded it, and downloading also needs the
  per field `DOWNLOAD_<FIELD>` action. The servlet reports a guest permission failure as
  404, not 403.
- *The tree cannot name an attachment mapping.* Attachment subfields are keyed by
  numeric object field ID, and the importer drops display page mappings it cannot
  validate. The info template is a real workaround, not a mistake.

Fixes: guest grants in `resource-permissions.json`, templates that read the URL from
their own fields, a missing blog image restored, and a removable module that scopes
collections to the Space. Issue peterrichards-lr/devcon2026#13 has the batch half.

### Lessons

1. **Test as the visitor, on a clean instance, before believing a diagnosis.**
   Both conditions mattered: signed in hid the permission bugs, and a reused instance
   made run 2 look fixed.
   *Slide angle: "works on my machine" now has a second clause: "as me".*

1. **A confident explanation is not evidence.** The race story was detailed, cited
   real source, and was wrong because it read one dependency list instead of the graph.
   One clean run settled what an hour of reasoning could not.

1. **Silent fallbacks compound.** `!{}` in the template, 404 for a refused guest, an
   importer that drops what it cannot validate: each hid the next problem.

1. **A 200 is not an image.** The first fix for the missing blog image produced an empty
   file. Every URL for it returned `200 image/jpeg` with zero bytes, so an automated
   check passed while the card stayed blank, and a person looking at the page caught it.
   Checking content size, not status, found it in one step (rlluis/devcon2026#43).
   *Slide angle: verify the thing the user sees, not the thing that is easy to assert.*

---

## 2026-10-09 — The modules that forgot their numbers

**What happened.** Rafa found every course module showing an empty duration and `0` for
module number and lesson count. The module batch file had all three values, so the data
looked right. The bad import was the one that ran **after** it.

**Root cause.** The course batch nests its modules, teachers and sessions by reference:
just an external reference code and a title. Liferay doesn't treat a nested item as a
link. It upserts it with a full replace, so every field the item leaves out is reset.
Courses imported last, so they blanked the modules, and very likely teacher photos and
descriptions too. Issue peterrichards-lr/devcon2026#13.

### Lessons

1. **The file with the bug isn't the file with the symptom.** Reading the module data
   proves nothing. The defect was in a different file, two steps later in the import.
   *Slide angle: when correct data arrives wrong, look at what touched it afterwards.*

1. **The obvious fix didn't work.** `PARTIAL_UPDATE` looks like the answer, but on a fresh
   bundle the course doesn't exist yet. It takes the create path, which ignores that
   setting. Reading the source caught this before we shipped a fix that only worked on
   a second deploy.

1. **File numbering can be load bearing.** The fix was to import courses first and let
   the later files overwrite the stubs. Nothing enforces that order except the file
   names, so the README now says why.

---

## 2026-10-08 — The blog that would not save

**What happened.** Editing any `ElearningBlog` entry in the CMS and clicking Publish
without changing anything failed with *"An error occurred while sending the form
information."* Emptying Image Author made it save. Rafa spent the morning chasing it with
Gemini.

**Root cause.** A portal bug, set off by our field names. The editor form assigns request
parameters to a field by **prefix**, so the `image` field also claimed the
`imageAuthor` text and failed attachment validation. The real error was logged only at
DEBUG; the UI showed a generic toast. Issue peterrichards-lr/devcon2026#8; skill fix #28, data fix #29.

### Lessons

1. **Reproduce before you theorise.** The breakthrough was not a smarter hypothesis. It was
   reproducing the exact click path in a headless browser, capturing the form POST, and
   turning on DEBUG for the class that swallowed the exception. From there it was a
   straight read through the portal source to `parameterName.startsWith(...)`.
   *Slide angle: AI is fastest when it can run the experiment, not just read the code.*

1. **A control that "works" can mislead you.** Rafa's hand-built copy of the structure
   saved fine, which seemed to rule out the field names. It did not. It differed in a
   second variable he was not watching: localization. The full 2×2 showed that only
   *upload not localized + text localized* fails, which is exactly the shape we shipped.
   *Slide angle: change one variable at a time, or test the matrix.*

1. **REST working proves nothing about the UI.** `PUT` and `PATCH` saved the same entry
   without complaint. Only the editor's form path was broken. Provisioning, batch import,
   rendering and REST were all green.
   *Slide angle: test the path your editors actually use.*

1. **Silent failures cost the most time.** No error in the log, a generic message in the
   UI, and a workaround (empty the field) that made it look like bad data. Nearly every
   expensive problem in this project shared that shape.

1. **History pinpoints where a defect came in.** `git log -S imageAuthor` showed the
   collision arrived during the DDM → object port (`MainImage` became `image`), not during
   the batch → site initializer move. The legacy names had been safe all along.
   *Slide angle: the conversion step is where new constraints sneak in.*

1. **Fix the skill, not just the data.** The rename fixes our tree. The rule in
   `manage-objects` and `migrate-cms-to-objects` stops the next migration repeating it,
   and `.gemini` reads the same files through symlinks, so Rafa's Gemini gets it too.
   *Slide angle: every bug is a chance to teach the agent.*

1. **Renaming a field is a new identity.** A published field cannot be renamed, so the fix
   meant a clean baseline and a reprovision rather than an edit in place.

1. **Two people, one environment.** We both reset the shared LDM within the same minute,
   and the reset brought back an old batch zip that would have run against the clean
   database. Say out loud who is driving the environment.

1. **The UI is not the source of truth.** After the reset the new site did not appear in
   the Sites list, which read as "the site initializer never ran". It had: the log said
   `Initialized … in 14722 ms`, and the site answered over the API and at its URL. The
   list is served from the search index, and the shared Elasticsearch index was stale
   after the database reset. Check the log and the API before acting on what a list
   shows, or you create a second site on top of the first.

1. **The fix was verified, not assumed.** The rename (#29) was proven on a clean
   baseline: all 8 blogs failed a no-change Publish before, and all 8 saved after, with
   their values intact. That before/after count is the number for the slide.

---

## Before PR tracking — CMS content structures must be draft-enabled

> Written up after the fact, on 2026-10-19. This happened before the work was tracked in pull
> requests, so there is no PR or measurement to point to; the account is Rafa's.

**What happened.** The CMS objects created by the site initializer looked fine: they provisioned,
took data from the batch, rendered, and answered over REST. The first sign of trouble was deleting
an entry (a Course, a Module and so on) through the CMS UI, which failed.

**Fix.** One property on each object definition: `"enableObjectEntryDraft": true`. It is set in
the site initializer tree, in
`modules/masterclass-cms-site-initializer/src/main/resources/site-initializer/object-definitions/`,
on the five Space scoped content structures (`03-elearning-blog.json` to `07-elearning-course.json`),
next to `"enableObjectEntryVersioning": true`. The two company scoped objects, `MyCourseSession` and
`MyCourseEnrollment`, are not CMS content structures and keep it `false`.

**Evidence.** Rafa's report; no PR. The tree has carried `true` on all five since they arrived
(`6d7a098`, 2026-09-30, then `91f2eda` when they moved into the initializer).

### Lessons

1. **A missing flag can pass every test but one.** Provisioning, import, rendering and REST were all
   green; only an editor's delete in the UI exposed it. The same shape as "the blog that would not
   save" below: test the path editors use.
   *Slide angle: The flag nobody tests for until someone clicks Delete.*

1. **Teach it to the agent.** The `manage-cms` and `manage-objects` skills list
   `enableObjectEntryDraft: true` in their examples, but nothing says what breaks without it. They
   tie the failing UI delete to versioning instead, so which flag (or both) the delete actually
   needs is still to be confirmed before that rule is written.

---

## Earlier, from `.agent-state.md`

Carried over so they are in one place. The detail and evidence live in `.agent-state.md`.

- **An eval that cannot see the skill measures nothing.** `skills` was committed as a
  14-byte file rather than a symlink, so every eval run before 7 Oct measured the model
  alone while reporting the plugin as loaded. One case went from +0.00 to +0.60 when
  fixed. *Check your instrument before trusting its numbers.*
- **Undocumented behaviour is where skills earn their keep.** Facts the model can work out
  or look up measure close to zero uplift; undocumented implementation behaviour measures
  +0.32 to +0.60. *Write skills for what is not in the docs.*
- **Compound graders fail correct answers.** One rubric demanding four things read +0.08;
  split into narrow graders, the same case read +0.32.
- **A clean merge can delete the whole conversion.** Merging `master` into
  `02-aiconversion` replays a revert and removes the conversion without a single conflict.
- **A 409 that is not a conflict.** Depot scoped objects answer `409 Conflict with
  getObjectEntriesPage` on the plain path; the entries are at `/scopes/{siteId}`. The
  message points somewhere else entirely.
- **A relationship cannot cross a Space boundary**, so moving content into a Space costs
  referential integrity with anything outside it. That is a real trade-off of the new CMS,
  not a bug.
- **Generated UUIDs are a portability defect.** A relationship ERC captured from one
  instance made every later provision roll the whole site back.
- **Read the list, do not assert a property.** An automated check passed
  `M-Y-E-N-R-O-L-L-M-E-N-T-S-T-A-T-U-S`; a human reading the output caught it.

---

# Approach 2: live site, migrated in place

## 2026-10-15 — Headless REST Deletions of legacy content bypass the Recycle Bin; new CMS entries do not

**What happened.** While cleaning up legacy Web Content articles, Documents & Media files, and obsolete
site collections after migrating them to modern Headless CMS Objects, the site's Recycle Bin remained
completely empty before and after all deletion operations. Deletions executed via the REST APIs and MCP
tools were immediately permanent and bypassed the Recycle Bin entirely.

Inspecting Liferay's `headless-delivery` implementation revealed why this happens by design:
1. **Admin UI vs. Headless REST deletion engines:** In the Liferay UI, clicking "Delete" on an article or
   file routes through the MVC portlet action, which invokes `moveArticleToTrash()` and `moveFileEntryToTrash()`,
   creating records in the `TrashEntry` table so administrators can restore them.
2. **REST endpoints execute hard deletes:** In `StructuredContentResourceImpl.java` and `DocumentResourceImpl.java`,
   the HTTP `DELETE` handler directly calls `JournalArticleService.deleteArticle(...)` and `DLAppService.deleteFileEntry(...)`.
   The headless layer adheres to strict REST semantics where `DELETE` is permanent, completely bypassing the
   `TrashHandler` subsystem.
3. **Collections:** Collections (`AssetListEntry`) do not participate in the Recycle Bin framework at all;
   deleting one is always permanent.
4. **New CMS entries are the exception: they are soft deleted.** Verified on 2026.q3.5 (2026-10-16): a
   `DELETE /o/c/elearningblogs/{id}` on an entry in the eLearning Space returned `204`, yet the entry was
   still readable by ERC with `status = 8` (in trash), a `TrashEntry` row existed, and creating a new entry
   with the same ERC failed with `400 This external reference code is already in use.` This matches the
   2026-10-15 DAM ingestion lesson below. Company scoped custom objects were not tested.

### Lessons

1. **What a REST `DELETE` does depends on what you delete.** Legacy web content, documents and
   collections are gone for good: never assume they can be recovered from the Recycle Bin. New CMS entries
   in a Space go to the Recycle Bin and keep their ERC reserved, so a re-run that recreates them with the
   same ERC fails until the trash is emptied.
2. **Take full database snapshots before automated cleanup.** In migration pipelines or automated cleanup
   scripts, full database and document store backups are the only recovery mechanism against accidental
   data loss during programmatic cleanup.
   *Slide angle: The Invisible Trash: the same DELETE is permanent for the old CMS and reversible for the new one, so snapshot before cleanup and empty the trash before a re-run.*

---

## 2026-10-15 — Site Page Inventory Audits: Why visual navigation browsing misses pages like 'My Learning'

**What happened.** During the public content page migration phase, we initially audited and retargeted
`/courses`, `/blog`, and `/home`. We inadvertently omitted `/my-learning` until the final review.
Tracing why this happened revealed two critical gaps in migration planning:
1. **Primary Navigation Bias:** The initial page inventory was gathered by browsing the top header
   navbar (Home, Courses, Blog, Apply). However, `/my-learning` had `hiddenFromNavigation: true` because
   it belongs to a secondary, user-profile-scoped navigation menu ("Private Area Navigation"). Pages
   outside primary menus are completely invisible to navbar-based audits.
2. **Missing Entity Listing Audit:** In earlier phases, we migrated 4 CMS Content Structures: `Blog`,
   `Teacher`, `Course`, and `Classroom`. While we migrated listings for Courses and Blogs, we never
   cross-referenced `Classroom` to ask: *"Where on the site are Classroom entries listed?"* In this site's
   information architecture, classrooms are listed as enrolled courses on `/my-learning` rather than a
   public `/classrooms` route.

By relying on visual navigation instead of querying the site-pages endpoint directly:
`GET /o/headless-admin-site/v1.0/sites/{siteERC}/site-pages`
a content page hosting an active `CollectionDisplay` was temporarily overlooked.

### Lessons

1. **Always perform an exhaustive API-based page inventory.** Never rely on visible navbar links or
   sitemaps to inventory pages for migration. Always query `GET /site-pages` to discover all pages,
   especially utility, private-area, and `hiddenFromNavigation: true` pages.
2. **Cross-reference every migrated data model against site listings.** When migrating multiple
   content structures or objects, audit every single model against the site pages to verify where its
   collection displays, search facets, or listings reside. If an entity exists in the backend without a
   matching collection display in your page list, a page has been missed.
   *Slide angle: The Navigation Trap: Why visual inspection misses critical pages and how to audit site-wide collection coverage.*

---

## 2026-10-15 — Navigation Menus during CMS migration: silent regressions, type immutability, and cross-scope references

**What happened.** While auditing the site after retargeting Display Page Templates and Content Pages,
the top header's "Courses" dropdown in the "Main Navigation" menu appeared completely empty.
The menu originally contained 3 items pointing to legacy Structured Content (`JournalArticle`) courses.
Because the legacy structure's default DPT had been retargeted to modern Object definitions, Liferay's
navigation taglib (`NavItemUtil.java`) silently omitted the un-renderable items without throwing any
server errors or logs, making it an invisible regression on the live site.

Reconnecting the navigation menu to modern Course Object entries via the Headless Admin Site API
(`PUT /v1.0/sites/{siteERC}/navigation-menus/{menuERC}`) revealed two core engine behaviors:

1. **Menu Item `type_` is immutable on update:** In `NavigationMenuResourceImpl._updateNavigationMenuItems`,
   updating an existing item by its `externalReferenceCode` calls `updateSiteNavigationMenuItem()`,
   which updates `typeSettings` but physically cannot alter the database column `type_`. Updating a
   `JournalArticle` item in-place left its type stuck on `com.liferay.journal.model.JournalArticle`.
   To convert an item to an Object display page, assigning a **new `externalReferenceCode`** is mandatory:
   it forces `_fetchSiteNavigationMenuItem` to return `null`, calling `_createNavigationMenuItem` with the
   new Object type (`com.liferay.object.model.ObjectDefinition#<Hash>`), while `_deleteNavigationMenuItems`
   automatically prunes the obsolete legacy records.
2. **Space scoping on cross-site navigation items:** In `DisplayPageTypeContext.java`, Liferay validates
   and resolves display-page menu items via `InfoItemReference` using `ERCInfoItemIdentifier(externalReferenceCode, scopeExternalReferenceCode)`.
   Because the navigation menu lives on the Site (`groupId: 65391`) while our modern CMS Objects live in
   the Headless Space, `navigationMenuItemSettings` must explicitly pass `scopeExternalReferenceCode: "SPACE-MASTERCLASS-CMS"`.
   Omitting it causes `_hasModel` to look for the object in the Site group and throw `400 IllegalArgumentException`.

### Lessons

1. **Navigation Menus must be included in CMS migration audits.** Navigation menus often embed typed
   content items (e.g. Web Content articles). When legacy structures lose their default DPTs, Liferay
   silently drops them from navigation renders. Always audit `/navigation-menus` alongside pages and collections.
2. **Assign new `externalReferenceCode`s when changing a menu item's type.** Menu item types are immutable
   on in-place REST updates. Generating fresh ERCs allows the API to create the modern Object item and
   safely purge the legacy item.
3. **Always supply `scopeExternalReferenceCode` for Space-scoped Object items.** When a navigation menu
   references Object entries living inside a Headless CMS Space (Asset Library / depot scope), the item
   settings must explicitly declare `scopeExternalReferenceCode` pointing to the Space ERC.
   *Slide angle: The Silent Drop: Why Navigation Menus are the hidden victims of CMS object migrations, and how Liferay's type immutability handles model transitions.*

---

## 2026-10-15 — Publishing Display Page Templates via REST: sub-resource draft locks vs. parent-level automation

**What happened.** When automating Display Page Template (DPT) migration, we attempted to publish
the updated draft layouts (`blog-entry`, `course`, `classroom`) via the sub-resource endpoint:
`POST /v1.0/sites/{siteERC}/page-specifications/{draftERC}/publish`.
The endpoint returned an immediate `204 No Content`, leading us to assume the layout had been promoted
to published/approved. However, the changes remained unpromoted drafts, and the DPTs continued rendering
legacy content until an administrator opened each DPT in the Page Editor and clicked "Publish".
Attempting to send `status: "Approved"` directly to `PUT /page-specifications/{erc}` failed with:
`IllegalArgumentException: The page specification must be in draft status for content pages`.

Consulting Liferay's engineering team and inspecting `headless-admin-site-impl` revealed the full architecture:
1. **The `/publish` sub-resource is an un-implemented stub:** In `BasePageSpecificationResourceImpl.java`,
   `postSitePageSpecificationPublish` returns an empty `new PageSpecification()`. It executes zero backend
   promotion logic, returning 204 as a false positive.
2. **`putSitePageSpecification` is draft-only by design:** The sub-resource `/page-specifications/{erc}`
   mirrors the Page Editor UI draft workspace; Liferay strictly blocks saving non-draft specifications here.
3. **The Solution — Parent-Level REST Publishing:** DPTs **can** be published programmatically without
   touching the UI by updating the top-level parent entity:
   `PUT /o/headless-admin-site/v1.0/sites/{siteERC}/display-page-templates/{dptERC}?nestedFields=pageSpecifications`
   When both `pageSpecifications` (draft and layout) are submitted with `status: "Approved"`,
   `DisplayPageTemplateResourceImpl` executes `LayoutUtil.updateContentLayout()` and calls
   `_layoutPageTemplateEntryService.updateStatus(..., WorkflowConstants.STATUS_APPROVED)`,
   promoting the DPT to live status automatically.

### Lessons

1. **`postSitePageSpecificationPublish` is an un-implemented stub.** Never use the `/page-specifications/{erc}/publish`
   endpoint for layout promotion; it returns a `204 No Content` false positive.
2. **`putSitePageSpecification` is restricted to drafts.** The `/page-specifications/{erc}` sub-resource only
   accepts `status: "Draft"`.
3. **Publish DPTs headlessly via the parent resource.** To publish a Display Page Template programmatically
   without human UI intervention, call `PUT /display-page-templates/{dptERC}?nestedFields=pageSpecifications`
   passing both `pageSpecifications` with `status: "Approved"`.
   *Slide angle: The Sub-Resource Trap: Why DPT publishing fails on `/page-specifications` and how parent-level REST unlocks 100% headless automation.*

---

## 2026-10-15 — MCP Tool Invocations vs. Programmatic Script Execution: When to Use Each and How to Steer AI

**What happened.** Throughout the site migration to Headless CMS Objects, two execution channels
were used in parallel:
1. Direct Liferay MCP tool invocations (e.g. `getObjectDefinitionsPage`, `patchSiteDisplayPageTemplate`,
   `postSitePageSpecificationPublish`).
2. Targeted Python scripts executed locally against the live REST APIs (`http://localhost:8080/o/...`).

While MCP served as the canonical discovery and lifecycle interface, mutating complex page layouts
revealed clear operational boundaries between direct tool calling and programmatic script execution:
- **Payload volume and context cost:** Liferay has no granular endpoint to update a single fragment
  or field mapping. Mutating a layout requires sending the entire `PageSpecification` tree
  (`pageExperiences[0].pageElements`), which frequently spans 100KB–200KB of JSON. Passing payloads
  of this size inside LLM tool arguments strains context window limits, inflates per-turn token costs,
  and introduces latency.
- **RPC transport stability:** Large JSON payloads or rapid consecutive mutations sent across
  stdio JSON-RPC occasionally triggered transport timeouts or `fetch failed` errors. In contrast,
  local Python scripts streamed `urllib` HTTP calls directly to the portal with immediate status codes.
- **In-memory data transformation:** Sanitizing layouts (stripping read-only fields like `customFields`,
  `creator`, `uuid`), generating unique element UUIDs, and updating nested dictionary keys is executed
  reliably in memory in milliseconds via code, avoiding polluting the conversational context with huge diffs.

### Lessons

1. **Use MCP for:**
   - **Introspection & Discovery:** Inspecting schemas, fetching available toolsets, querying Object definitions,
     and checking template metadata.
   - **Discrete CRUD & Lifecycle Transitions:** Patching a DPT's `contentTypeReference`, creating individual
     records, publishing drafts, and operations where structured tool output provides high signal.
2. **Use Programmatic Scripts (Python/Shell) for:**
   - **Deep Tree & Batch Transformations:** Reading, modifying, and re-submitting massive nested trees
     (e.g., 100KB+ `PageSpecification` hierarchies) where passing full payloads through the LLM context
     is token-inefficient and error-prone.
   - **DTO Sanitization:** Stripping server-generated read-only attributes before PUT operations.
   - **High-Volume Binary Streaming:** Uploading multi-megabyte media to DAM via file streaming to prevent
     Base64 buffer truncation.
3. **Agent Autonomy vs. Steering:**
   - Allow the agent the architectural autonomy to select the optimal execution mechanism dynamically:
     defaulting to MCP for control-plane and lifecycle operations, while escalating to programmatic script
     execution when payload volume, RPC limits, or complex data transformations demand it.
   *Slide angle: MCP vs Code Execution: Finding the pragmatic boundary between LLM tool calls and programmatic execution.*

---

## 2026-10-15 — Site Page layout mutations vs DPTs: endpoints, privateLayout flag, HTML templates, and Object link keys

**What happened.** When retargeting the public `/courses` page (`SitePage`) to a modern Object
`CollectionProvider`, several subtle API and schema differences from Display Page Templates
(`LayoutPageTemplateEntry`) caused repeated errors and blank card renders:

1. **DPTs vs Site Pages endpoint split:** DPT drafts are mutated via `PUT /page-specifications/<dptERC>-layout-draft`
   because Liferay persists a distinct `LayoutPageTemplateEntry` record for DPT drafts. In contrast,
   standard Content Pages (`SitePage`) do not register their draft layouts under `<pageERC>-draft` in
   the `Layout` table; attempting to mutate them via `/page-specifications/<pageERC>-draft` fails with
   `400 UnsupportedOperationException`. Standard Content Pages must be mutated via the SitePage resource:
   `PUT /o/headless-admin-site/v1.0/sites/{siteERC}/site-pages/{sitePageERC}?nestedFields=pageSpecifications&privateLayout=false`.
2. **`privateLayout=false` query parameter:** Omitting `privateLayout=false` on `PUT /site-pages/{sitePageERC}`
   causes Liferay to check `EnabledUtil.checkPrivateLayoutEnabled(contextCompany)`, which throws a silent
   `400 UnsupportedOperationException` on portals with private layouts disabled. Passing `?privateLayout=false`
   is mandatory.
3. **Payload stripping:** `GET /site-pages/{sitePageERC}?nestedFields=pageSpecifications` returns server-generated
   read-only fields (`creator`, `dateCreated`, `dateModified`, `datePublished`, `uuid`, `customFields`) that
   trigger `400 BAD_REQUEST` schema rejections if re-submitted in `PUT`. They must be stripped.
4. **Fragment hierarchy hygiene:** Borrowing fragments from other pages requires assigning fresh UUIDs as
   `externalReferenceCode`, setting `parentExternalReferenceCode` to the target container, and stripping
   old layout-scoped IDs (`fragmentInstanceExternalReferenceCode`, `draftFragmentInstanceExternalReferenceCode`,
   `namespace`, `uuid`). Any mismatched parent reference causes `PageElementDTOConverter` to throw
   `UnsupportedOperationException`.
5. **Fragment HTML is mandatory:** `fragmentInstance.html` must contain the fragment's full HTML markup with
   `data-lfr-editable-id`. Unlike headless templates in other frameworks, Liferay does not dynamically pull
   the template from the fragment definition during layout evaluation. If `html: ""` is empty, Liferay renders
   a blank DOM node even if the editable values are mapped.
6. **Object Display Page Link Key:** Inside a `CollectionItem` over an Object Definition, the display page
   link key is `ObjectEntry_displayPageURL` (not `displayPageURL`).
7. **Styling preservation:** To preserve Clay design tokens and typography, `fragmentViewports` (e.g.
   `fontFamilySansSerif`, `textColor: "secondaryColor"`), `fragmentConfigurationFieldValues` (e.g.
   `headingLevel: "h3"`), and fragment `css` must be retained when injecting or updating fragments.

### Lessons

1. **Differentiate DPT and SitePage REST endpoints:** Use `/page-specifications/<erc>` exclusively for
   Display Page Templates. Use `/site-pages/<erc>?nestedFields=pageSpecifications&privateLayout=false` for
   standard Content Pages.
2. **Never send empty `html` on fragment instances:** Always include the fragment template markup with
   `data-lfr-editable-id` and preserve `fragmentViewports` and `css` to retain typography and spacing.
3. **Use `ObjectEntry_displayPageURL` for Object collection links.**
   *Slide angle: Pitfalls in Headless Page Mutations: Why Site Pages and DPTs require completely different REST lifecycles.*

---

## 2026-10-15 — Display Page Templates can host nested Collections: remember to remap related feeds

**What happened.** When retargeting Display Page Templates (`blog-entry`, `course`, `classroom`)
to modern Headless CMS Objects (`Blog`, `Course`, `Classroom`), initial attention was focused
strictly on primary entity fields sourced from `DisplayPageItem` (such as titles, descriptions,
and video URLs). However, rich display page templates frequently host **nested collection displays**
(such as *"More like this"* on a Blog DPT, or *"Teachers on this Course"* on Course and Classroom DPTs).

If these embedded collections are overlooked:
- The `CollectionDisplay` remains bound to legacy site collections or obsolete filter criteria.
- Child fragments inside `CollectionItem` continue trying to map to legacy `DDMStructure_*` fields
  instead of modern `ObjectField_*` fields.
- The page renders as partially migrated while related content sections appear empty or broken.

Auditing the entire page specification tree for `CollectionDisplay` elements allowed us to
rebind each nested feed to the appropriate modern `CollectionProvider`:
```json
"collectionSettings": {
  "collectionReference": {
    "className": "com.liferay.object.model.ObjectDefinition#<Hash>",
    "collectionType": "CollectionProvider"
  }
}
```
and remap their child `CollectionItem` fragment fields (e.g., photo to `ObjectField_<id>#fileURL`,
name to `ObjectField_name`, and link target to `displayPageURL`).

### Lessons

1. **DPT retargeting must audit nested collections.** When retargeting a Display Page Template,
   do not stop at the primary `DisplayPageItem` fields. Always traverse the full page element
   tree to discover nested `CollectionDisplay` elements (`collectionType: "Collection"`).
   Rebind them to the modern Object `CollectionProvider` (`collectionType: "CollectionProvider"`)
   and remap child `CollectionItem` fragment fields to ensure related content feeds remain fully
   operational.
   *Slide angle: Beyond the single entity: why DPT migration must traverse nested collection displays.*

---

## 2026-10-15 — Page Specification REST mutations require LPD-74328 and Object attachment #fileURL mapping

**What happened.** When retargeting the `blog-entry` Display Page Template from legacy Structured
Content (`JournalArticle`) to our modern Headless CMS Object (`Blog`), updating the page
specification via `PUT /o/headless-admin-site/v1.0/sites/{siteERC}/page-specifications/{draftERC}`
failed with a silent `400: {"status": "BAD_REQUEST", "type": "UnsupportedOperationException"}`.
Tracing `PageSpecificationResourceImpl.java` revealed that write operations on page specifications
are strictly guarded by the developer feature flag **`LPD-74328`**; without it enabled under
**Instance Settings → Feature Flags**, all mutation calls throw `UnsupportedOperationException`.

Once `LPD-74328` was enabled and the specification was submitted with `"type": "ContentPageSpecification"`
and `"status": "Draft"` (which Liferay strictly enforces for content page drafts), the page editor
rendered the title, subtitle, author, and body mappings, but failed to bind the main image.
In Liferay's Object & Info Item framework (`ObjectEntryInfoItemFormProviderUtil.java`), an Object
Attachment field is not exposed as a single scalar value. Instead, it is decomposed into subfields:
`#fileName`, `#mimeType`, and **`#fileURL`**. An Image fragment (`data-lfr-editable-type="image"`)
requires a URL to render the asset, requiring the specific composite key:
`"fieldKey": "ObjectField_<objectFieldId>#fileURL"` (e.g., `ObjectField_143894#fileURL`), rather than
a plain `ObjectField_mainImage`.

### Lessons

1. **`putSitePageSpecification` is gated by `LPD-74328`.** The headless admin site API for mutating
   page specifications requires developer feature flag `LPD-74328`. Without it, the endpoint throws
   an unhelpful `400 UnsupportedOperationException`. Furthermore, the specification payload must
   specify `"type": "ContentPageSpecification"` and `"status": "Draft"`.
   *Slide angle: The hidden gatekeeper: why headless page authoring demands LPD-74328.*

2. **Object Attachment fields map via `#fileURL` with the field ID.** While text fields map using
   their semantic name (`ObjectField_title`), Attachment fields in Liferay Objects expose subfields.
   To map an Image fragment to an Object attachment in a DPT or page specification, the fieldKey
   must point to the URL subfield using the object field's numeric ID:
   `ObjectField_<objectFieldId>#fileURL`.
   *Slide angle: Deconstructing Object attachments: why images demand #fileURL in page mappings.*

---

## 2026-10-15 — Headless CMS Space Categorization: Company scope with assetLibraries association

**What happened.** When categorizing custom Object Entries in a Headless CMS Space (`depot` scope),
passing site-scoped category IDs failed with `400: Asset category <id> does not belong to the object entry's scope`.
Furthermore, creating a vocabulary directly via the asset library endpoint
(`postAssetLibraryTaxonomyVocabulary`) created an internal vocabulary that was accepted by the API
but completely hidden from the Liferay UI under **Space → Categorization → Categories**.

To make a vocabulary both valid for depot-scoped entries and visible in the Space's UI, it must be
created at the **Company/Global scope** with an explicit `assetLibraries` association:
```json
{
  "name": "Masterclass",
  "externalReferenceCode": "VOCAB_MASTERCLASS_SPACE",
  "visibilityType": "PUBLIC",
  "multiValued": true,
  "assetLibraries": [
    {
      "id": 143544,
      "externalReferenceCode": "SPACE-MASTERCLASS-CMS"
    }
  ],
  "assetTypes": [
    {
      "type": "AllAssetTypes",
      "subtype": "AllAssetSubtypes",
      "required": false
    }
  ]
}
```
Posting this body to `POST /v1.0/sites/{companyGroupId}/taxonomy-vocabularies` (`postSiteTaxonomyVocabulary`
with `siteId: 20121`) creates the vocabulary. Categories added to it via
`POST /v1.0/taxonomy-vocabularies/{id}/taxonomy-categories` inherit the Space association, render
in the Space Categorization UI, and bind seamlessly to modern CMS entries via `"taxonomyCategoryIds": [<id>]`.

### Lessons

1. **Space vocabularies live at company scope with an `assetLibraries` association.** Liferay's
   Space Categorization UI filters vocabularies by looking for company-level vocabularies explicitly
   linked to the Space's groupId via the `assetLibraries` property array. To automate space vocabulary
   provisioning, always call `postSiteTaxonomyVocabulary` on the company site (`20121`) passing
   `"assetLibraries": [{"id": <spaceGroupId>, "externalReferenceCode": "<spaceERC>"}]`. Calling
   `postAssetLibraryTaxonomyVocabulary` creates an unlinked vocabulary that the UI ignores.
   *Slide angle: The taxonomy scope paradox: why Space vocabularies belong to the Company.*

---

## 2026-10-15 — DAM ingestion via fileURL vs base64 and the ERC Recycle Bin trap

**What happened.** When migrating media assets from an existing site DAM into the modern
Headless CMS Space (`CMSBasicDocument`), passing image data as inline `file.fileBase64`
through API request buffers led to truncated payloads. The resulting document saved in
the Space was corrupt (only a few kilobytes, failing image preview and downloads).

Additionally, when deleting the corrupted document to recreate it, a subsequent `POST` with
the same `externalReferenceCode` failed with `400: This external reference code is already in use.`
Deleting via Headless REST performs a soft delete, moving the entry to the Recycle Bin while
retaining uniqueness constraints on its `externalReferenceCode`.

Switching to `file.fileURL` pointing directly to the live document endpoint:
```json
{
  "externalReferenceCode": "BLOG_IMG_01",
  "title": "blog_01.jpg",
  "objectEntryFolderExternalReferenceCode": "CMS_FOLDER_BLOG_IMAGES",
  "file": {
    "name": "blog_01.jpg",
    "fileURL": "http://localhost:8080/documents/65391/0/blog_01.jpg/cf5929fe-...?download=true"
  }
}
```
allowed Liferay to stream the uncorrupted binary directly from source to destination at full
fidelity. For the soft-deleted entry, calling the restore endpoint
(`PUT .../by-external-reference-code/{erc}/restore`) followed by `PATCH` seamlessly updated
the record without ERC collisions.

### Lessons

1. **Prefer `fileURL` over Base64 for headless asset migrations.** In modern CMS
   (`CMSBasicDocument`), inline Base64 strings risk buffer truncation and memory bloat.
   Supplying `file.fileURL` lets the portal fetch the binary directly over HTTP without
   intermediate serialization overhead or truncation risks.
   *Slide angle: Clean asset ingestion: why streaming beats Base64 in headless migrations.*

2. **REST delete is a soft delete.** Deleting an object entry or document sends it to the
   Recycle Bin, keeping its `externalReferenceCode` reserved. Recreating an entry with the
   same ERC fails immediately. To replace an existing ERC, either restore and patch the
   entry or assign a new unique ERC.
   *Slide angle: The ghost in the trash: handling ERC collisions after REST deletion.*

---

## 2026-10-15 — Attachment fileSource in Headless CMS: userComputer vs CMSBasicDocument item selector

**What happened.** When authoring custom depot-scoped Object Definitions intended as Headless
CMS Content Structures (`scope: "depot"`, `objectFolderExternalReferenceCode: "L_CMS_CONTENT_STRUCTURES"`),
attachment fields configured with `"fileSource": "userComputerToCMSBasicDocument"` restricted
the CMS editorial UI to a local disk file-picker only. Users could not browse or select existing
media assets from the Space's CMS library / DAM. Furthermore, this prevented referencing
already-migrated CMS documents by their `externalReferenceCode`.

Updating the attachment field settings to `"fileSource": "CMSBasicDocument"`:
```json
{
  "name": "image",
  "businessType": "Attachment",
  "objectFieldSettings": [
    {"name": "acceptedFileExtensions", "value": "jpeg, jpg, pdf, png"},
    {"name": "maximumFileSize", "value": 100},
    {"name": "fileSource": "CMSBasicDocument"}
  ]
}
```
enabled the full **Item Selector** in the CMS editor, granting users the ability to both
browse/select existing media assets in the library and upload new files from their computer.
Crucially, Liferay allows live patching of `objectFieldSettings` on published attachment
fields via `PATCH /o/object-admin/v1.0/object-fields/{id}` without deleting or recreating
the object definition.

### Lessons

1. **`CMSBasicDocument` gives both choices, `userComputer` locks to local only.** In modern
   CMS structures, always prefer `"fileSource": "CMSBasicDocument"`. It provides the complete
   Item Selector experience (library browsing + direct upload) and allows Headless API entries
   to link media assets by `externalReferenceCode`.
   *Slide angle: Field settings that empower editors: why fileSource choice dictates DAM integration.*

2. **Published field settings are live patchable.** Unlike structural constraints (such as
   renaming fields or toggling versioning), `objectFieldSettings` on attachment fields can be
   updated via `PATCH /v1.0/object-fields/{id}` on live, published definitions without data loss
   or schema reprovisioning.
   *Slide angle: Painless schema iteration: what you can and cannot patch live in Liferay Objects.*

---

## 2026-10-13 — The missing site ERC in headless-admin-user

**What happened.** When attempting to inspect an existing live site (`myOldMasterClass`,
numeric site ID `65391`) to begin page and DPT migration, an agent queried
`GET /o/headless-admin-user/v1.0/sites/65391` to discover the site's
`externalReferenceCode`. The response returned `None` for the ERC. Passing the numeric
ID `65391` into `headless-admin-site` returned `404 NOT_FOUND`. The UI, however, clearly
showed the site's ERC as `455c08a5-8ad6-96f7-6833-94055442141b`.

**Root cause.** API schema asymmetry between sibling headless modules.
`headless-admin-site` strictly keys all site pages, navigation menus, and DPTs by
`{siteExternalReferenceCode}` — passing a numeric ID returns 404. But the most common
site lookup endpoint, `headless-admin-user/v1.0/sites/{id}`, **omits the
`externalReferenceCode` field from its DTO entirely**. The field is not `null` in the
database; the endpoint simply doesn't expose it.

To discover a site's ERC from its numeric ID or friendly URL, one must query
`headless-admin-site` directly using an OData filter:
`GET /o/headless-admin-site/v1.0/sites?filter=id eq <siteId>` (or in MCP:
`headless-admin-site-v1.0:getSitesPage` with `filter: "id eq <siteId>"`).

### Lessons

1. **DTO omission masquerades as missing data.** When a REST call returns `null` or omits a
   property, agents easily confuse "this record has no value" with "this API does not
   project this column". Checking the OpenAPI schema or sibling modules prevents chasing
   ghost issues.
   *Slide angle: API blindness: when the endpoint you ask doesn't know the answer exists.*

1. **Modules that mandate ERCs must provide ERC discovery.** `headless-admin-site` requires
   ERC on every subresource path, but developers and admins naturally start with numeric
   IDs or URLs. Always use `headless-admin-site/v1.0/sites?filter=...` as the discovery
   bridge.
   *Slide angle: Live migrations require robust discovery bridges.*
