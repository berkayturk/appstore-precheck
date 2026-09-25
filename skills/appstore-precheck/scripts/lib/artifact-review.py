#!/usr/bin/env python3
"""Read-only inspection of an existing .app, .ipa, or .xcarchive.

Results describe evidence, not a blanket App Store approval. Missing build/tool
evidence is explicitly NOT_RUN/SKIP. No application code is launched.
"""
import argparse
import json
import pathlib
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

CHECKS = (
    "artifact-entitlements", "artifact-reason-api", "artifact-private-api",
    "artifact-url-schemes", "artifact-ats", "artifact-sdk",
    "artifact-embedded-sdk", "artifact-executable-loading", "artifact-debug",
)


def record(check_id, status, reason, evidence=None):
    return {"check_id": check_id, "status": status, "evidence_class": "artifact",
            "reason": reason, "evidence": evidence or []}


def plist(path):
    try:
        with path.open("rb") as stream:
            return plistlib.load(stream)
    except (OSError, ValueError, TypeError, OverflowError):
        return None


def tool(name, *args):
    binary = shutil.which(name)
    if not binary:
        return None
    try:
        return subprocess.run([binary] + list(args), stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, timeout=20, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return None


def output(result):
    if result is None:
        return ""
    return (result.stdout + b"\n" + result.stderr).decode("utf-8", "replace")


def select_app(path, temp):
    if not path or not path.exists():
        return None, None, "No built artifact was supplied"
    if path.is_dir() and path.suffix == ".app":
        return path, "app", ""
    if path.is_dir() and path.suffix == ".xcarchive":
        apps = sorted((path / "Products" / "Applications").glob("*.app"))
        if len(apps) == 1:
            return apps[0], "xcarchive", ""
        return None, "xcarchive", "Archive must contain exactly one .app"
    if path.is_file() and path.suffix == ".ipa":
        try:
            with zipfile.ZipFile(path) as archive:
                entries = [i for i in archive.infolist() if re.match(r"^Payload/[^/]+\.app/", i.filename)]
                apps = {i.filename.split("/")[1] for i in entries}
                if len(apps) != 1 or not entries:
                    return None, "ipa", "IPA must contain exactly one Payload .app"
                if len(entries) > 10000 or sum(i.file_size for i in entries) > 1024 * 1024 * 1024:
                    return None, "ipa", "IPA has too many or too-large members"
                root = temp / "Payload" / next(iter(apps))
                for info in entries:
                    member = pathlib.PurePosixPath(info.filename)
                    if ".." in member.parts or info.file_size > 512 * 1024 * 1024:
                        return None, "ipa", "Unsafe or oversized IPA member"
                    target = temp.joinpath(*member.parts)
                    if info.is_dir():
                        target.mkdir(parents=True, exist_ok=True)
                        continue
                    target.parent.mkdir(parents=True, exist_ok=True)
                    with archive.open(info) as src, target.open("wb") as dst:
                        shutil.copyfileobj(src, dst)
                return root, "ipa", ""
        except (OSError, zipfile.BadZipFile, RuntimeError):
            return None, "ipa", "Unreadable IPA"
    return None, None, "Expected .app, .ipa, or .xcarchive"


def embedded_frameworks(app):
    return sorted((app / "Frameworks").glob("*.framework"))


def executable(app, info):
    name = info.get("CFBundleExecutable")
    path = app / name if isinstance(name, str) else None
    return path if path and path.is_file() else None


def machos(app, main_binary):
    binaries = [main_binary] if main_binary else []
    for framework in embedded_frameworks(app):
        framework_info = plist(framework / "Info.plist")
        if isinstance(framework_info, dict):
            binary = executable(framework, framework_info)
            if binary:
                binaries.append(binary)
    return binaries


def entitlements(app):
    result = tool("codesign", "-d", "--entitlements", ":-", str(app))
    if result is None:
        return None, "codesign unavailable (install Xcode Command Line Tools)"
    raw = result.stdout or result.stderr
    start = raw.find(b"<?xml")
    if start < 0:
        start = raw.find(b"<plist")
    if start < 0:
        return None, "No readable code-signing entitlements (unsigned simulator app or invalid signature)"
    try:
        value = plistlib.loads(raw[start:])
        return value if isinstance(value, dict) else None, ""
    except (ValueError, TypeError, OverflowError):
        return None, "Could not parse code-signing entitlements"


def review_entitlements(info, ents, error, binary):
    if ents is None:
        return record(CHECKS[0], "SKIP", error)
    issues = []
    if ents.get("com.apple.developer.healthkit") and not any(
            info.get(k) for k in ("NSHealthShareUsageDescription", "NSHealthUpdateUsageDescription")):
        issues.append("HealthKit entitlement without Health usage description")
    modes = info.get("UIBackgroundModes") or []
    if "remote-notification" in modes and not ents.get("aps-environment"):
        issues.append("remote-notification background mode without aps-environment entitlement")
    if ents.get("com.apple.developer.associated-domains") and not isinstance(
            ents.get("com.apple.developer.associated-domains"), list):
        issues.append("associated-domains entitlement is malformed")
    if binary:
        try:
            data = binary.read_bytes()
            if b"HKHealthStore" in data and not ents.get("com.apple.developer.healthkit"):
                issues.append("HealthKit symbol without HealthKit entitlement")
            if b"registerForRemoteNotifications" in data and not ents.get("aps-environment"):
                issues.append("push registration symbol without aps-environment entitlement")
        except OSError:
            pass
    if issues:
        return record(CHECKS[0], "NEEDS_REVIEW", "Entitlements and Info.plist need reconciliation", issues)
    return record(CHECKS[0], "PASS", "No checked entitlement/Info.plist mismatch observed")


def review_reasons(app, binary):
    if not binary:
        return record(CHECKS[1], "SKIP", "CFBundleExecutable is missing")
    categories = {
        "NSPrivacyAccessedAPICategoryFileTimestamp": ("_stat", "_fstat", "_lstat", "_getattrlist"),
        "NSPrivacyAccessedAPICategoryDiskSpace": ("_statfs", "_fstatfs"),
        "NSPrivacyAccessedAPICategoryUserDefaults": ("_OBJC_CLASS_$_NSUserDefaults",),
        "NSPrivacyAccessedAPICategorySystemBootTime": ("kern.boottime",),
    }
    declared = set()
    for bundle in [app] + embedded_frameworks(app):
        manifest = plist(bundle / "PrivacyInfo.xcprivacy")
        if isinstance(manifest, dict):
            for item in manifest.get("NSPrivacyAccessedAPITypes", []):
                if isinstance(item, dict):
                    declared.add(item.get("NSPrivacyAccessedAPIType"))
    missing = []
    unavailable = []
    for candidate in machos(app, binary):
        result = tool("nm", "-u", str(candidate))
        if result is None or result.returncode != 0:
            unavailable.append(candidate.name)
            continue
        symbols = output(result)
        observed = {category for category, needles in categories.items()
                    if any(re.search(re.escape(s) + r"(?:\s|$)", symbols, re.M) for s in needles)}
        missing.extend(candidate.name + ":" + category for category in sorted(observed - declared))
    if missing:
        return record(CHECKS[1], "NEEDS_REVIEW",
                      "Undefined symbols suggest required-reason API use absent from app manifest; inspect linked SDKs and approved reasons",
                      missing + ["nm unavailable: " + x for x in unavailable])
    if unavailable:
        return record(CHECKS[1], "SKIP", "nm -u unavailable or unable to inspect every Mach-O (install Xcode Command Line Tools)", unavailable)
    return record(CHECKS[1], "PASS", "No manifest mismatch found among mapped nm symbols; dynamic calls remain unverified")


def review_private(app, binary):
    if not binary:
        return record(CHECKS[2], "SKIP", "CFBundleExecutable is missing")
    private, restricted, unavailable = [], [], []
    for candidate in machos(app, binary):
        linked = tool("otool", "-L", str(candidate))
        symbols = tool("nm", "-u", str(candidate))
        if linked is None or linked.returncode != 0:
            unavailable.append(candidate.name + ":otool")
        else:
            private.extend(candidate.name + ":" + line.strip() for line in output(linked).splitlines()
                           if "/System/Library/PrivateFrameworks/" in line)
        if symbols is None or symbols.returncode != 0:
            unavailable.append(candidate.name + ":nm")
        elif re.search(r"\b_task_for_pid\b", output(symbols)):
            restricted.append(candidate.name + ":task_for_pid")
    if private:
        return record(CHECKS[2], "FINDING", "App executable directly links a private Apple framework", private)
    if restricted:
        return record(CHECKS[2], "NEEDS_REVIEW", "Restricted symbol observed; verify public API entitlement and use", restricted + unavailable)
    if unavailable:
        return record(CHECKS[2], "SKIP", "otool -L or nm -u unavailable for some Mach-O files (install Xcode Command Line Tools)", unavailable)
    return record(CHECKS[2], "PASS", "No direct private framework linkage observed; selectors resolved at runtime remain unverified")


def review_schemes(info):
    value = info.get("LSApplicationQueriesSchemes", [])
    if not isinstance(value, list):
        return record(CHECKS[3], "NEEDS_REVIEW", "LSApplicationQueriesSchemes is not an array")
    suspicious = [x for x in value if isinstance(x, str) and x.lower() in
                  {"cydia", "sileo", "zbra", "filza"}]
    malformed = [str(x) for x in value if not isinstance(x, str) or not re.fullmatch(r"[A-Za-z][A-Za-z0-9+.-]*", x)]
    if suspicious or malformed:
        return record(CHECKS[3], "NEEDS_REVIEW", "URL scheme queries need purpose and format review", suspicious + malformed)
    return record(CHECKS[3], "PASS", "Declared URL scheme queries have no mapped suspicious or malformed values")


def review_ats(info):
    ats = info.get("NSAppTransportSecurity", {})
    if not isinstance(ats, dict):
        return record(CHECKS[4], "NEEDS_REVIEW", "NSAppTransportSecurity is malformed")
    exceptions = []
    for key in ("NSAllowsArbitraryLoads", "NSAllowsArbitraryLoadsInWebContent", "NSAllowsLocalNetworking"):
        if ats.get(key):
            exceptions.append(key)
    domains = ats.get("NSExceptionDomains") or {}
    if isinstance(domains, dict):
        exceptions += ["NSExceptionDomains:" + str(d) for d in domains]
    if exceptions:
        return record(CHECKS[4], "NEEDS_REVIEW", "ATS exception requires a documented transport justification", exceptions)
    return record(CHECKS[4], "PASS", "No Info.plist ATS exception observed")


def version(value):
    if not isinstance(value, str) or not re.fullmatch(r"\d+(?:\.\d+)*", value):
        return None
    return tuple(int(x) for x in value.split("."))


def review_sdk(info):
    minimum, sdk = info.get("MinimumOSVersion"), info.get("DTSDKName")
    if not version(minimum) or not isinstance(sdk, str) or not re.fullmatch(r"iphone(?:os|simulator)\d+(?:\.\d+)*", sdk):
        return record(CHECKS[5], "NEEDS_REVIEW", "MinimumOSVersion or DTSDKName is missing/malformed",
                      ["MinimumOSVersion=" + str(minimum), "DTSDKName=" + str(sdk)])
    sdk_version = version(re.search(r"\d+(?:\.\d+)*$", sdk).group())
    if version(minimum) > sdk_version:
        return record(CHECKS[5], "FINDING", "MinimumOSVersion exceeds build SDK version",
                      ["minimum=" + minimum, "sdk=" + sdk])
    return record(CHECKS[5], "NEEDS_REVIEW", "Versions are internally consistent; compare SDK with Apple's current submission requirement",
                  ["minimum=" + minimum, "sdk=" + sdk])


def review_frameworks(app, info):
    frameworks = embedded_frameworks(app)
    if not frameworks:
        return record(CHECKS[6], "PASS", "No embedded frameworks found")
    issues = []
    unverified = []
    simulator = str(info.get("DTSDKName", "")).startswith("iphonesimulator")
    for framework in frameworks:
        if plist(framework / "PrivacyInfo.xcprivacy") is None:
            issues.append(framework.name + ": no readable PrivacyInfo.xcprivacy")
        result = tool("codesign", "--verify", "--strict", str(framework))
        if result is None:
            unverified.append(framework.name + ": codesign unavailable")
        elif result.returncode != 0:
            (unverified if simulator else issues).append(framework.name + ": signature not verified")
    if issues:
        return record(CHECKS[6], "NEEDS_REVIEW", "Embedded SDK manifest/signature review required; not every framework necessarily requires a manifest", issues + unverified)
    if unverified:
        return record(CHECKS[6], "SKIP", "Embedded signature verification unavailable", unverified)
    return record(CHECKS[6], "PASS", "Embedded frameworks contain readable manifests and signatures verified")


def review_loading(binary):
    if not binary:
        return record(CHECKS[7], "SKIP", "CFBundleExecutable is missing")
    try:
        data = binary.read_bytes()
    except OSError:
        return record(CHECKS[7], "SKIP", "Could not read executable")
    tokens = [name for name, needle in (("dlopen", b"dlopen"), ("download", b"download"),
              ("HTTP", b"HTTP"), ("executable", b"executable")) if needle in data]
    if "dlopen" in tokens or {"download", "executable"}.issubset(tokens):
        return record(CHECKS[7], "NEEDS_REVIEW", "Binary strings suggest dynamic loading or downloaded executable content; inspect code path", tokens)
    return record(CHECKS[7], "PASS", "No mapped dynamic loading/download string combination observed")


def review_debug(app, ents):
    paths = [str(p.relative_to(app)) for p in app.rglob("*") if p.is_file() and
             (p.suffix in (".mobileprovision", ".dSYM", ".xctest") or
              p.name in (".DS_Store", "debug.log"))]
    if ents and ents.get("get-task-allow") is True:
        paths.append("get-task-allow=true")
    if paths:
        return record(CHECKS[8], "NEEDS_REVIEW", "Bundle contains debug/test artifacts or a development entitlement", paths[:30])
    if ents is None:
        return record(CHECKS[8], "SKIP", "No mapped debug files found, but entitlements could not be read")
    return record(CHECKS[8], "PASS", "No mapped debug artifacts or get-task-allow entitlement observed")


def inspect(app):
    info = plist(app / "Info.plist")
    if not isinstance(info, dict):
        return [record(c, "SKIP", "App Info.plist is absent or unreadable") for c in CHECKS]
    binary = executable(app, info)
    ents, error = entitlements(app)
    return [review_entitlements(info, ents, error, binary), review_reasons(app, binary),
            review_private(app, binary), review_schemes(info), review_ats(info), review_sdk(info),
            review_frameworks(app, info), review_loading(binary), review_debug(app, ents)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", help="Existing .app, .ipa, or .xcarchive")
    parser.add_argument("--format", choices=("json", "text"), default="text")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="appstore-precheck-artifact-") as scratch:
        app, kind, gap = select_app(pathlib.Path(args.app) if args.app else None,
                                    pathlib.Path(scratch))
        checks = inspect(app) if app else [record(c, "NOT_RUN", gap) for c in CHECKS]
        result = {"artifact_type": kind, "artifact": args.app, "executed": False,
                  "checks": checks}
        if args.format == "json":
            print(json.dumps(result, indent=2, sort_keys=True))
        else:
            for item in checks:
                print("ARTIFACT-{}: [{}] {} — {}".format(item["status"], item["check_id"],
                                                         item["reason"], "; ".join(item["evidence"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
