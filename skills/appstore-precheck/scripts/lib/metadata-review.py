#!/usr/bin/env python3
"""Read local store metadata and optional App Store Connect GET resources.

The JSON output carries presence and review decisions only. It never contains API
keys, demo credentials, raw review notes, URLs, or product names.
"""
import argparse
import base64
import http.client
import ipaddress
import importlib.util
import json
import os
import pathlib
import shutil
import socket
import ssl
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
        if fixture is not None and (not isinstance(fixture, dict) or not isinstance(fixture.get("responses"), dict)):
            raise ApiError("Fixture API response collection malformed")
        self.fixture = fixture
        self.token = None
        self.responses = {}
        self.deadline = time.monotonic() + 120
        if fixture is None:
            key_id = os.environ.get("ASC_KEY_ID")
            issuer_id = os.environ.get("ASC_ISSUER_ID")
            key_path = os.environ.get("ASC_KEY_PATH")
            if not all((key_id, issuer_id, key_path)):
                raise ApiError("ASC_KEY_ID, ASC_ISSUER_ID, and ASC_KEY_PATH are required")
            self.token = make_jwt(key_id, issuer_id, key_path)

    def get(self, path):
        if time.monotonic() >= self.deadline:
            raise ApiError("App Store Connect collection deadline exceeded")
        value = self._get(path)
        self.responses[path] = value
        return value

    def _get(self, path):
        if not path.startswith("/v1/") and not path.startswith("/v2/"):
            raise ApiError("Unsupported App Store Connect resource")
        if self.fixture is not None:
            value = self.fixture.get("responses", {}).get(path)
            if not isinstance(value, dict):
                raise ApiError("Fixture API resource unavailable")
            if value.get("fixture_error") in ("authorization", "timeout"):
                raise ApiError("App Store Connect request unavailable")
            return value
        request = urllib.request.Request(API_BASE + path,
                                         headers={"Authorization": "Bearer " + self.token,
                                                  "Accept": "application/json"}, method="GET")
        try:
            with urllib.request.build_opener(NoRedirect()).open(request, timeout=max(0.1, min(12, self.deadline - time.monotonic()))) as response:
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
        seen = set()
        for _ in range(10):
            if next_path in seen:
                raise ApiError("App Store Connect pagination cycle")
            seen.add(next_path)
            value = self.get(next_path)
            data = value.get("data")
            if not isinstance(data, list) or any(not isinstance(x, dict) for x in data):
                raise ApiError("App Store Connect list unavailable")
            result.extend(data)
            links = value.get("links")
            next_url = links.get("next") if isinstance(links, dict) else None
            if not next_url:
                total = value.get("meta", {}).get("paging", {}).get("total") if isinstance(value.get("meta"), dict) and isinstance(value.get("meta", {}).get("paging"), dict) else None
                if total is not None and (type(total) is not int or total != len(result)):
                    raise ApiError("App Store Connect list incomplete")
                return result
            if not isinstance(next_url, str):
                raise ApiError("Malformed App Store Connect pagination URL")
            parsed = urllib.parse.urlparse(next_url)
            if parsed.scheme != "https" or parsed.netloc != "api.appstoreconnect.apple.com" or parsed.path != path.split("?", 1)[0] or parsed.fragment:
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
    value = item.get("attributes") if isinstance(item, dict) else None
    return value if isinstance(value, dict) else {}


def relation(item, name):
    relationships = item.get("relationships") if isinstance(item, dict) else None
    value = relationships.get(name) if isinstance(relationships, dict) else None
    return value.get("data") if isinstance(value, dict) else None


def identifier(item):
    return item.get("id") if isinstance(item, dict) else None


def encode_id(value):
    return urllib.parse.quote(str(value), safe="")


def collect_asc(api, app_id, version_id=None, info_id=None, bundle_id=None, version_string=None, build_number=None):
    """Fetch only documented GET routes. Each field retains its own failure."""
    app = "/v1/apps/" + encode_id(app_id)
    out = {"app": safe(api, "get", app)}
    infos = safe(api, "items", app + "/appInfos")
    if isinstance(infos, ApiError):
        out["info"] = infos
    else:
        matches = [x for x in infos if identifier(x) == info_id] if info_id else infos
        info = matches[0] if len(matches) == 1 and identifier(matches[0]) else None
        out["info"] = info or ApiError("App info selection missing or ambiguous")
        # Capture every info localization for conservative whole-listing name proof.
        for candidate in infos:
            if identifier(candidate):
                safe(api, "items", "/v1/appInfos/" + encode_id(identifier(candidate)) + "/appInfoLocalizations")
        if info:
            path = "/v1/appInfos/" + encode_id(identifier(info))
            out["age"] = safe(api, "get", path + "/ageRatingDeclaration")
            out["info_localizations"] = safe(api, "items", path + "/appInfoLocalizations")
    versions = safe(api, "items", app + "/appStoreVersions")
    if isinstance(versions, ApiError):
        out["version"] = versions
    else:
        ios = [x for x in versions if attrs(x).get("platform") == "IOS"]
        matches = [x for x in ios if (not version_id or identifier(x) == version_id) and
                   (not version_string or attrs(x).get("versionString") == version_string)]
        version = matches[0] if len(matches) == 1 and identifier(matches[0]) else None
        out["version"] = version or ApiError("App Store version selection missing or ambiguous")
        out["selection_status"] = "SELECTED" if version else "UNRESOLVED"
        if bundle_id and attrs(one(out["app"])).get("bundleId") != bundle_id:
            version = None
            out["version"] = ApiError("Bundle identity mismatch or unavailable")
            out["selection_status"] = "UNRESOLVED"
        if version:
            path = "/v1/appStoreVersions/" + encode_id(identifier(version))
            out["build"] = safe(api, "get", path + "/build")
            if build_number and attrs(one(out["build"])).get("version") != build_number:
                out["version"] = ApiError("Build identity mismatch or unavailable")
                out["selection_status"] = "UNRESOLVED"
                out["review"] = ApiError("Build selection unavailable")
                out["version_localizations"] = ApiError("Build selection unavailable")
                out["screenshots"] = ApiError("Build selection unavailable")
            else:
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
    if isinstance(out.get("version"), ApiError):
        for key in ("review", "version_localizations", "screenshots"):
            out[key] = ApiError("App Store version or build selection unavailable")
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


def checked_addresses(host, port):
    """Resolve once and return the address records only if every answer is global."""
    try:
        infos = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
        if infos and all(ipaddress.ip_address(x[4][0]).is_global for x in infos):
            return infos
    except (OSError, ValueError):
        pass
    return []


def public_url(value):
    """Cheap pre-check (used to vet redirect targets); the connection itself re-validates."""
    return valid_url(value) and bool(checked_addresses(urllib.parse.urlparse(value).hostname, None))


def connect_pinned(host, port, timeout):
    """Connect to an address from the SAME lookup that was validated.

    Resolving here, checking the answers, and dialling one of those answers closes the
    DNS-rebinding window: no second lookup can return a private address between the
    check and the connect. The hostname is kept for the Host header and TLS SNI.
    """
    last_error = OSError("URL host does not resolve to a public address")
    for family, socktype, proto, _canonical, sockaddr in checked_addresses(host, port):
        sock = socket.socket(family, socktype, proto)
        try:
            if timeout is not None and timeout is not getattr(socket, "_GLOBAL_DEFAULT_TIMEOUT", None):
                sock.settimeout(timeout)
            sock.connect(sockaddr)
            return sock
        except OSError as error:
            sock.close()
            last_error = error
    raise last_error


class PinnedHTTPConnection(http.client.HTTPConnection):
    def connect(self):
        self.sock = connect_pinned(self.host, self.port, self.timeout)


class PinnedHTTPSConnection(http.client.HTTPSConnection):
    def connect(self):
        sock = connect_pinned(self.host, self.port, self.timeout)
        self.sock = self._context.wrap_socket(sock, server_hostname=self.host)


class PinnedHTTPHandler(urllib.request.HTTPHandler):
    def http_open(self, request):
        return self.do_open(PinnedHTTPConnection, request)


class PinnedHTTPSHandler(urllib.request.HTTPSHandler):
    def https_open(self, request):
        return self.do_open(PinnedHTTPSConnection, request, context=ssl.create_default_context())


class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        if not public_url(newurl):
            raise urllib.error.URLError("Unsafe redirect")
        return super().redirect_request(request, fp, code, msg, headers, newurl)


def head_reachable(value):
    if not valid_url(value):
        return False
    request = urllib.request.Request(value, method="HEAD", headers={"User-Agent": "appstore-precheck/metadata-review"})
    # Environment proxies are disabled on purpose: a proxy would resolve the name
    # itself, so the address we validated would not be the one contacted.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), PinnedHTTPHandler,
                                         PinnedHTTPSHandler, SafeRedirect)
    try:
        with opener.open(request, timeout=8) as response:
            return 200 <= response.status < 400
    except (urllib.error.URLError, http.client.HTTPException, OSError, ValueError):
        return False


def unavailable(check_id, source, reason):
    return record(check_id, "SKIP" if source else "NOT_RUN", reason)


def local_metadata_dir(args):
    if args.metadata_dir:
        return pathlib.Path(args.metadata_dir)
    repo = pathlib.Path(args.repo)
    for path in (repo / "fastlane" / "metadata", repo / "ios" / "fastlane" / "metadata"):
        if path.is_dir():
            return path
    return repo / "fastlane" / "metadata"


def review(args, asc):
    metadata = local_metadata_dir(args)
    screenshots = metadata.parent / "screenshots"
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
    notes = attrs(one(review_data)).get("notes") if asc_on and not isinstance(review_data, ApiError) else (None if asc_on else local_review(metadata, "notes"))
    if isinstance(review_data, ApiError) and notes is None:
        results.append(unavailable(CHECKS[1], True, "App Review details could not be read"))
    elif notes is None and not local and not asc_on:
        results.append(unavailable(CHECKS[1], False, "No fastlane metadata or App Store Connect review details"))
    else:
        results.append(record(CHECKS[1], "PASS" if bool(notes) else "NEEDS_REVIEW",
                              "App Review notes are present" if notes else "App Review notes are empty or absent"))

    required = args.login_required or (attrs(one(review_data)).get("demoAccountRequired") is True if asc_on and not isinstance(review_data, ApiError) else False)
    user = attrs(one(review_data)).get("demoAccountName") if asc_on and not isinstance(review_data, ApiError) else (None if asc_on else local_review(metadata, "demo_user"))
    password = attrs(one(review_data)).get("demoAccountPassword") if asc_on and not isinstance(review_data, ApiError) else (None if asc_on else local_review(metadata, "demo_password"))
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
            values = [] if asc_on else local_values
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
    if not category and not asc_on:
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
    elif asc_on:
        results.append(unavailable(CHECKS[10], True, "Store screenshots could not be read for selected version"))
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
    parser.add_argument("--bundle-id", help="Expected ASC bundle identifier")
    parser.add_argument("--version", help="Expected App Store version string")
    parser.add_argument("--build-number", help="Expected attached build number")
    parser.add_argument("--verification-evidence-out", help="Private name-only ASC evidence output; requires exact target selectors")
    parser.add_argument("--asc-fixture", help="Offline API response fixture for tests")
    parser.add_argument("--login-required", action="store_true", help="Assess demo credentials as required")
    parser.add_argument("--check-urls", action="store_true", help="Opt in to HEAD requests for public support/privacy URLs")
    parser.add_argument("--out", help="Write the sanitized JSON report to this path")
    args = parser.parse_args(argv)
    if args.asc_fixture and not args.asc_app_id:
        parser.error("--asc-fixture requires --asc-app-id")
    if args.asc_fixture and os.environ.get("APPSTORE_PRECHECK_TEST_MODE") != "1":
        parser.error("--asc-fixture is available only with APPSTORE_PRECHECK_TEST_MODE=1")
    if args.verification_evidence_out and not all((args.asc_app_id, args.asc_version_id, args.bundle_id, args.version, args.build_number)):
        parser.error("--verification-evidence-out requires app/version IDs, bundle ID, version and build number")
    input_roots = [pathlib.Path(args.repo).resolve(), local_metadata_dir(args).resolve()]
    for output in (args.out, args.verification_evidence_out):
        if output:
            resolved = pathlib.Path(output).resolve()
            if any(resolved == root or root in resolved.parents for root in input_roots):
                parser.error("Metadata outputs must be outside the read-only input project")
    if args.out and args.verification_evidence_out and pathlib.Path(args.out).resolve() == pathlib.Path(args.verification_evidence_out).resolve():
        parser.error("Report and private evidence require separate output paths")
    asc = None
    api = None
    asc_status = "NOT_RUN"
    if args.asc_app_id:
        try:
            fixture = json.loads(pathlib.Path(args.asc_fixture).read_text(encoding="utf-8")) if args.asc_fixture else None
            api = ASC(fixture)
            asc_status = "FIXTURE" if args.asc_fixture else "ATTEMPTED"
            asc = collect_asc(api, args.asc_app_id, args.asc_version_id, args.asc_info_id, args.bundle_id, args.version, args.build_number)
        except (ApiError, OSError, ValueError, UnicodeError) as exc:
            asc = {key: ApiError("App Store Connect unavailable") for key in
                   ("age", "info", "review", "purchases", "subscriptions", "info_localizations",
                    "version_localizations", "price", "availability", "screenshots")}
    if api is not None:
        api.token = None
    results = review(args, asc)
    summary = {s: sum(x["status"] == s for x in results) for s in
               ("PASS", "FINDING", "NEEDS_REVIEW", "SKIP", "NOT_RUN")}
    payload = {"schema_version": 1,
               "sources": {"fastlane_metadata": local_metadata_dir(args).is_dir(),
                           "app_store_connect_requested": bool(args.asc_app_id),
                           "app_store_connect_fixture": bool(args.asc_fixture),
                           "app_store_connect_status": asc_status,
                           "url_head_requested": bool(args.check_urls)},
               "results": results, "summary": summary,
               "selection": {"status": asc.get("selection_status", "UNRESOLVED") if asc else "NOT_RUN",
                             "target_binding_requested": all((args.bundle_id, args.version, args.build_number))},
               "local_results": review(args, None) if asc else results,
               "limitations": ["Presence checks do not verify metadata accuracy, login success, price correctness or regional payment exceptions.",
                               "App privacy labels require separately supplied App Store Connect evidence; no privacy-label endpoint is assumed.",
                               "Local fastlane metadata is evaluated separately and cannot repair an unavailable ASC resource."]}
    if args.verification_evidence_out:
        path = pathlib.Path(__file__).with_name("verification-metadata.py")
        spec = importlib.util.spec_from_file_location("verification_metadata", path)
        verifier = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(verifier)
        proof = verifier.capture(api.responses if api else {}, args.asc_app_id, args.asc_version_id,
                                 bool(args.asc_fixture))
        # Create exclusively, mode 0600; never follow or overwrite a user file/symlink.
        try:
            fd = os.open(args.verification_evidence_out, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as stream:
                json.dump(proof, stream, indent=2, sort_keys=True)
                stream.write("\n")
        except OSError:
            parser.error("Private verification evidence output could not be created")
    encoded = json.dumps(payload, indent=2, sort_keys=True) + "\n"
    if args.out:
        try:
            pathlib.Path(args.out).write_text(encoded, encoding="utf-8")
        except OSError:
            parser.error("Sanitized report output could not be written")
    sys.stdout.write(encoded)
    return 0


if __name__ == "__main__":
    sys.exit(main())
