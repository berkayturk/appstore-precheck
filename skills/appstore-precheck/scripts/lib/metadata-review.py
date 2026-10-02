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

SPEC = importlib.util.spec_from_file_location('asc_client', pathlib.Path(__file__).with_name('asc-client.py'))
CLIENT = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(CLIENT)
ApiError, ASC, collect_asc = CLIENT.ApiError, CLIENT.ASC, CLIENT.collect_asc
attrs, one, relation = CLIENT.attrs, CLIENT.one, CLIENT.relation
CHECKS = (
    "meta-age-rating", "meta-review-notes", "meta-demo-account",
    "meta-iap-review-notes", "meta-iap-screenshot", "meta-privacy-url",
    "meta-support-url", "meta-category", "meta-price", "meta-storefront",
    "meta-screenshots",
)

def record(check_id, status, reason, evidence=None):
    return {"check_id": check_id, "status": status, "evidence_class": "metadata",
            "reason": reason, "evidence": evidence or []}

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
    locales = [x for x in root.iterdir() if x.is_dir() and x.name not in {"review_information", "trade_representative_contact_information", "default"}] if root.is_dir() else []
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
        addresses = [ipaddress.ip_address(x[4][0]) for x in infos]
        nat64 = ipaddress.ip_network("64:ff9b::/96")
        if infos and all(address.is_global and address not in nat64 for address in addresses):
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

def review_part_0(args, asc, metadata, results):
    local, asc_on = metadata.is_dir(), asc is not None
    screenshots = metadata.parent / "screenshots"
    age = asc.get("age") if asc_on else None
    if isinstance(age, ApiError):
        results.append(unavailable(CHECKS[0], True, "Age rating declaration could not be read from App Store Connect"))
    elif asc_on and any(value is not None for value in attrs(one(age)).values()):
        results.append(record(CHECKS[0], "NEEDS_REVIEW", "Age rating declaration responses are present; present, unverified"))
    elif asc_on and isinstance(asc.get("info"), ApiError):
        results.append(unavailable(CHECKS[0], True, "App info could not be read from App Store Connect"))
    elif asc_on:
        results.append(record(CHECKS[0], "NEEDS_REVIEW", "Age rating declaration is absent or empty"))
    else:
        results.append(unavailable(CHECKS[0], False, "Age rating declaration needs opt-in App Store Connect access"))



def review_part_1(args, asc, metadata, results):
    local, asc_on = metadata.is_dir(), asc is not None
    screenshots = metadata.parent / "screenshots"
    review_data = asc.get("review") if asc_on else None
    notes = attrs(one(review_data)).get("notes") if asc_on and not isinstance(review_data, ApiError) else (None if asc_on else local_review(metadata, "notes"))
    if isinstance(review_data, ApiError) and notes is None:
        results.append(unavailable(CHECKS[1], True, "App Review details could not be read"))
    elif notes is None and not local and not asc_on:
        results.append(unavailable(CHECKS[1], False, "No fastlane metadata or App Store Connect review details"))
    else:
        results.append(record(CHECKS[1], "NEEDS_REVIEW",
                              "App Review notes are present; present, unverified" if notes else "App Review notes are empty or absent"))

    required = args.login_required or (attrs(one(review_data)).get("demoAccountRequired") is True if asc_on and not isinstance(review_data, ApiError) else False)
    user = attrs(one(review_data)).get("demoAccountName") if asc_on and not isinstance(review_data, ApiError) else (None if asc_on else local_review(metadata, "demo_user"))
    password = attrs(one(review_data)).get("demoAccountPassword") if asc_on and not isinstance(review_data, ApiError) else (None if asc_on else local_review(metadata, "demo_password"))
    if isinstance(review_data, ApiError) and user is None and password is None:
        results.append(unavailable(CHECKS[2], True, "Demo account fields could not be read"))
    elif not required and not user and not password:
        results.append(unavailable(CHECKS[2], bool(asc_on or local), "Login requirement unknown; demo account applicability needs review"))
    else:
        results.append(record(CHECKS[2], "NEEDS_REVIEW",
                              "Demo account fields are both present; present, unverified" if user and password else "Demo account name or password is missing"))



def review_part_2(args, asc, metadata, results):
    local, asc_on = metadata.is_dir(), asc is not None
    screenshots = metadata.parent / "screenshots"
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
            results.append(record(CHECKS[3], "NEEDS_REVIEW",
                                  "Review notes are present for returned purchases; present, unverified" if notes_ok else "At least one purchase lacks review notes"))
            shots = asc.get("iap_screenshots")
            if not isinstance(shots, list) or any(isinstance(x, ApiError) for x in shots):
                results.append(unavailable(CHECKS[4], True, "Purchase review screenshots could not all be read"))
            else:
                shots_ok = len(shots) == len(all_products) and all(one(x) for x in shots)
                results.append(record(CHECKS[4], "NEEDS_REVIEW",
                                      "Review screenshots are present for returned purchases; present, unverified" if shots_ok else "At least one purchase lacks a review screenshot"))
    else:
        for check_id in CHECKS[3:5]:
            results.append(unavailable(check_id, False, "Purchase review metadata needs opt-in App Store Connect access"))



def review_part_3(args, asc, metadata, results):
    local, asc_on = metadata.is_dir(), asc is not None
    screenshots = metadata.parent / "screenshots"
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



def review_part_4(args, asc, metadata, results):
    local, asc_on = metadata.is_dir(), asc is not None
    screenshots = metadata.parent / "screenshots"
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



def review_part_5(args, asc, metadata, results):
    local, asc_on = metadata.is_dir(), asc is not None
    screenshots = metadata.parent / "screenshots"
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



def review_part_6(args, asc, metadata, results):
    local, asc_on = metadata.is_dir(), asc is not None
    screenshots = metadata.parent / "screenshots"
    version_locs = asc.get("version_localizations") if asc_on else None
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



def review(args, asc):
    metadata, results = local_metadata_dir(args), []
    for check in (review_part_0, review_part_1, review_part_2, review_part_3, review_part_4, review_part_5, review_part_6):
        check(args, asc, metadata, results)
    if [row['check_id'] for row in results] != list(CHECKS):
        raise ValueError('metadata review produced an incomplete check collection')
    return results


def arguments(argv):
    parser = argparse.ArgumentParser(description='Read-only metadata review')
    parser.add_argument('--repo', default='.')
    for name in ('metadata-dir', 'asc-app-id', 'asc-version-id', 'asc-info-id', 'bundle-id', 'version', 'build-number', 'asc-fixture', 'out'):
        parser.add_argument('--' + name)
    parser.add_argument('--login-required', action='store_true')
    parser.add_argument('--check-urls', action='store_true')
    args = parser.parse_args(argv)
    if args.asc_fixture and (not args.asc_app_id or os.environ.get('APPSTORE_PRECHECK_TEST_MODE') != '1'):
        parser.error('--asc-fixture requires --asc-app-id and APPSTORE_PRECHECK_TEST_MODE=1')
    if args.out:
        output = pathlib.Path(args.out).resolve()
        for root in (pathlib.Path(args.repo).resolve(), local_metadata_dir(args).resolve()):
            if output == root or root in output.parents:
                parser.error('output must be outside read-only metadata inputs')
    return args


def main(argv=None):
    args = arguments(argv); asc, error, api = None, None, None
    if args.asc_app_id:
        try:
            fixture = json.loads(pathlib.Path(args.asc_fixture).read_text()) if args.asc_fixture else None
            api = ASC(fixture)
            asc = collect_asc(api, args.asc_app_id, args.asc_version_id, args.asc_info_id, args.bundle_id, args.version, args.build_number)
        except (ApiError, OSError, ValueError, UnicodeError) as exc:
            error = ' '.join(str(exc).split())[:300]
            asc = {key: ApiError(error) for key in ('age', 'info', 'review', 'purchases', 'subscriptions', 'info_localizations', 'version_localizations', 'price', 'availability', 'screenshots')}
        finally:
            if api is not None:
                api.token = None
    results = review(args, asc)
    payload = {'schema_version': 1, 'results': results, 'asc_error': error,
               'summary': {s: sum(r['status'] == s for r in results) for s in ('PASS', 'NEEDS_REVIEW', 'SKIP', 'NOT_RUN')},
               'limitations': ['Presence is not accuracy, successful login, or a regional payment exemption.']}
    encoded = json.dumps(payload, indent=2) + '\n'
    if args.out:
        spec = importlib.util.spec_from_file_location('safe_write', pathlib.Path(__file__).with_name('safe_write.py'))
        writer = importlib.util.module_from_spec(spec); spec.loader.exec_module(writer)
        writer.write_text(args.out, encoded)
    sys.stdout.write(encoded); return 0


if __name__ == '__main__':
    raise SystemExit(main())
