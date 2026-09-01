#!/usr/bin/env bash
# tests/test-dynamic-reconcile.sh — Phase 1 of the dynamic tier: the layer becomes
# machine-readable and honest WITHOUT running a simulator. Nothing here boots a
# device; the inputs are recorded DYNAMIC-* transcripts under
# tests/fixtures/dynamic-transcripts/ plus a static findings buffer produced by the
# real findings.sh code path.
#
# What is pinned:
#   findings.sh  — id / resolved_by / runtime_target / build_config fields; RESOLVED
#                  is structurally inert (never counted, never moves the verdict).
#   dynamic.sh   — transcript parsing; the reconciliation table, one case per row;
#                  the Debug guard (summary.needs_build_verification unchanged);
#                  SKIP carries no labels; the runtime-not-audited gap record.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=tests/_assert.sh
source "$HERE/_assert.sh"
S="$ROOT/skills/appstore-precheck/scripts"
DYN="$S/dynamic.sh"
TX="$HERE/fixtures/dynamic-transcripts"
# shellcheck source=skills/appstore-precheck/scripts/findings.sh
source "$S/findings.sh"
# shellcheck source=skills/appstore-precheck/scripts/evidence.sh
source "$S/evidence.sh"

# The static side is built through _record so every label is DERIVED by the real
# code, never typed into a fixture by hand.
make_static_a() { # the "risky" repo: two purpose strings missing, no demo account, no Restore button
  FINDINGS_TMP="$1"; : > "$FINDINGS_TMP"
  set_rule "usage-description-crosscheck"
  _record FAIL "5.1.1 camera capture API used but Info.plist is missing NSCameraUsageDescription" "App/Cam.swift" "12"
  _record FAIL "5.1.1 microphone capture API used but Info.plist is missing NSMicrophoneUsageDescription" "App/Mic.swift" "40"
  set_rule "demo-account"
  _record WARN "2.1 Demo account — a credential login was detected (e.g. Login.swift) but no demo account/credentials for App Review found"
  set_rule "subscription-links-restore"
  _record FAIL "3.1.2 Restore Purchases — not found in the paywall views (e.g. Paywall.swift)"
  set_rule "ats-arbitrary-loads"
  _record WARN "1.6 App Transport Security disabled" "App/Info.plist" "3"
  set_rule "private-api"
  _record PASS "2.5.1 Private API — clean"
  FINDINGS_TMP=""
}
make_static_b() { # the "clean" repo: demo credentials declared
  FINDINGS_TMP="$1"; : > "$FINDINGS_TMP"
  set_rule "demo-account"
  _record PASS "2.1 Demo account — credential login present and reviewer demo credentials/notes found"
  FINDINGS_TMP=""
}
by_rule() { jq -c --arg r "$2" '[.findings[]|select(.rule_id==$r)]' <<<"$1"; }
one() { jq -c --arg r "$2" '[.findings[]|select(.rule_id==$r)][0]' <<<"$1"; }

# ---------------------------------------------------------------------------------
section "findings.sh: every record carries a stable id and null runtime fields"
FINDINGS_TMP="$(mktemp)"; : > "$FINDINGS_TMP"
set_rule "ats-arbitrary-loads"
_record WARN "1.6 App Transport Security disabled" "App/Info.plist" "3"
_record WARN "1.6 App Transport Security disabled" "App/Info.plist" "3"
_record WARN "1.6 App Transport Security disabled" "App/Info.plist" "4"
r1="$(sed -n 1p "$FINDINGS_TMP")"; r2="$(sed -n 2p "$FINDINGS_TMP")"; r3="$(sed -n 3p "$FINDINGS_TMP")"
assert_not_empty "$(jq -r '.id // empty' <<<"$r1")" "id present"
assert_eq "$(jq -r .id <<<"$r1")" "$(jq -r .id <<<"$r2")" "id is deterministic (same rule+file+line+message)"
[[ "$(jq -r .id <<<"$r1")" != "$(jq -r .id <<<"$r3")" ]] && echo "  ok: a different line gives a different id" || { echo "  FAIL: id ignores the line"; fails=$((fails+1)); }
assert_eq "null" "$(jq -r .resolved_by <<<"$r1")"     "resolved_by null by default"
assert_eq "null" "$(jq -r .runtime_target <<<"$r1")"  "runtime_target null by default"
assert_eq "null" "$(jq -r .build_config <<<"$r1")"    "build_config null by default"
rm -f "$FINDINGS_TMP"

section "findings.sh: RESOLVED is structurally inert"
# render_json and verdict.sh count by string equality on FAIL/WARN/PASS/SKIP, so a
# RESOLVED record must fall through every tally and never move the verdict.
FINDINGS_TMP="$(mktemp)"; : > "$FINDINGS_TMP"
set_rule "usage-description-crosscheck"
_record RESOLVED "5.1.1 camera capture API used but Info.plist is missing NSCameraUsageDescription" "App/Cam.swift" "12"
set_rule "ats-arbitrary-loads"
_record WARN "1.6 App Transport Security disabled" "App/Info.plist" "3"
out="$(render_json)"
assert_eq "GREEN" "$(jq -r .verdict <<<"$out")"              "a RESOLVED FAIL does not make RED"
assert_eq "0" "$(jq -r .summary.fail <<<"$out")"             "RESOLVED is not a FAIL"
assert_eq "0" "$(jq -r .summary.pass <<<"$out")"             "RESOLVED is not a PASS"
assert_eq "0" "$(jq -r .summary.not_audited <<<"$out")"      "RESOLVED is not a SKIP"
assert_eq "1" "$(jq -r .summary.warn <<<"$out")"             "the live WARN is still counted"
assert_eq "0" "$(jq -r '.summary.by_confidence["validator-blocking"]' <<<"$out")" "RESOLVED is not an issue in the confidence roll-up"
assert_eq "0" "$(jq -r .summary.needs_build_verification <<<"$out")" "RESOLVED never counts as needing build verification"
assert_eq "2" "$(jq -r '.findings|length' <<<"$out")"        "…but the record is kept, not erased"
# verdict.sh: a RESOLVED: text line (should one ever be printed) is not a verdict line.
v="$(printf 'RESOLVED: 5.1.1 x\nPASS: y\n' | bash "$S/verdict.sh")"
assert_contains "$v" "VERDICT: GREEN" "verdict.sh ignores RESOLVED"
assert_contains "$v" "fail=0 warn=0 pass=1 skip=0" "verdict.sh counts are untouched by RESOLVED"
rm -f "$FINDINGS_TMP"

# ---------------------------------------------------------------------------------
section "dynamic.sh: transcript parsing (no static findings)"
out="$(bash "$DYN" --transcript "$TX/full-run.txt" --target simulator --build-config release)"
assert_eq "appstore-precheck" "$(jq -r .tool <<<"$out")" "same envelope as scan.sh --format json"
assert_eq "9" "$(jq -r '.findings|length' <<<"$out")" "every column-0 DYNAMIC-* line is one record; prose, Pierre and indented lines are not"
l="$(one "$out" dyn-launch)"
assert_eq "PASS"      "$(jq -r .severity <<<"$l")"       "DYNAMIC-PASS -> PASS"
assert_eq "2.1"       "$(jq -r .guideline <<<"$l")"      "guideline taken from the line"
assert_eq "runtime"   "$(jq -r .evidence <<<"$l")"       "evidence is runtime"
assert_eq "review-risk" "$(jq -r .confidence <<<"$l")"   "confidence from the dynamic catalogue"
assert_eq "simulator" "$(jq -r .runtime_target <<<"$l")" "runtime_target recorded"
assert_eq "release"   "$(jq -r .build_config <<<"$l")"   "build_config recorded"
assert_eq "null"      "$(jq -r .resolved_by <<<"$l")"    "a fresh observation resolves nothing"
assert_not_empty "$(jq -r '.id // empty' <<<"$l")"       "dynamic record has an id"
assert_contains "$(jq -r .message <<<"$l")" "process alive after 10s" "message kept"
assert_eq "https://developer.apple.com/app-store/review/guidelines/#2.1" "$(jq -r .guideline_url <<<"$l")" "guideline deep link derived"
f="$(one "$out" 'dyn-permission-prompt:NSCameraUsageDescription')"
assert_eq "WARN" "$(jq -r .severity <<<"$f")" "DYNAMIC-FINDING -> WARN (advisory; blocking is Phase 3, opt-in)"
assert_eq "false" "$(jq -r .needs_build_verification <<<"$f")" "runtime + release -> established"
s="$(one "$out" dyn-paywall-visible)"
assert_eq "SKIP" "$(jq -r .severity <<<"$s")"      "DYNAMIC-SKIP -> SKIP"
assert_eq "null" "$(jq -r .evidence <<<"$s")"      "SKIP carries no evidence class"
assert_eq "null" "$(jq -r .confidence <<<"$s")"    "SKIP carries no confidence"
assert_eq "null" "$(jq -r .runtime_target <<<"$s")" "SKIP carries no runtime target (it observed nothing)"
assert_eq "false" "$(jq -r .needs_build_verification <<<"$s")" "SKIP never needs build verification"
assert_eq "2" "$(jq -r .summary.not_audited <<<"$out")" "SKIPs are counted as not audited"
assert_eq "7" "$(jq -r .summary.runtime.observed <<<"$out")" "observed = PASS + FINDING lines (SKIP observed nothing)"
assert_eq "0" "$(jq -r .summary.runtime.resolved <<<"$out")" "nothing to resolve without static findings"
assert_eq "0" "$(jq -r .summary.runtime.confirmed <<<"$out")" "nothing to confirm without static findings"
assert_eq "GREEN" "$(jq -r .verdict <<<"$out")" "one advisory WARN does not tip the verdict"
# Debug build: a standalone D-check is review-risk, and the qualifier only ever
# applies to a validator-blocking claim — so it stays false here. The Debug guard
# bites on the MERGED validator-blocking record; see the reconciliation sections.
outd="$(bash "$DYN" --transcript "$TX/full-run.txt" --target simulator --build-config debug)"
fd="$(one "$outd" 'dyn-permission-prompt:NSCameraUsageDescription')"
assert_eq "false" "$(jq -r .needs_build_verification <<<"$fd")" "a review-risk observation never carries the qualifier"
assert_eq "debug" "$(jq -r .build_config <<<"$fd")" "build_config debug recorded"
# Omitted config is unknown, treated like debug.
outu="$(bash "$DYN" --transcript "$TX/full-run.txt")"
assert_eq "unknown" "$(jq -r '.build_config' <<<"$(one "$outu" dyn-launch)")" "build_config defaults to unknown"
assert_eq "null" "$(jq -r '.runtime_target' <<<"$(one "$outu" dyn-launch)")" "no --target -> runtime_target null, never guessed"

section "dynamic.sh: an unknown dynamic id is recorded unclassified, never guessed"
out="$(bash "$DYN" --transcript "$TX/rule-level-permission.txt" --build-config release)"
u="$(one "$out" not-a-known-check)"
assert_eq "PASS" "$(jq -r .severity <<<"$u")"    "the line is kept"
assert_eq "runtime" "$(jq -r .evidence <<<"$u")" "it was observed at runtime"
assert_eq "null" "$(jq -r .confidence <<<"$u")"  "but no confidence is invented"

# ---------------------------------------------------------------------------------
section "reconciliation: static FAIL + runtime CONFIRMS -> one record, evidence runtime"
sa="$(mktemp)"; make_static_a "$sa"
static_nb="$(jq -s '[.[]|select(.severity=="FAIL" or .severity=="WARN")|select(.needs_build_verification==true)]|length' "$sa")"
assert_eq "2" "$static_nb" "(precondition) two static issues need build verification"
out="$(bash "$DYN" --transcript "$TX/full-run.txt" --findings "$sa" --target simulator --build-config release)"
cam="$(jq -c '[.findings[]|select(.message|test("NSCameraUsageDescription"))]' <<<"$out")"
assert_eq "1" "$(jq length <<<"$cam")" "exactly ONE camera record (static + dynamic merged)"
cam="$(jq -c '.[0]' <<<"$cam")"
assert_eq "usage-description-crosscheck" "$(jq -r .rule_id <<<"$cam")" "the merged record keeps the static rule id"
assert_eq "FAIL"    "$(jq -r .severity <<<"$cam")"       "severity unchanged (confirmed, not escalated)"
assert_eq "runtime" "$(jq -r .evidence <<<"$cam")"       "evidence upgraded to runtime"
assert_eq "validator-blocking" "$(jq -r .confidence <<<"$cam")" "confidence stays the rule's"
assert_eq "false"   "$(jq -r .needs_build_verification <<<"$cam")" "release runtime clears the qualifier"
assert_eq "App/Cam.swift" "$(jq -r .file <<<"$cam")"     "static file:line kept"
assert_eq "simulator" "$(jq -r .runtime_target <<<"$cam")" "runtime target on the merged record"
assert_eq "null"    "$(jq -r .resolved_by <<<"$cam")"    "confirmed is not resolved"
assert_eq "1" "$(jq -r .summary.runtime.confirmed <<<"$out")" "summary counts the confirmation"
assert_eq "RED" "$(jq -r .verdict <<<"$out")" "a confirmed FAIL is still a FAIL"

section "reconciliation: runtime CONTRADICTS a COMPLETE check -> RESOLVED"
mic="$(jq -c '[.findings[]|select(.message|test("NSMicrophoneUsageDescription"))]' <<<"$out")"
assert_eq "1" "$(jq length <<<"$mic")" "one microphone record"
mic="$(jq -c '.[0]' <<<"$mic")"
assert_eq "RESOLVED" "$(jq -r .severity <<<"$mic")"  "per-key permission check is complete -> RESOLVED"
assert_eq "runtime"  "$(jq -r .resolved_by <<<"$mic")" "resolved_by runtime"
assert_eq "runtime"  "$(jq -r .evidence <<<"$mic")"    "evidence runtime"
assert_eq "false"    "$(jq -r .suppressed <<<"$mic")"  "NOT suppressed — suppression means a human signed"
demo="$(one "$out" demo-account)"
assert_eq "RESOLVED" "$(jq -r .severity <<<"$demo")" "demo-account <-> dyn-demo-login is complete -> RESOLVED"
assert_eq "0" "$(jq '[.findings[]|select(.rule_id=="dyn-demo-login")]|length' <<<"$out")" "the resolving observation is absorbed, not duplicated"
assert_eq "2" "$(jq -r .summary.runtime.resolved <<<"$out")" "summary counts both resolutions"
assert_eq "0" "$(jq -r .summary.needs_build_verification <<<"$out")" "release run: nothing left needing build verification"

section "reconciliation: runtime contradicts a PARTIAL check -> FAIL->WARN only, never PASS"
res="$(one "$out" subscription-links-restore)"
assert_eq "WARN"   "$(jq -r .severity <<<"$res")"  "FAIL downgraded to WARN"
assert_eq "source" "$(jq -r .evidence <<<"$res")"  "evidence stays static (the conclusion still rests on the grep)"
assert_eq "null"   "$(jq -r .resolved_by <<<"$res")" "not resolved"
assert_contains "$(jq -r .message <<<"$res")" "runtime:" "the observation is appended to the message"
assert_contains "$(jq -r .message <<<"$res")" "Restore Purchases tapped" "…verbatim"
assert_eq "0" "$(jq '[.findings[]|select(.rule_id=="dyn-restore-tap")]|length' <<<"$out")" "the observation is absorbed into the static record"
# WARN on a partial contradiction stays WARN (no double downgrade).
sw="$(mktemp)"; FINDINGS_TMP="$sw"; : > "$sw"; set_rule "subscription-links-restore"
_record WARN "3.1.2 Restore Purchases — not in app source, but a remote-configured paywall was detected"; FINDINGS_TMP=""
o2="$(bash "$DYN" --transcript "$TX/full-run.txt" --findings "$sw" --build-config release)"
assert_eq "WARN" "$(jq -r .severity <<<"$(one "$o2" subscription-links-restore)")" "a static WARN stays WARN"
rm -f "$sw"

section "reconciliation: untouched static records pass through unchanged"
ats="$(one "$out" ats-arbitrary-loads)"
assert_eq "WARN"     "$(jq -r .severity <<<"$ats")" "ATS WARN untouched"
assert_eq "manifest" "$(jq -r .evidence <<<"$ats")" "labels untouched"
assert_eq "null"     "$(jq -r .runtime_target <<<"$ats")" "no runtime fields on a record runtime never saw"
assert_eq "PASS" "$(jq -r .severity <<<"$(one "$out" private-api)")" "static PASS untouched"

section "reconciliation: static PASS + runtime FINDING -> new record, the PASS stays"
sb="$(mktemp)"; make_static_b "$sb"
out="$(bash "$DYN" --transcript "$TX/finding-on-static-pass.txt" --findings "$sb" --target simulator --build-config release)"
assert_eq "PASS" "$(jq -r .severity <<<"$(one "$out" demo-account)")" "the static PASS was true about the repo and stays"
dl="$(one "$out" dyn-demo-login)"
assert_eq "WARN"    "$(jq -r .severity <<<"$dl")" "the runtime finding is its own WARN record"
assert_eq "runtime" "$(jq -r .evidence <<<"$dl")" "evidence runtime"
assert_eq "2.1"     "$(jq -r .guideline <<<"$dl")" "guideline from the line"
assert_eq "0" "$(jq -r .summary.runtime.resolved <<<"$out")" "nothing resolved"
assert_eq "0" "$(jq -r .summary.runtime.confirmed <<<"$out")" "a PASS cannot be confirmed by a FINDING"
rm -f "$sb"

section "reconciliation: the Debug guard — summary.needs_build_verification does not move"
outd="$(bash "$DYN" --transcript "$TX/full-run.txt" --findings "$sa" --target simulator --build-config debug)"
assert_eq "$static_nb" "$(jq -r .summary.needs_build_verification <<<"$outd")" "needs_build_verification unchanged by a Debug transcript"
cam="$(jq -c '[.findings[]|select(.message|test("NSCameraUsageDescription"))][0]' <<<"$outd")"
assert_eq "runtime" "$(jq -r .evidence <<<"$cam")" "confirmation still upgrades the evidence…"
assert_eq "true"    "$(jq -r .needs_build_verification <<<"$cam")" "…but a Debug run keeps the qualifier"
mic="$(jq -c '[.findings[]|select(.message|test("NSMicrophoneUsageDescription"))][0]' <<<"$outd")"
assert_eq "WARN" "$(jq -r .severity <<<"$mic")" "a build-dependent FAIL is only downgraded by a Debug contradiction, never RESOLVED"
assert_eq "true" "$(jq -r .needs_build_verification <<<"$mic")" "and it still needs build verification"
assert_contains "$(jq -r .message <<<"$mic")" "debug" "the message says why it was not resolved"
assert_eq "RESOLVED" "$(jq -r .severity <<<"$(one "$outd" demo-account)")" "a finding that never depended on the build can still be resolved by a Debug run"
assert_eq "1" "$(jq -r .summary.runtime.resolved <<<"$outd")" "one resolution under Debug"
# The same holds when no config is given at all.
outu="$(bash "$DYN" --transcript "$TX/full-run.txt" --findings "$sa")"
assert_eq "$static_nb" "$(jq -r .summary.needs_build_verification <<<"$outu")" "unknown config is as cautious as debug"

section "reconciliation: a rule-level (keyless) permission observation is PARTIAL"
out="$(bash "$DYN" --transcript "$TX/rule-level-permission.txt" --findings "$sa" --build-config release)"
assert_eq "0" "$(jq '[.findings[]|select(.rule_id=="usage-description-crosscheck" and .severity=="RESOLVED")]|length' <<<"$out")" "no per-key FAIL is resolved by a keyless PASS"
assert_eq "2" "$(jq '[.findings[]|select(.rule_id=="usage-description-crosscheck" and .severity=="WARN")]|length' <<<"$out")" "both are downgraded to WARN only"
rm -f "$sa"

section "reconciliation: a confirming observation is folded into the merged record, never lost"
sa="$(mktemp)"; make_static_a "$sa"
out="$(bash "$DYN" --transcript "$TX/full-run.txt" --findings "$sa" --target simulator --build-config release)"
cam="$(jq -c '[.findings[]|select(.message|test("NSCameraUsageDescription"))][0]' <<<"$out")"
assert_contains "$(jq -r .message <<<"$cam")" "runtime:" "the merged record carries the observation"
assert_contains "$(jq -r .message <<<"$cam")" "no OS prompt appeared" "…verbatim, with its screenshot reference"
assert_contains "$(jq -r .message <<<"$cam")" "d4-camera.png" "screenshot filename survives"
assert_eq "$(jq -r .id <<<"$(jq -c '[.findings[]|select(.message|test("NSCameraUsageDescription"))][0]' <<<"$out")")" \
  "$(jq -r 'select(.message|test("NSCameraUsageDescription")).id' "$sa")" "the merged record keeps the static id (a stable handle across reconciliation)"
# A confirmation never WEAKENS an already-established claim: static nb false stays false on Debug.
se="$(mktemp)"; FINDINGS_TMP="$se"; : > "$se"; set_rule "usage-description-crosscheck"; set_evidence manifest
_record FAIL "5.1.1 Purpose String — empty NSCameraUsageDescription" "App/Info.plist" "3"; FINDINGS_TMP=""
o="$(bash "$DYN" --transcript "$TX/full-run.txt" --findings "$se" --build-config debug)"
assert_eq "false" "$(jq -r '.findings[0].needs_build_verification' <<<"$o")" "a Debug confirmation does not raise the qualifier on manifest-established evidence"
rm -f "$se"

section "reconciliation: several lines for one rule are all kept"
out="$(bash "$DYN" --transcript "$TX/duplicate-lines.txt" --findings "$sa" --target simulator --build-config release)"
res="$(one "$out" subscription-links-restore)"
assert_eq "FAIL" "$(jq -r .severity <<<"$res")" "a FINDING among the observations confirms (conservative)"
assert_eq "1" "$(jq -r .summary.runtime.confirmed <<<"$out")" "counted once"
assert_contains "$(jq -r .message <<<"$res")" "first attempt" "the PASS observation is folded in"
assert_contains "$(jq -r .message <<<"$res")" "second attempt" "and the FINDING observation too"
assert_eq "0" "$(jq '[.findings[]|select(.rule_id=="dyn-restore-tap")]|length' <<<"$out")" "nothing left dangling as standalone"
assert_eq "2" "$(jq '[.findings[]|select(.rule_id=="dyn-launch")]|length' <<<"$out")" "unmapped duplicates are both standalone records"
assert_eq "4" "$(jq -r .summary.runtime.observed <<<"$out")" "all four observations counted"

section "reconciliation: a malformed per-key id can never resolve or downgrade anything"
# The key is free text an agent typed. An empty key, a bare substring, a one-character
# key or a second colon must not be allowed to match a static message.
out="$(bash "$DYN" --transcript "$TX/malformed-keys.txt" --findings "$sa" --build-config release)"
assert_eq "2" "$(jq '[.findings[]|select(.rule_id=="usage-description-crosscheck" and .severity=="FAIL")]|length' <<<"$out")" "both static FAILs untouched"
assert_eq "0" "$(jq -r .summary.runtime.resolved <<<"$out")" "nothing resolved"
assert_eq "0" "$(jq '[.findings[]|select(.severity=="RESOLVED")]|length' <<<"$out")" "no RESOLVED record"
assert_eq "4" "$(jq '[.findings[]|select(.rule_id|startswith("dyn-permission-prompt"))]|length' <<<"$out")" "the malformed lines are kept as standalone records"
assert_eq "RED" "$(jq -r .verdict <<<"$out")" "verdict unchanged"
rm -f "$sa"

section "parser: CRLF, trailing blanks, double spaces, a line with no message"
out="$(bash "$DYN" --transcript "$TX/messy.txt" --build-config release --format jsonl)"
assert_eq "4" "$(wc -l <<<"$out" | tr -d ' ')" "four records"
fs="$(jq -c 'select(.rule_id=="dyn-first-screen")' <<<"$out")"
assert_not_empty "$fs" "a double space after the colon still yields the rule id"
assert_eq "2.1" "$(jq -r .guideline <<<"$fs")" "guideline intact"
assert_absent "$(jq -r .message <<<"$fs")" $'\r' "no carriage return in the message"
assert_eq "2.1 double space after the colon" "$(jq -r .message <<<"$fs")" "trailing blanks trimmed"
nm="$(jq -c 'select(.guideline=="4.0")' <<<"$out")"
assert_eq "SKIP" "$(jq -r .severity <<<"$nm")" "a line with no message is still a record"
assert_eq "4.0" "$(jq -r .message <<<"$nm")" "and the guideline is not duplicated into the message"
assert_eq "" "$(jq -r '.rule_id' <<<"$nm")" "no id -> empty rule id"

section "build config is corroborated against the D0 line"
# The D0 line records the .app's parent directory. A caller asserting --build-config
# release over a transcript whose D0 says Debug-iphonesimulator is degraded to unknown.
sa="$(mktemp)"; make_static_a "$sa"
out="$(bash "$DYN" --transcript "$TX/messy.txt" --findings "$sa" --build-config release 2>/dev/null)"
assert_eq "unknown" "$(jq -r '.build_config' <<<"$(one "$out" dyn-first-screen)")" "release claim contradicted by D0 -> unknown"
assert_eq "$static_nb" "$(jq -r .summary.needs_build_verification <<<"$out")" "and nothing is established on the caller's word"
mic="$(jq -c '[.findings[]|select(.message|test("NSMicrophoneUsageDescription"))][0]' <<<"$out")"
assert_eq "WARN" "$(jq -r .severity <<<"$mic")" "the per-key PASS only downgrades under the degraded config"
err="$(bash "$DYN" --transcript "$TX/messy.txt" --findings "$sa" --build-config release 2>&1 >/dev/null)"
assert_contains "$err" "Debug-iphonesimulator" "the degradation is reported on stderr"
rm -f "$sa"

section "reconciliation: a crash leaves the static findings alone and adds the observation"
sa="$(mktemp)"; make_static_a "$sa"
out="$(bash "$DYN" --transcript "$TX/crash.txt" --findings "$sa" --target simulator --build-config release)"
assert_eq "WARN" "$(jq -r .severity <<<"$(one "$out" dyn-launch)")" "the crash is a WARN observation (advisory in Phase 1)"
assert_eq "FAIL" "$(jq -r '[.findings[]|select(.message|test("NSCameraUsageDescription"))][0].severity' <<<"$out")" "static FAILs untouched by SKIPs"
assert_eq "$(grep -c "^DYNAMIC-SKIP" "$TX/crash.txt")" "$(jq -r .summary.not_audited <<<"$out")" "every un-driven check is not audited"
assert_eq "0" "$(jq '[.findings[]|select(.severity=="SKIP" and (.evidence!=null or .confidence!=null or .runtime_target!=null))]|length' <<<"$out")" "no SKIP carries a label"
rm -f "$sa"

section "runtime-not-audited: the gap record when the tier did not run"
sa="$(mktemp)"; make_static_a "$sa"
out="$(bash "$DYN" --not-run --findings "$sa")"
g="$(one "$out" runtime-not-audited)"
assert_eq "SKIP" "$(jq -r .severity <<<"$g")" "a gap record is a SKIP"
assert_contains "$(jq -r .message <<<"$g")" "did not run" "it says the tier did not run"
assert_contains "$(jq -r .message <<<"$g")" ".app" "and what would close the gap"
n="$(jq -r .message <<<"$g" | grep -oE '[0-9]+ dynamic check' | grep -oE '[0-9]+')"
assert_gt "${n:-0}" "5" "the count is derived from the dynamic catalogue, not typed"
assert_eq "RED" "$(jq -r .verdict <<<"$out")" "static verdict untouched"
assert_eq "$(jq -s length "$sa")" "$(jq '.findings|length' <<<"$out" | awk '{print $1-1}')" "static records pass through plus the one gap record"
# is_gap_record already recognises the suffix; no evidence.sh change needed.
assert_eq "true" "$(is_gap_record runtime-not-audited && echo true || echo false)" "runtime-not-audited is a gap record by convention"
rm -f "$sa"

section "dynamic.sh accepts the public --format json envelope as --findings"
sa="$(mktemp)"; make_static_a "$sa"
env="$(mktemp)"; FINDINGS_TMP="$sa" render_json > "$env"; FINDINGS_TMP=""
out="$(bash "$DYN" --transcript "$TX/full-run.txt" --findings "$env" --build-config release)"
assert_eq "1" "$(jq -r .summary.runtime.confirmed <<<"$out")" "envelope input reconciles the same way"
assert_eq "2" "$(jq -r .summary.runtime.resolved <<<"$out")" "…including resolutions"
rm -f "$sa" "$env"

section "dynamic.sh --format jsonl and argument validation"
out="$(bash "$DYN" --transcript "$TX/crash.txt" --format jsonl)"
assert_eq "8" "$(wc -l <<<"$out" | tr -d ' ')" "jsonl: one line per record"
bash "$DYN" --build-config nightly --transcript "$TX/crash.txt" >/dev/null 2>&1; st=$?
assert_eq "64" "$st" "an unknown build config is rejected (exit 64)"
bash "$DYN" --target cloud --transcript "$TX/crash.txt" >/dev/null 2>&1; st=$?
assert_eq "64" "$st" "an unknown target is rejected"
bash "$DYN" --transcript /nonexistent >/dev/null 2>&1; st=$?
assert_eq "66" "$st" "a missing transcript is exit 66"

# ---------------------------------------------------------------------------------
# Phase 2: the shipped-bundle family reads the INSTALLED product (nothing executed).
make_static_c() { # purpose strings, ATT, SDK floor, private API — all build-dependent
  FINDINGS_TMP="$1"; : > "$FINDINGS_TMP"
  set_rule "usage-description-crosscheck"
  _record FAIL "5.1.1 camera capture API used but Info.plist is missing 'NSCameraUsageDescription'" "App/Cam.swift" "12"
  _record FAIL "5.1.1 microphone capture API used but Info.plist is missing 'NSMicrophoneUsageDescription'" "App/Mic.swift" "40"
  set_rule "att-usage"
  _record FAIL "5.1.2 ATT framework imported but NSUserTrackingUsageDescription missing in Info.plist (App/Ads.swift)" "App/Info.plist"
  set_rule "xcode-sdk-requirement"
  _record WARN "2.1 Xcode/SDK minimum — LastUpgradeCheck=1540 suggests the project was last upgraded with a pre-26 Xcode" "App.xcodeproj/project.pbxproj" "9"
  set_rule "private-api"
  _record FAIL "2.5.1 Private/Deprecated API:" "App/Legacy.m" "3"
  FINDINGS_TMP=""
}

section "shipped bundle (release): a per-key plist observation resolves the matching static FAIL"
sc="$(mktemp)"; make_static_c "$sc"
nb_c="$(jq -s '[.[]|select(.severity=="FAIL" or .severity=="WARN")|select(.needs_build_verification==true)]|length' "$sc")"
assert_eq "5" "$nb_c" "(precondition) five build-dependent claims"
out="$(bash "$DYN" --transcript "$TX/shipped-bundle.txt" --findings "$sc" --target simulator --build-config release)"
cam="$(jq -c '[.findings[]|select(.message|test("NSCameraUsageDescription"))][0]' <<<"$out")"
assert_eq "RESOLVED" "$(jq -r .severity <<<"$cam")" "installed plist declares the key -> the static FAIL is RESOLVED"
assert_eq "runtime"  "$(jq -r .resolved_by <<<"$cam")" "resolved_by runtime"
assert_eq "usage-description-crosscheck" "$(jq -r .rule_id <<<"$cam")" "under the static rule id"
mic="$(jq -c '[.findings[]|select(.message|test("NSMicrophoneUsageDescription"))][0]' <<<"$out")"
assert_eq "FAIL" "$(jq -r .severity <<<"$mic")" "a key the bundle did NOT declare stays a FAIL"
assert_eq "true" "$(jq -r .needs_build_verification <<<"$mic")" "…and still needs build verification"
assert_absent "$(jq -r .message <<<"$mic")" "runtime:" "the keyless summary line did not touch it (require_key)"

section "shipped bundle: one dyn id may aim at several static rules"
att="$(one "$out" att-usage)"
assert_eq "RESOLVED" "$(jq -r .severity <<<"$att")" "NSUserTrackingUsageDescription in the installed plist resolves att-usage"
assert_eq "3" "$(jq -r .summary.runtime.resolved <<<"$out")" "camera + ATT + SDK resolved"

section "shipped bundle: DTXcode is the complete test of the SDK floor; otool -L is partial"
sdk="$(one "$out" xcode-sdk-requirement)"
assert_eq "RESOLVED" "$(jq -r .severity <<<"$sdk")" "installed DTXcode=2660 resolves the LastUpgradeCheck proxy (release build)"
assert_contains "$(jq -r .message <<<"$sdk")" "DTXcode=2660" "the observation is folded into the record"
pa="$(one "$out" private-api)"
assert_eq "WARN" "$(jq -r .severity <<<"$pa")" "no private-framework link only downgrades private-api (selectors are not linkage)"
assert_eq "null" "$(jq -r .resolved_by <<<"$pa")" "not resolved"
assert_eq "0" "$(jq '[.findings[]|select(.rule_id=="dyn-shipped-sdk" or .rule_id=="dyn-shipped-links")]|length' <<<"$out")" "both observations absorbed"
assert_eq "1" "$(jq '[.findings[]|select(.rule_id=="dyn-shipped-bundle")]|length' <<<"$out")" "the keyless drift summary stays a standalone PASS record"
assert_eq "SKIP" "$(jq -r .severity <<<"$(one "$out" dyn-hosts-contacted)")" "an unobservable hosts check is a SKIP"

section "shipped bundle (debug): the same transcript establishes nothing"
outd="$(bash "$DYN" --transcript "$TX/shipped-bundle.txt" --findings "$sc" --target simulator --build-config debug)"
assert_eq "$nb_c" "$(jq -r .summary.needs_build_verification <<<"$outd")" "needs_build_verification unchanged by a Debug bundle"
assert_eq "0" "$(jq -r .summary.runtime.resolved <<<"$outd")" "nothing resolved: every claim here depended on the build"
assert_eq "WARN" "$(jq -r '[.findings[]|select(.message|test("NSCameraUsageDescription"))][0].severity' <<<"$outd")" "camera FAIL only downgraded"
assert_eq "WARN" "$(jq -r .severity <<<"$(one "$outd" xcode-sdk-requirement)")" "SDK WARN stays WARN"
assert_contains "$(jq -r '.message' <<<"$(one "$outd" xcode-sdk-requirement)")" "debug build" "and says why"
assert_eq "RED" "$(jq -r .verdict <<<"$outd")" "the untouched microphone FAIL keeps the verdict RED (a Debug bundle moves nothing it did not observe)"
# A --build-config release claim over this transcript is honoured: D0 says Release-iphonesimulator.
assert_eq "release" "$(jq -r '.build_config' <<<"$(one "$out" dyn-shipped-bundle)")" "release claim corroborated by the D0 line"
rm -f "$sc"

section "runtime-not-audited counts the Phase 2 observations too"
sa="$(mktemp)"; make_static_a "$sa"
n="$(bash "$DYN" --not-run --findings "$sa" | jq -r '[.findings[]|select(.rule_id=="runtime-not-audited")][0].message' | grep -oE '[0-9]+ dynamic check' | grep -oE '[0-9]+')"
assert_gt "${n:-0}" "12" "the gap record counts every non-setup id in the catalogue"
rm -f "$sa"

section "no simulator command is ever run by this test or by dynamic.sh"
assert_eq "0" "$(grep -cE 'simctl|xcodebuild|maestro' "$DYN" | grep -vE '^#' | awk '{print $1}')" "dynamic.sh is a pure text transform"

exit "$fails"
