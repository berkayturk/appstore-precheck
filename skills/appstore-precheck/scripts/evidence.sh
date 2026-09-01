#!/usr/bin/env bash
# evidence.sh — evidence-strength layer for scan.sh.
# Sourced by scan.sh (after findings.sh). Answers two questions the FAIL/WARN
# severity cannot: *what artifact was this read from*, and *who enforces it*.
# Bash 3.2 compatible: NO associative arrays (catalogues are case lookups).
#
# WHY THIS EXISTS
# ---------------
# Severity says how bad a finding is. It does not say how firmly it is
# established. Apple's automated validators run against the BUILT PRODUCT; this
# scanner reads a repository. A missing purpose string found by grepping .swift
# files is a real upload blocker *if that code ships* — and conditional
# compilation, `#if DEBUG`, unused targets, and files excluded from the shipping
# target can all make it not ship. Reporting that identically to a missing key in
# a checked-in Info.plist overstates the second-weakest evidence we have. This
# module makes the difference machine-readable instead of implicit.
#
# Prior art: the confidence taxonomy in dabodamjan/app-store-rejection-checker
# (MIT) makes the same validator-vs-reviewer distinction for an LLM auditor. This
# is the deterministic-scanner adaptation: labels are pinned per rule and gated by
# a completeness test, not decided per run.

# --- Closed vocabularies -------------------------------------------------------
# Evidence classes, ordered strongest -> weakest. "Strength" is how faithfully the
# artifact represents what actually ships:
#   metadata      fastlane/metadata/** — uploaded to App Store Connect verbatim.
#   manifest      Info.plist, *.entitlements, PrivacyInfo.xcprivacy — ship as authored.
#   resource      String Catalogs, screenshot assets — shipped/uploaded files.
#   build-setting project.pbxproj values — resolved per target AND per configuration,
#                 so a repo-level read is a proxy for what the archive was built with.
#   source        .swift/.m/.mm/.h greps — the weakest: presence in a file is not
#                 proof of presence in the shipping binary.
EVIDENCE_CLASSES="metadata manifest resource build-setting source"

# Confidence levels — who acts on the finding, and how deterministically:
#   validator-blocking  Apple's automated validation (upload or App Store Connect)
#                       blocks this. Mechanical, not a matter of opinion.
#   review-risk         A human reviewer rejects this pattern frequently. Well
#                       evidenced, but a person decides.
#   judgment-call       A heuristic signal. A reasonable reviewer could go either
#                       way, and a false positive is expected.
CONFIDENCE_LEVELS="validator-blocking review-risk judgment-call"

GUIDELINES_BASE_URL="https://developer.apple.com/app-store/review/guidelines/"

# rule_evidence <rule-id> -> evidence class, or "" if the rule is not catalogued.
#
# The class is the WEAKEST artifact the rule's CONCLUSION depends on, not the
# strongest one it happens to open. A parity check that reads Info.plist *and*
# greps source (e.g. "framework imported but no purpose string") is `source`: if
# the grep is wrong about what ships, the conclusion is wrong, however solid the
# plist read was. A rule may refine this for one finding with set_evidence.
rule_evidence() {
  case "$1" in
    # --- metadata: read from fastlane/metadata/**, uploaded to ASC verbatim ---
    competitor-mentions|metadata-char-limits|locale-metadata-parity) echo metadata ;;
    subscription-eula-metadata|support-privacy-url|placeholder-metadata) echo metadata ;;
    misleading-marketing|kids-wording|kids-ads-analytics|realmoney-gambling) echo metadata ;;
    metadata-pricing-language|saturated-category) echo metadata ;;

    # --- manifest: Info.plist / entitlements / PrivacyInfo, shipped as authored ---
    screentime-justification|export-compliance|ats-arbitrary-loads) echo manifest ;;
    keyboard-full-access|background-modes-unused|safari-extension) echo manifest ;;
    generic-purpose-string) echo manifest ;;

    # --- resource: String Catalogs and screenshot assets ---
    screenshots-per-locale|screenshot-dimensions) echo resource ;;
    trial-disclosure|autorenew-disclosure) echo resource ;;

    # --- build-setting: pbxproj values, resolved per target/configuration ---
    # LastUpgradeCheck is a proxy for the SDK the archive was actually built with,
    # which no repository read can establish.
    xcode-sdk-requirement) echo build-setting ;;

    # --- source: concluded from a code grep (weakest) ---
    privacy-manifest-parity|usage-description-crosscheck|att-usage) echo source ;;
    subscription-links-restore|private-api|min-functionality-nav|siwa-parity) echo source ;;
    external-purchase-link|tracking-sdk-no-att|analytics-privacyinfo-mismatch) echo source ;;
    thirdparty-payment-sdk|ugc-no-moderation|applepay-recurring-disclosure) echo source ;;
    custom-review-prompt|health-icloud-sync|vpn-networkextension|demo-account) echo source ;;
    executable-code-download|crypto-wallet-mining|webview-wrapper|remote-desktop) echo source ;;
    account-no-delete|mdm|permission-priming-cta|paywall-trial-emphasis) echo source ;;
    ai-provider-consent|paywall-urgency|rating-sentiment-gate|forced-login) echo source ;;
    push-marketing-optout) echo source ;;

    *) echo "" ;;
  esac
}

# rule_confidence <rule-id> -> confidence level, or "" if not catalogued.
#
# This is about the RULE, not about this run: does Apple's machinery block it, does
# a human reviewer reject it, or is it a hint. Rules whose own message calls itself
# a heuristic must never be graded above judgment-call.
rule_confidence() {
  case "$1" in
    # --- validator-blocking: Apple's machinery refuses the build or the submission ---
    # Missing purpose string / required-reason declaration / private API -> upload
    # validation. Metadata limits, missing localized metadata, missing screenshots,
    # missing support+privacy URL, unanswered export compliance -> App Store Connect
    # will not accept the submission. The SDK minimum is an upload floor.
    usage-description-crosscheck|privacy-manifest-parity|att-usage|private-api) echo validator-blocking ;;
    metadata-char-limits|locale-metadata-parity|screenshots-per-locale) echo validator-blocking ;;
    screenshot-dimensions|support-privacy-url|export-compliance) echo validator-blocking ;;
    xcode-sdk-requirement) echo validator-blocking ;;

    # --- review-risk: a person rejects this often ---
    competitor-mentions|subscription-links-restore|subscription-eula-metadata) echo review-risk ;;
    screentime-justification|siwa-parity|external-purchase-link|tracking-sdk-no-att) echo review-risk ;;
    analytics-privacyinfo-mismatch|placeholder-metadata|thirdparty-payment-sdk) echo review-risk ;;
    ugc-no-moderation|ats-arbitrary-loads|applepay-recurring-disclosure) echo review-risk ;;
    custom-review-prompt|misleading-marketing|kids-wording|keyboard-full-access) echo review-risk ;;
    health-icloud-sync|vpn-networkextension|demo-account|executable-code-download) echo review-risk ;;
    background-modes-unused|safari-extension|account-no-delete) echo review-risk ;;
    kids-ads-analytics|realmoney-gambling|trial-disclosure|autorenew-disclosure) echo review-risk ;;

    # --- judgment-call: heuristic signal, false positives expected ---
    min-functionality-nav|crypto-wallet-mining|webview-wrapper|remote-desktop) echo judgment-call ;;
    mdm|permission-priming-cta|paywall-trial-emphasis|metadata-pricing-language) echo judgment-call ;;
    generic-purpose-string|ai-provider-consent|paywall-urgency) echo judgment-call ;;
    rating-sentiment-gate|forced-login|push-marketing-optout) echo judgment-call ;;
    saturated-category) echo judgment-call ;;

    *) echo "" ;;
  esac
}

# needs_build_verification <evidence> <confidence> -> "true" | "false"
#
# DERIVED, never stored — so it cannot drift out of sync with the two catalogues.
# A validator-blocking claim is only established when the evidence reflects what
# ships. `source` and `build-setting` are pre-build indirections, so from them the
# same finding means "this WILL block the upload if it ships as-is" — true and
# actionable, but not yet confirmed. Non-validator findings never carry the
# qualifier: a human reviewer looks at the running app either way.
needs_build_verification() {
  local ev="${1:-}" cf="${2:-}"
  [[ "$cf" == "validator-blocking" ]] || { echo false; return; }
  case "$ev" in
    source|build-setting) echo true ;;
    *) echo false ;;
  esac
}

# evidence_label <evidence> <confidence> -> the one-line human-readable tag, or ""
# when the rule is unclassified (an unlabelled finding is honest; a guessed one is not).
evidence_label() {
  local ev="${1:-}" cf="${2:-}"
  [[ -n "$ev" && -n "$cf" ]] || { echo ""; return; }
  local out="evidence: $ev · $cf"
  [[ "$(needs_build_verification "$ev" "$cf")" == "true" ]] && out+=" · needs build verification"
  echo "$out"
}

# rules_with_evidence <class> -> the catalogued rule ids in that evidence class, one
# per line. Derived by asking rule_evidence about every slug in the findings.sh
# catalogue, so it can never disagree with the classification it reports on. Used to
# tell the user how many checks a missing artifact actually cost them, rather than
# hardcoding a number that rots the next time a rule is added.
rules_with_evidence() {
  local want="${1:-}" n slug
  [[ -n "$want" ]] || return 0
  command -v rule_slug >/dev/null 2>&1 || return 0
  for n in $(seq 1 54); do
    slug="$(rule_slug "$n")"
    [[ -n "$slug" ]] || continue
    [[ "$(rule_evidence "$slug")" == "$want" ]] && echo "$slug"
  done
  return 0
}

# guideline_url <guideline-number> -> deep link to that section, or "" if the
# token is not a guideline number. Apple anchors each section by its bare number
# (id="5.1.1"), so the link is derivable; parenthetical suffixes like 5.1.1(v)
# and 3.1.1(a) are not anchors and are trimmed to their numeric stem.
guideline_url() {
  local g="${1:-}" stem
  stem="$(printf '%s' "$g" | sed -E 's/\(.*$//')"
  [[ "$stem" =~ ^[1-5](\.[0-9]+)+$ ]] || { echo ""; return; }
  echo "${GUIDELINES_BASE_URL}#${stem}"
}
