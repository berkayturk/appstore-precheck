#!/usr/bin/env python3
"""Bounded Maestro accessibility exploration and conservative runtime review.

Python 3.8+ stdlib. The offline --screens mode is the portable fixture interface.
Live mode only operates on a simulator owned by the caller; it never erases or deletes.
"""
import argparse
import collections
import hashlib
import importlib.util
import json
import pathlib
import re
import subprocess
import sys
import time
import tempfile

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
    r"\b(delete|remove|purchase|buy|subscribe|submit|send|sign out|log out|erase|post|pay|checkout|report|block|allow|accept|agree|confirm|yes|follow|like|share|invite|reset|clear|unsubscribe|cancel|deactivate|transfer|order|donate|restore|continue|sign in|log in|login)\b",
    re.I,
)
ACTION_WORDS = re.compile(
    r"\b(open|show|view|next|settings|profile|account|menu|more|help)\b",
    re.I,
)
_spec = importlib.util.spec_from_file_location("dyn_process", pathlib.Path(__file__).with_name("dyn-process.py"))
_process = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_process)
# Maestro evaluates ${...} as JavaScript inside string parameters and documents no escape,
# so a value carrying the marker is refused rather than mangled.
MAESTRO_EXPR = "${"
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
    value = _scrub.scrub_text(value)
    if SECRET_WORDS.search(value):
        return "[redacted control]"
    return value[:120]


_scrub_spec = importlib.util.spec_from_file_location('dyn_scrub', pathlib.Path(__file__).with_name('dyn-scrub.py'))
_scrub = importlib.util.module_from_spec(_scrub_spec)
_scrub_spec.loader.exec_module(_scrub)
scrub_tree = _scrub.scrub_tree
_safe_write = _scrub.sibling('safe_write')


def summarize(tree, name, screenshot=None, timestamp=None):
    nodes = list(walk(tree))
    labels = [label(a) for a in nodes]
    labels = [x for x in labels if x]
    text = "\n".join(labels)
    interactive = []
    for a in nodes:
        value = label(a)
        if value and (a.get("clickable") is True or ACTION_WORDS.search(value)):
            interactive.append({"label": safe_label(value), "safe_to_tap": False})
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
        result.append(record(k, "REVIEW_REQUIRED", reason, [s["hierarchy"] for s in good]))
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
    elif seen(r"(?:sign in|continue) with (?!apple\b|email\b|password\b|passkey\b|phone\b|your\b)[\w-]+"):
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
    evaluate_remaining(result, good, context, seen, review, skip)
    return result


def evaluate_remaining(result, good, context, seen, review, skip):
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
        review("dyn-placeholder", "Placeholder-like copy captured in %d scanned screen(s); inspect shipped context" % len(good))
    else:
        result.append(record("dyn-placeholder", "REVIEW_REQUIRED", "%d screen(s) scanned; unvisited screens and visual content remain unreviewed" % len(good),
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
    result = _process.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                          timeout=timeout, cwd=cwd)
    if result.returncode:
        raise subprocess.CalledProcessError(result.returncode, argv)
    return result.stdout


def safe_to_tap(value, allowed):
    return bool(value and MAESTRO_EXPR not in value and not DESTRUCTIVE.search(value)
                and not SECRET_WORDS.search(value) and not value.startswith('[redacted')
                and (allowed is None or value in allowed))


def navigation_allowlist(authorization):
    if authorization is None:
        return None
    if not isinstance(authorization, dict) or not isinstance(authorization.get('selectors'), list):
        raise ValueError('navigation allowlist must contain selectors')
    if any(not isinstance(x, str) or not x or MAESTRO_EXPR in x for x in authorization['selectors']):
        raise ValueError('invalid navigation selector')
    return set(authorization['selectors'])


def navigate(udid, bundle_id, path, out, deadline):
    with tempfile.TemporaryDirectory(prefix='.maestro-navigation-', dir=str(out)) as temporary:
        private = pathlib.Path(temporary)
        flow = private / 'navigation-flow.yaml'
        content = 'appId: ' + json.dumps(bundle_id) + '\n---\n- launchApp:\n    clearState: false\n'
        content += ''.join('- tapOn:\n    text: ' + json.dumps('^' + re.escape(label) + '$') + '\n' for label in path)
        _safe_write.write_text(flow, content)
        flow.chmod(0o600)
        command(['maestro', '--device', udid, 'test', '--debug-output', str(private / 'debug'),
                 '--test-output-dir', str(private / 'output'), str(flow)],
                min(45, max(.01, deadline-time.monotonic())), cwd=out)


def capture_screen(udid, out, name, deadline, authenticated=False, allowed=None):
    raw = command(['maestro', '--device', udid, 'hierarchy'], min(45, max(.01, deadline-time.monotonic())), cwd=out)
    tree = scrub_tree(json.loads(raw), authenticated=authenticated, allowed=allowed)
    _safe_write.write_text(out / (name + '.json'), json.dumps(tree, indent=2))
    png = None if authenticated else name + '.png'
    try:
        if png:
            with tempfile.TemporaryDirectory(prefix='.screenshot-', dir=str(out)) as temporary:
                image = pathlib.Path(temporary) / png
                command(['xcrun', 'simctl', 'io', udid, 'screenshot', '--type=png', str(image)],
                        min(15, max(.01, deadline-time.monotonic())), cwd=out)
                _safe_write.write_bytes(out / png, image.read_bytes())
    except (OSError, subprocess.SubprocessError):
        png = None
    screen = summarize(tree, name, png, time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()))
    return screen, hashlib.sha256(json.dumps(tree, sort_keys=True).encode()).hexdigest()


def live_explore(udid, bundle_id, out, max_screens, seconds, authorization=None, authenticated=False):
    if not udid or not bundle_id or MAESTRO_EXPR in bundle_id:
        raise ValueError('non-evaluated bundle id and owned device required')
    allowed = navigation_allowlist(authorization)
    if authenticated and not allowed:
        raise ValueError("authenticated exploration requires an explicit navigation allowlist")
    deadline = time.monotonic() + seconds
    todo, visited, screens = collections.deque([()]), set(), []
    while todo and len(screens) < max_screens and time.monotonic() < deadline:
        path = todo.popleft()
        try:
            if path:
                navigate(udid, bundle_id, path, out, deadline)
            screen, signature = capture_screen(udid, out, 'screen-%03d' % len(screens), deadline, authenticated, allowed)
            if signature in visited:
                continue
            visited.add(signature); screen['path'] = list(path)
            for action in screen['actions']:
                action['safe_to_tap'] = safe_to_tap(action['label'], allowed)
            screens.append(screen)
            if len(path) < 4:
                for action in screen['actions']:
                    if action['safe_to_tap'] and action['label'] not in path:
                        todo.append(path + (action['label'],))
        except (OSError, subprocess.SubprocessError, ValueError):
            continue
    return screens


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--screens', type=pathlib.Path)
    parser.add_argument('--out', required=True, type=pathlib.Path)
    parser.add_argument('--repo', type=pathlib.Path)
    parser.add_argument('--udid'); parser.add_argument('--bundle-id')
    parser.add_argument('--authorized-navigation', type=pathlib.Path)
    parser.add_argument('--authenticated', action='store_true')
    parser.add_argument('--max-screens', type=int, default=25)
    parser.add_argument('--seconds', type=int, default=360)
    args = parser.parse_args()
    if bool(args.screens) == bool(args.udid) or not 1 <= args.max_screens <= 25 or not 1 <= args.seconds <= 360:
        parser.error('choose screens or owned device and bounded budgets')
    out = args.out.resolve()
    if args.repo and (out == args.repo.resolve() or args.repo.resolve() in out.parents):
        parser.error('--out must be outside --repo')
    out.mkdir(parents=True, exist_ok=True)
    if args.screens:
        screens = []
        for path in sorted(args.screens.glob('*.json'))[:args.max_screens]:
            try:
                screens.append(summarize(json.loads(path.read_text()), path.stem))
            except (OSError, ValueError):
                continue
    else:
        authorization = json.loads(args.authorized_navigation.read_text()) if args.authorized_navigation else None
        screens = live_explore(args.udid, args.bundle_id, out, args.max_screens, args.seconds, authorization, args.authenticated)
    report = {'schema_version': 1, 'screens': screens, 'checks': evaluate(screens, {}),
              'screen_budget': args.max_screens, 'time_budget_seconds': args.seconds}
    _safe_write.write_text(out / 'screen-inventory.json', json.dumps(report, indent=2) + '\n')
    print(json.dumps(report)); return 0


if __name__ == '__main__':
    raise SystemExit(main())
