#!/usr/bin/env python3
# make-png.py — generate a minimal valid solid-color PNG of exact WxH.
# Used ONCE to produce committed test fixtures; not part of the scanner or test runtime.
import sys, zlib, struct

def make_png(w, h, path):
    def chunk(typ, data):
        body = typ + data
        return struct.pack('>I', len(data)) + body + struct.pack('>I', zlib.crc32(body) & 0xffffffff)
    sig = b'\x89PNG\r\n\x1a\n'
    ihdr = struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)  # 8-bit, colour type 2 (RGB)
    row = b'\x00' + b'\x00\x00\x00' * w                  # filter byte 0 + black pixels
    idat = zlib.compress(row * h, 9)
    with open(path, 'wb') as f:
        f.write(sig + chunk(b'IHDR', ihdr) + chunk(b'IDAT', idat) + chunk(b'IEND', b''))

if __name__ == '__main__':
    make_png(int(sys.argv[1]), int(sys.argv[2]), sys.argv[3])
