#!/usr/bin/env python3
"""Conservative, read-only evidence packet for App Review guideline section 1.

Source hints cannot establish a working user flow or the meaning of app content.
Accordingly, this command never turns absent keywords into a compliance PASS.
"""
import argparse
import json
import pathlib
import re
import sys

SOURCE_SUFFIXES = {".swift", ".m", ".mm", ".h", ".kt", ".java", ".dart", ".js", ".jsx", ".ts", ".tsx"}
TEXT_SUFFIXES = SOURCE_SUFFIXES | {".strings", ".xml", ".json", ".txt"}
MANIFESTS = {"Package.resolved", "Podfile", "Podfile.lock", "package.json", "pubspec.yaml", "build.gradle", "build.gradle.kts"}
EXCLUDE_DIRS = {".git", "node_modules", "Pods", "build", "DerivedData", ".build", ".dart_tool", "vendor", "test", "tests", "__tests__", "fixtures"}
MAX_FILES = 4000
MAX_BYTES = 512 * 1024
CHECKS = ("section1-ugc-controls", "section1-kids-dependencies", "section1-safety-signals")

UGC = re.compile(r"\b(?:createPost|publishPost|postComment|submitComment|sendMessage|uploadUserPhoto|userGeneratedContent|StreamChat|MessageKit|SendbirdSDK)\b", re.I)
UGC_CONTROLS = {
    "prepublication_filter": re.compile(r"\b(?:moderationQueue|pendingApproval|contentFilter|filterContent|moderatePost|preModeration)\b", re.I),
    "report": re.compile(r"\b(?:report(?:Post|Content|Comment|Message|User|Abuse)|flag(?:Post|Content|Comment|Message|User))\b", re.I),
    "block": re.compile(r"\b(?:blockUser|blockedUsers|blockAccount|unblockUser)\b", re.I),
}
SDK = {
    "analytics": re.compile(r"\b(?:FirebaseAnalytics|GoogleAnalytics|Amplitude|Mixpanel|Segment|AppsFlyer)\b", re.I),
    "advertising": re.compile(r"\b(?:GoogleMobileAds|GADBannerView|AdMob|AppLovin|UnityAds|FacebookAudienceNetwork)\b", re.I),
}
CONTENT = {
    "weapons_commerce": re.compile(r"\b(?:buy|purchase|order|checkout|sell)\b.{0,35}\b(?:firearms?|ammunition|rifles?|guns?)\b|\b(?:firearms?|ammunition|rifles?|guns?)\b.{0,35}\b(?:buy|purchase|order|checkout|sell)\b", re.I),
    "medical_measurement": re.compile(r"\b(?:measure|detect|diagnose|calculate)\b.{0,45}\b(?:blood pressure|blood glucose|blood oxygen|body temperature|heart attack)\b", re.I),
    "substance_commerce": re.compile(r"\b(?:buy|purchase|order|checkout|sell)\b.{0,35}\b(?:tobacco|vape|cannabis|opioids?)\b|\b(?:tobacco|vape|cannabis|opioids?)\b.{0,35}\b(?:buy|purchase|order|checkout|sell)\b", re.I),
    "anonymous_calling": re.compile(r"\b(?:anonymous|prank|spoof)\b.{0,30}\b(?:call|sms|text message)\b", re.I),
}


def record(check_id, status, reason, evidence=None, facets=None):
    result = {"check_id": check_id, "status": status, "evidence_class": "source",
              "reason": reason, "evidence": evidence or []}
    if facets is not None:
        result["facets"] = facets
    return result


def files(root):
    count = 0
    for path in sorted(root.rglob("*")):
        if any(part in EXCLUDE_DIRS or part.startswith(".") for part in path.relative_to(root).parts[:-1]):
            continue
        if not path.is_file() or path.is_symlink() or (path.suffix.lower() not in TEXT_SUFFIXES and path.name not in MANIFESTS):
            continue
        try:
            if path.stat().st_size > MAX_BYTES:
                continue
        except OSError:
            continue
        yield path
        count += 1
        if count >= MAX_FILES:
            break


def collect(root):
    source = []
    all_text = []
    for path in files(root):
        try:
            raw = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        target = source if path.suffix.lower() in SOURCE_SUFFIXES else None
        rel = path.relative_to(root).as_posix()
        for number, line in enumerate(raw.splitlines(), 1):
            row = (rel, number, line[:1000])
            all_text.append(row)
            if target is not None:
                target.append(row)
    return source, all_text


def hits(rows, pattern, label, limit=8):
    return [{"file": path, "line": number, "signal": label}
            for path, number, line in rows if pattern.search(line)][:limit]


def review_ugc(source):
    signals = hits(source, UGC, "ugc_surface")
    if not signals:
        return record(CHECKS[0], "SKIP", "No UGC source signal found; app and backend applicability remain unverified")
    facets = {name: hits(source, pattern, name) for name, pattern in UGC_CONTROLS.items()}
    evidence = signals + [entry for matches in facets.values() for entry in matches]
    absent = [name for name, matches in facets.items() if not matches]
    reason = "UGC source signal found; review actual filtering, reporting, blocking, response time, and published contact flow"
    if absent:
        reason += "; no source hint for: " + ", ".join(absent)
    return record(CHECKS[0], "NEEDS_REVIEW", reason, evidence, {name: bool(matches) for name, matches in facets.items()})


def review_kids(source, all_text, kids_category):
    if kids_category != "yes":
        return record(CHECKS[1], "SKIP", "Kids Category applicability was not confirmed; pass --kids-category yes when confirmed")
    sdk_rows = [row for row in all_text if pathlib.Path(row[0]).name in MANIFESTS]
    evidence = [entry for name, pattern in SDK.items() for entry in hits(source + sdk_rows, pattern, name)]
    if evidence:
        return record(CHECKS[1], "NEEDS_REVIEW", "Kids Category with third-party analytics/advertising SDK signals; inspect data flows and narrow exception conditions", evidence)
    return record(CHECKS[1], "NEEDS_REVIEW", "Kids Category confirmed; no mapped SDK signal found, but transitive dependencies and child-data flows need review")


def review_safety(all_text):
    evidence = [entry for name, pattern in CONTENT.items() for entry in hits(all_text, pattern, name)]
    if not evidence:
        return record(CHECKS[2], "SKIP", "No mapped source-text signal found; images, remote content, and context were not assessed")
    return record(CHECKS[2], "NEEDS_REVIEW", "Source text may describe a Section 1 safety-sensitive feature; inspect its meaning and actual behavior", evidence)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=pathlib.Path, required=True)
    parser.add_argument("--kids-category", choices=("yes", "no", "unknown"), default="unknown")
    parser.add_argument("--format", choices=("json",), default="json")
    args = parser.parse_args()
    root = args.repo.resolve()
    if not root.is_dir():
        checks = [record(check, "NOT_RUN", "Repository directory unavailable") for check in CHECKS]
    else:
        source, all_text = collect(root)
        checks = [review_ugc(source), review_kids(source, all_text, args.kids_category), review_safety(all_text)]
    json.dump({"schema_version": 1, "checks": checks}, sys.stdout, sort_keys=True)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
