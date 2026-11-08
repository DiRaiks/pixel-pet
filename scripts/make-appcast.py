"""Writes the Sparkle appcast for one release: a single item with the DMG and its EdDSA signature.

    python3 -I scripts/make-appcast.py --version 0.3.0 --url URL --length N --signature SIG --out appcast.xml

What's new isn't in it: the update card links to the release page on GitHub. scripts/appcast.sh signs the
file afterwards.
"""

import argparse
from xml.sax.saxutils import escape, quoteattr


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--url", required=True)
    parser.add_argument("--length", required=True, type=int)
    parser.add_argument("--signature", required=True)
    parser.add_argument("--min-system", default="26.0")
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    xml = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Pixel Pet</title>
    <item>
      <title>{escape(f"Pixel Pet {args.version}")}</title>
      <sparkle:version>{escape(args.version)}</sparkle:version>
      <sparkle:shortVersionString>{escape(args.version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{escape(args.min_system)}</sparkle:minimumSystemVersion>
      <enclosure url={quoteattr(args.url)} length="{args.length}" type="application/octet-stream" sparkle:edSignature={quoteattr(args.signature)}/>
    </item>
  </channel>
</rss>
"""
    with open(args.out, "w", encoding="utf-8") as f:
        f.write(xml)


if __name__ == "__main__":
    main()
