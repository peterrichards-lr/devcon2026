# Masterclass CMS Workarounds

Corrects two things the site initializer cannot express, as the site is being created.
Each one works around a product limitation, and the bundle is meant to be deleted once
both are fixed in the product.

**Deploy it before creating the site.** Both listeners act when records are saved, so a
site created first keeps the uncorrected versions until it is recreated.

## Collections scoped to the Space

The initializer always scopes a collection to the site alone, and no token names a
Space's group ID. Collections over eLearning entries therefore showed "No Results Found"
until someone added the Space by hand after every provision.

`AssetListEntrySegmentsEntryRelModelListener` adds the site's connected Spaces when a
collection is **created** in `/masterclass-cms` with the site as its only scope. A scope
an editor changes later is left alone.

## Attachment fields mapped by name

An attachment field can only be mapped through subfields keyed by its numeric ID, such
as `ObjectField_37434#fileURL`, which the tree cannot know in advance. The tree names
the field with a token instead, and `FragmentEntryLinkModelListener` resolves it:

```
[$OBJECT_FIELD_KEY:<ObjectName>:<fieldName>#<subfield>$]
```

| Where the mapping is | Put the token in | Becomes |
| --- | --- | --- |
| A collection item | the mapping's `fieldKey`, `contextSource` `CollectionItem` | `collectionFieldId` |
| A display page | the editable's literal value (`value_i18n`) | `mappedField` |

A display page needs the literal form because the importer validates a display page
mapping against the live fields and drops it when it does not match.

## Removing it

Delete the jar. Pages and collections it already saved hold real IDs and keep working.
New sites need the tree changed at the same time: tokens switched to whatever named form
the product adopts, and collection scope set however the initializer allows. Removing
only the jar leaves those images unmapped and those collections empty.
