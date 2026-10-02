"""Symlink-refusing, atomic text writes for report outputs (stdlib only, Python 3.8).

Report paths are chosen by the caller but often live in a directory another user or a
scanned project can influence. A plain ``Path.write_text`` follows a planted symlink
and overwrites whatever it points at. ``write_text`` here refuses any existing target
that is not a regular file (symlinks, dangling symlinks, directories, devices) and
otherwise writes a private temporary file in the same directory and renames it into
place, so a concurrent reader never sees a partial report and, even if a link is
planted between the check and the rename, ``os.replace`` swaps the link itself
instead of writing through it.
"""
import os
import stat
import tempfile


class UnsafeWriteError(OSError):
    """The output path is not a plain file that may be replaced."""


def _existing_mode(path):
    try:
        return os.lstat(path).st_mode
    except FileNotFoundError:
        return None


def _current_umask():
    value = os.umask(0)
    os.umask(value)
    return value


def write_text(path, text, encoding="utf-8"):
    """Atomically write ``text`` to ``path``; refuse a symlink or non-regular target."""
    target = os.path.abspath(os.fspath(path))
    mode = _existing_mode(target)
    if mode is not None and not stat.S_ISREG(mode):
        raise UnsafeWriteError("refusing to write through a symlink or non-regular file: " + target)
    permissions = stat.S_IMODE(mode) if mode is not None else 0o666 & ~_current_umask()
    directory = os.path.dirname(target)
    # mkstemp opens with O_CREAT|O_EXCL|O_NOFOLLOW, so the temporary name cannot be a link.
    fd, temporary = tempfile.mkstemp(dir=directory, prefix="." + os.path.basename(target) + ".",
                                     suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding=encoding) as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        if hasattr(os, "chmod"):
            os.chmod(temporary, permissions)
        recheck = _existing_mode(target)
        if recheck is not None and not stat.S_ISREG(recheck):
            raise UnsafeWriteError("output path changed to a symlink or non-regular file: " + target)
        os.replace(temporary, target)
    except BaseException:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise
