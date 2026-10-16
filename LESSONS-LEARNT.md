# Lessons Learnt

Raw material for the DevCon 2026 talk. Each entry is something that happened while moving
the Masterclass LMS from web content to the objects based CMS, what it taught us, and how
it might land on a slide.

Newest first. Add to it as things happen; tidy it when the slides are planned.

Every entry should say **what happened**, **the lesson**, and **the evidence** (an issue,
PR, commit, or measurement), so a claim on a slide can be traced back to something real.

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

## 2026-10-14 — The dual personality of collection classPK: string in pages, number in templates

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
