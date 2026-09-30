---

description: Migrate a site initializer tree from the legacy CMS (DDM structures, DDM templates, journal articles) to object backed content, and audit an already migrated tree for references captured from the authoring instance. Use when the user asks to move web content to objects, convert a DDM structure to an object definition, or check whether an initializer will provision on a fresh bundle.
name: migrate-cms-to-objects

---

# Migrate CMS To Objects

Convert a site initializer whose content lives in DDM structures and journal articles into one whose content lives in Liferay Objects, and audit the result.

Propose the object model and the rewrites first, and apply only once the user has agreed them. A wrong data model is expensive to undo after entries exist.

## When to Invoke

- "Move this site from web content to objects"
- "Convert the Course structure to an object definition"
- "Will this initializer work on a clean bundle?"
- "Why is this collection empty after provisioning?"
- Audit only: the tree is already object backed and you want the portability report

## What This Skill Is For

Everything here is **undocumented implementation behaviour** — how handlers actually
behave, and failure modes that are silent. The build succeeds, the site provisions, no
warning is logged, and the defect shows up as a blank region on a page.

The test for anything added here is: **could someone find this in the documentation?**
If yes, leave it out. Measured against baseline, an agent already reconstructs the DDM
to object field type mapping from the stored values, spots that a display page
template's `JournalArticle` binding has to change, and rewrites every DDM `fieldKey` to
`ObjectField_…` — all unaided, five times out of five. Sections covering those were
removed rather than kept for completeness.

Work out the object model the way you would any data model. Use this skill for the
parts Liferay will not tell you.

## Packaging: Client Extension Or OSGi Module

The `site-initializer/` tree format is identical either way — same handlers, same
`page.json`, same tokens. Only the build and deployment differ.

| Form | Marker | Deploys to |
| --- | --- | --- |
| Client extension | `client-extension.yaml`, flat `site-initializer/` | Self hosted, **LXC and SaaS** |
| OSGi module | `bnd.bnd` + `build.gradle`, `src/main/resources/site-initializer/` | Self hosted only |

**Default to a client extension**, and do not change an existing CET into a module as
part of a content migration — that is two changes to untangle when the site provisions
wrong.

The canonical object based initializers in liferay-portal (`site-initializer-dsr`,
`-cmp`, `-pim`, `-cms`) are all OSGi modules because they ship inside the product. They
are authoritative for tree structure, object definition format and reference forms; they
are not a signal about how a customer workspace should package its own.

## Where Object Definitions Live

**Default to keeping them in the tree.** Handlers run in a fixed order, so the tree can
carry the whole model and its seed data:

```
list-type-definitions -> object-folders -> object-definitions -> object-relationships
    -> object-fields -> publishObjectDefinitions -> object-actions -> object-entries
```

Omit `status` from a definition file — `publishObjectDefinitions` runs after the
definitions are created.

**The reason is the dependency, not the tidiness.** `[$OBJECT_DEFINITION_ID:<Name>$]` and
`[$OBJECT_DEFINITION_CLASS_NAME:<Name>$]` resolve company wide, but only against
**published** definitions. When the definitions come from a sibling `batch` CET, the
initializer depends on that CET having already deployed and published. Nothing declares
that ordering and nothing enforces it — provision in the wrong order and every object
token resolves to nothing: the site builds, the pages render, the collections are empty.

Historically this was the only option; there was no way to couple a `batch` CET to an
initializer, so the batch had to be deployed by hand first. Trees built under that
constraint carry no `object-definitions/` at all, which is a reason to move them in
rather than evidence that they belong outside.

Keep in the tree whatever this tree renders — reached from a display page template, a
collection provider or a fragment fetch — plus anything reached transitively through a
relationship, since a relationship whose other end is absent fails to create, plus the
picklists those objects reference (`list-type-definitions` is tree scoped and will not
resolve against a picklist created elsewhere). Objects that no page here renders, or
that are shared across sites, stay in a sibling `batch` CET — and that tree must then
use the **token** reference form throughout, because it declares no aliases.

> **There is no `batch/` directory in a site initializer.** `BundleSiteInitializer` reads
> a fixed set of directories and `batch/` is not one of them. Files placed there are
> packaged into the zip and silently ignored: the build succeeds, the site provisions,
> no objects appear. The `*.batch-engine-data.json` envelope belongs to the separate
> `batch` CET type.

## Source File Encoding

Journal article XML from an older export may not be UTF-8. Converting it with a UTF-8
tool replaces accented characters with U+FFFD silently, corrupting localised strings
with no error. Check the encoding of `journal-articles/**/*.xml` before reading values
out of them.

## Applying

1. **Object definitions.** Reserved field names abort initialization and **roll back the
   entire site creation** — no site, no objects, no picklists, reading as "the CET never
   deployed". `status`, `id`, `creator`, `keywords`, `userId` are rejected; `name`,
   `email`, `location`, `company` are fine. A field with `"state": true` makes
   `defaultValue` and `defaultValueType` mandatory on that same field, and `defaultValue`
   must match a picklist entry key an earlier handler created.

1. **Relationships.** The foreign key lands on the **child**, named for the **parent**,
   first letter lowercased: `r_<relationshipName>_c_<parent>Id`. Getting it wrong is
   silent — the unknown key is ignored, the child is created with the FK at `0`, and the
   POST still returns `200`. There is an ERC twin, `r_<relationshipName>_c_<parent>ERC`,
   which is what OData relationship filters require.

1. **Entries.** One parent article becomes one parent entry; a repeating group becomes N
   child entries carrying the ordinal.

1. **DDM templates to fragments.** `ddm-templates/<name>/` holds FreeMarker over the DDM
   field namespace. This is a rewrite, not a transform. Where a template only rendered a
   field, prefer an editable mapped to the object field over reimplementing the logic.

1. **Delete the CMS sources** once the tree provisions, or they drift.

## Verification

**A page composition change needs a full reprovision.** Retriggering upserts pages but
does not retrofit composition onto pages that already exist, so an edited
`page-definition.json` takes effect only after the site is deleted and recreated. Object
definitions and entries are company scoped and survive site deletion, so runtime data
persists across it.

Then verify **as the visitor** — every failure here is silent and an authenticated
session hides all of them. An unauthenticated `curl` of the page is a Guest request:
assert on real values and confirm placeholder tokens are absent.

An object backed collection renders empty for Guest until `resource-permissions.json`
grants `VIEW` at **company** scope — `"1"`. Scope `"3"` is the trap: it sets defaults for
newly created entries only, applies without error, and changes nothing for entries that
already exist. A migrated page that looks blank is more often a missing grant than a bad
mapping.

Finally, audit the tree. The rewrite above is exactly where captured identifiers get
introduced:

| Check | Severity |
| --- | --- |
| No `[#…#]` token delimiters — only `[$…$]` substitutes | Error |
| Every `ObjectDefinition#XXXX` alias is declared by an object definition the tree can see | Error |
| No `ObjectField_<digits>` field keys — the named form is required | Error |
| No `name<hex>` relationship names inside collection provider class names | Error |
| Tree scoped tokens (`ASSET_LIST_ENTRY_ID`, `LIST_TYPE_DEFINITION_ID`, `DDM_*`, `DOCUMENT_*`, `ROLE_ID`, `LAYOUT_ID`) resolve within this tree | Error |
| Company scoped tokens (`OBJECT_DEFINITION_*`) resolve against this tree or a sibling batch CET | Warning |
| Every file is valid JSON and valid UTF-8 | Error |
| `resource-permissions.json` uses `scope` `"1"` or `"2"`, never `"3"` | Warning |

Handler timings are the fastest diagnosis of a directory that was never read — a step
reporting `took 0 ms` found no files. Fragments log as `addFragmentEntries`, with **no**
`addOrUpdate` prefix, so grepping for `addOrUpdateFragmentEntries` matches nothing and
reads exactly like the directory was missing. Site navigation menus log no line at all.

## Success Signal

The site provisions with the CMS directories removed; an unauthenticated `curl` of each
migrated page returns real field values with no placeholder tokens left in the HTML; and
the audit table above reports no errors.

## References

Ships with this skill:

- `references/site-initializer-portability.md` — which identifiers survive a move to
  another bundle, the token vocabulary and scopes, and the two object reference forms.

Available in a Liferay workspace, but **not** bundled here — optional context, never a
step this skill depends on:

- `rules/site-initializer-format.md` — tree layout, handler order, reprovision script.
- `rules/guest-access.md` — why a migrated public page renders empty for a visitor.
- `skills/manage-objects` — object definitions, fields, relationships, reserved names.
- `skills/scaffold-fragment` — for DDM template conversion.
