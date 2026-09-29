---

description: Migrate a site initializer tree from the legacy CMS (DDM structures, DDM templates, journal articles) to object backed content, and audit an already migrated tree for references captured from the authoring instance. Use when the user asks to move web content to objects, convert a DDM structure to an object definition, or check whether an initializer will provision on a fresh bundle.
name: migrate-cms-to-objects

---

# Migrate CMS To Objects

Convert a site initializer whose content lives in DDM structures and journal articles into one whose content lives in Liferay Objects, and audit the result.

The skill runs in two phases. **Phase 1 produces a plan and stops.** The plan is the dry run: it states every field mapping, every structural decision and every unresolvable reference, and nothing is written until the user confirms it. This exists because the decisions below are not derivable from the source — a skill that guessed them would silently produce the wrong data model.

## When to Invoke

- "Move this site from web content to objects"
- "Convert the Course structure to an object definition"
- "Will this initializer work on a clean bundle?"
- "Why is this collection empty after provisioning?"
- Audit only: the tree is already object backed and you want the Phase 1 report without migrating

## What Cannot Be Derived — Read This First

Three decisions carry the migration, and none of them follow from the DDM source. They are why the plan phase exists.

**DDM types under specify.** Every nested field in a fieldset is typically `type=text dataType=string`, regardless of what it holds. A field named `NumberOfLessons` carrying `"12"` is a string in DDM and wants to be an `Integer` object field. Propose the upgrade; do not apply it unasked.

**A fieldset has two possible fates.** See the classification rule below. Both outcomes are correct in different cases, and both occur in real migrations of the same structure.

**Field names get rethought, not transliterated.** `Name` → `title`, `ProgramDescription` → `courseProgram`, `Info` → `description`, `Image` → `photo`. PascalCase to camelCase is the floor, not the answer. Propose it; let the user correct it.

## Phase 1 — Plan

Produce the whole plan before writing anything. Read only.

### Step 1: Inventory the Source

```bash
TREE=client-extensions/<name>/site-initializer      # or src/main/resources/site-initializer

ls "${TREE}"/ddm-structures/ "${TREE}"/ddm-templates/ 2>/dev/null
find "${TREE}/journal-articles" -name '*.xml' | wc -l
```

A DDM structure is JSON inside a CDATA block inside XML. Extract the field list:

```bash
python3 - <<'EOF'
import json,re,glob,os
for f in sorted(glob.glob("<TREE>/ddm-structures/*.xml")):
	m=re.search(r'<!\[CDATA\[(.*?)\]\]>',open(f,encoding="utf8").read(),re.S)
	if not m: continue
	d=json.loads(m.group(1))
	print("--",os.path.basename(f))
	for fl in d.get("fields",[]):
		nested=fl.get("nestedFields",[]) or []
		print(f"   {fl['name']:26} type={fl.get('type',''):12} dataType={fl.get('dataType',''):8} nested={len(nested)}")
		for nf in nested:
			print(f"        {nf['name']:24} type={nf.get('type','')}")
EOF
```

### Step 2: Map Field Types

Observed mapping. `businessType` drives the object field; `DBType` follows from it.

| DDM `type` | DDM `dataType` | `businessType` | `DBType` |
| --- | --- | --- | --- |
| `text` | `string` | `Text` | `String` |
| `text` | `string` | `LongText` | `Clob` |
| `rich_text` | `string` | `RichText` | `Clob` |
| `image` | `image` | `Attachment` | `Long` |
| `document_library` | `document-library` | `Attachment` | `Long` |
| `select`, `radio` | `string` | `Picklist` | `String` |
| `checkbox` | `boolean` | `Boolean` | `Boolean` |
| `date` | `date` | `Date` | `Date` |
| `numeric` | `integer` / `double` | `Integer` / `Decimal` | `Integer` / `Double` |
| `fieldset` | — | **no equivalent — classify it** | — |

`text` maps to `Text` or `LongText` depending on the values actually stored, not on the structure. Sample the journal articles before choosing: a field holding prose belongs in `LongText`/`Clob`, a label belongs in `Text`/`String`.

Propose a type upgrade wherever the stored values are consistently numeric, boolean or date shaped, and say so explicitly in the plan.

### Step 3: Classify Every Fieldset

This is the decision that shapes the data model. Apply the rule, then state the conclusion and the evidence in the plan.

**Repeating group → a related object.** Several fieldsets whose names differ only by a trailing integer, whose nested fields have parallel shape:

```
Module1 { Module1Name, Module1Description, Module1Duration, Module1NumberOfLessons }
Module2 { Module2Name, Module2Description, Module2Duration, Module2NumberOfLessons }
Module3 { Module3Name, Module3Description, Module3Duration, Module3NumberOfLessons }
```

Becomes one `Module` object with the prefix stripped (`name`, `description`, `duration`, `numberOfLessons`), a discriminator field carrying the ordinal (`moduleNumber`, `Integer`), and a relationship to the parent. Ask for `type` and `deletionType` — a real migration of exactly this structure chose `manyToMany` with `disassociate`, which is not the obvious answer.

**Presentational grouping → flatten to scalars.** A lone fieldset whose nested fields have distinct names and no sibling of the same shape:

```
Features { NumberOfLessons, Quizzes, Duration, MaxRetakes, PassPercentage }
```

Becomes five ordinary fields directly on the parent object. The fieldset carried layout, not structure.

Both patterns occur in the same DDM structure. Do not apply one rule to the whole file.

### Step 4: Decide Where Object Definitions Live

**Default to keeping them in the tree.** A site initializer can carry the entire data layer, and doing so makes it self contained — it provisions correctly on a clean bundle with nothing deployed beside it.

Handlers run in a fixed order, so the tree can express the whole model and its seed data:

```
list-type-definitions -> object-folders -> object-definitions -> object-relationships
    -> object-fields -> publishObjectDefinitions -> object-actions -> object-entries
```

Two of the three canonical object based initializers do exactly this. The third does not, and the consequence is visible in how each one writes its references:

| Initializer | Object definitions | Reference form used |
| --- | --- | --- |
| `site-initializer-dsr` | in tree | alias — `ObjectDefinition#D1S2` |
| `site-initializer-pim` | in tree | alias — `ObjectDefinition#C0N1` |
| `site-initializer-cmp` | out of tree (Java batch) | token — `[$OBJECT_DEFINITION_CLASS_NAME:CMPProject$]` |

**The reason to prefer in tree is the dependency, not the tidiness.** Object tokens resolve company wide, but only against **published** definitions — the registering pass filters on `STATUS_APPROVED`. When the definitions come from a sibling `batch` CET, the initializer therefore depends on that CET having already deployed and published. Nothing in either CET declares that ordering and nothing enforces it. Provision in the wrong order and every object token silently resolves to nothing: the site builds, the pages render, the collections are empty.

Keeping `object-definitions/` in the tree removes the ordering question entirely.

Reach for a sibling `batch` CET only when the objects genuinely belong to something larger than this site — shared across several initializers, or already owned and managed elsewhere. Then the tree must use the **token** form throughout, because it declares no aliases and an `ObjectDefinition#XXXX` reference in it is always dangling.

One caveat when moving definitions into the tree: object definitions are **company scoped and survive site deletion**, so a reprovision re-runs `object-definitions/` against objects that already exist. The handler logs as `addObjectDefinitions` rather than `addOrUpdate…`, unlike its neighbours — confirm against your bundle how it behaves on a second run before relying on the tree to carry field changes, as opposed to the initial creation.

See `rules/site-initializer-portability.md` for the reference forms.

### Step 5: Inventory References To Rewrite

Every place the CMS binding is named:

```bash
grep -rn 'JournalArticle\|ddmStructureKey\|ddmTemplateKey\|DDM_STRUCTURE_ID\|TEMPLATE_ENTRY_ID' "${TREE}"
grep -rn '"fieldKey"' "${TREE}" | grep -v ObjectField_
```

| Location | From | To |
| --- | --- | --- |
| `display-page-templates/*/display-page-template.json` | `contentType.className: com.liferay.journal.model.JournalArticle` + structure ERC subtype | `[$OBJECT_DEFINITION_CLASS_NAME:<Name>$]` |
| `page-definition.json` field mappings | `"fieldKey": "CourseName"` | `"fieldKey": "ObjectField_courseName"` |
| Collection displays | asset list / DDM structure source | object collection provider (see the portability card) |
| `asset-list-entries.json` | `classNameId` of `JournalArticle` | the object definition |

### Step 6: Emit the Plan

Present all of it and stop. The plan must state, per structure:

- Source field → target field, with `businessType`, and a marker on every proposed type upgrade
- Every fieldset, its classification, and the evidence for it
- Proposed relationships with `type` and `deletionType`
- Where object definitions will live, and the reference form that follows
- Every reference to rewrite, with its file and line
- Anything unresolvable, named explicitly — never guessed

Ask for confirmation. Do not write.

## Phase 2 — Apply

Only after confirmation.

1. **Write object definitions.** Either `object-definitions/<NN-name>.json` in the tree, or a sibling `batch` CET. Omit `status` — the initializer publishes. Reserved field names abort the whole provision: `status`, `id`, `creator`, `keywords`, `userId` are rejected. See `manage-objects`.

1. **Write relationships.** `object-relationships/<name>.json`, resolving the parent with `[$OBJECT_DEFINITION_ID:<Name>$]`. The foreign key lands on the **child**, named for the **parent**: `r_<relationshipName>_c_<parent>Id`.

1. **Convert journal articles to entries.** Each `journal-articles/<type>/<name>.xml` holds the field values; the sibling `.json` holds metadata. Emit object entries, setting the relationship FK on children. For a repeating group, one parent article becomes one parent entry plus N child entries carrying the discriminator.

1. **Rewrite the references** from Step 5.

1. **Convert DDM templates to fragments.** `ddm-templates/<name>/` holds FreeMarker operating on the DDM field namespace. This is a rewrite, not a transform — the output is a fragment with `index.html`, `index.css`, `index.js` and `index.json`. Load `scaffold-fragment` before authoring one. Where the template only rendered a field, prefer an editable mapped to the object field over reimplementing the logic.

1. **Delete the CMS sources** once the tree provisions: `ddm-structures/`, `ddm-templates/`, `journal-articles/`. Leaving them is not harmful, but they will drift.

## Verification

A page composition change needs a reprovision — retriggering upserts pages but does not retrofit composition onto pages that already exist. Delete the site, redeploy the CET, and compare handler timings against the previous run. See `rules/site-initializer-format.md` for the reprovision script.

Then verify as the visitor, because every failure here is silent and an authenticated session hides all of them:

```bash
curl --silent --url "http://localhost:${PORT}/web/<site>/<page>" > /tmp/page.html
```

Assert on real values and confirm placeholders are **absent**. An object backed collection renders empty for Guest until `resource-permissions.json` grants `VIEW` at company scope — `scope` `"1"`. A migrated page that looks blank is far more often a missing grant than a bad mapping. See `rules/guest-access.md`.

Finally, run the audit checklist in `rules/site-initializer-portability.md` against the migrated tree. The rewrite in Step 5 is exactly where captured identifiers get introduced.

## Failure Modes

- **A fieldset flattened when it should have been a relationship.** Recoverable only by redoing the data model. This is why Step 3 stops for confirmation.
- **Numeric field keys after rewriting.** `ObjectField_39733` cannot be repaired from the tree alone. Always write the named form.
- **An alias reference in a batch backed tree.** Provisions cleanly, renders nothing. Use the token form.
- **Reserved field name.** Aborts initialization and rolls back the entire site creation, leaving no site and no objects — reads as "the CET never deployed".
- **Latin-1 source files.** Journal article XML from an older export may not be UTF-8. Converting it with a UTF-8 tool corrupts accented characters silently.

## Success Signal

The site provisions with the CMS directories removed; an unauthenticated `curl` of each migrated page returns the real field values with no placeholder tokens left in the HTML; and the audit checklist reports no errors.

## References

- `rules/site-initializer-portability.md` — the identifier rules this skill rewrites against.
- `rules/site-initializer-format.md` — tree layout, handler order, reprovision.
- `skills/manage-objects/SKILL.md` — object definitions, fields, relationships, reserved names.
- `skills/scaffold-fragment/SKILL.md` — for DDM template conversion.
- `rules/guest-access.md` — why a migrated public page renders empty.
