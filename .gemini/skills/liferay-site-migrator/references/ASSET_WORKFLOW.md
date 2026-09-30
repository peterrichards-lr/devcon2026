# Asset Workflow

This guide describes how to move images and fonts from a source site into Liferay's Documents and Media (DAM).

## 1. Automatic Sync
The `sync_assets.py` script automates the process of downloading images found in your extracted HTML/CSS and uploading them to Liferay.

```bash
python .gemini/skills/liferay-site-migrator/scripts/sync_assets.py \
  "./my-hero-fragment/index.html" \
  "./my-hero-fragment/index.css" \
  --site-id 12345 \
  --base-url "https://my-liferay-instance.com" \
  --user "test@liferay.com" \
  --password "test"
```

## 2. Manual Verification
After running the script, verify:
- Images are visible in the Liferay DAM under the specified site.
- The `index.html` and `index.css` now point to Liferay URLs (usually containing `/documents/`).

## 3. Fonts
Fonts are often hosted on CDNs (Google Fonts, Adobe Fonts).
- If the font is a standard CDN link, keep it in the `<head>` or `@import`.
- If the font is local to the source site, download the `.woff2` files, upload them to DAM, and update the `@font-face` rules in `index.css`.

## 4. MCP Integration (Recommended)
Since the Liferay MCP server is configured in `.gemini/settings.json`, you should prioritize using the `liferay` MCP tools for asset management.
- Use `liferay.upload_document` (or similar tool provided by the MCP server) to upload local files directly.
- This avoids the need for manual credentials in scripts and is more secure.
- After uploading via MCP, retrieve the `contentUrl` and update the fragment code.
