---

description: Build a Liferay Form Container — the native page element that creates or edits an Object entry from a Content Page or a Display Page Template — over the live page API or the site initializer tree. Covers field fragment keys, the submit button, multistep forms, success redirects, hidden context fields, edit forms on a DPT, and the permission that makes a form render at all. Use when the user asks for a form that saves to an object, a lead or contact form, an edit form on a display page, or a form that renders nothing.
name: manage-form-containers

---

# Manage Form Containers

A **Form Container** binds a form to a published object. Its children are field fragments (`INPUTS-*`) and a submit button, and submission creates the entry, or updates it on an edit form. Submissions post to the classic `/c/portal/edit_info_item` controller, not to `/o/c/...`, so no custom fragment or client extension is needed for the common case.

Everything below was verified live on 2026.q3.2 (2026-09-29), mostly against shapes the Page Editor itself produced.

## When to Invoke

- "Add a form that saves to <object>", "a contact / lead / registration form"
- "An edit form on the display page", "a two-step form", "redirect after submit"
- A form that renders nothing, or submits and stores empty values

`manage-pages` owns the page and the whole-page write; `manage-roles-permissions` owns the grants; `scaffold-form-fragment` owns custom input fragments.

## First: Grant `ADD_OBJECT_ENTRY`, or the Form Does Not Exist

**A viewer without `ADD_OBJECT_ENTRY` on the bound object gets no form at all.** Nothing renders: no `<form>`, no fields, not even the element's layout wrapper. There is no error and no log line, so it reads exactly like a broken import. Grant it on `com.liferay.object#<definitionId>` at company scope (`scope` `"1"`), **without** `VIEW` for a public form (`rules/guest-access.md` → "Public Forms Are Write Only"). Then test as the real audience — an admin session always sees the form.

## The Element, Over the Live API

Place it with the whole-page PUT (`manage-pages` → "Page Specification Workflow"). This is what the Page Editor produces:

```json
{
	"pageElementDefinition": {
		"formContainerConfig": {
			"formContainerReference": {
				"className": "com.liferay.object.model.ObjectDefinition#<code>",
				"type": "FormContainerClassSubtypeReference"
			},
			"formContainerType": "Simple",
			"numberOfSteps": 0,
			"successFormContainerSubmissionResult": {"type": "EmbeddedMessage", "message": {"value_i18n": {"en-US": "Thank you."}}}
		},
		"type": "FormContainer"
	},
	"pageElements": [ /* FormFragment children, then the submit button */ ]
}
```

- **`className` is the definition's suffixed class name.** Read it from `GET /o/object-admin/v1.0/object-definitions/by-external-reference-code/<erc>` (`className`); never strip the `#<code>`.
- **`numberOfSteps` must be present**, or the PUT returns `500` (NPE on `getNumberOfSteps()`). `0` and `1` both work for one step, whether `formContainerType` is `Simple` or `Multistep`.

### Fields

Each field is a `FormFragment`:

```json
{
	"pageElementDefinition": {
		"fieldKey": "ObjectField_<fieldName>",
		"fragmentInstance": {
			"fragmentConfigurationFieldValues": {},
			"fragmentEditableElements": [],
			"fragmentReference": {
				"defaultFragmentKey": "INPUTS-text-input",
				"fragmentReferenceType": "DefaultFragmentReference"
			}
		},
		"type": "FormFragment"
	},
	"pageElements": []
}
```

- **`fieldKey` binds the input to the object field.** The platform writes `ObjectField_<name>`, and a bare `<name>` binds too. The system ERC field is `ObjectEntry_externalReferenceCode`. **A field without `fieldKey` still submits and shows the success message, but stores an empty value.**
- **Keys produced by the Page Editor, per field type:**

| Object field type | `defaultFragmentKey` | Generated `fragmentConfigurationFieldValues` |
| --- | --- | --- |
| Text | `INPUTS-text-input` | `showCharactersCount: {"type": "Checkbox", "value": false}` |
| LongText | `INPUTS-textarea` | `numberOfLines`, `showCharactersCount` (both optional) |
| RichText | `INPUTS-rich-text-input` | none |
| Integer, Decimal, PrecisionDecimal | `INPUTS-numeric-input` (not `INPUTS-numeric-upload`) | none |
| Date | `INPUTS-date-input` | none |
| DateTime | `INPUTS-date-time-input` (renders `datetime-local`) | none |
| Picklist | `INPUTS-select-from-list` | none |
| Relationship (child side, `fieldKey` `ObjectField_r_<rel>_c_<parent>Id`) | `INPUTS-select-from-list` | none |
| Boolean | `INPUTS-checkbox` | none |
| Attachment | `INPUTS-file-upload` | `showSupportedFileInfo: {"type": "Checkbox", "value": true}` |

Generating the form in the Page Editor also adds an `INPUTS-text-input` bound to `ObjectEntry_externalReferenceCode`; drop it unless visitors should set the ERC. A full submission of every type round-tripped correctly, the file included. Picklists and relationships render an autocomplete text box plus two hidden inputs, `ObjectField_<field>` (the key or related id) and `ObjectField_<field>-label`. A rich text field is a hidden `ObjectField_<field>` fed by CKEditor, so do not read or set it as a plain `<input>`.

### The Submit Button

```json
{
	"pageElementDefinition": {
		"fragmentInstance": {
			"fragmentConfigurationFieldValues": {
				"buttonSize": {"type": "Select", "value": "nm"},
				"buttonType": {"type": "Select", "value": "primary"},
				"submittedEntryStatus": {"type": "Select", "value": "0"},
				"type": {"type": "Select", "value": "submit"}
			},
			"fragmentEditableElements": [],
			"fragmentReference": {
				"defaultFragmentKey": "INPUTS-submit-button",
				"fragmentReferenceType": "DefaultFragmentReference"
			}
		},
		"type": "FormFragment"
	},
	"pageElements": []
}
```

- **No `fieldKey`.**
- **`submittedEntryStatus`:** `"0"` stores approved entries, `"2"` stores drafts. `"2"` **requires `enableObjectEntryDraft: true` on the object**. Without it, every submission shows "An error occurred while sending the form information.", stores nothing, and logs nothing.
- **`type`:** `submit`, `next`, or `previous`.

### Laying Out Fields — Rows, Columns, Spacers

Do not stack every field full width. A `FormContainer`'s children may mix `FormFragment` fields with a `Grid` of `Module` columns and plain `BasicFragment` elements (headings, spacers), at any depth, and a `Module` may hold several fields. Field discovery (`data-field-name="ObjectField_<field>"`) and submission are unaffected, so scripts reading the form keep working. Verified on 2026.q3.2 (2026-10-02): a Page-Editor-built form read back over the API, and the tree shape below imported and rendered anonymously.

A row, inside the `FormContainer`'s `pageElements` (give every element its `externalReferenceCode`, `parentExternalReferenceCode`, and `position`, as for any page element):

```json
{
	"pageElementDefinition": {
		"gridViewports": [
			{"gridViewportDefinition": {"modulesPerRow": 2}, "id": "Desktop"},
			{"gridViewportDefinition": {"modulesPerRow": 1}, "id": "LandscapeMobile"},
			{"gridViewportDefinition": {}, "id": "PortraitMobile"},
			{"gridViewportDefinition": {}, "id": "Tablet"}
		],
		"gutters": true,
		"numberOfModules": 2,
		"reverseOrder": false,
		"type": "Grid"
	},
	"pageElements": [
		{
			"pageElementDefinition": {
				"moduleViewports": [
					{"id": "Desktop", "moduleViewportDefinition": {"size": 6}},
					{"id": "LandscapeMobile", "moduleViewportDefinition": {"size": 12}}
				],
				"type": "Module"
			},
			"pageElements": []
		}
	]
}
```

A spacer, anywhere a field can go — `height` takes `py-1`, `py-2`, or `py-3`:

```json
{
	"pageElementDefinition": {
		"fragmentInstance": {
			"fragmentConfigurationFieldValues": {"height": {"type": "Select", "value": "py-2"}},
			"fragmentReference": {
				"defaultFragmentKey": "BASIC_COMPONENT-spacer",
				"fragmentReferenceType": "DefaultFragmentReference"
			}
		},
		"type": "BasicFragment"
	}
}
```

Layout rules, native elements only and no custom CSS:

- **Sections:** group fields by meaning (what happened, who, how much, attachments) under an `h3` heading each.
- **Side by side:** short fields — picklists, booleans, phone and email, city and postal code, numbers, file uploads — in rows of 2 to 4 columns summing to 12 (`6+6`, `4+4+4`, `3+3+3+3`). Pair fields read together.
- **Full width:** long-text and rich-text fields, a free-text title or summary, a street address, and a field that opens a section on its own.
- **Stacked in one column:** a field and the one depending on it (a checkbox and its follow-up), separated by a `py-1` spacer.
- **Mobile:** every column `12` and every row one module per row on landscape and portrait mobile.
- **Spacing:** `py-3` before each section heading, before the submit button, and before the form when it follows other content; `py-2` after each heading and between rows of a section; `py-1` between two fields stacked in one column. Never two spacers in a row.

### Multistep Forms

`formContainerType: "Multistep"` with `numberOfSteps: <N>`. The first child is an `INPUTS-stepper` fragment (`fragmentConfigurationFieldValues.numberOfSteps: {"type": "Text", "value": "<N>"}`), then a `FormStepContainer` holding one `FormStep` per step. Each `FormStep` holds a `Container` with that step's fields and its `INPUTS-submit-button`s typed `next`, `previous`, and on the last step `submit`. A two-step submission stored all values.

### After Submission — `successFormContainerSubmissionResult`

| `type` | Extra keys | Effect |
| --- | --- | --- |
| `EmbeddedMessage` | `message.value_i18n` | Stays on the page and shows the message. The default the platform reads back when none is set |
| `StayInPage` | — | Reloads the page with an empty form and **no message** |
| `Url` | `url.value_i18n` | Redirects. **A URL outside the portal's allowed redirect domains stores the entry, then fails with a hidden `500`** (`WARN [PortalImpl] Redirect URL … is not allowed`); the visitor sees the page reload with no feedback. Same-domain URLs work |
| `SitePage` | `itemExternalReference: {"className": "com.liferay.portal.kernel.model.Layout", "externalReferenceCode": "<page-erc>"}` | Redirects to that page |
| `DisplayPage` | `itemExternalReference: {"className": "com.liferay.layout.page.template.model.LayoutPageTemplateEntry", "externalReferenceCode": "<dpt-erc>"}` | Redirects to that DPT, showing the entry just created (`/web/<site>/e/<dpt-url>/<classNameId>/<entryId>`) |

## The Element, in the Site Initializer Tree

The tree uses a different vocabulary: a `Form` element with `formConfig.formReference`, not `FormContainer`. See `manage-pages` → "Links, Forms, and Menus in the Tree". Its field children are `INPUTS-*` fragments with `fragmentConfig.inputFieldId: "ObjectField_<field>"`. For a form bound to another object than the DPT's, use `formReference.className` with the suffixed class name; an `ObjectEntry` plus `classType` renders an empty drop zone.

Rows and spacers in the tree are `Row` → `Column` → `Fragment`, inside the `Form` element:

```json
{
	"definition": {
		"gutters": true,
		"indexed": true,
		"modulesPerRow": 3,
		"numberOfColumns": 3,
		"reverseOrder": false,
		"rowViewports": [
			{"id": "landscapeMobile", "rowViewportDefinition": {"modulesPerRow": 1}},
			{"id": "portraitMobile", "rowViewportDefinition": {"modulesPerRow": 1}}
		],
		"verticalAlignment": "top"
	},
	"pageElements": [
		{
			"definition": {
				"columnViewports": [
					{"columnViewportDefinition": {"size": 12}, "id": "landscapeMobile"},
					{"columnViewportDefinition": {"size": 12}, "id": "portraitMobile"}
				],
				"size": 4
			},
			"pageElements": [
				{"definition": {"fragment": {"key": "INPUTS-select-from-list"}, "fragmentConfig": {"inputFieldId": "ObjectField_<field>"}}, "type": "Fragment"}
			],
			"type": "Column"
		}
	],
	"type": "Row"
}
```

- The importer reads `rowViewports[].rowViewportDefinition` and `columnViewports[].columnViewportDefinition` with **lowerCamel** viewport ids (`landscapeMobile`, `portraitMobile`, `tablet`); the flat `modulesPerRow` and `size` are the Desktop values (`RowLayoutStructureItemImporter`, `ColumnLayoutStructureItemImporter`, 2026.q3.2 bytecode).
- A spacer is `{"definition": {"fragment": {"key": "BASIC_COMPONENT-spacer"}, "fragmentConfig": {"height": "py-2"}}, "type": "Fragment"}`.
- Read back over the live API, `Row` becomes `Grid` and `Column` becomes `Module`, and **the `Form` reads back as `formContainerType: "Multistep"` with `numberOfSteps: 0`** even when the tree says nothing about steps. It still renders and submits as one step — not a manual change when comparing a live page with its tree.

## Custom Input Fragments as Fields

A custom `"type": "input"` fragment (`scaffold-form-fragment`) placed through the live API is a `FormFragment` with `"fragmentReferenceType": "FragmentItemExternalReference"` and the fragment's ERC. **Send its real `html`, `css`, and `js` on `fragmentInstance`.** With an empty `html`, the field wrapper renders but its content is empty, and the field submits nothing — no error anywhere. Only `DefaultFragmentReference` (the built-in `INPUTS-*`) is backfilled from an empty `html`. To change such a field's code later, re-add it under a **new** element ERC (`manage-pages`).

## On a Display Page Template

### Hidden Field From the Displayed Entry

A form for object B placed on object A's DPT can carry A's id in a relationship field, through a custom hidden input fragment:

```html
[#assign infoItem = (request.getAttribute("INFO_ITEM"))! /]
<input
	name="${input.name}"
	type="hidden"
	[#if infoItem?? && infoItem.objectEntryId??]
		value="${infoItem.objectEntryId}"
	[/#if] />
```

Submitting from entry A's display page stored a B entry whose FK is A's id, and the same held for entry B.

**`INFO_ITEM` also exposes the entry's custom fields, through `getValues()`:**

| Expression | Result |
| --- | --- |
| `infoItem.objectEntryId`, `.externalReferenceCode`, `.status` | Direct values |
| `infoItem.getValues()["<fieldName>"]` | The field's value (e.g. `10.5`) |
| `infoItem.price`, `.getInfoFieldValue("price")`, `.getMap(locale)` | "evaluated to null or missing" |
| `infoItem.createDate?string` | Error — dates need `?datetime` |

So a form, or any fragment on a DPT, can pre-fill or display another object's values without a client-side fetch.

### Edit Forms

**A Form Container bound to the same object as its DPT is an edit form.** Binding by `formReference.className` or by `contextSource: "DisplayPageItem"` gives the same result: the fields are pre-filled from the displayed entry, and submission updates it without creating an entry.

## Reacting to Success in the Browser

There is no submission event to hook. Liferay swaps the form's markup for the success message, and anything inside the Form Container is replaced with it. So put the watcher on the **wrapping** fragment, and look for the success text in `document.body.innerText`, never in `textContent`, which includes the fragment's own inline `<script>` and matches itself on load (verified 2026.q3.2):

```javascript
(function () {
	var MARKER = 'Your information was successfully received';
	var fired = false;

	function check() {
		if (fired || document.body.innerText.indexOf(MARKER) === -1) {
			return;
		}

		fired = true;

		// track, reveal content, or redirect here
	}

	check();

	new MutationObserver(check).observe(document.body, {childList: true, subtree: true});
})();
```

Use a native `successFormContainerSubmissionResult` whenever one fits. An Analytics Cloud `Analytics.track()` call followed by an immediate redirect is not lost: the SDK queues events in `localStorage` and flushes them on the next page (verified 2026.q3.2).

## Account-Restricted Objects

**A Form Container does not bypass `accountEntryRestricted`.** A Guest submission that sets the account relationship to an account the visitor does not belong to fails ("An error occurred while sending the form information."), stores nothing, and logs nothing, exactly as the REST `POST` returns `403`. For a signed-in user with `ADD_OBJECT_ENTRY` on the User role, the form did not render on a restricted object at all, and the cause was not established.

## Page Editor Pitfalls

- **Duplicating a Form Container in the Page Editor drops every field's `fieldKey`.** The copy keeps the object binding and the success settings, and its fields then store empty values. Re-map each field on the copy.
- **LongText can end up as a plain text input.** One LongText field sat on an `INPUTS-text-input` in a multistep form; it is unclear whether that was a manual choice. Check the generated keys before copying a form's JSON.

## Not Verified

- `COMMERCE_CONTEXT` in a hidden field (no Commerce channel was available).
- Master-detail patterns (a Data Set row loading an entry into a form).
- The signed-in case on an account-restricted object.

## Success Signal

- The form renders for the real audience: an unauthenticated browser for a public form.
- A real submission stores every field with the right value, read back over REST as admin.
- The chosen success behavior happens.
- The audience still cannot read other entries if the form is public.