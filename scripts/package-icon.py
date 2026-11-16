#!/usr/bin/env python3
"""Fallback ICNS container writer for hosts where Apple's ICNS encoder fails.

Uses lossless PNG representations already made by sips; no image dependencies.
Element identifiers come from the CLT SDK's OSServices/IconStorage.h.
"""
from pathlib import Path
import struct
import sys

iconset, output = map(Path, sys.argv[1:])
elements = []
for kind, size, name in [
    (b"ic07", 128, "icon_128x128.png"),
    (b"ic08", 256, "icon_256x256.png"),
    (b"ic09", 512, "icon_512x512.png"),
    (b"ic10", 1024, "icon_512x512@2x.png"),
]:
    data = (iconset / name).read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or struct.unpack(">II", data[16:24]) != (size, size):
        raise SystemExit(f"Invalid PNG representation: {name}")
    elements.append(kind + struct.pack(">I", len(data) + 8) + data)
body = b"".join(elements)
output.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)
print(f"Packaged four PNG representations: {output}")
