# Lessons Learnt

Raw material for the DevCon 2026 talk. Each entry is something that happened while moving
the Masterclass LMS from web content to the objects based CMS, what it taught us, and how
it might land on a slide.

Newest first. Add to it as things happen; tidy it when the slides are planned.

Every entry should say **what happened**, **the lesson**, and **the evidence** (an issue,
PR, commit, or measurement), so a claim on a slide can be traced back to something real.

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
