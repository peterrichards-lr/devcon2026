# Masterclass CMS Workarounds

Corrects three things the site initializer cannot express, as the site is being created.
Each one works around a product limitation, and the bundle is meant to be deleted once
they are fixed in the product.

**Deploy it before creating the site.** The listeners act when records are saved, so a
site created first keeps the uncorrected versions until it is recreated.

The portal logs everything under `com.liferay` at ERROR, which would hide what these
listeners report, so the bundle's `META-INF/module-log4j.xml` sets its own package to INFO.

## Collections scoped to the Space

The initializer always scopes a collection to the site alone, and no token names a
Space's group ID. Collections over eLearning entries therefore showed "No Results Found"
until someone added the Space by hand after every provision.

`AssetListEntrySegmentsEntryRelModelListener` adds the site's connected Spaces when a
collection is **created** with the site as its only scope. It is not tied to this site:
it works for any site connected to a Space, and leaves a site with no connected Spaces,
or a collection created with any other scope, untouched. A scope an editor changes later
is left alone.

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
| A display page image or text | the editable's literal value (`value_i18n`) | `mappedField` |
| A display page link | the link's literal `href` (`"href": {"value": …}`) | `mappedField` in the editable's `config` |

Use `#fileURL` for an image and `#downloadURL` for a link or a URL shown as text. A
display page needs the literal form because the importer validates a display page
mapping against the live fields and drops it when it does not match.

## One registration per student per session

A student could register for the same session twice. The fix is a composite key
validation rule on MyCourseEnrollment over its two relationship fields, the student
(`r_courseToUser_userId`) and the session
(`r_enrollmentToCourseSession_c_myCourseSessionId`): saving a second enrolment with the
same pair is refused with "You are already registered for this session."

The initializer can declare validation rules inline in an object definition, but not one
over relationship fields. Those fields are created by the `object-relationships/`
handler, which runs after the definitions (Discuss #1074, UPSTREAM-FEEDBACK.md item 8).

`ObjectDefinitionModelListener` adds the rule once MyCourseEnrollment's publication has
committed (the initializer publishes after creating the relationships) and logs
`Added composite key rule MY-COURSE-ENROLLMENT-ONE-PER-SESSION`. It has to wait for the
commit: publishing marks the definition approved before it creates the object's table, and
adding the rule inside that transaction failed on PostgreSQL and rolled the whole site
creation back.

It also tries every company when the bundle starts, but **the platform only allows a
composite key before an object has entries with values in its fields.** On a site that
already has enrolments the rule is refused (reported, unhelpfully, as an invalid field
value), and the listener logs a warning saying so. To get the rule there, recreate the site
with this bundle deployed. A rule already present, found by its external reference code,
is left alone.

To reuse it for another object, add an entry to `_RULES` in that class: the object's
external reference code, the rule's code, name and error message, and 2 to 5 field names
(Integer, Picklist, Relationship or Text fields).

## Removing it

Delete the jar. Pages and collections it already saved hold real IDs and keep working, and
a session rule it added stays on MyCourseEnrollment.
New sites need the tree changed at the same time: tokens switched to whatever named form
the product adopts, and collection scope set however the initializer allows. Removing
only the jar leaves those images unmapped and those collections empty.
