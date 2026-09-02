#!/usr/bin/env python3
"""png-uniform.py — is a screenshot a single flat colour?

One of the four launch-health signals of the Phase 6 dynamic tier (D1): a black or
white full-frame screenshot is a hung splash or a dead process, whatever the process
table says. Pure standard library (zlib + struct): no Pillow, no ImageMagick, so it
runs on a stock macOS python3 and on the ubuntu CI runner alike.

Handles the PNGs `xcrun simctl io <udid> screenshot` writes: 8-bit RGB / RGBA,
non-interlaced. Anything else exits 2 ("could not be read"): the caller records the
signal as unreadable, never as healthy.

Usage: png-uniform.py <file.png>
  stdout: "uniform" | "varied <sampled-distinct-colours>"
  exit:   0 decoded, 2 unreadable / unsupported
"""
import struct
import sys
import zlib

SIG = b"\x89PNG\r\n\x1a\n"
# Sample every Nth pixel on every Nth row: enough to see a spinner or a text line,
# cheap on a 1179x2556 frame.
STRIDE = 8
# "Uniform" tolerates a status bar: the dominant colour must cover >= 99% of samples.
DOMINANT = 0.99


def chunks(data):
    pos = len(SIG)
    while pos + 8 <= len(data):
        length, typ = struct.unpack(">I4s", data[pos:pos + 8])
        yield typ, data[pos + 8:pos + 8 + length]
        pos += 12 + length


def unfilter(raw, width, height, bpp):
    stride = width * bpp
    out = bytearray()
    prev = bytearray(stride)
    pos = 0
    for _ in range(height):
        ftype = raw[pos]
        line = bytearray(raw[pos + 1:pos + 1 + stride])
        pos += 1 + stride
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if ftype == 1:
                line[i] = (line[i] + a) & 0xFF
            elif ftype == 2:
                line[i] = (line[i] + b) & 0xFF
            elif ftype == 3:
                line[i] = (line[i] + ((a + b) >> 1)) & 0xFF
            elif ftype == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 0xFF
            elif ftype != 0:
                raise ValueError("unknown filter %d" % ftype)
        out += line
        prev = line
    return bytes(out), stride


def main(path):
    with open(path, "rb") as fh:
        data = fh.read()
    if not data.startswith(SIG):
        return 2
    width = height = None
    idat = b""
    for typ, body in chunks(data):
        if typ == b"IHDR":
            width, height, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", body)
            if depth != 8 or ctype not in (2, 6) or interlace != 0:
                return 2
            bpp = 3 if ctype == 2 else 4
        elif typ == b"IDAT":
            idat += body
        elif typ == b"IEND":
            break
    if width is None or not idat:
        return 2
    try:
        pixels, stride = unfilter(zlib.decompress(idat), width, height, bpp)
    except (zlib.error, ValueError, IndexError):
        return 2
    counts = {}
    total = 0
    for y in range(0, height, STRIDE):
        row = y * stride
        for x in range(0, width, STRIDE):
            px = pixels[row + x * bpp:row + x * bpp + 3]
            counts[px] = counts.get(px, 0) + 1
            total += 1
    if total == 0:
        return 2
    top = max(counts.values())
    if top / float(total) >= DOMINANT:
        print("uniform")
    else:
        print("varied %d" % len(counts))
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(2)
    try:
        sys.exit(main(sys.argv[1]))
    except (OSError, struct.error):
        sys.exit(2)
