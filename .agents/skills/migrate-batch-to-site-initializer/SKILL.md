---

description: Move Liferay Object definitions, picklists and relationships out of a batch client extension and into a site initializer tree, leaving the batch to carry entry data. Use when the user asks to move object definitions into the site initializer, says the batch owns the objects and the initializer should, or wants a tree that provisions on a fresh bundle without a sibling batch CET.
name: migrate-batch-to-site-initializer

---

# Migrate Batch To Site Initializer

Convert `*.batch-engine-data.json` files into site initializer tree files, so the
initializer carries its own object model instead of depending on a batch CET having
already deployed.

The two formats describe the same DTOs. What changes is the envelope, how a relationship
names its ends, and who publishes the definition.

## When to Invoke

- "Move the object definitions into the site initializer"
- "The batch CET owns our objects, the initializer should"
- "Convert these batch-engine-data files into tree files"
- A collection bound to an object renders empty on a clean bundle, because the batch had
  not published when the site provisioned

## Prerequisites

- `skills/migrate-cms-to-objects/SKILL.md` → **Where Object Definitions Live** decides
  *which* objects move. Read it first; this skill is the mechanics once that is settled.
- `rules/site-initializer-format.md` for the per file formats and handler order.

## Decide What Moves

Move what this tree renders, plus anything reached through a relationship, plus the
picklists those objects reference. Leave entry data in the batch — it is the half that
benefits from batch semantics and the half the initializer is worst at.

**Split by scope before anything else.** Company scoped objects move with no further
dependency. A `site` or `depot` scoped object depends on a group that has to exist first,
which is a separate problem — see **The Space Ordering Hazard**.

## Converting A File

### Unwrap The Envelope

A batch file is `{"configuration": {...}, "items": [...]}`. A tree file is **one raw DTO**,
no wrapper and no array. One item per file.

Three keys are dropped on the way:

| Key | Why |
| --- | --- |
| `status` | `publishObjectDefinitions` runs after the definitions are created and sets it |
| `id` | The authoring instance's primary key |
| `restContextPath` | Derived from `pluralLabel` |

`updateStrategy` is read and stripped by the handler, so it may stay.

### Rewrite Relationship Ends

This is the one conversion that is not mechanical. The batch names both ends by external
reference code. **The tree's relationship handler resolves the parent by numeric ID**, so
the ERC fields alone resolve to nothing:

```json
"objectDefinitionExternalReferenceCode1": "MY-COURSE-SESSION",
"objectDefinitionExternalReferenceCode2": "MY-COURSE-ENROLLMENT"
```

becomes

```json
"objectDefinitionId1": "[$OBJECT_DEFINITION_ID:MyCourseSession$]",
"objectDefinitionId2": "[$OBJECT_DEFINITION_ID:MyCourseEnrollment$]",
"objectDefinitionName2": "MyCourseEnrollment"
```

The token is keyed on the definition **`name`**, not its ERC.

### A System Object End Needs The Directory To Exist

A relationship onto `User`, `AccountEntry` or another system object uses the same token
form — `[$OBJECT_DEFINITION_ID:User$]`. It resolves only once the tree has an
`object-definitions/` directory.

`_addObjectDefinitions` registers company wide tokens for custom definitions, then
returns early when `getResourcePaths("/site-initializer/object-definitions")` is empty —
**before** the loop that registers system object definitions. So a tree with no
`object-definitions/` cannot name a system object at all, and adding the first definition
file is what makes the system tokens available. Source: `BundleSiteInitializer`.

### Give Every Moved Entity A Readable ERC

Relationships and picklist entries are routinely authored without one, and Liferay then
generates a UUID that differs on every bundle. Converting is the cheap moment to fix it,
because nothing references the old value yet. See `rules/site-initializer-portability.md`.

## Remove The Originals From The Batch

Delete the moved files from the batch CET and rebuild it. Leaving both in place is not a
harmless duplicate: the batch runs on deploy and the initializer on site creation, so the
two race, and whichever loses reports an error against an entity that already exists.

A relationship file with `"createStrategy": "INSERT"` is not idempotent and fails on every
redeploy after the first:

```text
Unable to deploy batch engine file .../00-08-....json:
There is already an object relationship with this name in the object definition "User"
```

That failure is a reason to move a relationship out, not something to fix in place.

## The Space Ordering Hazard

**Inferred from source; not yet measured.** Applies only to `site` and `depot` scoped
definitions — a company scoped move is unaffected.

`BundleSiteInitializer` can create a Space itself, from `depot-entries.json` with
`"type": "Space"`, and connects it to the site it is provisioning. But the handler graph
does not couple the two steps:

```java
addObjectDefinitionsR, _dependsOn(
    addOrUpdateListTypeDefinitionsR, addOrUpdateObjectFoldersR, addUserAccountsR)
...
addOrUpdateDepotEntriesR, _dependsOn()
```

Nothing orders `addOrUpdateDepotEntries` before `addObjectDefinitions`. The executor walks
a `HashMap` via `entrySet()`, and its key class overrides neither `hashCode` nor `equals`,
so among handlers whose dependencies are already satisfied the order follows identity hash
and need not repeat between runs.

A depot scoped definition naming its Space in `acceptedGroupExternalReferenceCodes` may
therefore be created before that Space exists. Measure before relying on it: provision
repeatedly and compare the two `Invoking …` lines.

```bash
grep --extended-regexp 'Invoking (addOrUpdateDepotEntries|addObjectDefinitions)' \
	bundles/tomcat*/logs/catalina.out
```

If the order is not stable, keep the Space in the batch CET, which completes on deploy.

## Patterns and Gotchas

- **A `took 0 ms` handler found no files.** `addOrUpdateDepotEntries took 0 ms` on a tree
  with no `depot-entries.json` is correct and proves nothing about a tree that has one.
- **Moving a definition does not move its data.** Object definitions and entries are
  company scoped and survive site deletion, so a reprovision does not re-run the batch.
  Entries created earlier stay attached to the definition the initializer now owns.
- **A `state: true` field still needs `defaultValue` and `defaultValueType`**, and the
  value must match a picklist entry key the tree creates earlier. Omitting either rolls
  back the whole site. See `skills/manage-objects/SKILL.md`.

## Success Signal

Delete the moved entities from the instance first, then provision — otherwise the handler
upserts what is already there and proves only that the files parse.

Delete by **numeric ID**; the by external reference code path returns `405`. Relationships
go first, because `deletionType: prevent` blocks the definition.

Each moved handler should report real work, and no `InitializationException` should
appear. Observed on 2026.q3.5 for two definitions, one picklist and two relationships:

```text
Invoking addOrUpdateListTypeDefinitions took 31 ms
Invoking addObjectDefinitions took 202 ms
Invoking addOrUpdateObjectRelationships took 13 ms
Invoking publishObjectDefinitions took 900 ms
Initialized <initializer> for group <id> in 9039 ms
```

Then assert the result rather than the timings — the definitions `approved` and at the
scope authored, the relationship external reference codes the ones written rather than
UUIDs, and an entry created through the relationship resolving its
`r_<relationship>_c_<parent>Id` foreign key and defaulting any `state` field.

## References

- `skills/migrate-cms-to-objects/SKILL.md` — decides which objects belong in the tree.
- `skills/manage-objects/SKILL.md` — field, relationship and scope behaviour.
- `rules/site-initializer-format.md` — per file formats, handler order, tokens.
- `rules/site-initializer-portability.md` — which identifiers survive a move.
- `rules/client-extension-types.md` — why a batch and an initializer cannot share a project.