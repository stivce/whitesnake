#!/usr/bin/env python3
"""Updates appcast.xml with the latest release entry."""
import sys
import datetime

VERSION   = sys.argv[1]
ED_SIG    = sys.argv[2]
FILE_SIZE = sys.argv[3]

TAG  = f"v{VERSION}"
DATE = datetime.datetime.now(datetime.timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")
URL  = f"https://github.com/stivce/whitesnake/releases/download/{TAG}/Whitesnake-{VERSION}.dmg"

content = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
    xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
    xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>Whitesnake</title>
        <link>https://github.com/stivce/whitesnake</link>
        <item>
            <title>Whitesnake {VERSION}</title>
            <pubDate>{DATE}</pubDate>
            <sparkle:version>{VERSION}</sparkle:version>
            <sparkle:shortVersionString>{VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <enclosure
                url="{URL}"
                sparkle:edSignature="{ED_SIG}"
                length="{FILE_SIZE}"
                type="application/octet-stream"/>
        </item>
    </channel>
</rss>
"""

with open("appcast.xml", "w") as f:
    f.write(content)

print(f"appcast.xml updated for {VERSION}")
