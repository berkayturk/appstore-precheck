#!/usr/bin/env python3
"""Bounded Maestro accessibility exploration and conservative runtime review.

Python 3.8+ stdlib. The offline --screens mode is the portable fixture interface.
Live mode only operates on a simulator owned by the caller; it never erases or deletes.
"""
import argparse
import collections
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import time

RULES = {
    "dyn-account-deletion": "5.1.1(v)",
    "dyn-siwa-parity": "4.8",
    "dyn-restore-response": "3.1.1",
    "dyn-paywall-disclosure": "3.1.2",
    "dyn-permission-purpose": "5.1.1",
    "dyn-ugc-safety": "1.2",
    "dyn-login-wall": "5.1.1(v)",
    "dyn-external-payment": "3.1.1",
    "dyn-placeholder": "2.1",
    "dyn-navigation-crash": "2.1",
    "dyn-layout-review": "4.0",
    "dyn-host-privacy": "5.1.2",
    "dyn-bundle-drift": "2.1",
}
PATTERNS = {
    "login": r"\b(log[ -]?in|sign[ -]?in|email|password|continue with apple)\b",
    "paywall": r"\b(subscri\w*|paywall|purchase|free trial|restore purchases)\b",
    "settings": r"\b(settings|preferences|profile)\b",
    "account": r"\b(account|delete account|deactivate account)\b",
    "permission": r"\b(allow|permission|camera|photos|location|microphone|tracking)\b",
    "ugc": r"\b(post|comment|feed|report|block user|filter)\b",
    "webview": r"\b(browser|webview|open in safari)\b",
    "external_link": r"\b(https?://|privacy policy|terms of use|support|external link)\b",
}
DESTRUCTIVE = re.compile(
    r"\b(delete|remove|purchase|buy|subscribe|submit|send|sign out|log out|erase|post|pay|checkout)\b",
    re.I,
)
ACTION_WORDS = re.compile(
    r"\b(open|show|view|continue|next|settings|profile|account|login|log in|sign in|restore|menu|more|help|report|block)\b",
    re.I,
)
SECRET_WORDS = re.compile(r"password|token|secret|credential|api.?key", re.I)


def attrs(node):
    return node.get("attributes", {}) if isinstance(node, dict) else {}


def walk(node):
    if isinstance(node, dict):
        if "attributes" in node:
            yield attrs(node)
        for child in node.get("children", []):
            yield from walk(child)
    elif isinstance(node, list):
        for child in node:
            yield from walk(child)


def label(a):
    values = [a.get(k) for k in ("accessibilityText", "text", "contentDescription", "label", "id")]
    return next((str(v).strip() for v in values if isinstance(v, str) and v.strip()), "")


def safe_label(value):
    for secret in (os.getenv("PRECHECK_DEMO_USERNAME", ""), os.getenv("PRECHECK_DEMO_PASSWORD", "")):
        if secret:
            value = value.replace(secret, "[redacted]")
    if SECRET_WORDS.search(value):
        return "[redacted control]"
    return value[:120]


def scrub_tree(value):
    if isinstance(value, str):
        for secret in (os.getenv("PRECHECK_DEMO_USERNAME", ""), os.getenv("PRECHECK_DEMO_PASSWORD", "")):
            if secret:
                value = value.replace(secret, "[redacted]")
        return value
    if isinstance(value, list):
        return [scrub_tree(x) for x in value]
    if isinstance(value, dict):
        return {k: scrub_tree(v) for k, v in value.items()}
    return value


def summarize(tree, name, screenshot=None, timestamp=None):
    nodes = list(walk(tree))
    labels = [label(a) for a in nodes]
    labels = [x for x in labels if x]
    text = "\n".join(labels)
    interactive = []
    for a in nodes:
        value = label(a)
        if value and (a.get("clickable") is True or ACTION_WORDS.search(value)):
            interactive.append({"label": safe_label(value), "safe_to_tap": not bool(DESTRUCTIVE.search(value))})
    return {
        "screen": name,
        "title": safe_label(labels[0]) if labels else "",
        "node_count": len(nodes),
        "degenerate": len(nodes) <= 3 or not labels,
        "actions": interactive,
        "patterns": sorted(k for k, rx in PATTERNS.items() if re.search(rx, text, re.I)),
        "labels": [safe_label(x) for x in labels],
        "hierarchy": name + ".json",
        "screenshot": screenshot,
        "observed_at": timestamp,
    }


def record(check_id, status, reason, evidence=None):
    return {"check_id": check_id, "guideline": RULES[check_id], "status": status,
            "reason": reason, "evidence_class": "runtime", "evidence": evidence or []}


def evaluate(screens, context):
    result = []
    good = [s for s in screens if not s["degenerate"]]
    labels = "\n".join(x for s in good for x in s["labels"])
    if not screens:
        return [record(k, "NOT_RUN", "No runtime screen was captured") for k in RULES]
    if not good:
        return [record(k, "SKIP", "Accessibility trees contain no usable semantics; inspect screenshots") for k in RULES]
    def seen(rx):
        return bool(re.search(rx, labels, re.I))
    def review(k, reason):
        result.append(record(k, "NEEDS_REVIEW", reason, [s["hierarchy"] for s in good]))
    def skip(k, reason):
        result.append(record(k, "SKIP", reason))

    if seen(r"\b(delete|deactivate) (my )?account\b"):
        review("dyn-account-deletion", "Deletion entry was visible; verify end-to-end completion and retention disclosures")
    elif seen(r"\b(account|settings|profile)\b"):
        review("dyn-account-deletion", "Account/settings was visible but no deletion entry was captured; explore authenticated screens")
    else:
        skip("dyn-account-deletion", "No authenticated account screen was observed")
    if seen(r"sign in with apple|continue with apple"):
        review("dyn-siwa-parity", "Apple sign-in control observed; compare terms with other identity providers")
    elif seen(r"sign in with google|continue with google|sign in with facebook"):
        review("dyn-siwa-parity", "Third-party sign-in observed without Apple control on captured screens; assess entitlement exceptions")
    else:
        skip("dyn-siwa-parity", "No third-party sign-in choice was observed")
    if seen(r"restore purchases"):
        review("dyn-restore-response", "Restore control observed; tap response requires a StoreKit-capable review run")
    else:
        skip("dyn-restore-response", "No purchase screen was observed")
    if any("paywall" in s["patterns"] for s in good):
        review("dyn-paywall-disclosure", "Paywall content captured; inspect price, billing interval, terms, and privacy links together")
    else:
        skip("dyn-paywall-disclosure", "No paywall screen was observed")
    if any("permission" in s["patterns"] for s in good):
        review("dyn-permission-purpose", "Permission-related content captured; compare purpose explanation with OS prompt timing")
    else:
        skip("dyn-permission-purpose", "No permission request was triggered")
    if any("ugc" in s["patterns"] for s in good):
        review("dyn-ugc-safety", "UGC surface captured; inspect filtering, reporting, blocking, and response paths")
    else:
        skip("dyn-ugc-safety", "No user-generated content surface was observed")
    if any("login" in s["patterns"] for s in good):
        review("dyn-login-wall", "Login screen captured; determine whether account creation is necessary for core use")
    else:
        skip("dyn-login-wall", "No registration wall was observed")
    if seen(r"\b(pay (on|with)|external payment|visit (our )?website|checkout)\b"):
        review("dyn-external-payment", "Possible external payment direction captured; assess storefront and entitlement context")
    else:
        skip("dyn-external-payment", "No external payment direction was observed")
    if seen(r"lorem ipsum|placeholder|coming soon|todo\b"):
        review("dyn-placeholder", "Placeholder-like copy captured; inspect whether it is shipped user-facing content")
    else:
        result.append(record("dyn-placeholder", "PASS", "No placeholder marker in captured accessible text; visual review remains useful",
                             [s["hierarchy"] for s in good]))
    skip("dyn-navigation-crash", "Screen inventory alone cannot establish crash health; use three fresh device repeats")
    review("dyn-layout-review", "Review screenshots at dark mode, large type, and iPad size")
    if context.get("hosts") and context.get("privacy_manifest"):
        review("dyn-host-privacy", "Observed hosts and privacy manifest supplied; classify data purpose before judging consistency")
    else:
        skip("dyn-host-privacy", "Host capture or installed privacy manifest was unavailable")
    if context.get("installed_bundle") and context.get("source_bundle"):
        review("dyn-bundle-drift", "Installed and source bundles supplied; compare shipped declarations and build configuration")
    else:
        skip("dyn-bundle-drift", "Installed bundle or source bundle was unavailable")
    return result


def command(argv, timeout, cwd=None):
    return subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                          timeout=timeout, check=True, cwd=cwd).stdout


def live_explore(udid, bundle_id, out, max_screens, seconds):
    """Conservative BFS: relaunch from root for each path, never persist app state."""
    if not udid or not bundle_id:
        raise ValueError("--udid and --bundle-id are required for live exploration")
    deadline = time.monotonic() + seconds
    todo = collections.deque([()])
    visited = set()
    screens = []
    while todo and len(screens) < max_screens and time.monotonic() < deadline:
        path = todo.popleft()
        try:
            # Maestro performs the entire navigation path in one flow/call.
            flow = out / "navigation-flow.yaml"
            flow.write_text("appId: " + json.dumps(bundle_id) + "\n---\n- launchApp:\n    clearState: true\n" +
                            "\n".join("- tapOn:\n    text: " + json.dumps(x) for x in path) + "\n")
            command(["maestro", "--device", udid, "test", str(flow)],
                    min(45, max(1, int(deadline-time.monotonic()))), cwd=out)
            name = "screen-%03d" % len(screens)
            raw = command(["maestro", "--device", udid, "hierarchy"],
                          min(45, max(1, int(deadline-time.monotonic()))), cwd=out)
            tree = scrub_tree(json.loads(raw))
            sig = hashlib.sha256(json.dumps(tree, sort_keys=True).encode()).hexdigest()
            if sig in visited:
                continue
            visited.add(sig)
            (out / (name + ".json")).write_text(json.dumps(tree, indent=2))
            png = name + ".png"
            command(["xcrun", "simctl", "io", udid, "screenshot", "--type=png", str(out / png)], 15, cwd=out)
            screen = summarize(tree, name, png, time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()))
            screen["path"] = list(path)
            screens.append(screen)
            if len(path) < 4:
                for action in screen["actions"]:
                    if action["safe_to_tap"] and action["label"] not in path:
                        todo.append(path + (action["label"],))
        except (subprocess.SubprocessError, OSError, ValueError, json.JSONDecodeError):
            # Driver failures leave the screen unobserved; no finding is inferred.
            continue
        finally:
            (out / "navigation-flow.yaml").unlink(missing_ok=True)
    return screens


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--screens", type=pathlib.Path)
    p.add_argument("--udid")
    p.add_argument("--bundle-id")
    p.add_argument("--out", required=True, type=pathlib.Path)
    p.add_argument("--max-screens", type=int, default=25)
    p.add_argument("--seconds", type=int, default=360)
    p.add_argument("--hosts", type=pathlib.Path)
    p.add_argument("--privacy-manifest", type=pathlib.Path)
    p.add_argument("--installed-bundle", type=pathlib.Path)
    p.add_argument("--source-bundle", type=pathlib.Path)
    a = p.parse_args()
    if not (1 <= a.max_screens <= 25 and 1 <= a.seconds <= 360):
        p.error("screen and time budgets must be within 25 screens and 360 seconds")
    if bool(a.screens) == bool(a.udid):
        p.error("choose exactly one of --screens or --udid")
    a.out.mkdir(parents=True, exist_ok=True)
    a.out = a.out.resolve()
    if a.screens:
        screens = []
        for path in sorted(a.screens.glob("*.json"))[:a.max_screens]:
            try:
                png = path.with_suffix(".png")
                screens.append(summarize(json.loads(path.read_text()), path.stem,
                                         png.name if png.exists() else None, None))
            except (OSError, ValueError):
                continue
    else:
        screens = live_explore(a.udid, a.bundle_id, a.out, a.max_screens, a.seconds)
    context = {"hosts": bool(a.hosts and a.hosts.exists() and a.hosts.stat().st_size), "privacy_manifest": bool(a.privacy_manifest and a.privacy_manifest.exists()),
               "installed_bundle": bool(a.installed_bundle and a.installed_bundle.exists()),
               "source_bundle": bool(a.source_bundle and a.source_bundle.exists())}
    inventory = {"schema_version": 1, "screen_budget": a.max_screens, "time_budget_seconds": a.seconds,
                 "screens": screens, "checks": evaluate(screens, context)}
    (a.out / "screen-inventory.json").write_text(json.dumps(inventory, indent=2) + "\n")
    print(json.dumps(inventory))


if __name__ == "__main__":
    main()
