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

---

# Approach 1: site initializer to site initializer

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

---

# Approach 2: live site, migrated in place

## 2026-10-15 — Headless REST Deletions Bypass the Recycle Bin: deleteArticle vs. moveArticleToTrash

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
3. **Collections and Object definitions:** Collections (`AssetListEntry`) and modern Custom Objects (`/o/c/...`)
   do not participate in the legacy Recycle Bin framework at all; deletions on these models are always permanent.

### Lessons

1. **Headless REST `DELETE` operations are irreversible hard deletes.** Never assume items deleted via
   REST APIs or MCP tools can be recovered from the Recycle Bin. There is no soft-delete safety net in
   the Headless layer.
2. **Take full database snapshots before automated cleanup.** In migration pipelines or automated cleanup
   scripts, full database and document store backups are the only recovery mechanism against accidental
   data loss during programmatic cleanup.
   *Slide angle: The Invisible Trash: Why Headless REST DELETES bypass the Recycle Bin and why automated migrations need external backup nets.*

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
