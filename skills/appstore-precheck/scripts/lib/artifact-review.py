#!/usr/bin/env python3
"""Read-only inspection of an existing .app, .ipa, or .xcarchive.

Results describe evidence, not a blanket App Store approval. Missing build/tool
evidence is explicitly NOT_RUN/SKIP. No application code is launched.
"""
import argparse
import datetime
import hashlib
import fnmatch
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


def code_bundles(app):
    """Include extension and App Clip executable boundaries, not just the main app."""
    return [app] + sorted(p for p in app.rglob('*') if p.is_dir() and
                         p.suffix in ('.appex', '.framework', '.app'))


def embedded_frameworks(app):
    return [p for p in code_bundles(app)[1:] if p.suffix == '.framework']


def executable(app, info):
    name = info.get("CFBundleExecutable")
    path = app / name if isinstance(name, str) and pathlib.Path(name).name == name else None
    return path if path and path.is_file() else None


def machos(app, main_binary):
    binaries = [main_binary] if main_binary else []
    for framework in code_bundles(app)[1:]:
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
    if result.returncode != 0:
        return None, "Code-signing entitlements unavailable; signature not verified"
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


# Identifiers checked against Apple's required-reason API documentation, 2026-09-27.
# Membership does not prove that the declared reason matches actual use.
REASON_SOURCE = "https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype"
APPROVED_REASONS = {
    "NSPrivacyAccessedAPICategoryFileTimestamp": {"DDA9.1", "C617.1", "3B52.1", "0A2A.1"},
    "NSPrivacyAccessedAPICategorySystemBootTime": {"35F9.1", "8FFB.1", "3D61.1"},
    "NSPrivacyAccessedAPICategoryDiskSpace": {"85F4.1", "E174.1", "7D9E.1", "B728.1"},
    "NSPrivacyAccessedAPICategoryActiveKeyboards": {"3EC4.1", "54BD.1"},
    "NSPrivacyAccessedAPICategoryUserDefaults": {"CA92.1", "1C8F.1", "C56D.1", "AC6B.1"},
}


REASON_SYMBOLS = {
    "NSPrivacyAccessedAPICategoryFileTimestamp": ("_stat", "_fstat", "_lstat", "_fstatat", "_getattrlist"),
    "NSPrivacyAccessedAPICategoryDiskSpace": ("_statfs", "_fstatfs", "_statvfs", "_fstatvfs"),
    "NSPrivacyAccessedAPICategoryUserDefaults": ("_OBJC_CLASS_$_NSUserDefaults",),
    "NSPrivacyAccessedAPICategorySystemBootTime": ("_mach_absolute_time",),
}

def review_reasons(app, binary):
    if not binary:
        return record(CHECKS[1], "SKIP", "CFBundleExecutable is missing")
    issues, unavailable = [], []
    for bundle in code_bundles(app):
        label = str(bundle.relative_to(app))
        info = plist(bundle / 'Info.plist')
        candidate = executable(bundle, info) if isinstance(info, dict) else None
        manifest = plist(bundle / "PrivacyInfo.xcprivacy")
        declared = set()
        if manifest is not None:
            rows = manifest.get('NSPrivacyAccessedAPITypes', []) if isinstance(manifest, dict) else None
            if not isinstance(rows, list):
                issues.append(label + ': malformed required-reason API array')
                rows = []
            for item in rows:
                if not isinstance(item, dict):
                    issues.append(label + ': malformed required-reason API entry')
                    continue
                category = item.get('NSPrivacyAccessedAPIType')
                reasons = item.get('NSPrivacyAccessedAPITypeReasons')
                if not isinstance(category, str) or category not in APPROVED_REASONS:
                    issues.append(label + ': unknown API category; compare current Apple documentation')
                elif not isinstance(reasons, list) or not reasons or any(
                        not isinstance(reason, str) or reason not in APPROVED_REASONS[category] for reason in reasons):
                    issues.append(label + ':' + category + ': empty, malformed or unrecognized reason identifier')
                else:
                    declared.add(category)
        elif (bundle / 'PrivacyInfo.xcprivacy').exists():
            issues.append(label + ': unreadable privacy manifest')
        if not candidate:
            unavailable.append(label + ': executable unavailable')
            continue
        result = tool("nm", "-u", str(candidate))
        if result is None or result.returncode != 0:
            unavailable.append(label + ': nm unavailable')
            continue
        symbols = output(result)
        observed = {category for category, needles in REASON_SYMBOLS.items()
                    if any(re.search(re.escape(needle) + r"(?:\s|$)", symbols, re.M) for needle in needles)}
        issues.extend(label + ':' + category + ': no valid reason in this code bundle manifest'
                      for category in sorted(observed - declared))
    if issues:
        return record(CHECKS[1], "NEEDS_REVIEW",
                      "Bundle-local API/reason mismatch; applicability and actual API purpose require review", issues + unavailable)
    if unavailable:
        return record(CHECKS[1], "SKIP", "Could not inspect every code bundle", unavailable)
    return record(CHECKS[1], "PASS", "Mapped bundle-local symbols/reason identifiers are consistent; dynamic use and reason eligibility remain unverified")


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
    tokens = [name for name, needle in (("download", b"download"), ("executable", b"executable")) if needle in data]
    if {"download", "executable"}.issubset(tokens):
        return record(CHECKS[7], "NEEDS_REVIEW", "Binary strings suggest dynamic loading or downloaded executable content; inspect code path", tokens)
    return record(CHECKS[7], "PASS", "No mapped dynamic loading/download string combination observed")


def review_debug(app, ents):
    paths = [str(p.relative_to(app)) for p in app.rglob("*") if p.is_file() and
             ((p.suffix == ".mobileprovision" and p.name != "embedded.mobileprovision") or p.suffix in (".dSYM", ".xctest") or
              p.name in (".DS_Store", "debug.log"))]
    if ents and ents.get("get-task-allow") is True:
        paths.append("get-task-allow=true")
    if paths:
        return record(CHECKS[8], "NEEDS_REVIEW", "Bundle contains debug/test artifacts or a development entitlement", paths[:30])
    if ents is None:
        return record(CHECKS[8], "SKIP", "No mapped debug files found, but entitlements could not be read")
    return record(CHECKS[8], "PASS", "No mapped debug artifacts or get-task-allow entitlement observed")


def inspect(app, signatures):
    info = plist(app / "Info.plist")
    if not isinstance(info, dict):
        return [record(c, "SKIP", "App Info.plist is absent or unreadable") for c in CHECKS]
    binary = executable(app, info)
    records, main_ents = [], None
    for bundle, signed in zip(code_bundles(app), signatures):
        if bundle.suffix == '.framework':
            continue
        bundle_info = plist(bundle / 'Info.plist')
        if not isinstance(bundle_info, dict):
            records.append(record(CHECKS[0], 'SKIP', 'Bundle Info.plist unavailable'))
            continue
        ents, error = entitlements(bundle)
        if signed['signature_status'] != 'VERIFIED':
            ents, error = None, 'Signature unavailable or invalid; entitlement inspection cannot establish signed consistency'
        if bundle == app:
            main_ents = ents
        row = review_entitlements(bundle_info, ents, error, executable(bundle, bundle_info))
        if signed['profile_issues']:
            row = record(CHECKS[0], 'NEEDS_REVIEW', 'Decoded provisioning profile and signed entitlement mismatch',
                         row['evidence'] + signed['profile_issues'])
        row['evidence'] = [signed['bundle'] + ': ' + entry for entry in row['evidence']]
        records.append(row)
    issues = [entry for row in records if row['status'] == 'NEEDS_REVIEW' for entry in row['evidence']]
    gaps = [row['reason'] for row in records if row['status'] == 'SKIP']
    combined = (record(CHECKS[0], 'NEEDS_REVIEW', 'App/extension entitlement or profile mismatch requires review', issues + gaps)
                if issues else record(CHECKS[0], 'SKIP', 'App/extension signed entitlement inspection incomplete', gaps)
                if gaps else record(CHECKS[0], 'PASS', 'No checked app/extension entitlement or decoded profile mismatch observed'))
    return [combined, review_reasons(app, binary), review_private(app, binary),
            review_schemes(info), review_ats(info), review_sdk(info), review_frameworks(app, info),
            review_loading(binary), review_debug(app, main_ents)]


def digest_file(path):
    if not path or not path.is_file():
        return None
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def identity(app):
    info = plist(app / 'Info.plist') or {}
    if not isinstance(info, dict):
        info = {}
    binary = executable(app, info)
    return {'bundle_id': info.get('CFBundleIdentifier'), 'version': info.get('CFBundleShortVersionString'),
            'build': info.get('CFBundleVersion'), 'binary_sha256': digest_file(binary),
            'info_plist_sha256': digest_file(app / 'Info.plist'), 'sdk': info.get('DTSDKName')}


def permitted(value, allowed):
    if isinstance(value, str) and isinstance(allowed, str):
        return fnmatch.fnmatchcase(value, allowed)
    if isinstance(value, list) and isinstance(allowed, list):
        return all(any(permitted(item, rule) for rule in allowed) for item in value)
    return type(value) is type(allowed) and value == allowed


def signing_evidence(app):
    rows = []
    for bundle in code_bundles(app):
        info = plist(bundle / 'Info.plist') or {}
        if not isinstance(info, dict):
            info = {}
        verified = tool('codesign', '--verify', '--strict', str(bundle))
        details = tool('codesign', '-d', str(bundle))
        # Verification errors alone cannot distinguish unsigned code from invalid signatures.
        present = details is not None and details.returncode == 0
        status = ('UNAVAILABLE' if verified is None else 'UNSIGNED' if not present else
                  'VERIFIED' if verified.returncode == 0 else 'INVALID')
        ents, _ = entitlements(bundle)
        issues, gaps = [], []
        if status != 'VERIFIED':
            gaps.append('Code signature not verified')
        if ents is None:
            gaps.append('Entitlements not readable')
        profile_path = bundle / 'embedded.mobileprovision'
        profile = None
        if profile_path.is_file():
            decoded = tool('security', 'cms', '-D', '-i', str(profile_path))
            if decoded is not None and decoded.returncode == 0:
                try:
                    profile = plistlib.loads(decoded.stdout)
                except (ValueError, TypeError, OverflowError):
                    pass
        if isinstance(profile, dict) and isinstance(profile.get('Entitlements'), dict) and ents is not None:
            allowed = profile['Entitlements']
            for key, value in ents.items():
                if key not in allowed or not permitted(value, allowed[key]):
                    issues.append('Entitlement not authorized by decoded profile: ' + key)
            app_id = ents.get('application-identifier')
            bundle_id = info.get('CFBundleIdentifier')
            if not isinstance(app_id, str) or not isinstance(bundle_id, str) or not app_id.endswith('.' + bundle_id):
                issues.append('Signed application identifier does not match bundle identifier')
            expiration = profile.get('ExpirationDate')
            if isinstance(expiration, datetime.datetime):
                if expiration.replace(tzinfo=datetime.timezone.utc) <= datetime.datetime.now(datetime.timezone.utc):
                    issues.append('Decoded provisioning profile has expired')
            else:
                gaps.append('Profile expiry unavailable')
        else:
            gaps.append('Embedded provisioning profile consistency not inspected')
        rows.append({'bundle': str(bundle.relative_to(app)), 'signature_status': status,
                     'identity': identity(bundle), 'profile_issues': issues, 'gaps': gaps})
    return rows


def scope_report(app, args):
    observed = identity(app)
    mismatches = [key for key, value in (('bundle_id', args.expected_bundle),
                  ('version', args.expected_version), ('build', args.expected_build))
                  if value is not None and observed.get(key) != value]
    simulator = str(observed.get('sdk') or '').startswith('iphonesimulator')
    signatures = signing_evidence(app)
    return {'identity': observed, 'identity_matches_expected': not mismatches,
            'identity_expectations_supplied': any(x is not None for x in
                                                (args.expected_bundle, args.expected_version, args.expected_build)),
            'identity_mismatches': mismatches,
            'evidence_kind': 'simulator_app' if simulator else 'device_artifact',
            'signing': signatures, 'distribution_status': 'NOT_VERIFIED',
            'physical_device_status': 'NOT_RUN', 'source_binding_status': 'NOT_PROVIDED',
            'limitations': ['Signature verification is not App Store distribution eligibility or certificate/profile authority verification.',
                            'No physical-device behavior was executed.',
                            'API symbols and network domains do not prove complete privacy or tracking compliance.',
                            'No source provenance was inferred from the supplied artifact.']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", help="Existing .app, .ipa, or .xcarchive")
    parser.add_argument("--format", choices=("json", "text"), default="text")
    parser.add_argument('--expected-bundle', help='Expected CFBundleIdentifier; mismatch invalidates identity binding')
    parser.add_argument('--expected-version', help='Expected CFBundleShortVersionString')
    parser.add_argument('--expected-build', help='Expected CFBundleVersion')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="appstore-precheck-artifact-") as scratch:
        app, kind, gap = select_app(pathlib.Path(args.app) if args.app else None,
                                    pathlib.Path(scratch))
        scope = scope_report(app, args) if app else None
        checks = inspect(app, scope["signing"]) if app else [record(c, "NOT_RUN", gap) for c in CHECKS]
        result = {"artifact_type": kind, "artifact": args.app, "executed": False,
                  "checks": checks, "scope": scope}
        if args.format == "json":
            print(json.dumps(result, indent=2, sort_keys=True))
        else:
            if app:
                scope = result['scope']
                print('ARTIFACT-SCOPE: {} distribution=NOT_VERIFIED physical=NOT_RUN source=NOT_PROVIDED'.format(scope['evidence_kind']))
                if scope['identity_mismatches']:
                    print('ARTIFACT-SKIP: identity mismatch — ' + ', '.join(scope['identity_mismatches']))
            for item in checks:
                print("ARTIFACT-{}: [{}] {} — {}".format(item["status"], item["check_id"],
                                                         item["reason"], "; ".join(item["evidence"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
