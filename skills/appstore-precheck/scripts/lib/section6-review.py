#!/usr/bin/env python3
"""Read-only introduction and submission preparation evidence hints.

Dependency and hardware signals only select questions for human review. Absence
of a signal never establishes that a submitted app satisfies these duties.
"""
import argparse
import json
import os
import pathlib
import re
import sys

EXCLUDED = {".git", "node_modules", "Pods", "build", "DerivedData", ".build",
            ".dart_tool", "vendor", "test", "tests", "__tests__", "fixtures"}
SOURCE_EXT = {".swift", ".m", ".mm", ".h", ".kt", ".java", ".dart",
              ".js", ".jsx", ".ts", ".tsx"}
MANIFESTS = {"Podfile.lock", "Package.resolved", "package.json", "pubspec.yaml",
             "pubspec.lock", "Cartfile.resolved", "gradle.lockfile"}
MAX_FILES = 4000
MAX_BYTES = 512 * 1024
CHECKS = ("section6-external-components", "section6-special-hardware")
HARDWARE = re.compile(r"\b(?:CoreBluetooth|CBCentralManager|CBPeripheralManager|"
                      r"ExternalAccessory|EAAccessoryManager|CoreNFC|NFCNDEFReaderSession|"
                      r"NearbyInteraction|NISession|HomeKit|HMHomeManager)\b")


def record(check_id, status, reason, evidence=None):
    return {"check_id": check_id, "status": status, "evidence_class": "source",
            "reason": reason, "evidence": evidence or []}


def eligible(root, path):
    try:
        relative = path.relative_to(root)
        if any(part in EXCLUDED or part.startswith(".") for part in relative.parts[:-1]):
            return False
        return path.is_file() and not path.is_symlink() and path.stat().st_size <= MAX_BYTES
    except (ValueError, OSError):
        return False


def files(root, predicate):
    found = 0
    for current, dirs, names in os.walk(str(root), followlinks=False):
        dirs[:] = sorted(name for name in dirs if name not in EXCLUDED and
                         not name.startswith(".") and
                         not (pathlib.Path(current) / name).is_symlink())
        for name in sorted(names):
            path = pathlib.Path(current) / name
            if predicate(path) and eligible(root, path):
                yield path
                found += 1
                if found >= MAX_FILES:
                    return


def relative(root, path):
    return path.relative_to(root).as_posix()


def has_dependencies(path, text):
    if path.name in ("package.json", "Package.resolved"):
        try:
            data = json.loads(text)
        except ValueError:
            return False
        if not isinstance(data, dict):
            return False
        if path.name == "package.json":
            return any(isinstance(data.get(key), dict) and bool(data[key])
                       for key in ("dependencies", "optionalDependencies"))
        pins = data.get("pins")
        if pins is None and isinstance(data.get("object"), dict):
            pins = data["object"].get("pins")
        return isinstance(pins, list) and bool(pins)
    if path.name == "Podfile.lock":
        return bool(re.search(r"(?m)^PODS:\s*\n\s*-\s+\S", text))
    if path.name == "pubspec.yaml":
        return bool(re.search(r"(?m)^dependencies:\s*\n(?:\s*#.*\n)*\s{2,}[A-Za-z][\w-]*\s*:", text))
    if path.name == "pubspec.lock":
        return bool(re.search(r"(?m)^packages:\s*\n\s{2,}[A-Za-z][\w-]*\s*:", text))
    return bool(text.strip())


def review_external_components(root):
    evidence = []
    for path in files(root, lambda value: value.name in MANIFESTS):
        try:
            content = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if has_dependencies(path, content):
            evidence.append({"file": relative(root, path), "line": 0,
                             "signal": "dependency_manifest"})
            if len(evidence) >= 8:
                break
    if not evidence:
        return record(CHECKS[0], "SKIP", "No supported external dependency manifest signal found; shipped components remain unverified")
    return record(CHECKS[0], "NEEDS_REVIEW",
                  "Dependency manifests indicate external components; assess their shipped behavior and ongoing compliance",
                  evidence)


def review_special_hardware(root):
    evidence = []
    for path in files(root, lambda value: value.suffix.lower() in SOURCE_EXT):
        try:
            content = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for number, line in enumerate(content.splitlines(), 1):
            if HARDWARE.search(line):
                evidence.append({"file": relative(root, path), "line": number,
                                 "signal": "hardware_api_hint"})
                if len(evidence) >= 8:
                    break
        if len(evidence) >= 8:
            break
    if not evidence:
        return record(CHECKS[1], "SKIP", "No mapped hardware API signal found; review resource needs remain unverified")
    return record(CHECKS[1], "NEEDS_REVIEW",
                  "Source references a hardware API; decide whether reviewers need a device, accessory, sample data, or demonstration",
                  evidence)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=pathlib.Path, required=True)
    parser.add_argument("--format", choices=("json",), default="json")
    args = parser.parse_args()
    root = args.repo.resolve()
    if root.is_dir():
        checks = [review_external_components(root), review_special_hardware(root)]
    else:
        checks = [record(check_id, "NOT_RUN", "Repository directory unavailable")
                  for check_id in CHECKS]
    json.dump({"schema_version": 1, "checks": checks}, sys.stdout, sort_keys=True)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
