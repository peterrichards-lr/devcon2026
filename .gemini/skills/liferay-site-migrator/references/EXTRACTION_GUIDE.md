# Extraction Guide

This guide explains how to use the `liferay-site-migrator` scripts to extract high-fidelity components from any website.

## 1. Preparation & Locator Strategy
Don't just use standard CSS selectors. Modern sites often have dynamic class names or deeply nested structures.
- **Text-based Locator**: `xpath=//h2[contains(., 'My Section Title')]/ancestor::div[1]` is often more stable than `.css-12345`.
- **Closest Container**: If you find the text but it's inside a smaller box, move up the tree until you find the element with the padding/background you want.

## 2. Wait Strategies
- **`wait_until='load'`**: Default to this. It waits for the basic page and images.
- **`wait_until='networkidle'`**: Only use this for highly dynamic SPAs where content loads long after the 'load' event. Beware of timeouts from persistent analytics connections.

## 3. Running the Extraction
```bash
python .gemini/skills/liferay-site-migrator/scripts/extract_site_component.py \
  "https://example.com" \
  "xpath=//section[contains(., 'Hero')]" \
  --out ./extracted-fragment
```

## 4. Troubleshooting
- **Selector not found**: The site might be lazy-loading content. Try scrolling to the bottom of the page in the extraction script if needed.
- **Styles missing**: Some styles (like fonts or global variables) might not be captured if they are defined on the `<html>` or `<body>` tags. You may need to manually copy these into your fragment's CSS.
