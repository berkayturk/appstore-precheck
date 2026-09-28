#!/usr/bin/env python3
"""Path containment helper for the runtime tier (Python 3.8+ stdlib).

  dyn-paths.py inside <path> <root>
      exit 0  <path> is <root> or lives under it
      exit 1  <path> is outside <root>
      exit 2  usage error

Both paths may not exist yet. Symlinks are resolved for every component that
exists (os.path.realpath), the rest is appended lexically, so an --out that does
not exist yet still resolves through a symlinked parent. Each existing ancestor
is also compared with os.path.samefile, which is correct on the case-insensitive
default macOS volume where the spelling of two paths can differ.
"""
import os
import sys


def inside(path, root):
    """True when path == root or path is beneath root, after symlink resolution."""
    real_path = os.path.realpath(os.path.expanduser(path))
    real_root = os.path.realpath(os.path.expanduser(root))
    if real_path == real_root or real_path.startswith(real_root.rstrip(os.sep) + os.sep):
        return True
    probe = real_path
    while True:
        try:
            if os.path.exists(probe) and os.path.samefile(probe, real_root):
                return True
        except OSError:
            pass
        parent = os.path.dirname(probe)
        if parent == probe:
            return False
        probe = parent


def main(argv):
    if len(argv) != 4 or argv[1] != "inside":
        sys.stderr.write("usage: dyn-paths.py inside <path> <root>\n")
        return 2
    return 0 if inside(argv[2], argv[3]) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
