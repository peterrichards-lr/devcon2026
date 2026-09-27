---
name: liferay-site-migrator
description: "Copies, clones, or migrates existing website designs into Liferay Fragments. Extracts HTML/CSS, handles images/fonts via DAM, and generates Liferay-ready fragments with FreeMarker mapping. Use when a user says 'copy this site', 'clone this section', or 'migrate this design'."
---

# Liferay Site Migrator

This skill provides the procedural knowledge to clone existing website components into Liferay fragments with high visual fidelity.

## Core Workflows

### 1. Robust Extraction
- **Locate**: Use Playwright's advanced locators (text-based, XPath) to find the "deepest" unique container for a component.
- **Extract**: Capture the exact HTML and the CSS rules applying to its children.
- **Wait Strategy**: Use `wait_until='load'` for sites with heavy analytics/background noise that break `networkidle`.

### 2. Asset & Style Scoping
- **Prefixing**: ALWAYS scope extracted CSS under a fragment-specific class (e.g., `.fragment-sura-cards`) to prevent style leaks.
- **Relinking**: Move images to Liferay DAM and update paths.
- **Cleanup**: Remove global resets (`* { ... }`) that might conflict with the Liferay theme.

### 3. Liferay Adaptation
- **Mapping**: Identify static content and convert to `${configuration.fieldName}`.
- **JSON Config**: Generate the `configuration.json` schema to match the mapped fields.
- **Internationalization**: Use Liferay's i18n patterns for buttons and labels.

### 4. Data & Logic Migration
- **Schema Mapping**: Use defined `Migration` patterns for MongoDB/DB logic when moving complex system data.
- **Relational Integrity**: Prioritize `externalReferenceCode` (ERC) preservation for KB and Object migrations.
- **Component UI**: Utilize established React patterns (Tables, Attachments) for displaying migrated data in workspaces.

## Procedural Guidance

### When to use which locator?
1. **CSS Selector**: Best for clean, well-structured IDs/Classes.
2. **XPath**: Best for deeply nested elements where you need to move "up" (e.g., `//h2[text()="..."]/ancestor::div[1]`).
3. **Text Search**: Use `page.get_by_text()` when the target has unique content but non-unique classes.

## Bundled Resources

- **[EXTRACTION_GUIDE.md](references/EXTRACTION_GUIDE.md)**: Troubleshooting selectors and timeouts.
- **[LIFERAY_ADAPTATION.md](references/LIFERAY_ADAPTATION.md)**: Converting raw HTML to FreeMarker fragments.
- **[ASSET_WORKFLOW.md](references/ASSET_WORKFLOW.md)**: Syncing images/fonts to DAM.
- **[LIFERAY_MIGRATION_PATTERNS.md](references/LIFERAY_MIGRATION_PATTERNS.md)**: Database, content, and workspace migration code patterns.
- **`scripts/extract_site_component.py`**: The primary extraction engine.
- **`scripts/sync_assets.py`**: Asset migration script.
