#!/usr/bin/env python3
"""Read local store metadata and optional App Store Connect GET resources.

The JSON output carries presence and review decisions only. It never contains API
keys, demo credentials, raw review notes, URLs, or product names.
"""
import argparse
import base64
import ipaddress
import json
import os
import pathlib
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


API_BASE = "https://api.appstoreconnect.apple.com"
CHECKS = (
    "meta-age-rating", "meta-review-notes", "meta-demo-account",
    "meta-iap-review-notes", "meta-iap-screenshot", "meta-privacy-url",
    "meta-support-url", "meta-category", "meta-price", "meta-storefront",
    "meta-screenshots",
)


class ApiError(Exception):
    """An unavailable, unauthorized, incomplete, or malformed API response."""


def record(check_id, status, reason, evidence=None):
    return {"check_id": check_id, "status": status, "evidence_class": "metadata",
            "reason": reason, "evidence": evidence or []}


def b64url(raw):
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def der_to_jose(raw):
    """Convert OpenSSL ECDSA DER signature to the 64-byte JWT R||S format."""
    def length(offset):
        if offset >= len(raw):
            raise ApiError("JWT signature encoding unavailable")
        n = raw[offset]
        if n < 128:
            return n, offset + 1
        width = n & 127
        if not width or width > 2 or offset + 1 + width > len(raw):
            raise ApiError("JWT signature encoding unavailable")
        return int.from_bytes(raw[offset + 1:offset + 1 + width], "big"), offset + 1 + width

    if not raw or raw[0] != 0x30:
        raise ApiError("JWT signature encoding unavailable")
    total, at = length(1)
    if at + total != len(raw):
        raise ApiError("JWT signature encoding unavailable")
    values = []
    for _ in range(2):
        if at >= len(raw) or raw[at] != 0x02:
            raise ApiError("JWT signature encoding unavailable")
        size, at = length(at + 1)
        value = int.from_bytes(raw[at:at + size], "big")
        at += size
        if value <= 0 or value >= (1 << 256):
            raise ApiError("JWT signature encoding unavailable")
        values.append(value.to_bytes(32, "big"))
    if at != len(raw):
        raise ApiError("JWT signature encoding unavailable")
    return b"".join(values)


def make_jwt(key_id, issuer_id, key_path):
    if not shutil.which("openssl"):
        raise ApiError("openssl unavailable; install OpenSSL to inspect App Store Connect")
    if not pathlib.Path(key_path).is_file():
        raise ApiError("ASC_KEY_PATH file unavailable")
    now = int(time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {"iss": issuer_id, "iat": now, "exp": now + 600,
               "aud": "appstoreconnect-v1"}
    compact = ".".join(b64url(json.dumps(x, separators=(",", ":")).encode("utf-8"))
                       for x in (header, payload))
    try:
        signed = subprocess.run(["openssl", "dgst", "-sha256", "-sign", key_path],
                                input=compact.encode("ascii"), stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, timeout=10, check=False)
    except (OSError, subprocess.TimeoutExpired):
        raise ApiError("JWT signing unavailable")
    if signed.returncode != 0:
        raise ApiError("JWT signing unavailable")
    return compact + "." + b64url(der_to_jose(signed.stdout))


class ASC:
    def __init__(self, fixture=None):
        self.fixture = fixture
        self.token = None
        if fixture is None:
            key_id = os.environ.get("ASC_KEY_ID")
            issuer_id = os.environ.get("ASC_ISSUER_ID")
            key_path = os.environ.get("ASC_KEY_PATH")
            if not all((key_id, issuer_id, key_path)):
                raise ApiError("ASC_KEY_ID, ASC_ISSUER_ID, and ASC_KEY_PATH are required")
            self.token = make_jwt(key_id, issuer_id, key_path)

    def get(self, path):
        if not path.startswith("/v1/") and not path.startswith("/v2/"):
            raise ApiError("Unsupported App Store Connect resource")
        if self.fixture is not None:
            value = self.fixture.get("responses", {}).get(path)
            if not isinstance(value, dict):
                raise ApiError("Fixture API resource unavailable")
            return value
        request = urllib.request.Request(API_BASE + path,
                                         headers={"Authorization": "Bearer " + self.token,
                                                  "Accept": "application/json"}, method="GET")
        try:
            with urllib.request.build_opener(NoRedirect()).open(request, timeout=12) as response:
                if response.status != 200:
                    raise ApiError("App Store Connect request unavailable")
                raw = response.read(4 * 1024 * 1024 + 1)
                if len(raw) > 4 * 1024 * 1024:
                    raise ApiError("App Store Connect response too large")
                value = json.loads(raw.decode("utf-8"))
                if not isinstance(value, dict):
                    raise ValueError("not an object")
                return value
        except (urllib.error.URLError, OSError, ValueError, UnicodeError):
            raise ApiError("App Store Connect request unavailable")

    def items(self, path):
        result = []
        next_path = path
        for _ in range(10):
            value = self.get(next_path)
            data = value.get("data")
            if not isinstance(data, list):
                raise ApiError("App Store Connect list unavailable")
            result.extend(data)
            links = value.get("links")
            next_url = links.get("next") if isinstance(links, dict) else None
            if not next_url:
                return result
            parsed = urllib.parse.urlparse(next_url)
            if parsed.scheme != "https" or parsed.netloc != "api.appstoreconnect.apple.com":
                raise ApiError("Unexpected App Store Connect pagination URL")
            next_path = parsed.path + ("?" + parsed.query if parsed.query else "")
        raise ApiError("App Store Connect list exceeded page budget")


def safe(api, method, path):
    try:
        return getattr(api, method)(path)
    except ApiError as exc:
        return exc


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        raise urllib.error.URLError("App Store Connect redirect refused")


def one(data):
    return data.get("data") if isinstance(data, dict) else None


def attrs(item):
    return item.get("attributes", {}) if isinstance(item, dict) else {}


def relation(item, name):
    relationships = item.get("relationships") if isinstance(item, dict) else None
    value = relationships.get(name) if isinstance(relationships, dict) else None
    return value.get("data") if isinstance(value, dict) else None


def identifier(item):
    return item.get("id") if isinstance(item, dict) else None


def encode_id(value):
    return urllib.parse.quote(str(value), safe="")


def collect_asc(api, app_id, version_id=None, info_id=None):
    """Fetch only documented GET routes. Each field retains its own failure."""
    app = "/v1/apps/" + encode_id(app_id)
    out = {}
    infos = safe(api, "items", app + "/appInfos")
    if isinstance(infos, ApiError):
        out["info"] = infos
    else:
        info = next((x for x in infos if identifier(x) == info_id), None) if info_id else (infos[0] if infos else None)
        out["info"] = info
        if info:
            path = "/v1/appInfos/" + encode_id(identifier(info))
            out["age"] = safe(api, "get", path + "/ageRatingDeclaration")
            out["info_localizations"] = safe(api, "items", path + "/appInfoLocalizations")
    versions = safe(api, "items", app + "/appStoreVersions")
    if isinstance(versions, ApiError):
        out["version"] = versions
    else:
        ios = [x for x in versions if attrs(x).get("platform") == "IOS"]
        if version_id:
            version = next((x for x in ios if identifier(x) == version_id), None)
        else:
            preferred = [x for x in ios if attrs(x).get("appStoreState") in
                         ("PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW", "REJECTED", "METADATA_REJECTED")]
            version = max(preferred or ios, key=lambda x: attrs(x).get("createdDate", "")) if ios else None
        out["version"] = version
        if version:
            path = "/v1/appStoreVersions/" + encode_id(identifier(version))
            out["review"] = safe(api, "get", path + "/appStoreReviewDetail")
            locs = safe(api, "items", path + "/appStoreVersionLocalizations")
            out["version_localizations"] = locs
            if isinstance(locs, list):
                screenshots = []
                for loc in locs:
                    loc_id = identifier(loc)
                    if not loc_id:
                        continue
                    sets = safe(api, "items", "/v1/appStoreVersionLocalizations/" + encode_id(loc_id) + "/appScreenshotSets")
                    if isinstance(sets, ApiError):
                        screenshots.append(sets)
                    else:
                        for image_set in sets:
                            set_id = identifier(image_set)
                            if set_id:
                                screenshots.append(safe(api, "items", "/v1/appScreenshotSets/" + encode_id(set_id) + "/appScreenshots"))
                out["screenshots"] = screenshots
    purchases = safe(api, "items", app + "/inAppPurchasesV2")
    groups = safe(api, "items", app + "/subscriptionGroups")
    if isinstance(groups, list):
        subscriptions = []
        for group in groups:
            gid = identifier(group)
            if gid:
                items = safe(api, "items", "/v1/subscriptionGroups/" + encode_id(gid) + "/subscriptions")
                if isinstance(items, ApiError):
                    subscriptions = items
                    break
                subscriptions.extend(items)
        out["subscriptions"] = subscriptions
    else:
        out["subscriptions"] = groups
    out["purchases"] = purchases
    if isinstance(purchases, list) and isinstance(out["subscriptions"], list):
        shots = []
        for product in purchases:
            pid = identifier(product)
            if pid:
                shots.append(safe(api, "get", "/v2/inAppPurchases/" + encode_id(pid) + "/appStoreReviewScreenshot"))
        for product in out["subscriptions"]:
            pid = identifier(product)
            if pid:
                shots.append(safe(api, "get", "/v1/subscriptions/" + encode_id(pid) + "/appStoreReviewScreenshot"))
        out["iap_screenshots"] = shots
    out["price"] = safe(api, "get", app + "/appPriceSchedule")
    out["availability"] = safe(api, "get", app + "/appAvailabilityV2")
    available = one(out["availability"])
    if available and identifier(available):
        out["territories"] = safe(api, "items", "/v2/appAvailabilities/" +
                                  encode_id(identifier(available)) + "/territoryAvailabilities")
    return out


def local_text(root, relative):
    try:
        path = root / relative
        if path.is_file() and path.stat().st_size <= 64 * 1024:
            return path.read_text(encoding="utf-8").strip()
    except (OSError, UnicodeError):
        return None
    return None


def local_review(root, name):
    value = local_text(root, "review_information/" + name + ".txt")
    if value is not None:
        return value
    legacy = {"notes": "review_notes", "demo_user": "review_demo_user",
              "demo_password": "review_demo_password"}.get(name)
    return local_text(root, "review_information/" + legacy + ".txt") if legacy else None


def local_urls(root, name):
    locales = [x for x in root.iterdir() if x.is_dir() and x.name != "review_information"] if root.is_dir() else []
    return [local_text(loc, name + ".txt") for loc in locales]


def valid_url(value):
    if not isinstance(value, str):
        return False
    parsed = urllib.parse.urlparse(value.strip())
    return parsed.scheme in ("https", "http") and bool(parsed.hostname) and not parsed.username and not parsed.password


def public_url(value):
    if not valid_url(value):
        return False
    host = urllib.parse.urlparse(value).hostname
    try:
        addrs = socket.getaddrinfo(host, None)
    except (OSError, ValueError):
        return False
    return bool(addrs) and all(ipaddress.ip_address(x[4][0]).is_global for x in addrs)


class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        if not public_url(newurl):
            raise urllib.error.URLError("Unsafe redirect")
        return super().redirect_request(request, fp, code, msg, headers, newurl)


def head_reachable(value):
    if not public_url(value):
        return False
    request = urllib.request.Request(value, method="HEAD", headers={"User-Agent": "appstore-precheck/metadata-review"})
    try:
        with urllib.request.build_opener(SafeRedirect()).open(request, timeout=8) as response:
            return 200 <= response.status < 400
    except (urllib.error.URLError, OSError, ValueError):
        return False


def unavailable(check_id, source, reason):
    return record(check_id, "SKIP" if source else "NOT_RUN", reason)


def review(args, asc):
    metadata = pathlib.Path(args.metadata_dir) if args.metadata_dir else pathlib.Path(args.repo) / "fastlane" / "metadata"
    screenshots = pathlib.Path(args.repo) / "fastlane" / "screenshots"
    local = metadata.is_dir()
    asc_on = asc is not None
    results = []

    age = asc.get("age") if asc_on else None
    if isinstance(age, ApiError):
        results.append(unavailable(CHECKS[0], True, "Age rating declaration could not be read from App Store Connect"))
    elif asc_on and any(value is not None for value in attrs(one(age)).values()):
        results.append(record(CHECKS[0], "PASS", "Age rating declaration responses are present"))
    elif asc_on and isinstance(asc.get("info"), ApiError):
        results.append(unavailable(CHECKS[0], True, "App info could not be read from App Store Connect"))
    elif asc_on:
        results.append(record(CHECKS[0], "NEEDS_REVIEW", "Age rating declaration is absent or empty"))
    else:
        results.append(unavailable(CHECKS[0], False, "Age rating declaration needs opt-in App Store Connect access"))

    review_data = asc.get("review") if asc_on else None
    notes = attrs(one(review_data)).get("notes") if asc_on and not isinstance(review_data, ApiError) else local_review(metadata, "notes")
    if isinstance(review_data, ApiError) and notes is None:
        results.append(unavailable(CHECKS[1], True, "App Review details could not be read"))
    elif notes is None and not local and not asc_on:
        results.append(unavailable(CHECKS[1], False, "No fastlane metadata or App Store Connect review details"))
    else:
        results.append(record(CHECKS[1], "PASS" if bool(notes) else "NEEDS_REVIEW",
                              "App Review notes are present" if notes else "App Review notes are empty or absent"))

    required = args.login_required or (attrs(one(review_data)).get("demoAccountRequired") is True if asc_on and not isinstance(review_data, ApiError) else False)
    user = attrs(one(review_data)).get("demoAccountName") if asc_on and not isinstance(review_data, ApiError) else local_review(metadata, "demo_user")
    password = attrs(one(review_data)).get("demoAccountPassword") if asc_on and not isinstance(review_data, ApiError) else local_review(metadata, "demo_password")
    if isinstance(review_data, ApiError) and user is None and password is None:
        results.append(unavailable(CHECKS[2], True, "Demo account fields could not be read"))
    elif not required and not user and not password:
        results.append(unavailable(CHECKS[2], bool(asc_on or local), "Login requirement unknown; demo account applicability needs review"))
    else:
        results.append(record(CHECKS[2], "PASS" if user and password else "NEEDS_REVIEW",
                              "Demo account fields are both present" if user and password else "Demo account name or password is missing"))

    products = asc.get("purchases") if asc_on else None
    subs = asc.get("subscriptions") if asc_on else None
    if isinstance(products, ApiError) or isinstance(subs, ApiError):
        for check_id in CHECKS[3:5]:
            results.append(unavailable(check_id, True, "In-app purchase resources could not be read"))
    elif asc_on and isinstance(products, list) and isinstance(subs, list):
        all_products = products + subs
        if not all_products:
            for check_id in CHECKS[3:5]:
                results.append(unavailable(check_id, True, "No in-app purchases were returned; applicability not established"))
        else:
            notes_ok = all(bool(attrs(x).get("reviewNote")) for x in all_products)
            results.append(record(CHECKS[3], "PASS" if notes_ok else "NEEDS_REVIEW",
                                  "Review notes are present for returned purchases" if notes_ok else "At least one purchase lacks review notes"))
            shots = asc.get("iap_screenshots")
            if not isinstance(shots, list) or any(isinstance(x, ApiError) for x in shots):
                results.append(unavailable(CHECKS[4], True, "Purchase review screenshots could not all be read"))
            else:
                shots_ok = len(shots) == len(all_products) and all(one(x) for x in shots)
                results.append(record(CHECKS[4], "PASS" if shots_ok else "NEEDS_REVIEW",
                                      "Review screenshots are present for returned purchases" if shots_ok else "At least one purchase lacks a review screenshot"))
    else:
        for check_id in CHECKS[3:5]:
            results.append(unavailable(check_id, False, "Purchase review metadata needs opt-in App Store Connect access"))

    info_locs = asc.get("info_localizations") if asc_on else None
    version_locs = asc.get("version_localizations") if asc_on else None
    url_sources = (
        (CHECKS[5], info_locs, "privacyPolicyUrl", local_urls(metadata, "privacy_url")),
        (CHECKS[6], version_locs, "supportUrl", local_urls(metadata, "support_url")),
    )
    for check_id, remote, field, local_values in url_sources:
        if isinstance(remote, list):
            values = [attrs(x).get(field) for x in remote]
        else:
            values = local_values
        if isinstance(remote, ApiError) and not values:
            results.append(unavailable(check_id, True, "Store URL fields could not be read"))
        elif not values and not local and not asc_on:
            results.append(unavailable(check_id, False, "Store URL fields unavailable"))
        elif not values or not all(valid_url(x) for x in values):
            results.append(record(check_id, "NEEDS_REVIEW", "A required localized URL is absent or invalid"))
        elif args.check_urls and not all(head_reachable(x) for x in values):
            results.append(record(check_id, "NEEDS_REVIEW", "An opt-in HEAD request did not confirm URL reachability"))
        else:
            results.append(record(check_id, "PASS", "Localized URL fields are present and well-formed" +
                                  ("; HEAD reachability confirmed" if args.check_urls else "; reachability not checked")))

    info = asc.get("info") if asc_on else None
    category = relation(info, "primaryCategory") if isinstance(info, dict) else None
    if not category:
        category = local_text(metadata, "primary_category.txt")
    if isinstance(info, ApiError) and category is None:
        results.append(unavailable(CHECKS[7], True, "Primary category could not be read"))
    elif not local and not asc_on:
        results.append(unavailable(CHECKS[7], False, "Primary category metadata unavailable"))
    else:
        results.append(record(CHECKS[7], "PASS" if category else "NEEDS_REVIEW",
                              "Primary category is set" if category else "Primary category is absent"))

    for check_id, key in ((CHECKS[8], "price"), (CHECKS[9], "availability")):
        value = asc.get(key) if asc_on else None
        if isinstance(value, ApiError):
            results.append(unavailable(check_id, True, "Store pricing or availability could not be read"))
        elif not asc_on:
            results.append(unavailable(check_id, False, "Pricing and storefront need opt-in App Store Connect access"))
        elif check_id == CHECKS[8]:
            schedule = one(value)
            ok = bool(schedule and relation(schedule, "baseTerritory") and relation(schedule, "manualPrices"))
            results.append(record(check_id, "PASS" if ok else "NEEDS_REVIEW",
                                  "Price schedule, base territory, and manual price are configured" if ok else "Price schedule or base price configuration is absent"))
        else:
            territories = asc.get("territories")
            if isinstance(territories, ApiError):
                results.append(unavailable(check_id, True, "Territory availability could not be read"))
            else:
                ok = isinstance(territories, list) and any(attrs(x).get("available") is True for x in territories)
                results.append(record(check_id, "PASS" if ok else "NEEDS_REVIEW",
                                      "At least one storefront is marked available" if ok else "No available storefront was confirmed"))

    remote_shots = asc.get("screenshots") if asc_on else None
    if isinstance(remote_shots, list) and remote_shots:
        if any(isinstance(x, ApiError) for x in remote_shots):
            results.append(unavailable(CHECKS[10], True, "Store screenshots could not all be read"))
        else:
            ok = any(isinstance(x, list) and x for x in remote_shots)
            results.append(record(CHECKS[10], "PASS" if ok else "NEEDS_REVIEW",
                                  "Store screenshots are present" if ok else "Store screenshot sets contain no images"))
    elif isinstance(version_locs, list):
        results.append(record(CHECKS[10], "NEEDS_REVIEW", "Store screenshots are absent from returned localizations"))
    else:
        images = [x for x in screenshots.rglob("*") if x.is_file() and x.suffix.lower() in (".png", ".jpg", ".jpeg")] if screenshots.is_dir() else []
        if images:
            results.append(record(CHECKS[10], "PASS", "Local fastlane screenshots are present"))
        elif screenshots.is_dir():
            results.append(record(CHECKS[10], "NEEDS_REVIEW", "Local fastlane screenshot directory has no images"))
        else:
            results.append(unavailable(CHECKS[10], asc_on, "No readable store screenshot source"))

    assert [x["check_id"] for x in results] == list(CHECKS)
    return results


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=".", help="Read-only project root")
    parser.add_argument("--metadata-dir", help="Optional fastlane metadata directory")
    parser.add_argument("--asc-app-id", help="Opt in to read-only App Store Connect GET requests")
    parser.add_argument("--asc-version-id", help="Choose an iOS App Store version")
    parser.add_argument("--asc-info-id", help="Choose an app info resource")
    parser.add_argument("--asc-fixture", help="Offline API response fixture for tests")
    parser.add_argument("--login-required", action="store_true", help="Assess demo credentials as required")
    parser.add_argument("--check-urls", action="store_true", help="Opt in to HEAD requests for public support/privacy URLs")
    parser.add_argument("--out", help="Write the sanitized JSON report to this path")
    args = parser.parse_args(argv)
    if args.asc_fixture and not args.asc_app_id:
        parser.error("--asc-fixture requires --asc-app-id")
    if args.asc_fixture and os.environ.get("APPSTORE_PRECHECK_TEST_MODE") != "1":
        parser.error("--asc-fixture is available only with APPSTORE_PRECHECK_TEST_MODE=1")
    asc = None
    if args.asc_app_id:
        try:
            fixture = json.loads(pathlib.Path(args.asc_fixture).read_text(encoding="utf-8")) if args.asc_fixture else None
            asc = collect_asc(ASC(fixture), args.asc_app_id, args.asc_version_id, args.asc_info_id)
        except (ApiError, OSError, ValueError, UnicodeError) as exc:
            asc = {key: ApiError("App Store Connect unavailable") for key in
                   ("age", "info", "review", "purchases", "subscriptions", "info_localizations",
                    "version_localizations", "price", "availability", "screenshots")}
    results = review(args, asc)
    summary = {s: sum(x["status"] == s for x in results) for s in
               ("PASS", "FINDING", "NEEDS_REVIEW", "SKIP", "NOT_RUN")}
    payload = {"schema_version": 1,
               "sources": {"fastlane_metadata": pathlib.Path(args.metadata_dir or pathlib.Path(args.repo) / "fastlane" / "metadata").is_dir(),
                           "app_store_connect_requested": bool(args.asc_app_id),
                           "app_store_connect_fixture": bool(args.asc_fixture),
                           "url_head_requested": bool(args.check_urls)},
               "results": results, "summary": summary}
    encoded = json.dumps(payload, indent=2, sort_keys=True) + "\n"
    if args.out:
        pathlib.Path(args.out).write_text(encoded, encoding="utf-8")
    sys.stdout.write(encoded)
    return 0


if __name__ == "__main__":
    sys.exit(main())
