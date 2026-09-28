#!/usr/bin/env python3
"""Deadline watchdog for dynamic-run.sh (Python 3.8+ stdlib, POSIX).

  dyn-watchdog.py --pid <runner-pid> --after <seconds>

Sleeps until <seconds> have passed (exiting quietly if the runner is gone first),
then asks the runner to wind down BEFORE its supervisor's own deadline fires:
SIGUSR1 to the runner (its trap exits 124 and the EXIT trap tears down the devices
this run created), then SIGTERM to every descendant of the runner so a long
foreground step (a Maestro call, an observation sleep, the explore driver) ends now
instead of delaying the teardown. Nested dyn-process.py drivers catch that TERM and
stop their own process group. This process never signals itself or anything outside
the runner's process tree.
"""
import argparse
import os
import signal
import subprocess
import sys
import time


def descendants(root):
    """PIDs below `root` according to one `ps` snapshot (root itself excluded)."""
    try:
        out = subprocess.run(["ps", "-A", "-o", "pid=,ppid="], stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL, universal_newlines=True, timeout=10).stdout
    except (OSError, subprocess.SubprocessError):
        return []
    children = {}
    for line in out.splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[0].isdigit() and parts[1].isdigit():
            children.setdefault(int(parts[1]), []).append(int(parts[0]))
    found, todo = [], [root]
    while todo:
        for child in children.get(todo.pop(), []):
            if child not in found:
                found.append(child)
                todo.append(child)
    return found


def alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pid", type=int, required=True)
    parser.add_argument("--after", type=float, required=True)
    args = parser.parse_args()
    if args.pid <= 1 or args.after <= 0:
        parser.error("a runner pid above 1 and a positive delay are required")
    stop_at = time.monotonic() + args.after
    while time.monotonic() < stop_at:
        if not alive(args.pid):
            return 0
        time.sleep(min(0.5, max(0.01, stop_at - time.monotonic())))
    if not alive(args.pid):
        return 0
    me = os.getpid()
    # Snapshot BEFORE the runner is told to wind down: once its trap runs it starts
    # teardown children that must never be caught in this sweep.
    victims = [pid for pid in descendants(args.pid) if pid != me]
    try:
        os.kill(args.pid, signal.SIGUSR1)
    except OSError:
        return 0
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except OSError:
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
