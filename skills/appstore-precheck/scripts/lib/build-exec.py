#!/usr/bin/env python3
"""Run one build tool with a deadline and a deliberately minimal environment.

Only structured status is logged. Tool stdout/stderr is held in memory long enough to
classify failure and is never copied into a persistent report or printed to the user.
"""
import argparse
import json
import os
import re
import selectors
import signal
import subprocess
import sys
import time


def classify(output):
    # Xcode prints configuration exports and successful task headings even when a
    # later, unrelated step fails. Neither CodeSignContext nor a TLS certificate
    # error is evidence of an application signing failure.
    output = "\n".join(line for line in output.splitlines()
                       if not re.match(r"^\s*(?:export\s+)?[A-Z][A-Z0-9_]*\\?=", line)
                       and not re.search(r"\bwarning:", line, re.IGNORECASE))
    signing = (
        r"command\s+codesign\s+failed|errSecInternalComponent|"
        r"(?:error|failed|failure)[^\n]*(?:code[ -]?sign(?:ing)?|provisioning profile|development team|signing certificate)|"
        r"(?:code[ -]?signing|signing for|provisioning profile|development team)[^\n]*"
        r"(?:requires|required|not found|missing|expired|doesn't|does not|invalid|failed)|"
        r"no signing certificate|no profiles for[^\n]*(?:found|available)"
    )
    patterns = (
        ("SIGNING", signing),
        ("MISSING_POD", r"(no such module|unable to find a specification|pod install|pods/.*not found)"),
        ("MISSING_SDK", r"(sdk .*not found|unable to find a destination|iphoneos.*not found|iphonesimulator.*not found|xcode-select)"),
        ("MISSING_FRAMEWORK", r"(framework .* not found|could not find.*framework|no such module.*shared)"),
        ("MISSING_TOOL", r"(command not found|no such file or directory)"),
    )
    for status, pattern in patterns:
        if re.search(pattern, output, re.IGNORECASE):
            return status
    return "BUILD_FAILED"


def kill_group(proc):
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


class BuildCancelled(Exception):
    pass


def cancelled(signum, frame):
    raise BuildCancelled()


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--step", required=True)
    p.add_argument("--cwd", required=True)
    p.add_argument("--timeout", type=int, required=True)
    p.add_argument("--log", required=True)
    p.add_argument("--home", required=True)
    p.add_argument("--temp", required=True)
    p.add_argument("--scheme", action="store_true")
    p.add_argument("command", nargs=argparse.REMAINDER)
    a = p.parse_args()
    command = a.command[1:] if a.command[:1] == ["--"] else a.command
    if not command or a.timeout < 1:
        return 64
    env = {
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "HOME": a.home,
        "CFFIXED_USER_HOME": a.home,
        "XDG_CACHE_HOME": os.path.join(a.home, '.cache'),
        "npm_config_cache": os.path.join(a.home, '.npm'),
        "GRADLE_USER_HOME": os.path.join(a.home, '.gradle'),
        "PUB_CACHE": os.path.join(a.home, '.pub-cache'),
        "TMPDIR": a.temp,
        "LANG": "C.UTF-8",
        "LC_ALL": "C.UTF-8",
        "CI": "1",
        "COCOAPODS_DISABLE_STATS": "1",
        "EXPO_NO_TELEMETRY": "1",
    }
    if os.environ.get("DEVELOPER_DIR"):
        env["DEVELOPER_DIR"] = os.environ["DEVELOPER_DIR"]
    if os.environ.get("GEM_PATH"):
        env["GEM_PATH"] = os.environ["GEM_PATH"]
    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(sig, cancelled)
    start = time.monotonic()
    status = "OK"
    result = bytearray()
    proc = None
    try:
        proc = subprocess.Popen(command, cwd=a.cwd, env=env, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, start_new_session=True)
        selector = selectors.DefaultSelector()
        selector.register(proc.stdout, selectors.EVENT_READ)
        deadline = start + a.timeout
        while selector.get_map():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                kill_group(proc)
                status = "TIMEOUT"
                break
            for key, _ in selector.select(remaining):
                chunk = os.read(key.fileobj.fileno(), 65536)
                if not chunk:
                    selector.unregister(key.fileobj)
                else:
                    result.extend(chunk)
                    if len(result) > 262144:
                        del result[:-262144]
        selector.close()
        proc.stdout.close()
        if status == "TIMEOUT":
            proc.wait()
        else:
            remaining = deadline - time.monotonic()
            try:
                proc.wait(timeout=max(0.01, remaining))
            except subprocess.TimeoutExpired:
                kill_group(proc)
                proc.wait()
                status = "TIMEOUT"
        if status == "OK" and proc.returncode:
            status = classify(result.decode("utf-8", "replace"))
    except BuildCancelled:
        if proc is not None:
            kill_group(proc)
            proc.wait()
        status = 'CANCELLED'
    except FileNotFoundError:
        status = "MISSING_TOOL"
    except OSError:
        status = "BUILD_FAILED"
    if status == "OK" and a.scheme:
        try:
            raw = result.decode("utf-8", "replace")
            # xcodebuild may print simulator diagnostics before its JSON, and
            # those diagnostics can themselves contain braces. Keep the last
            # valid project/workspace object instead of trusting the first '{'.
            schemes = []
            preferred = []
            decoder = json.JSONDecoder()
            for pos, char in enumerate(raw):
                if char != "{":
                    continue
                try:
                    data, _ = decoder.raw_decode(raw[pos:])
                except ValueError:
                    continue
                if not isinstance(data, dict):
                    continue
                found = []
                found_preferred = []
                for value in data.values():
                    if isinstance(value, dict) and isinstance(value.get("schemes"), list):
                        found.extend(value["schemes"])
                        if value.get("name") in value["schemes"]:
                            found_preferred.append(value["name"])
                if found:
                    schemes = found
                    preferred = found_preferred
            schemes = sorted(s for s in schemes if isinstance(s, str) and s)
            if schemes:
                print("SCHEME=" + (sorted(set(preferred))[0] if preferred else schemes[0]))
            else:
                status = "NO_SCHEME"
        except (ValueError, UnicodeError, AttributeError):
            status = "NO_SCHEME"
    with open(a.log, "a", encoding="utf-8") as f:
        f.write(json.dumps({"step": a.step, "status": status,
                            "seconds": round(time.monotonic() - start, 2)}) + "\n")
    if status != "OK":
        print("STATUS=" + status)
        return 3
    if not a.scheme:
        print("STATUS=OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
