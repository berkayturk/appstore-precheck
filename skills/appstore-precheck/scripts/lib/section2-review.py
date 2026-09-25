#!/usr/bin/env python3
"""Read-only, partial evidence for App Review performance and listing duties.

Only location and signal labels are emitted. Source text, credentials, URLs,
and screenshot pixels never enter the JSON report. Absent signals are SKIP,
because source and local fastlane data cannot prove release readiness.
"""
import argparse
import json
import os
import pathlib
import re
import sys

CHECKS = ("section2-completeness-signals", "section2-review-access-signals",
          "section2-screenshot-packet")
SOURCE_SUFFIXES = {".swift", ".m", ".mm", ".kt", ".java", ".dart", ".js", ".jsx", ".ts", ".tsx", ".strings"}
EXCLUDE = {".git", "node_modules", "Pods", "build", "DerivedData", ".build",
           ".dart_tool", "vendor", "test", "tests", "__tests__", "fixtures"}
MAX_FILES = 4000
MAX_BYTES = 512 * 1024
MAX_LINES = 100000

UI_STRING = re.compile(r"(?:\b(?:Text|NSLocalizedString|LocalizedStringKey)\s*\(\s*['\"][^'\"\n]{0,160}(?:lorem ipsum|placeholder|insert [^'\"\n]{1,30} here)|<Text[^>]*>[^<]{0,160}(?:lorem ipsum|placeholder))", re.I)
LOCALIZED_STRING = re.compile(r"^\s*['\"][^'\"\n]{1,160}['\"]\s*=\s*['\"][^'\"\n]{0,160}(?:lorem ipsum|placeholder|insert [^'\"\n]{1,30} here)", re.I)
UNFINISHED_CODE = re.compile(r"\b(?:fatalError|preconditionFailure)\s*\(\s*['\"](?:TODO|FIXME|not implemented)|\bthrow\s+(?:UnimplementedError\s*\(|new\s+Error\s*\(\s*['\"](?:TODO|FIXME|not implemented))", re.I)
LOGIN = re.compile(r"\b(?:signIn|logIn|login|authenticateUser|authenticate|passwordField|secureTextField)\b", re.I)
NETWORK = re.compile(r"\b(?:URLSession|OkHttpClient|HttpURLConnection|Retrofit|Dio|axios|fetch\s*\(|http\.get\s*\()", re.I)
IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg"}


def record(check_id, status, reason, evidence=None, facets=None):
    result = {"check_id": check_id, "status": status, "evidence_class": "source",
              "reason": reason, "evidence": evidence or []}
    if facets is not None:
        result["facets"] = facets
    return result


def source_rows(root):
    count = 0
    line_count = 0
    for directory, dirs, names in os.walk(root, topdown=True, followlinks=False):
        dirs[:] = sorted(name for name in dirs if name not in EXCLUDE and not name.startswith(".")
                         and not (pathlib.Path(directory) / name).is_symlink())
        for name in sorted(names):
            path = pathlib.Path(directory) / name
            if path.is_symlink() or not path.is_file() or path.suffix.lower() not in SOURCE_SUFFIXES:
                continue
            try:
                if path.stat().st_size > MAX_BYTES:
                    continue
                lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
            except OSError:
                continue
            relative = path.relative_to(root).as_posix()
            for number, line in enumerate(lines, 1):
                line_count += 1
                if line_count > MAX_LINES:
                    return
                trimmed = line.strip()
                if trimmed.startswith(("//", "/*", "*", "#")):
                    continue
                yield relative, number, line[:1000], path.suffix.lower()
            count += 1
            if count >= MAX_FILES:
                return


def evidence(rows, pattern, signal, limit=8):
    return [{"file": path, "line": number, "signal": signal}
            for path, number, line, suffix in rows if pattern.search(line)][:limit]


def review_completeness(rows):
    ui = [row for row in rows if row[3] != ".strings"]
    localizations = [row for row in rows if row[3] == ".strings"]
    placeholders = evidence(ui, UI_STRING, "placeholder") + evidence(localizations, LOCALIZED_STRING, "placeholder")
    unfinished = evidence(rows, UNFINISHED_CODE, "unfinished_code")
    if not placeholders and not unfinished:
        return record(CHECKS[0], "SKIP", "No mapped placeholder or unfinished-code source signal; generated UI and runtime content were not assessed")
    return record(CHECKS[0], "NEEDS_REVIEW",
                  "Visible placeholder or explicit unfinished-code source signal needs release-build inspection",
                  (placeholders + unfinished)[:16],
                  {"placeholder": bool(placeholders), "unfinished_code": bool(unfinished)})


def review_access(rows):
    login = evidence(rows, LOGIN, "login")
    network = evidence(rows, NETWORK, "network")
    if not login and not network:
        return record(CHECKS[1], "SKIP", "No mapped login or network source signal; remote services and reviewer access remain unverified")
    return record(CHECKS[1], "NEEDS_REVIEW",
                  "Source suggests login or network dependence; verify reviewer access and service availability throughout review",
                  login + network, {"login": bool(login), "network": bool(network)})


def review_screenshots(root):
    directory = root / "fastlane" / "screenshots"
    if not directory.is_dir():
        directory = root / "ios" / "fastlane" / "screenshots"
    if not directory.is_dir() or directory.is_symlink():
        return record(CHECKS[2], "SKIP", "No local fastlane screenshots; App Store Connect images were not inspected")
    files = [p for p in sorted(directory.rglob("*")) if p.is_file() and not p.is_symlink()
             and p.suffix.lower() in IMAGE_SUFFIXES][:200]
    if not files:
        return record(CHECKS[2], "SKIP", "Local screenshot directory has no mapped images; App Store Connect images were not inspected")
    locales = {p.relative_to(directory).parts[0] for p in files if len(p.relative_to(directory).parts) > 1}
    packet = [{"file": p.relative_to(root).as_posix(), "signal": "screenshot_for_visual_review"} for p in files[:20]]
    return record(CHECKS[2], "NEEDS_REVIEW",
                  "Local screenshots are available for a human or vision comparison with actual in-app screens; visual content is undecided",
                  packet, {"image_count": len(files), "locales": len(locales)})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=pathlib.Path, required=True)
    args = parser.parse_args()
    root = args.repo.resolve()
    if root.is_dir():
        rows = list(source_rows(root))
        checks = [review_completeness(rows), review_access(rows), review_screenshots(root)]
    else:
        checks = [record(check, "NOT_RUN", "Repository directory unavailable") for check in CHECKS]
    json.dump({"schema_version": 1, "checks": checks}, sys.stdout, sort_keys=True)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
