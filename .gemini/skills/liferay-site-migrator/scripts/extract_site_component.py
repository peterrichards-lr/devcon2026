import asyncio
import sys
import os
import argparse
from playwright.async_api import async_playwright

async def extract_component(url, selector, output_dir):
    os.makedirs(output_dir, exist_ok=True)
    html_path = os.path.join(output_dir, 'index.html')
    css_path = os.path.join(output_dir, 'index.css')

    async with async_playwright() as p:
        browser = await p.webkit.launch(headless=True)
        page = await browser.new_page()
        
        print(f"Navigating to {url}...")
        await page.goto(url, wait_until="load")
        
        try:
            locator = page.locator(selector).first
            await locator.wait_for(timeout=10000)
        except Exception:
            print(f"Error: Selector '{selector}' not found.")
            await browser.close()
            return

        # Script to extract HTML and relevant CSS rules
        extraction_script = """
        (root) => {
            if (!root) return null;

            const html = root.outerHTML;
            let css = "";

            const isElementInComponent = (el) => root.contains(el) || el === root;

            try {
                for (const sheet of document.styleSheets) {
                    try {
                        for (const rule of sheet.cssRules) {
                            if (rule.type === CSSRule.STYLE_RULE) {
                                try {
                                    const matches = document.querySelectorAll(rule.selectorText);
                                    for (const match of matches) {
                                        if (isElementInComponent(match)) {
                                            css += rule.cssText + "\\n";
                                            break;
                                        }
                                    }
                                } catch (e) {}
                            }
                        }
                    } catch (e) {}
                }
            } catch (e) {}

            return { html, css };
        }
        """

        result = await locator.evaluate(extraction_script)
        
        if not result:
            print("Failed to extract data.")
            await browser.close()
            return

        with open(html_path, 'w', encoding='utf-8') as f:
            f.write(result['html'])
        
        with open(css_path, 'w', encoding='utf-8') as f:
            f.write(result['css'])

        print(f"Extraction complete. Files saved in {output_dir}")
        await browser.close()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Extract a component and its CSS from a URL.')
    parser.add_argument('url', help='The URL to scrape')
    parser.add_argument('selector', help='The CSS selector for the component')
    parser.add_argument('--out', default='extracted_component', help='Output directory')

    args = parser.parse_args()
    
    asyncio.run(extract_component(args.url, args.selector, args.out))
