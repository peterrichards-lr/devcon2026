# Site Initializer Portability

> **Before authoring:** Load `manage-pages`, `manage-objects`, or `migrate-cms-to-objects` for the procedure. This card is the fact: which identifiers survive a move to another bundle and which do not.

A site initializer tree is portable when every identifier it contains either resolves at provision time or is declared inside the tree. An identifier captured from the instance the site was authored on looks correct in review, provisions without error, and silently resolves to nothing.

Every failure on this card is **silent**. The build succeeds, the site provisions, the handler logs no warning, and the defect surfaces as a blank region on a page or an empty collection.

## Token Delimiters Are `[$` and `$]`

`SiteInitializerUtil.replace` keys on `[$` and `$]`. Any other delimiter is not a token — it is a literal string that reaches the JSON parser unchanged and resolves to nothing.

```json
"classPK": "[$ASSET_LIST_ENTRY_ID:BLOG-ENTRIES$]"     // substituted
"classPK": "[#ASSET_LIST_ENTRY_ID:BLOG-ENTRIES#]"     // literal, never substituted
```

The `[#…#]` form is easy to introduce by hand and impossible to spot by eye, because the entity name inside it is correct. Grep for it directly:

```bash
grep -rn '\[#[A-Z_]*:' <tree>
```

## Two Token Scopes — This Decides Whether a Reference Resolves

Most tokens are registered by the handler that creates the entity, inside its per file loop, so they resolve **only** against entities created by an earlier handler in the same tree. Object definition tokens are the exception: `_addObjectDefinitions` runs a company wide pass before reading any file, registering every **published** definition in the company whoever created it.

| Token | Scope | Resolves against |
| --- | --- | --- |
| `[$OBJECT_DEFINITION_ID:<Name>$]` | Company | Any published object definition, including ones created by a sibling `batch` CET |
| `[$OBJECT_DEFINITION_CLASS_NAME:<Name>$]` | Company | As above |
| `[$OBJECT_DEFINITION_PORTLET_ID:<Name>$]` | Company | As above |
| `[$LIST_TYPE_DEFINITION_ID:<Name>$]` | Tree | `list-type-definitions/` in this tree only |
| `[$ASSET_LIST_ENTRY_ID:<Name>$]` | Tree | `asset-list-entries.json` in this tree only |
| `[$DDM_STRUCTURE_ID:<Name>$]`, `[$DDM_TEMPLATE_ID:<Name>$]` | Tree | This tree only |
| `[$TEMPLATE_ENTRY_ID:<Name>$]` | Tree | This tree only |
| `[$DOCUMENT_FILE_ENTRY_ID:<path>$]`, `[$DOCUMENT_URL:<path>$]`, `[$DOCUMENT_JSON:<path>$]` | Tree | `documents/` in this tree only |
| `[$ROLE_ID:<Name>$]` | Tree | `roles.json` in this tree only |
| `[$LAYOUT_ID:<friendly-url>$]` | Tree | `layouts/` in this tree only |
| `[$COMPANY_ID$]`, `[$GROUP_ID$]`, `[$GROUP_KEY$]`, `[$GROUP_FRIENDLY_URL$]`, `[$PORTAL_URL$]` | Context | Always available |

The practical consequence: **a tree whose objects come from a `batch` CET can still reference them**, because object tokens are company wide. It cannot reference that CET's picklists the same way.

Two conditions on the company wide pass: the definition must be **published** (the pass filters on `STATUS_APPROVED`, so a draft registers nothing), and the token is keyed on the definition's **short name**, which equals `name` for a custom object.

To confirm a token's scope, find where its handler calls `stringUtilReplaceValues.put` in `BundleSiteInitializer` — inside the loop means tree only, before the loop means company wide.

## Object References Have Two Valid Forms

Both forms appear in canonical portal initializers. They are not interchangeable, and picking the wrong one is the most common portability defect.

```json
// Token form — resolves company wide, for any published object
"contentType": {"className": "[$OBJECT_DEFINITION_CLASS_NAME:CMPProject$]"}

// Alias form — resolves only if an object definition in THIS tree declares it
"contentType": {"className": "com.liferay.object.model.ObjectDefinition#D1S2"}
```

The alias form is legitimate. `site-initializer-dsr` and `site-initializer-pim` use it, and it works because each ships `object-definitions/` declaring the alias on the definition itself:

```json
{
	"className": "com.liferay.object.model.ObjectDefinition#D1S2",
	"externalReferenceCode": "L_DSR_ROOM",
	"name": "DSRRoom"
}
```

Aliases are author chosen four character mnemonics (`#D1S2` for `DSRRoom`, `#C0N1` for `PIMConnector`, `#L1K2` for `PIMLink`). They are not derived from the ERC.

In all three canonical initializers the form follows from where the objects live — `dsr` and `pim` keep `object-definitions/` in the tree and use aliases; `cmp` creates its objects from a Java batch and uses the token form.

**The rule is resolvability, not form.** An alias reference is a defect only when nothing the tree can see declares it:

```bash
# For each ObjectDefinition#XXXX reference, the alias must appear in an object definition

grep -rho 'ObjectDefinition#[A-Za-z0-9]\{4\}' <tree> | sort -u
grep -rl '"className": "com.liferay.object.model.ObjectDefinition#' <tree>/object-definitions <sibling-batch>
```

A tree whose objects are created by a `batch` CET has **no** `object-definitions/` directory, so it can declare no aliases. Such a tree must use the token form throughout. An alias in that tree is always dangling — it was captured from the authoring instance, where Liferay generated it.

## Field References

| Form | Portable | Notes |
| --- | --- | --- |
| `"fieldKey": "ObjectField_shortDescription"` | Yes | Named form. Always use this. |
| `"fieldKey": "ObjectField_39733"` | **No** | Numeric object field ID from the authoring instance. |
| `"fieldKey": "ObjectField_39733#fileURL"` | **No** | Same, with an attachment subfield suffix. |
| `"fieldKey": "CourseName"` | n/a | A DDM field name. Valid only on a tree still bound to a DDM structure. |

A numeric field ID cannot be repaired from the tree alone — it needs the object definition that owns it. Resolve it against the definition's `objectFields[].name`, matching on the field the page is meant to display.

## Collection Provider Class Names

Related content collections encode the object and relationship into the provider class name. The portable form tokenises the company segment and names the relationship:

```
com.liferay.object.internal.info.collection.provider.OneToManyObjectRelationshipRelatedInfoCollectionProvider_[$COMPANY_ID$]_C_MyCourse_myCourseToMyCourseModule
```

The captured form carries an instance ID and an autogenerated relationship name, and never resolves elsewhere:

```
…ManyToManyObjectRelationshipRelatedInfoCollectionProvider_com.liferay.object.model.ObjectDefinition#B5C5_name7252b11db32e4f01aeb20124
```

A relationship name matching `name[0-9a-f]{20,}` is always autogenerated. Replace it with the declared `name` from `object-relationships/` or the batch CET.

## File Level Requirements

Two conditions that fail before any token is considered.

**Valid JSON.** Jackson has `ALLOW_UNQUOTED_FIELD_NAMES` disabled by default, so a bare key aborts the handler. Where the handler emits no log line of its own — `_addOrUpdateSiteNavigationMenus` runs inside `addOrUpdateLayoutsContent` — the only symptom is missing output.

**Valid UTF-8.** A Latin-1 file round trips through any UTF-8 tool as U+FFFD, corrupting localised strings irreversibly. `iconv -f ISO-8859-1 -t UTF-8` repairs it.

```bash
python3 - <<'EOF'
import json,os
for dp,_,fns in os.walk("."):
	for fn in [f for f in fns if f.endswith(".json")]:
		p=os.path.join(dp,fn); b=open(p,"rb").read()
		try: t=b.decode("utf8")
		except UnicodeDecodeError as e: print("NOT UTF-8:",p,e.start); continue
		try: json.loads(t)
		except json.JSONDecodeError as e: print("INVALID JSON:",p,e)
EOF
```

## Audit Checklist

Run against any tree before trusting it on a fresh bundle:

| Check | Severity |
| --- | --- |
| No `[#…#]` delimiters | Error |
| Every `ObjectDefinition#XXXX` alias declared in a visible object definition | Error |
| No `ObjectField_<digits>` field keys | Error |
| No `name<hex>` relationship names in provider class names | Error |
| Tree scoped tokens resolve against this tree | Error |
| Company scoped tokens resolve against this tree or a sibling batch CET | Warning |
| Every file valid JSON and valid UTF-8 | Error |
| `resource-permissions.json` uses `scope` `"1"` or `"2"`, not `"3"` | Warning |

## References

- `skills/migrate-cms-to-objects/SKILL.md` — the primary consumer of this card.
- `rules/site-initializer-format.md` — the tree layout and per file formats.
- `rules/guest-access.md` — why an unresolved reference reads as an empty collection.
- Canonical object based initializers: `modules/apps/site-initializer/site-initializer-{dsr,cmp,pim}` in liferay-portal.
