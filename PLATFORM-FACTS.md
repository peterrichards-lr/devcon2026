# Platform Facts

Liferay platform behaviour this project found the hard way: facts an agent could not have
known from the documentation, as opposed to bugs in our own code. Each one says where it was
found and which agent file it belongs in. This is the basis of a pull request to the agent
files in `liferay-se/liferay-workspace-ai` (Victor Ware's), after DevCon.

"In `.agents`" says whether this repository's own copy of the agent files already states it.
The PR upstream needs all of them, since our copy has local additions.

Process lessons, and bugs that were ours, are in [LESSONS-LEARNT.md](LESSONS-LEARNT.md);
what was reported to Liferay is in [UPSTREAM-FEEDBACK.md](UPSTREAM-FEEDBACK.md).

| # | Fact | Evidence | Belongs in | In `.agents` |
| --- | --- | --- | --- | --- |
| 1 | CMS content structures need `enableObjectEntryDraft: true`, or deleting an entry in the CMS UI fails. Whether versioning is also needed is still to be confirmed | Rafa, before PR tracking; #87 | `manage-cms` | example only |
| 2 | The site initializer runs its handlers in an unstable order (a `HashMap` keyed on identity hashes), so `[$ASSET_LIST_ENTRY_ID$]` can be unresolved when pages import, and the collection is dropped silently while the initializer reports success. Measured: 3 of 12 creations on 2026-10-19 | `d5e353b`, #74, #90 | `site-initializer-format.md`, portability card | yes |
| 3 | The object entry editor matches form fields by name prefix: `image` beside `imageAuthor` breaks Publish | #31, #28, #29 | `manage-objects` | yes |
| 4 | Space scoped objects answer `409 Conflict with getObjectEntriesPage` on `/o/c/<plural>`; use `/scopes/{groupId}` | #31 | `headless-apis.md` | yes |
| 5 | A relationship can't cross a Space boundary | #31 | `manage-cms` | no |
| 6 | `headless-admin-user` `/sites/{id}` omits `externalReferenceCode`; resolve it with `headless-admin-site/sites?filter=id eq <id>` | `68c68b1`, #58 | `headless-apis.md` | yes |
| 7 | REST `DELETE` on web content and documents is a hard delete (no Recycle Bin), collections never use the Recycle Bin, and CMS entries in a Space are soft deleted with their ERC still reserved | `5edae1f`, #80 | `manage-cms`, `migrate-cms-to-objects` | no |
| 8 | Restoring a soft deleted CMS entry (`PUT …/by-external-reference-code/{erc}/restore`) frees its ERC; a new POST with it returns 400 until then | `12c42ad`, #66 | `manage-cms` | no |
| 9 | A navigation menu item's `type_` can't change on update; give it a new ERC to change its type | `7ce6829`, #73 | `manage-pages` | no |
| 10 | Menu items pointing at Space entries need `scopeExternalReferenceCode`, or the call returns 400 | #73 | `manage-pages` | no |
| 11 | Menu items whose display page went away are dropped from the render silently | #73 | `manage-pages`, `migrate-cms-to-objects` | no |
| 12 | `POST …/page-specifications/{erc}/publish` is a stub that returns 204 and does nothing. Publish a display page template with `PUT /display-page-templates/{erc}?nestedFields=pageSpecifications`, both specifications `Approved` | `e60f03a`, #79; path corrected in #82 | `manage-pages` | partly (site pages only) |
| 13 | `PUT /page-specifications/{erc}` accepts only `status: "Draft"` and `type: "ContentPageSpecification"` | #79, #68 | `manage-pages` | no |
| 14 | Mutating page specifications needs `LPD-74328`, or it returns `400 UnsupportedOperationException` | `198ec71`, #68 | `feature-flags-catalog.md` | yes |
| 15 | Content page drafts aren't addressable as `/page-specifications/<page>-draft`; use `PUT /site-pages/{erc}?nestedFields=pageSpecifications&privateLayout=false` | `0b49e3a`, #70 | `manage-pages` | no |
| 16 | Without `privateLayout=false`, that PUT returns 400 when private pages are disabled | #70 | `manage-pages` | no |
| 17 | GET responses carry read only fields (`creator`, `dateCreated`, `uuid`, `customFields` and others) that a PUT rejects; strip them first | #70 | `manage-pages` | no |
| 18 | A fragment instance with `html: ""` renders blank; Liferay doesn't fall back to the fragment definition | #70 | `manage-pages`, `scaffold-fragment` | no |
| 19 | Inside an object collection, the display page link key is `ObjectEntry_displayPageURL` | #70 | `manage-pages` | no |
| 20 | Attachment fields map only through subfields keyed by the field's numeric ID: `ObjectField_<id>#fileURL` | #68 | `manage-pages`, portability card | partly |
| 21 | A Space vocabulary must be created at company scope with `assetLibraries`; one created on the Space itself is accepted but hidden in the UI | `f53bf6e`, #67 | `manage-cms` | no |
| 22 | `fileSource: "CMSBasicDocument"` gives editors the library picker and upload; `userComputerToCMSBasicDocument` allows local upload only | `9b48075`, #65 | `manage-cms` | partly |
| 23 | `objectFieldSettings` on a published field can be PATCHed live | #65 | `manage-objects` | no |
| 24 | `enableObjectEntryHistory` is always false on create, whatever the body says | skill port | `manage-cms` | yes |
| 25 | Users created by a site initializer's `user-accounts.json` are set inactive on purpose: `BundleSiteInitializer._addUserAccounts` PATCHes each one to `INACTIVE` (LPS-184738), so they can't sign in until activated. The same JSON over the user API gives an active user | `000dba9c42` in liferay-portal, #88 | `site-initializer-format.md` | no |
| 26 | An object entry's owner gets every action on it, including the standalone object actions, so an owner can run an "approve" action on their own entry or PATCH a status field. Pending is no gate unless something else stops the owner | 2026-10-19, LESSONS-LEARNT | `manage-object-logic`, `manage-roles-permissions` | no |
| 27 | Setting a relationship field when creating an entry needs VIEW on the related entry: without it the POST returns 403, while the same POST without the relationship succeeds | 2026-10-19, #86 | `manage-roles-permissions`, `manage-objects` | no |
| 28 | Entries are visible to their owner without a VIEW grant, so an entry created by an admin, initializer or batch "for" a user is invisible to that user | 2026-10-19, #88 | `manage-roles-permissions` | no |
| 29 | A `compositeKey` object validation rule accepts Integer, Picklist, Relationship and Text fields, 2 to 5 of them (setting `compositeKeyObjectFieldId`), and is always active. A site initializer can't declare one over relationship fields, which it creates after the object definitions | portal source on master, and the workarounds module compiles against 2026.q3.5; #100 (to be tested); UPSTREAM-FEEDBACK item 8 | `manage-objects`, `site-initializer-format.md` | no |
| 30 | About 40 s after a restored instance starts, a reindex task renders data set display tags before the data set serializer is up, logging `NullPointerException: … "this.fdsSerializer" is null`. Harmless, but alarming; a candidate to report | 2026-10-19 logs | `deploy-and-verify` | no |
