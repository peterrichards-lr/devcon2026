# Masterclass CMS Data Batch

Loads **data only**: 25 documents, 42 content entries, and the entry folders they live in.

The model it loads into — the Space, the object definitions, their picklist and their
relationships — belongs to `modules/masterclass-cms-site-initializer`, not here.

## Deploy order matters, and nothing enforces it

```
1. deploy modules/masterclass-cms-workarounds
2. deploy modules/masterclass-cms-site-initializer
3. create the site from it
4. deploy this client extension
```

Step 1 has to come before step 3. The workarounds module corrects collections and
attachment mappings **as the site saves them**; a site created without it keeps the
uncorrected versions until it is recreated. See `modules/masterclass-cms-workarounds/README.md`.

A client extension runs its batch files **when it deploys**. The site initializer runs
**when a site is created from it**. The Space is created by the initializer, so it does not
exist until step 3 — and every file here is scoped to it.

Deploy this before the site exists and the import fails:

```text
Unable to deploy batch engine file .../00-02-cms-folder...json:
    com.liferay.portal.kernel.exception.NoSuchGroupException
Unable to deploy batch engine file .../00-03-cms-basic-document...json:
    No ObjectEntryFolder exists with the key {externalReferenceCode=COURSES, groupId=0, ...}
```

It fails loudly rather than importing nothing, so the symptom is visible — but the fix is
to redeploy this after the site exists, not to change anything here.

## Scope key is the Space name, not an external reference code

Every file here scopes with `"scopeKey": "eLearning"`.

The initializer creates the Space from `depot-entries.json`, and that format has **no
`externalReferenceCode` field** — the handler matches on group name and Liferay generates a
UUID. So the Space has no stable code to scope by. `GroupUtil.getGroupId` resolves a scope
key by name first, then numeric id, then external reference code, which makes the name the
one value that is stable across bundles.

Do not change these back to `ELEARNING-SPACE`; it only resolves on an instance where the
Space happens to carry that code.

## Courses import before their modules, teachers and sessions

`06-elearning-course` runs **first** of the entry files, and the numbering is load bearing.

Each course nests its related entries by reference — `elearningCourseModules`,
`elearningCourseTeachers`, `elearningCourseSessions` — with only an `externalReferenceCode`
and a `title`. Liferay does not treat a nested item as a link to an existing entry: it
**upserts** it, and outside a partial update that is a full replace. Every field the
nested item leaves out is reset — integers to `0`, text to empty, attachments cleared.

Imported the other way round, the modules arrived with their `duration`, `moduleNumber`
and `numberOfLessons`, and the course import then blanked all three. `PARTIAL_UPDATE` on
the course file does not help: on a fresh bundle the course does not exist yet, so it
takes the create path, which updates nested entries non partially regardless.

So the course creates title only stubs and relates them, and the teacher, blog, module
and session files then overwrite those stubs with their full values. A full update that
carries no relationship property leaves the relationship alone, so the links survive.

Do not move the course file back after the files it nests. Source:
`DefaultObjectEntryManagerImpl._addOrUpdateNestedObjectEntries`.
