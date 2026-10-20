# Liferay Platform Feedback: Bugs & Feature Requests

This document tracks upstream product gaps, architectural defects, and feature requests identified during the **DevCon 2026** migration of the Masterclass LMS from legacy Web Content to modern Headless CMS and Liferay Objects.

---

## Executive Classification Summary

| # | Item Title | Team / Domain | Classification | Primary Beneficiary | Tracking / Status |
|---|---|---|---|---|---|
| **1** | **Headless REST API for Collections / Asset Lists (CRUD & Criteria)** | Headless CMS & Data Engine | Feature Request | Headless CMS APIs, MCP, External CI/CD & AI Agents | [Discuss #1075](https://discuss.liferay.com/t/headless-rest-api-for-managing-collections-asset-lists-crud-criteria/1075) |
| **2** | **Lightweight REST Endpoint to Publish Site Page Drafts** | Headless CMS & Data Engine | Bug / FR | Headless Site API (`headless-admin-site`) consumers | *Pending* |
| **3** | **Object Actions on Versioned/Draft Content Structures Fire on Empty Draft Shells** | Headless CMS & Data Engine | Bug / FR | Headless CMS Content Structures & Automation | [LPD-110575](https://liferay.atlassian.net/browse/LPD-110575) |
| **4** | **Custom Display Templates (Info Templates) Not Available for Related Collections** | Layouts & Info Framework | Bug | Page Editor, Headless CMS rendering & Site Initializers | [LPD-110572](https://liferay.atlassian.net/browse/LPD-110572) |
| **5** | **Page Layout Import Requires Internal Database Primary Key for Attachment Fields** | Layouts & Info Framework | Bug | Site Initializer portability & REST Page Specifications | [LPD-110573](https://liferay.atlassian.net/browse/LPD-110573) |
| **6** | **Display Page Templates Fail on Clean Site Initializer Deployments Due to Template Dependency Timing** | Site Initializers & DevEx | Bug | Clean bundle provisioning, CI/CD pipelines | [LPD-110574](https://liferay.atlassian.net/browse/LPD-110574) (under review) |
| **7** | **Collections in Page Definitions Are Dropped Depending on Site Initializer Handler Order** | Site Initializers & DevEx | Bug | Site Initializer predictability and automation | [LPD-110315](https://liferay.atlassian.net/browse/LPD-110315) |
| **8** | **Support Object Validation Rules in Site Initializers** | Site Initializers & DevEx | Feature Request | Site Initializers & Infrastructure-as-Code | [Discuss #1074](https://discuss.liferay.com/t/better-support-for-object-validation-rules-in-site-initializers/1074) |

---

## Detailed Breakdown by Product Team

### 1. Headless CMS & Data Engine Team

#### Item 1: Headless REST API for Collections / Asset Lists (CRUD & Criteria)
* **Type:** Feature Request
* **Tracking:** [discuss.liferay.com/t/1075](https://discuss.liferay.com/t/headless-rest-api-for-managing-collections-asset-lists-crud-criteria/1075)
* **Summary:** Provide a headless REST API to create, view, update, and configure Collections (Asset Lists) and their dynamic filtering criteria.

##### Description
Modern Liferay provides comprehensive REST APIs for virtually all Headless CMS building blocks: Spaces/Depots, Content Structures, Site Pages, Taxonomies, and Documents can all be managed completely headlessly. However, Collections (Asset Lists) remain a major missing piece: there is currently no Headless management API to create or configure collections (either manual asset lists or dynamic criteria collections). As a result, any organization looking to automate their digital experience via external CI/CD pipelines, orchestrators, or AI integrations is blocked and must resort to manual clicks in the Liferay UI.

##### Impact
Unlocks 100% headless, automated digital experience management for external orchestrators, CI/CD, and AI agents.

##### Proposed Solution
Expose endpoints under the headless admin suite (e.g., `headless-admin-asset-list` or similar) to:
* Create, update, and delete Collections.
* Set criteria rules (Object type, connected Spaces/Depots, taxonomy filters).
* Query existing collections and their configurations.

> **Clue for Engineering:**  
> This closes the single remaining API gap in achieving full headless content assembly coverage across Spaces and Object-backed structures.

---

#### Item 2: Lightweight REST Endpoint to Publish Site Page Drafts
* **Type:** Bug / Feature Request
* **Tracking:** *Pending*
* **Summary:** Provide a dedicated action endpoint to publish an existing page draft without re-sending the entire JSON layout specification.

##### Description
When managing site pages via the Headless Site API, publishing a draft page currently requires sending a heavy `PUT` request containing the entire page layout specification (which can easily exceed 100KB+ of JSON). A dedicated publish endpoint (`POST /v1.0/sites/{siteExternalReferenceCode}/page-specifications/{pageSpecificationExternalReferenceCode}/publish`) is referenced in API specifications, but invoking it currently returns a `204 No Content` response while leaving the page draft in an unpublished state.

##### Impact
Causes high overhead, wasted network bandwidth, and unnecessary latency when publishing pages via external workflows or automated pipelines.

##### Proposed Solution / Expected Behavior
Activate the existing `POST .../publish` endpoint so that it transitions the latest approved/draft specification to published status, or provide a lightweight action endpoint that does not require re-submitting the full page layout JSON.

> **Clue for Engineering:**  
> In `BasePageSpecificationResourceImpl`, the publish method currently returns 204 without executing the promotion logic, while sending an approved status via the parent page PUT endpoint works as an interim workaround. Making this dedicated endpoint functional would provide a significant performance and ergonomics win.

---

#### Item 3: Object Actions on Versioned/Draft Content Structures Fire on Empty Draft Shells
* **Type:** Bug / Feature Request
* **Tracking:** [LPD-110575](https://liferay.atlassian.net/browse/LPD-110575)
* **Summary:** Actions configured to trigger "On After Add" on Content Structures execute immediately when an empty draft is opened, rather than when content is published.

##### Description
In modern Headless CMS, Content Structures are Object Definitions with drafts and versioning enabled (`enableObjectEntryDraft: true`). When an author or API client creates a new content entry, an initial empty draft is created first. Currently, Object Actions configured to run **On After Add** fire immediately upon the creation of this empty draft—when all title and content fields are still null. Furthermore, the standard "Update Object Entry" action cannot perform dynamic lookups on related records.

##### Impact
Automated business logic, webhook notifications, and record synchronization fail or send blank values because they trigger before the author has actually written or published the content.

##### Proposed Solution / Expected Behavior
* Provide an **On After Publish** (or *On After Status Change: Approved*) trigger event for Objects that have drafts/versioning enabled.
* Allow Object Actions to perform lookups or conditional updates on related entries.

> **Clue for Engineering:**  
> Because CMS Content Structures set `enableObjectEntryDraft: true`, the initial database insert occurs before any field data is populated. An explicit publish lifecycle trigger would solve this without breaking standard add events on non-draft objects.

---

### 2. Layouts & Info Framework Team

#### Item 4: Custom Display Templates (Info Templates) Not Available for Related Collections in Page Editor
* **Type:** Bug
* **Tracking:** [LPD-110572](https://liferay.atlassian.net/browse/LPD-110572)
* **Summary:** When displaying related child entries in a Collection Display, custom Info Templates for that child type cannot be selected.

##### Description
When building a page or Display Page Template for an Object (for example, a *Course*), content authors often need to display a list of related items (such as the *Sessions* or *Instructors* linked to that course). When dropping a **Collection Display** fragment onto the page and configuring its source as the Relationship (e.g., *Course > Sessions*), the Page Editor does not show the custom Display Templates (Info Templates) created for the child Object (*Sessions*). Authors can only select generic, plain fields and cannot apply the tailored card layouts or formatted templates they designed for the child entity.

##### Impact
Blocks authors from rendering computed/transformed fields or specialized card templates for related entities in both live Page Editor usage and Site Initializers.

##### Steps to Reproduce
1. Create two Objects with a 1-to-many or many-to-many relationship (e.g., *Course* and *Session*).
2. Create an Info Template (Display Template) specifically for the child Object (*Session*).
3. Create a Display Page Template for the parent Object (*Course*).
4. Add a **Collection Display** fragment and set the collection provider to the relationship (*Course Sessions*).
5. Attempt to select the child Object's Info Template to style the collection items.
* **Expected Result:** The Page Editor lists the available Info Templates designed for the child entity so collection items render using the custom template.
* **Actual Result:** The Info Template selector is either unavailable or does not list the child entity's templates.

> **Clue for Engineering:**  
> It seems the collection provider for object relationships (`RelatedInfoCollectionProvider`) might not be registering or exposing the target child entity's class type to the Info Template dropdown resolution.

---

#### Item 5: Page Layout Import Requires Internal Database Primary Key for Attachment Fields
* **Type:** Bug
* **Tracking:** [LPD-110573](https://liferay.atlassian.net/browse/LPD-110573)
* **Summary:** Image fragment mappings to Object attachments require internal database primary keys instead of field names, preventing layout portability across environments.

##### Description
When exporting and importing site pages—or when defining pages via Site Initializers or the Headless Site API—mappings between page fragments (like an Image or Banner) and an Object's attachment field cannot be migrated between environments. For normal text fields (e.g., Title, Description), the page mapping accepts the friendly field name. However, for file and image attachments, the system only accepts the internal numeric database ID of the field. Because internal database IDs change across installations, any page imported into a fresh instance or staging environment fails to resolve the image mapping.

##### Impact
Prevents Infrastructure-as-Code practices and breaks automated site deployments (Dev > UAT > Prod), forcing teams to manually re-link every image fragment after deployment.

##### Steps to Reproduce
1. In Environment A, map an image fragment on a page to an Object entry's attachment field.
2. Export the page layout definition (or capture it in a Site Initializer).
3. Import the page layout into Environment B (where the same Object exists with the same field names, but different database primary keys).
* **Expected Result:** The page imports cleanly and resolves the attachment mapping using the field's natural name/key.
* **Actual Result:** The image mapping is broken or discarded because the database ID from Environment A does not match Environment B.

> **Clue for Engineering:**  
> In layout specifications, text fields map cleanly by name, but attachment fields appear to be serialized as `ObjectField_<database_id>#fileURL`. If this accepted semantic names (e.g., `ObjectField_<fieldName>#fileURL`), layouts would become fully portable.

---

### 3. Site Initializers & Developer Experience Team

#### Item 6: Display Page Templates Fail on Clean Site Initializer Deployments Due to Template Dependency Timing
* **Type:** Bug
* **Tracking:** [LPD-110574](https://liferay.atlassian.net/browse/LPD-110574)
* **Summary:** Display Page Templates referencing custom templates fail to import on fresh bundle installations, requiring a second run.
* **Status:** Under review. The handler dependency map does not support the root cause below; see the note at the end of this item.

##### Description
When provisioning a new site from a Site Initializer on a clean, empty Liferay bundle, Display Page Templates that use template replacement tokens fail to resolve their associated templates. This issue is non-deterministic: on a brand new database, the Display Page Template is created before the associated templates are ready in the system. If the exact same Site Initializer is triggered a second time on the already-running server, it succeeds because the templates already exist.

##### Impact
Completely blocks unattended CI/CD provisioning and automated Docker container spin-up for clean environments.

##### Steps to Reproduce
1. Configure a Site Initializer containing both custom templates (DDM Templates) and Display Page Templates that reference them via tokens.
2. Start a clean, empty Liferay instance.
3. Deploy the Site Initializer.
* **Expected Result:** Templates and Display Page Templates are imported in the correct sequence, and all token references resolve on the first deployment.
* **Actual Result:** Display Page Templates fail or import with missing template references.

> **Clue for Engineering:**  
> This looks like a topological dependency ordering gap in the bundle initializer: the routine creating layout page templates does not declare an explicit dependency on the routine importing DDM templates.

> **Review note (2026-10-19):** In `BundleSiteInitializer._createRMap`, `addLayoutPageTemplates` depends on
> `addOrUpdateJournalArticles`, which depends on `addOrUpdateDDMTemplates`. `TEMPLATE_ENTRY_ID` and
> `DDM_TEMPLATE_ID` are registered in `_addOrUpdateDDMTemplates`, so on `master` they are always registered
> before any display page template is read. Replacement tokens are also rebuilt from the tree on every run,
> so templates left by an earlier run do not explain a second run succeeding. Until a log from a failing run
> shows the order, treat this item as unconfirmed; the symptom may be the collection race in Item 7.

---

#### Item 7: Collections in Page Definitions Are Dropped Depending on Site Initializer Handler Order
* **Type:** Bug
* **Tracking:** [LPD-110315](https://liferay.atlassian.net/browse/LPD-110315)
* **Summary:** Collection Display fragments in page definitions are left with no collection on some site creations, depending on handler order.

##### Description
A collection display in a site initializer page definition that references a collection by token (e.g. `"classPK": "[$ASSET_LIST_ENTRY_ID:<Name>$]"`) is sometimes saved with no collection configured. Whether it works depends on the order the initializer's handlers happen to run in, and that order can change between two site creations from the same bundle. Nothing is logged and the initializer reports success.

##### Impact
Causes collections in `page-definition.json` to be dropped silently on any site creation where a page handler runs before `addAssetListEntries`, so two creations from the same bundle can differ.

##### Root Cause Summary
`ASSET_LIST_ENTRY_ID:<Name>` is registered in string replace values by `addAssetListEntries`. However, `addLayoutPageTemplates` (display page templates, master pages) and `addOrUpdateLayoutsContent` (content pages) do not declare a dependency on `addAssetListEntries`. Because handler execution order is non-deterministic, when page handlers run first, the token remains an unreplaced literal string, causing primary key parsing to fail and the collection configuration to be dropped.

> **Clue for Engineering:**  
> In `BundleSiteInitializer._createRMap()`, adding `addAssetListEntries` as an explicit dependency for layout and template handlers ensures the token is always resolved before page layouts are parsed.

---

#### Item 8: Support Object Validation Rules in Site Initializers
* **Type:** Feature Request
* **Tracking:** [discuss.liferay.com/t/1074](https://discuss.liferay.com/t/better-support-for-object-validation-rules-in-site-initializers/1074)
* **Summary:** Allow Object Validation Rules that reference relationship fields (such as composite uniqueness checks) to be defined in Site Initializer source files.

##### Description
Site Initializers let developers declare Object Definitions, fields, and relationships as source configuration. A validation rule on the object's own fields (a value range, a required format) can already be declared inline, in the `objectValidationRules` array of the object definition file: the initializer posts that file to `object-admin`, which creates the rules with the definition.

What cannot be declared is a rule that uses a **relationship field**, such as preventing duplicate enrollments (*a student cannot enroll in the same session twice*). The relationship, and the `r_<relationship>_c_<parent>Id` field it adds, is created by a later handler than the object definition, so the field does not exist when the definition's rules are created. These rules have to be added through the Control Panel or the API after every site creation, which defeats Infrastructure-as-Code for exactly the integrity rules that matter most.

##### Impact
Prevents data integrity rules from being defined as Infrastructure-as-Code in Site Initializers, forcing manual post-provisioning configuration.

##### Proposed Solution
* Introduce a standardized folder structure (e.g., `object-validation-rules/`) in Site Initializers, processed after relationships are created.
* Ensure validations can reference relationship fields to enforce composite business rules (e.g., *Student A cannot register for Session B more than once*).

##### Workaround in this repository
The workarounds module (`modules/masterclass-cms-workarounds`) adds the rule while the site is created: when the initializer publishes MyCourseEnrollment, after the relationships exist, it adds a `compositeKey` validation rule over `r_courseToUser_userId` and `r_enrollmentToCourseSession_c_myCourseSessionId`, so a student can't register for the same session twice. `scripts/student-check.sh` checks that a second registration is refused.

> **Clue for Engineering:**  
> Validations often depend on relationship fields. In the current import flow, relationships are created after definitions, so having a dedicated validation import stage that executes after relationships are established would prevent reference errors.
