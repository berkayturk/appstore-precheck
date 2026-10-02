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

class ApiError(Exception):
    """An unavailable, unauthorized, incomplete, or malformed API response."""

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

def collect_info(api, app, out, info_id=None, version_id=None, bundle_id=None, version_string=None, build_number=None):
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


def collect_version(api, app, out, info_id=None, version_id=None, bundle_id=None, version_string=None, build_number=None):
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


def collect_products(api, app, out, info_id=None, version_id=None, bundle_id=None, version_string=None, build_number=None):
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


def collect_asc(api, app_id, version_id=None, info_id=None, bundle_id=None, version_string=None, build_number=None):
    app = '/v1/apps/' + encode_id(app_id)
    out = {'app': safe(api, 'get', app)}
    collect_info(api, app, out, info_id=info_id)
    collect_version(api, app, out, version_id=version_id, bundle_id=bundle_id, version_string=version_string, build_number=build_number)
    collect_products(api, app, out)
    out['price'] = safe(api, 'get', app + '/appPriceSchedule')
    out['availability'] = safe(api, 'get', app + '/appAvailabilityV2')
    available = one(out['availability'])
    if available and identifier(available):
        out['territories'] = safe(api, 'items', '/v2/appAvailabilities/' + encode_id(identifier(available)) + '/territoryAvailabilities')
    return out
