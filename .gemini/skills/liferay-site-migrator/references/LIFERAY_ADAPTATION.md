# Liferay Adaptation Guide

Converting raw HTML/CSS into a functional Liferay Fragment involves scoping, mapping, and a "Clean Rewrite" strategy for high fidelity.

## 1. The "Clean Rewrite" Strategy (Recommended)
Don't rely on the source site's utility classes (like Tailwind or Bootstrap) as they likely won't exist in Liferay.
1. **Simplify HTML**: Use semantic, descriptive classes (e.g., `sura-card`, `sura-container`) instead of `w-full flex-col p-4`.
2. **Explicit CSS**: Write comprehensive, scoped CSS that defines every property (flex, padding, shadows, colors) explicitly.
3. **Isolation**: Wrap everything in a fragment-specific class (e.g., `.fragment-custom-section`) and scope all CSS rules under it.

## 2. CSS Scoping (Prefixing)
To prevent your styles from leaking into Liferay or vice-versa:
1. Wrap your fragment's `index.html` in a unique class: `<div class="fragment-custom-section">...</div>`.
2. Prefix all rules in `index.css` with that class: `.fragment-custom-section .my-element { ... }`.

## 3. Dynamic Content Mapping
Identify text, links, and images that should be editable.
- **Text**: Replace `<h2>My Title</h2>` with `<h2>${configuration.title}</h2>`.
- **Links**: Replace `<a href="/path">` with `<a href="${configuration.linkURL}">`.
- **Images**: Replace `<img src="...">` with `<img src="${configuration.imageURL}">`.

## 4. Fragment Configuration (`configuration.json`)
For every `${configuration.fieldName}` used in the HTML, add an entry in `configuration.json`.

> **CRITICAL**: Types such as `image`, `link`, and `rich-text` are **NOT VALID** for `configuration.json` and will cause import errors. 
> - Use `"type": "text"` for all URLs and simple text strings.
> - Use `"type": "select"` for dropdowns.

## 5. Relative Asset Paths
When mapping images and fonts, prioritize **relative paths** starting with `/documents/`.
- **Absolute**: `http://localhost:8080/documents/...` (Fragile, environment-specific)
- **Relative**: `/documents/38107/0/image.webp/...` (Robust, works across domains)

The `sync_assets.py` script defaults to relative paths. This ensures fragments remain portable across different Liferay environments.
