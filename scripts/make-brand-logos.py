#!/usr/bin/env python3
"""Builds Prosper/DesignSystem/BrandLogos.xcassets from Simple Icons SVGs (UX-28).

    python3 scripts/make-brand-logos.py <folder of simple-icons .svg files>

Simple Icons (https://simpleicons.org) publishes each brand mark as one SVG
path under CC0. The marks themselves are trademarks of their owners; the app
shows them only to identify the app or site a person is locking or labelling.

Only the path data is taken from each file, and only if it is nothing but path
commands and numbers. The SVG written into the asset catalog is ours.
"""
import json
import os
import re
import sys

# Catalog platform id -> Simple Icons file name.
LOGOS = {
    "facebook": "facebook", "instagram": "instagram", "youtube": "youtube",
    "tiktok": "tiktok", "x": "x", "reddit": "reddit", "snapchat": "snapchat",
    "whatsapp": "whatsapp", "netflix": "netflix", "twitch": "twitch",
    "pinterest": "pinterest", "linkedin": "linkedin", "zoom": "zoom",
    "slack": "slack", "teams": "microsoftteams", "gmail": "gmail",
}
EXPECTED = re.compile(
    r'^<svg role="img" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">'
    r'<title>[^<>]*</title><path d="([MmLlHhVvCcSsQqTtAaZz0-9eE\s,.\-+]+)"/></svg>\s*$'
)
OUT = os.path.join(os.path.dirname(__file__), "..", "Prosper", "DesignSystem", "BrandLogos.xcassets")


def main(source):
    os.makedirs(OUT, exist_ok=True)
    info = {"author": "xcode", "version": 1}
    with open(os.path.join(OUT, "Contents.json"), "w") as f:
        json.dump({"info": info}, f, indent=2)
    for platform, name in sorted(LOGOS.items()):
        with open(os.path.join(source, name + ".svg")) as f:
            match = EXPECTED.match(f.read())
        if not match:
            sys.exit(f"{name}.svg is not a single-path Simple Icons file")
        folder = os.path.join(OUT, f"brand-{platform}.imageset")
        os.makedirs(folder, exist_ok=True)
        with open(os.path.join(folder, f"brand-{platform}.svg"), "w") as f:
            f.write('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">'
                    f'<path d="{match.group(1)}"/></svg>\n')
        with open(os.path.join(folder, "Contents.json"), "w") as f:
            json.dump({
                "images": [{"filename": f"brand-{platform}.svg", "idiom": "universal"}],
                "info": info,
                "properties": {
                    "preserves-vector-representation": True,
                    "template-rendering-intent": "template",
                },
            }, f, indent=2)
        print("wrote", f"brand-{platform}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
