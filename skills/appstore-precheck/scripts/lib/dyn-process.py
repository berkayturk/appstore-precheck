#!/usr/bin/env python3
"""Bounded POSIX driver process groups; terminate descendants on cancel/deadline."""
import argparse
import os
import signal
import subprocess
import sys


DEFAULT_GRACE = 15


def stop(proc, grace=DEFAULT_GRACE):
    """TERM the whole group, wait ``grace`` seconds for cleanup, then KILL it."""
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        proc.wait(timeout=grace)
    except subprocess.TimeoutExpired:
        pass
    # The group leader may exit while its child ignores TERM.
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    proc.wait()


def run(argv, timeout, grace=DEFAULT_GRACE, **kwargs):
    try:
        proc = subprocess.Popen(argv, start_new_session=True, **kwargs)
    except FileNotFoundError as exc:
        error = str(exc) if kwargs.get('text') else str(exc).encode()
        return subprocess.CompletedProcess(argv, 127, '' if kwargs.get('text') else b'', error)
    previous = {}
    def cancelled(signum, _frame):
        raise InterruptedError(signum, 'Driver cancelled')
    try:
        for sig in (signal.SIGINT, signal.SIGTERM):
            previous[sig] = signal.signal(sig, cancelled)
        stdout, stderr = proc.communicate(timeout=timeout)
        return subprocess.CompletedProcess(argv, proc.returncode, stdout, stderr)
    except BaseException:
        # Do not let a second cancellation interrupt artifact/device cleanup.
        for sig in previous:
            signal.signal(sig, signal.SIG_IGN)
        stop(proc, grace)
        raise
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--timeout', type=float, required=True)
    parser.add_argument('--grace', type=float, default=DEFAULT_GRACE,
                        help='seconds between TERM and KILL when the deadline expires')
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    argv = args.command[1:] if args.command[:1] == ['--'] else args.command
    if args.timeout <= 0 or args.grace <= 0 or not argv:
        parser.error('positive deadline, grace and command required')
    try:
        return run(argv, args.timeout, args.grace).returncode
    except subprocess.TimeoutExpired:
        return 124
    except InterruptedError:
        return 143


if __name__ == '__main__':
    sys.exit(main())
