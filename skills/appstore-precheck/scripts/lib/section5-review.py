#!/usr/bin/env python3
"""Read-only source evidence for a narrow set of section 5 obligations.

Signals are partial. A source hit requests review; its absence cannot prove a
working UI flow or compliant data handling. Output omits source text and URLs.
"""
import argparse
import json
import os
import pathlib
import re
import sys

CHECKS = ("section5-contact-select-all", "section5-contact-preselect",
          "section5-safari-obscure", "section5-privacy-entry")
SUFFIXES = {".swift", ".m", ".mm", ".h", ".kt", ".java", ".dart",
            ".js", ".jsx", ".ts", ".tsx"}
EXCLUDE = {".git", "node_modules", "Pods", "build", "DerivedData", ".build",
           ".dart_tool", "vendor", "test", "tests", "__tests__", "fixtures"}
MAX_FILES = 4000
MAX_BYTES = 512 * 1024
MAX_LINES = 100000

CONTACT_PICKER = re.compile(r"\b(?:CNContactPickerViewController|CNContactStore)\b")
SELECT_ALL = re.compile(r"\b(?:Button|Text|Label|NSLocalizedString)\s*\(\s*['\"]Select\s+All['\"]", re.I)
PRESELECT_ALL = re.compile(r"\b(?:selectedContacts|selectedRecipients)\s*=\s*(?:allContacts|contacts|allRecipients)\b")
SAFARI = re.compile(r"\bSFSafariViewController\b")
SAFARI_COVER = re.compile(r"\b(?:safariVC|safariViewController|safariController)\.view\.(?:addSubview\s*\(|alpha\s*=|isHidden\s*=)")
PRIVACY_ENTRY = re.compile(r"\b(?:Link|Button|Text|Label|NSLocalizedString)\s*\(\s*['\"]Privacy\s+(?:Policy|Notice)['\"]", re.I)


def record(check_id, status, reason, evidence=None):
    return {"check_id": check_id, "status": status, "evidence_class": "source",
            "reason": reason, "evidence": evidence or []}


def source_rows(root):
    files = 0
    lines = 0
    for directory, dirs, names in os.walk(root, topdown=True, followlinks=False):
        dirs[:] = sorted(name for name in dirs if name not in EXCLUDE and not name.startswith(".")
                         and not (pathlib.Path(directory) / name).is_symlink())
        for name in sorted(names):
            path = pathlib.Path(directory) / name
            if path.is_symlink() or not path.is_file() or path.suffix.lower() not in SUFFIXES:
                continue
            try:
                if path.stat().st_size > MAX_BYTES:
                    continue
                content = path.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            relative = path.relative_to(root).as_posix()
            for number, line in enumerate(content.splitlines(), 1):
                lines += 1
                if lines > MAX_LINES:
                    return
                if line.lstrip().startswith(("//", "/*", "*", "#")):
                    continue
                yield relative, number, line[:1000]
            files += 1
            if files >= MAX_FILES:
                return


def matches(rows, pattern, signal, limit=8):
    return [{"file": path, "line": number, "signal": signal}
            for path, number, line in rows if pattern.search(line)][:limit]


def same_file(rows, context, pattern, signal):
    context_files = {entry[0] for entry in rows if context.search(entry[2])}
    scoped = [entry for entry in rows if entry[0] in context_files]
    return matches(scoped, pattern, signal)


def review_contact_select_all(rows):
    evidence = same_file(rows, CONTACT_PICKER, SELECT_ALL, "select_all_contact_ui")
    if evidence:
        return record(CHECKS[0], "NEEDS_REVIEW",
                      "A contact picker and Select All UI signal share a source file; inspect the actual recipient flow",
                      evidence)
    return record(CHECKS[0], "SKIP",
                  "No paired contact picker and Select All UI signal; generated and remote flows were not assessed")


def review_contact_preselect(rows):
    evidence = same_file(rows, CONTACT_PICKER, PRESELECT_ALL, "contact_preselection")
    if evidence:
        return record(CHECKS[1], "NEEDS_REVIEW",
                      "A contact picker and bulk selection assignment share a source file; inspect initial recipient state",
                      evidence)
    return record(CHECKS[1], "SKIP",
                  "No paired contact picker and bulk preselection signal; recipient state remains unverified")


def review_safari_obscure(rows):
    evidence = same_file(rows, SAFARI, SAFARI_COVER, "safari_view_overlay_or_hidden")
    if evidence:
        return record(CHECKS[2], "NEEDS_REVIEW",
                      "SafariViewController source and a view overlay or hidden-state signal coincide; inspect the rendered presentation",
                      evidence)
    return record(CHECKS[2], "SKIP",
                  "No mapped SafariViewController overlay or hidden-state signal; runtime presentation was not assessed")


def review_privacy_entry(rows):
    evidence = matches(rows, PRIVACY_ENTRY, "privacy_ui_entry")
    if evidence:
        return record(CHECKS[3], "NEEDS_REVIEW",
                      "Privacy policy or notice UI label found; verify that it opens the current policy and remains easy to access",
                      evidence)
    return record(CHECKS[3], "SKIP",
                  "No mapped privacy UI entry label; policy access may be implemented through another UI path")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=pathlib.Path, required=True)
    args = parser.parse_args()
    root = args.repo.resolve()
    if root.is_dir():
        rows = list(source_rows(root))
        checks = [review_contact_select_all(rows), review_contact_preselect(rows),
                  review_safari_obscure(rows), review_privacy_entry(rows)]
    else:
        checks = [record(check, "NOT_RUN", "Repository directory unavailable") for check in CHECKS]
    json.dump({"schema_version": 1, "checks": checks}, sys.stdout, sort_keys=True)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
