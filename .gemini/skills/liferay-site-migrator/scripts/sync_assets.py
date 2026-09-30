import os
import re
import requests
import argparse
from urllib.parse import urljoin, urlparse

def sync_assets(html_path, css_path, site_id, base_url, auth, relative=True):
    with open(html_path, 'r', encoding='utf-8') as f:
        html = f.read()
    with open(css_path, 'r', encoding='utf-8') as f:
        css = f.read()

    # Find images in HTML (img src, source srcset)
    img_urls = re.findall(r'src=["\'](https?://[^"\']+)["\']', html)
    img_urls += re.findall(r'srcset=["\'](https?://[^"\']+)["\']', html)
    # Find images in CSS (url(...))
    img_urls += re.findall(r'url\(["\']?(https?://[^"\')]+)["\']?\)', css)

    # De-duplicate
    img_urls = list(set(img_urls))
    
    mapping = {}

    for url in img_urls:
        print(f"Syncing {url}...")
        try:
            # Download
            response = requests.get(url)
            if response.status_code != 200:
                print(f"Failed to download {url}")
                continue
            
            filename = os.path.basename(urlparse(url).path)
            if not filename:
                filename = "image.png"

            # Upload to Liferay
            upload_url = f"{base_url}/o/headless-delivery/v1.0/sites/{site_id}/documents"
            
            files = {
                'file': (filename, response.content),
            }
            data = {
                'document': '{"title": "' + filename + '"}'
            }
            
            res = requests.post(upload_url, auth=auth, files=files, data=data)
            
            if res.status_code in [200, 201]:
                liferay_url = res.json().get('contentUrl')
                
                # If absolute URL is requested and we have a relative one, prepend base_url
                if not relative and liferay_url.startswith('/'):
                    liferay_url = base_url + liferay_url
                # If relative URL is requested and we have an absolute one, strip base_url
                elif relative and liferay_url.startswith('http'):
                    parsed_base = urlparse(base_url)
                    parsed_liferay = urlparse(liferay_url)
                    if parsed_base.netloc == parsed_liferay.netloc:
                        liferay_url = parsed_liferay.path + ("?" + parsed_liferay.query if parsed_liferay.query else "")

                mapping[url] = liferay_url
                print(f"Uploaded to {liferay_url}")
            else:
                print(f"Failed to upload {url}: {res.status_code} {res.text}")
        except Exception as e:
            print(f"Error syncing {url}: {e}")

    # Replace URLs in files
    for old_url, new_url in mapping.items():
        html = html.replace(old_url, new_url)
        css = css.replace(old_url, new_url)

    with open(html_path, 'w', encoding='utf-8') as f:
        f.write(html)
    with open(css_path, 'w', encoding='utf-8') as f:
        f.write(css)

    print("Asset sync complete.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Sync assets from a component to Liferay DAM.')
    parser.add_argument('html', help='HTML file path')
    parser.add_argument('css', help='CSS file path')
    parser.add_argument('--site-id', required=True, help='Liferay Site ID')
    parser.add_argument('--base-url', required=True, help='Liferay Base URL (e.g. http://localhost:8080)')
    parser.add_argument('--user', required=True, help='Liferay Username')
    parser.add_argument('--password', required=True, help='Liferay Password')
    parser.add_argument('--absolute', action='store_true', help='Use absolute URLs instead of relative')

    args = parser.parse_args()
    
    auth = (args.user, args.password)
    sync_assets(args.html, args.css, args.site_id, args.base_url, auth, relative=not args.absolute)
