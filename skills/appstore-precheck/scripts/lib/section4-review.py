#!/usr/bin/env python3
"""Read-only Section 4 evidence hints; source signals never prove compliance."""
import argparse
import json
import pathlib
import plistlib
import re
import sys

EXCLUDED = {".git", "node_modules", "Pods", "build", "DerivedData", ".build",
            ".dart_tool", "vendor", "test", "tests", "__tests__", "fixtures"}
SOURCE_EXT = {".swift", ".m", ".mm", ".h", ".kt", ".java", ".dart",
              ".js", ".jsx", ".ts", ".tsx"}
MAX_FILES = 4000
MAX_BYTES = 512 * 1024
CHECKS = ("section4-extension-commerce", "section4-keyboard-navigation",
          "section4-safari-access", "section4-apple-branding", "section4-placeholder-copy")
AD_SIGNAL = re.compile(r"\b(?:GADBannerView|GoogleMobileAds|AdMob|AppLovin|UnityAds|FBAdView)\b", re.I)
IAP_SIGNAL = re.compile(r"\b(?:SKPaymentQueue|SKProductsRequest|StoreKit|InAppPurchase|react-native-iap)\b", re.I)
NEXT_KEYBOARD = re.compile(r"\b(?:advanceToNextInputMode|handleInputModeList|nextKeyboardButton)\b")
APPLE_BRAND = re.compile(r"\b(?:Apple|App Store)\b", re.I)
PLACEHOLDER_COPY = re.compile(r"[\"']\s*(?:lorem ipsum|coming soon)\b", re.I)
BROAD_HOSTS = {"<all_urls>", "*://*/*", "https://*/*", "http://*/*"}


def record(check_id, status, reason, evidence=None, facets=None):
    result = {"check_id": check_id, "status": status, "evidence_class": "source",
              "reason": reason, "evidence": evidence or []}
    if facets is not None:
        result["facets"] = facets
    return result


def eligible(root, path):
    try:
        relative = path.relative_to(root)
        if any(part in EXCLUDED or part.startswith(".") for part in relative.parts[:-1]):
            return False
        return path.is_file() and not path.is_symlink() and path.stat().st_size <= MAX_BYTES
    except (ValueError, OSError):
        return False


def files(root, suffixes):
    found = 0
    for path in sorted(root.rglob("*")):
        if path.suffix.lower() in suffixes and eligible(root, path):
            yield path
            found += 1
            if found >= MAX_FILES:
                break


def rel(root, path):
    return path.relative_to(root).as_posix()


def extension_plists(root):
    found = []
    app_plists = []
    for path in files(root, {".plist"}):
        try:
            data = plistlib.loads(path.read_bytes())
        except (OSError, ValueError, TypeError, plistlib.InvalidFileException):
            continue
        if not isinstance(data, dict):
            continue
        extension = data.get("NSExtension")
        if isinstance(extension, dict):
            point = extension.get("NSExtensionPointIdentifier")
            if isinstance(point, str) and point:
                found.append((path, point))
        else:
            app_plists.append((path, data))
    return found, app_plists


def source_rows(root, extensions):
    rows = {}
    for plist, _point in extensions:
        base = plist.parent
        current = []
        for path in files(base, SOURCE_EXT):
            if not eligible(root, path):
                continue
            try:
                content = path.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            current.extend((rel(root, path), number, line[:1000])
                           for number, line in enumerate(content.splitlines(), 1))
        rows[plist] = current
    return rows


def line_hits(rows, pattern, signal):
    return [{"file": path, "line": line_no, "signal": signal}
            for path, line_no, line in rows if pattern.search(line)][:8]


def review_commerce(root, extensions, rows):
    evidence = []
    facets = {"advertising": False, "in_app_purchase": False}
    for plist, point in extensions:
        current = rows[plist]
        ad = line_hits(current, AD_SIGNAL, "advertising")
        iap = line_hits(current, IAP_SIGNAL, "in_app_purchase")
        if ad or iap:
            evidence.append({"file": rel(root, plist), "line": 0, "signal": "extension_type"})
            evidence.extend(ad + iap)
            facets["advertising"] |= bool(ad)
            facets["in_app_purchase"] |= bool(iap)
    if not evidence:
        return record(CHECKS[0], "SKIP", "No mapped commerce API signal in a discovered extension source tree")
    return record(CHECKS[0], "NEEDS_REVIEW",
                  "Extension source references advertising or purchase APIs; inspect shipped extension behavior",
                  evidence, facets)


def review_keyboard(root, extensions, rows):
    keyboards = [(path, point) for path, point in extensions if point == "com.apple.keyboard-service"]
    if not keyboards:
        return record(CHECKS[1], "SKIP", "No keyboard extension declaration found")
    evidence = [{"file": rel(root, path), "line": 0, "signal": "keyboard_extension"}
                for path, _point in keyboards]
    source_hints = [hit for path, _point in keyboards
                    for hit in line_hits(rows[path], NEXT_KEYBOARD, "next_keyboard_source_hint")]
    evidence.extend(source_hints)
    return record(CHECKS[1], "NEEDS_REVIEW",
                  "Keyboard extension found; verify the next-keyboard control in the installed UI",
                  evidence, {"next_keyboard_source_hint": bool(source_hints)})


def review_safari(root, extensions):
    safari = [(path, point) for path, point in extensions if point.startswith("com.apple.Safari.")]
    if not safari:
        return record(CHECKS[2], "SKIP", "No Safari extension declaration found")
    evidence = [{"file": rel(root, path), "line": 0, "signal": "safari_extension"}
                for path, _point in safari]
    broad = False
    for plist, _point in safari:
        for manifest in files(plist.parent, {".json"}):
            if manifest.name != "manifest.json" or not eligible(root, manifest):
                continue
            try:
                content = json.loads(manifest.read_text(encoding="utf-8"))
            except (OSError, ValueError):
                continue
            if not isinstance(content, dict):
                continue
            host_permissions = content.get("host_permissions", [])
            other_permissions = content.get("permissions", [])
            permissions = [part for part in (host_permissions, other_permissions) if isinstance(part, list)]
            if any(host in BROAD_HOSTS for part in permissions for host in part if isinstance(host, str)):
                broad = True
                evidence.append({"file": rel(root, manifest), "line": 0, "signal": "broad_host_access"})
    return record(CHECKS[2], "NEEDS_REVIEW",
                  "Safari extension found; assess website access against its actual functions",
                  evidence, {"broad_host_access": broad})


def review_brand(root, app_plists):
    evidence = []
    for path, data in app_plists:
        if path.name != "Info.plist":
            continue
        display = data.get("CFBundleDisplayName") or data.get("CFBundleName")
        if isinstance(display, str) and APPLE_BRAND.search(display):
            evidence.append({"file": rel(root, path), "line": 0, "signal": "brand_name_signal"})
    if not evidence:
        return record(CHECKS[3], "SKIP", "No mapped Apple brand term in app display-name metadata")
    return record(CHECKS[3], "NEEDS_REVIEW",
                  "App display-name metadata includes an Apple brand term; verify authorization and presentation",
                  evidence)


def review_placeholder(root):
    evidence = []
    for path in files(root, SOURCE_EXT):
        try:
            content = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        evidence.extend(line_hits(((rel(root, path), number, line[:1000])
                                   for number, line in enumerate(content.splitlines(), 1)),
                                  PLACEHOLDER_COPY, "placeholder_copy"))
        if len(evidence) >= 8:
            break
    if not evidence:
        return record(CHECKS[4], "SKIP", "No mapped placeholder literal in source; shipped UI remains unverified")
    return record(CHECKS[4], "NEEDS_REVIEW",
                  "Source contains possible placeholder copy; verify whether it appears in the shipped UI",
                  evidence[:8])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=pathlib.Path, required=True)
    parser.add_argument("--format", choices=("json",), default="json")
    args = parser.parse_args()
    root = args.repo.resolve()
    if not root.is_dir():
        checks = [record(check, "NOT_RUN", "Repository directory unavailable") for check in CHECKS]
    else:
        extensions, app_plists = extension_plists(root)
        rows = source_rows(root, extensions)
        checks = [review_commerce(root, extensions, rows), review_keyboard(root, extensions, rows),
                  review_safari(root, extensions), review_brand(root, app_plists), review_placeholder(root)]
    json.dump({"schema_version": 1, "checks": checks}, sys.stdout, sort_keys=True)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
