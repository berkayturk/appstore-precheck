#!/usr/bin/env python3
"""Read-only Section 3 source/configuration leads; never assert business compliance."""
import argparse
import json
import os
import pathlib
import plistlib
import re
import sys


CHECKS = (
    "section3-payment-mechanisms", "section3-license-unlock", "section3-subscription-offer",
    "section3-external-entitlement", "section3-iap-catalog",
    "section3-random-item-odds", "section3-loan-terms",
)
SOURCE_SUFFIXES = {".swift", ".m", ".mm", ".h", ".kt", ".java", ".dart", ".js", ".jsx", ".ts", ".tsx", ".strings"}
EXCLUDE_DIRS = {".git", "node_modules", "Pods", "build", "DerivedData", ".build", ".dart_tool",
                "vendor", "test", "tests", "__tests__", "fixtures", "output", "out", "dist", "coverage"}
MAX_FILES = 4000
MAX_BYTES = 512 * 1024

PAYMENT = {
    "storekit": re.compile(r"\b(?:StoreKit|Product\.products\b|SKPaymentQueue|purchase\(\s*product)\b", re.I),
    "external_payment": re.compile(r"\b(?:Stripe|PayPal|Adyen|Braintree|openExternalCheckout|externalPurchase|checkoutUrl|checkoutURL)\b", re.I),
}
LICENSE = {"license_unlock": re.compile(r"\b(?:unlockWithLicenseKey|redeemLicense|licenseKey|activationCode|unlockWithToken)\b", re.I)}
OFFER = {
    "offer": re.compile(r"\b(?:subscription|subscribe|free trial|auto[ -]?renew(?:al|s)?|per month|per year)\b", re.I),
    "price": re.compile(r"(?:[$€£]\s?\d|\b\d+(?:[.,]\d{2})?\s?(?:USD|EUR|GBP)\b|\bprice\b)", re.I),
    "duration": re.compile(r"\b(?:\d+\s?(?:day|week|month|year)s?|weekly|monthly|annual(?:ly)?)\b", re.I),
    "renewal": re.compile(r"\b(?:auto[ -]?renew|renews?|recurring)\b", re.I),
    "cancellation": re.compile(r"\b(?:cancel|manage subscription)\b", re.I),
    "benefits": re.compile(r"\b(?:includes?|access|premium|features?|benefits?)\b", re.I),
    "terms": re.compile(r"\b(?:terms(?: of (?:use|service))?|privacy policy|EULA)\b", re.I),
}
RANDOM = {
    "random_purchase": re.compile(r"\b(?:buy|purchase|paid|price|iap)\b.{0,90}\b(?:loot\s?box|mystery\s?box|random\s?(?:item|reward|draw)|gacha)\b|\b(?:loot\s?box|mystery\s?box|gacha)\b.{0,90}\b(?:buy|purchase|paid|price|iap)\b", re.I),
    "odds": re.compile(r"\b(?:odds|probability|drop rate|chance)\b", re.I),
}
LOAN = {
    "loan": re.compile(r"\b(?:personal\s+loan|payday\s+loan|loan\s+offer|borrow\s+money)\b", re.I),
    "apr": re.compile(r"\b(?:APR|annual percentage rate|effective annual rate)\b", re.I),
    "fees": re.compile(r"\b(?:fee|fees|charges?)\b", re.I),
    "repayment": re.compile(r"\b(?:repay|repayment|payment deadline|due in \d+)\b", re.I),
}
EXTERNAL = re.compile(r"\b(?:openExternalCheckout|externalPurchase|checkoutUrl|checkoutURL|externalPurchaseLink)\b", re.I)
PAYMENT_SEEDS = ("storekit", "skpayment", "product.products", "purchase(", "stripe", "paypal",
                 "adyen", "braintree", "checkout", "externalpurchase")
LICENSE_SEEDS = ("license", "activationcode", "unlockwithtoken")
OFFER_SEEDS = ("subscription", "subscribe", "trial", "renew", "per month", "per year", "price",
               "$", "€", "£", "usd", "eur", "gbp", "day", "week", "month", "year", "annual",
               "cancel", "benefit", "premium", "feature", "access", "terms", "privacy policy", "eula")
RANDOM_SEEDS = ("buy", "purchase", "paid", "price", "iap", "loot", "mystery", "random", "gacha",
                "odds", "probability", "drop rate", "chance")
LOAN_SEEDS = ("loan", "borrow money", "apr", "annual percentage rate", "effective annual rate",
              "fee", "charge", "repay", "payment deadline", "due in")


def record(check_id, status, reason, evidence=None, facets=None):
    result = {"check_id": check_id, "status": status, "evidence_class": "source",
              "reason": reason, "evidence": evidence or []}
    if facets is not None:
        result["facets"] = facets
    return result


def files(root):
    count = 0
    for directory, dirs, names in os.walk(str(root), followlinks=False):
        dirs[:] = sorted(name for name in dirs if name not in EXCLUDE_DIRS and not name.startswith(".")
                         and not (pathlib.Path(directory) / name).is_symlink())
        for name in sorted(names):
            path = pathlib.Path(directory) / name
            if path.suffix.lower() not in SOURCE_SUFFIXES | {".entitlements", ".storekit"}:
                continue
            if path.is_symlink() or not path.is_file():
                continue
            try:
                if path.stat().st_size > MAX_BYTES:
                    continue
            except OSError:
                continue
            yield path, path.relative_to(root).as_posix()
            count += 1
            if count >= MAX_FILES:
                return


def collect(root):
    source, entitlements, products = [], [], []
    for path, rel in files(root):
        suffix = path.suffix.lower()
        try:
            if suffix in SOURCE_SUFFIXES:
                raw = path.read_text(encoding="utf-8", errors="replace")
                source.extend((rel, number, line[:1000])
                              for number, line in enumerate(raw.splitlines(), 1))
            elif suffix == ".entitlements":
                with path.open("rb") as stream:
                    value = plistlib.load(stream)
                if isinstance(value, dict):
                    entitlements.append((rel, value))
            elif suffix == ".storekit":
                value = json.loads(path.read_text(encoding="utf-8"))
                if isinstance(value, dict):
                    products.append((rel, value))
        except (OSError, ValueError, TypeError, OverflowError, plistlib.InvalidFileException):
            continue
    return source, entitlements, products


def hits(rows, pattern, signal, limit=8):
    found = []
    for path, number, line in rows:
        if pattern.search(line):
            found.append({"file": path, "line": number, "signal": signal})
            if len(found) >= limit:
                break
    return found


def narrow(rows, seeds):
    return [row for row in rows if any(seed in row[2].lower() for seed in seeds)]


def source_review(check_id, rows, patterns, gate, reason):
    found = {name: hits(rows, pattern, name) for name, pattern in patterns.items()}
    evidence = [entry for matches in found.values() for entry in matches]
    facets = {name: bool(matches) for name, matches in found.items()}
    if not gate(facets):
        return record(check_id, "SKIP", "No mapped source signal; applicability and remote content remain unknown")
    return record(check_id, "NEEDS_REVIEW", reason, evidence, facets)


def review_payment(rows):
    return source_review(CHECKS[0], rows, PAYMENT, lambda f: any(f.values()),
                         "Payment mechanism signals need product, storefront, entitlement, and actual checkout review")


def review_license(rows):
    return source_review(CHECKS[1], rows, LICENSE, lambda f: f["license_unlock"],
                         "License or activation based unlock needs review against the applicable in-app purchase requirement")


def review_offer(rows):
    return source_review(CHECKS[2], rows, OFFER, lambda f: f["offer"],
                         "Subscription or trial offer needs on-screen comparison of price, duration, renewal, benefits, and terms")


def review_entitlement(rows, entitlements):
    evidence = hits(rows, EXTERNAL, "external_checkout")
    for rel, value in entitlements:
        if any(("external-purchase" in key or "reader" in key) and bool(enabled)
               for key, enabled in value.items() if isinstance(key, str)):
            evidence.append({"file": rel, "signal": "entitlement"})
    facets = {"external_checkout": any(e["signal"] == "external_checkout" for e in evidence),
              "entitlement": any(e["signal"] == "entitlement" for e in evidence)}
    if not any(facets.values()):
        return record(CHECKS[3], "SKIP", "No mapped external purchase or entitlement signal")
    return record(CHECKS[3], "NEEDS_REVIEW",
                  "External purchase evidence requires the current entitlement contract and eligible storefront verification",
                  evidence[:16], facets)


def product_objects(catalog):
    """Read common StoreKit test-config shapes without treating them as ASC truth."""
    for key in ("products", "nonConsumableProducts", "nonRenewingSubscriptions"):
        direct = catalog.get(key, [])
        if isinstance(direct, list):
            for item in direct[:500]:
                if isinstance(item, dict):
                    yield item
    groups = catalog.get("subscriptionGroups", [])
    if isinstance(groups, list):
        for group in groups[:100]:
            if isinstance(group, dict) and isinstance(group.get("subscriptions"), list):
                for item in group["subscriptions"][:500]:
                    if isinstance(item, dict):
                        yield item


def review_catalog(catalogs):
    facets = {"product": False, "subscription": False, "price": False,
              "introductory_offer": False, "period_present": False, "short_period": False}
    evidence = []
    for rel, catalog in catalogs:
        found = False
        for product in product_objects(catalog):
            found = True
            facets["product"] = True
            facets["subscription"] |= "subscription" in str(product.get("type", "")).lower() or any(
                key in product for key in ("subscriptionPeriod", "recurringSubscriptionPeriod"))
            facets["price"] |= any(key in product for key in ("price", "displayPrice"))
            facets["introductory_offer"] |= any(key in product for key in ("introductoryOffer", "introductoryOffers"))
            period = product.get("recurringSubscriptionPeriod", product.get("subscriptionPeriod"))
            facets["period_present"] |= isinstance(period, str) and bool(period)
            if isinstance(period, str):
                days = re.fullmatch(r"P(\d+)D", period)
                if days and int(days.group(1)) < 7:
                    facets["short_period"] = True
                    evidence.append({"file": rel, "signal": "local_short_subscription_period"})
        if found:
            evidence.append({"file": rel, "signal": "local_storekit_product"})
    if not facets["product"]:
        return record(CHECKS[4], "SKIP", "No readable local StoreKit product; App Store Connect product state remains unknown")
    if not facets["subscription"]:
        return record(CHECKS[4], "SKIP", "No local subscription product; App Store Connect product state remains unknown")
    return record(CHECKS[4], "NEEDS_REVIEW",
                  "Local StoreKit configuration is test data; compare product type, period, price, and introductory terms with App Store Connect",
                  evidence[:16], facets)


def review_random(rows):
    return source_review(CHECKS[5], rows, RANDOM, lambda f: f["random_purchase"],
                         "Paid randomized items require actual pre-purchase odds and category disclosure review")


def review_loan(rows):
    return source_review(CHECKS[6], rows, LOAN, lambda f: f["loan"],
                         "Loan terms require displayed APR, fees, repayment timing, and territory-specific legal review")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=pathlib.Path, required=True)
    parser.add_argument("--format", choices=("json",), default="json")
    args = parser.parse_args()
    root = args.repo.resolve()
    if not root.is_dir():
        checks = [record(check_id, "NOT_RUN", "Repository directory unavailable") for check_id in CHECKS]
    else:
        rows, entitlements, catalogs = collect(root)
        checks = [review_payment(narrow(rows, PAYMENT_SEEDS)),
                  review_license(narrow(rows, LICENSE_SEEDS)),
                  review_offer(narrow(rows, OFFER_SEEDS)),
                  review_entitlement(narrow(rows, ("externalpurchase", "checkouturl", "openexternalcheckout")), entitlements),
                  review_catalog(catalogs), review_random(narrow(rows, RANDOM_SEEDS)),
                  review_loan(narrow(rows, LOAN_SEEDS))]
    json.dump({"schema_version": 1, "checks": checks}, sys.stdout, sort_keys=True)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
