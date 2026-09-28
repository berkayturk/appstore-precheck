#!/usr/bin/env bash
# tests/test-dynamic-libs.sh — the pure parts of the Phase 6 runner, pinned on CI
# without a device: the decision rules (four launch signals -> one verdict, N repeats
# -> one line), the screenshot-uniformity decoder, the layout heuristics over recorded
# Maestro hierarchies, the contacted-hosts parity, and the installed-bundle readers.
# Nothing here boots a simulator; otool is shimmed.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=tests/_assert.sh
source "$HERE/_assert.sh"
S="$ROOT/skills/appstore-precheck/scripts"
L="$S/lib"
FX="$HERE/fixtures"
# shellcheck source=skills/appstore-precheck/scripts/lib/dyn-quorum.sh
source "$L/dyn-quorum.sh"
# shellcheck source=skills/appstore-precheck/scripts/lib/dyn-geometry.sh
source "$L/dyn-geometry.sh"
# shellcheck source=skills/appstore-precheck/scripts/lib/dyn-hosts.sh
source "$L/dyn-hosts.sh"
# shellcheck source=skills/appstore-precheck/scripts/lib/dyn-bundle.sh
source "$L/dyn-bundle.sh"
kind() { cut -f1 <<<"$1"; }
detail() { cut -f2- <<<"$1"; }

# ---------------------------------------------------------------------------------
section "launch verdict: a conjunction of four signals"
v="$(dyn_launch_verdict alive varied clean 42)"
assert_eq "PASS" "$(kind "$v")" "all four healthy -> PASS"
assert_contains "$(detail "$v")" "process alive" "detail names the signals"
assert_eq "FINDING" "$(kind "$(dyn_launch_verdict dead varied clean 42)")" "process gone -> FINDING"
assert_eq "FINDING" "$(kind "$(dyn_launch_verdict alive varied crash 42)")" "crash in log -> FINDING even if the process is alive again"
assert_eq "FINDING" "$(kind "$(dyn_launch_verdict alive uniform clean 42)")" "flat screenshot -> FINDING (hung splash)"
v="$(dyn_launch_verdict alive varied clean 1)"
assert_eq "PASS" "$(kind "$v")" "a degenerate tree alone is NEVER a failure (Flutter / Compose)"
assert_contains "$(detail "$v")" "degenerate" "…and is named as such"
v="$(dyn_launch_verdict dead varied clean 1)"
assert_eq "FINDING" "$(kind "$v")" "degenerate tree + dead process -> FINDING (the other signal decides)"
v="$(dyn_launch_verdict alive unread clean unread)"
assert_eq "PASS" "$(kind "$v")" "unreadable signals do not fail the launch"
assert_contains "$(detail "$v")" "could not be read" "…but are written into the line"
assert_contains "$(detail "$v")" "screenshot" "…by name"
v="$(dyn_launch_verdict unread unread unread unread)"
assert_eq "SKIP" "$(kind "$v")" "nothing readable -> SKIP, never PASS"
v="$(dyn_launch_verdict alive unread unread unread)"
assert_eq "PASS" "$(kind "$v")" "one readable healthy signal is a PASS with three caveats"
assert_contains "$(detail "$v")" "log stream" "caveat names the log"

section "no-crash log without a positive app signal is not a healthy launch"
# The real RN panel left a one-byte hierarchy, no screenshot, no process PID,
# and only SpringBoard bookkeeping. This anonymized fixture reproduces that shape.
source "$L/dyn-signals.sh"
UNREAD_FIXTURE="$FX/runtime/unread-launch"
[[ ! -e "$UNREAD_FIXTURE/launch.png" ]] || { echo "  FAIL: unread-launch fixture unexpectedly has a screenshot"; fails=$((fails+1)); }
assert_eq "1" "$(wc -c < "$UNREAD_FIXTURE/hierarchy.json" | tr -d ' ')" "recorded hierarchy is one newline"
lg="$(dyn_signal_log "$UNREAD_FIXTURE/log.txt" FixtureApp)"
assert_eq "clean" "$lg" "SpringBoard-only bookkeeping contains no app crash"
v="$(dyn_launch_verdict "$(dyn_signal_process "")" unread "$lg" unread)"
assert_eq "SKIP" "$(kind "$v")" "clean log alone cannot prove app launch"
assert_eq "SKIP" "$(kind "$(dyn_launch_verdict unread unread clean 1)")" "clean log and degenerate tree still have no positive app signal"
assert_eq "SKIP" "$(kind "$(dyn_launch_verdict unread unread clean malformed)")" "malformed node count is not a positive signal"
assert_eq "FINDING" "$(kind "$(dyn_launch_verdict unread unread crash unread)")" "explicit crash detection still wins without positive signals"
assert_eq "PASS" "$(kind "$(dyn_launch_verdict unread varied clean unread)")" "real screenshot remains a positive signal"
assert_eq "PASS" "$(kind "$(dyn_launch_verdict unread unread clean 4)")" "usable app tree remains a positive signal"

section "toolkit selector scope follows measured trees, not framework stereotypes"
reason="$(dyn_selector_scope kmp 72)"
assert_contains "$reason" "72 nodes" "healthy measured KMP tree is reported"
assert_contains "$reason" "not executed" "available tree does not imply dedicated flow completion"
assert_absent "$reason" "not driveable" "framework name cannot overrule measured capability"
reason="$(dyn_selector_scope flutter 1)"
assert_contains "$reason" "degenerate" "actual tiny tree keeps its limitation"
reason="$(dyn_selector_scope kmp unread)"
assert_contains "$reason" "not measured" "missing tree evidence does not mean no semantics"

section "quorum: FINDING only on N/N, mixed carries its ratio, all-SKIP is SKIP"
q="$(dyn_quorum 3 0 0)"; assert_eq "PASS" "$(kind "$q")" "3/3 pass -> PASS"; assert_contains "$(detail "$q")" "3/3" "ratio shown"
q="$(dyn_quorum 0 3 0)"; assert_eq "FINDING" "$(kind "$q")" "0/3 -> FINDING"; assert_contains "$(detail "$q")" "quorum 3/3" "unanimous ratio"
q="$(dyn_quorum 1 2 0)"; assert_eq "FINDING" "$(kind "$q")" "mixed -> FINDING (advisory)"
assert_contains "$(detail "$q")" "2 of 3 launches" "…with its ratio"
assert_contains "$(detail "$q")" "not unanimous" "…marked non-unanimous (Phase 3 never blocks on it)"
q="$(dyn_quorum 0 0 3)"; assert_eq "SKIP" "$(kind "$q")" "every repeat timed out -> SKIP, never FINDING"
q="$(dyn_quorum 2 0 1)"; assert_eq "PASS" "$(kind "$q")" "2 pass + 1 undriveable -> PASS"; assert_contains "$(detail "$q")" "could not be driven" "…noting the gap"
q="$(dyn_quorum 0 2 1)"; assert_eq "FINDING" "$(kind "$q")" "2 fail + 1 undriveable -> FINDING"; assert_contains "$(detail "$q")" "not unanimous" "…but NOT unanimous (one repeat unread)"
q="$(dyn_quorum 0 0 0)"; assert_eq "SKIP" "$(kind "$q")" "no repeats at all -> SKIP"

section "dyn_line renders the grammar dynamic.sh parses"
line="$(dyn_line FINDING 2.1 dyn-launch "quorum 3/3: failed on every launch")"
assert_eq "DYNAMIC-FINDING: 2.1 [dyn-launch] — quorum 3/3: failed on every launch" "$line" "exact shape"
rec="$(printf '%s\n' "$line" | bash "$S/dynamic.sh" --format jsonl --build-config debug)"
assert_eq "dyn-launch" "$(jq -r .rule_id <<<"$rec")" "dynamic.sh reads the id back"
assert_eq "WARN" "$(jq -r .severity <<<"$rec")" "a FINDING is a WARN record"
assert_eq "DYNAMIC-SKIP: x [y] — z" "$(dyn_line BOGUS x y z)" "an unknown kind degrades to SKIP, never PASS"

# ---------------------------------------------------------------------------------
section "png-uniform.py: flat vs varied, unreadable is exit 2"
T="$(mktemp -d)"
python3 "$HERE/make-png.py" 64 64 "$T/black.png"
assert_eq "uniform" "$(python3 "$L/png-uniform.py" "$T/black.png")" "an all-black frame is uniform"
python3 - "$T/varied.png" <<'PY'
import sys, zlib, struct
w = h = 64
def chunk(t, d):
    b = t + d
    return struct.pack('>I', len(d)) + b + struct.pack('>I', zlib.crc32(b) & 0xffffffff)
rows = b''
for y in range(h):
    # filter type 2 (Up) on odd rows to exercise the unfilter path; a diagonal gradient
    px = b''.join(bytes([(x * 4) & 255, (y * 4) & 255, ((x + y) * 2) & 255]) for x in range(w))
    if y % 2 == 1:
        prev = b''.join(bytes([(x * 4) & 255, ((y - 1) * 4) & 255, ((x + y - 1) * 2) & 255]) for x in range(w))
        px = bytes((a - b) & 255 for a, b in zip(px, prev))
        rows += b'\x02' + px
    else:
        rows += b'\x00' + px
data = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b'')
open(sys.argv[1], 'wb').write(data)
PY
out="$(python3 "$L/png-uniform.py" "$T/varied.png")"
assert_contains "$out" "varied" "a gradient is varied"
assert_gt "$(awk '{print $2}' <<<"$out")" "10" "…with many sampled colours"
printf 'not a png' > "$T/nope.png"
python3 "$L/png-uniform.py" "$T/nope.png" >/dev/null 2>&1; st=$?
assert_eq "2" "$st" "unreadable -> exit 2 (the runner records the signal as unread, never healthy)"
python3 "$L/png-uniform.py" "$T/missing.png" >/dev/null 2>&1; st=$?
assert_eq "2" "$st" "missing file -> exit 2"

# ---------------------------------------------------------------------------------
section "geometry heuristics over recorded Maestro hierarchies"
H="$FX/dynamic-hierarchies"
r="$(dyn_geometry_report "$H/clean.json" 393 852)"
assert_eq "false" "$(jq -r .degenerate <<<"$r")" "clean: not degenerate"
assert_eq "0" "$(jq -r '.clipped|length' <<<"$r")" "clean: nothing clipped"
assert_eq "0" "$(jq -r '.zero_size|length' <<<"$r")" "clean: nothing zero-size"
assert_eq "0" "$(jq -r '.overlap|length' <<<"$r")" "clean: no overlap (parent/child containment is not overlap)"
assert_contains "$(dyn_geometry_line "$r" 4.0 dyn-dark-mode "dark appearance" d-dark.png)" "DYNAMIC-PASS: 4.0 [dyn-dark-mode]" "clean -> PASS line"
r="$(dyn_geometry_report "$H/clipped.json" 393 852)"
assert_eq "2" "$(jq -r '.clipped|length' <<<"$r")" "clipped: the overflowing row and the off-screen button"
assert_contains "$(jq -r '.clipped[]' <<<"$r")" "Continue" "…the button is named"
assert_eq "1" "$(jq -r '.zero_size|length' <<<"$r")" "clipped: one zero-size label"
assert_eq "Hidden label" "$(jq -r '.zero_size[0]' <<<"$r")" "…named"
l="$(dyn_geometry_line "$r" 4.0 dyn-dynamic-type "Dynamic Type AX5")"
assert_contains "$l" "DYNAMIC-FINDING: 4.0 [dyn-dynamic-type]" "hits -> FINDING"
assert_contains "$l" "2 clipped, 1 zero-size" "counts in the line"
r="$(dyn_geometry_report "$H/overlap.json" 393 852)"
assert_eq "1" "$(jq -r '.overlap|length' <<<"$r")" "overlap: the two price rows"
assert_contains "$(jq -r '.overlap[0][1]' <<<"$r")" "Yearly" "…both named"
r="$(dyn_geometry_report "$H/degenerate.json" 393 852)"
assert_eq "true" "$(jq -r .degenerate <<<"$r")" "two nodes -> degenerate"
l="$(dyn_geometry_line "$r" 2.4.1 dyn-ipad-layout "iPad Pro 11-inch")"
assert_contains "$l" "DYNAMIC-SKIP: 2.4.1 [dyn-ipad-layout]" "degenerate -> SKIP, never FINDING, never PASS"
assert_contains "$l" "Flutter/Compose" "…with the reason"
r="$(dyn_geometry_report "$H/clean.json" 0 0)"
assert_eq "0" "$(jq -r '.clipped|length' <<<"$r")" "without a screen size, the screen is taken from the root node (nothing clipped)"
r="$(dyn_geometry_report "$T/nonexistent.json" 393 852)"
assert_eq "true" "$(jq -r .degenerate <<<"$r")" "missing hierarchy -> degenerate (SKIP path), not a crash"

# ---------------------------------------------------------------------------------
section "hosts: extraction from CFNetwork diagnostics and from tcpdump text"
hosts="$(dyn_hosts_from_log "$H/cfnetwork.log")"
assert_eq "4" "$(grep -c . <<<"$hosts")" "four distinct hosts (case-folded, deduped)"
assert_contains "$hosts" "api.receipts.example.com" "URL host"
assert_contains "$hosts" "launches.appsflyer.com" "attribution host"
assert_contains "$hosts" "203.0.113.10" "an IPv4 literal endpoint is kept (2.5.5 will care)"
assert_absent "$hosts" "API.Receipts" "lower-cased"
assert_absent "$hosts" "endpoint" "a dotless placeholder token is not a host"
th="$(dyn_hosts_from_tcpdump_text "$H/tcpdump.txt")"
assert_eq "3" "$(grep -c . <<<"$th")" "DNS queries -> three hosts (A and AAAA for one host collapse)"
assert_contains "$th" "dart-http.example.net" "a host only DNS saw (Flutter bypasses CFNetwork)"

section "hosts: parity with NSPrivacyTrackingDomains"
printf '%s\n' "$hosts" > "$T/hosts.txt"
p="$(dyn_hosts_parity "$T/hosts.txt" "$FX/dynamic-bundle/Installed.app/PrivacyInfo.xcprivacy")"
assert_eq "2" "$(jq -r '.tracking|length' <<<"$p")" "two hosts match known vendors"
assert_eq "1" "$(jq -r '.undeclared|length' <<<"$p")" "AppsFlyer is declared, graph.facebook.com is not"
assert_eq "graph.facebook.com" "$(jq -r '.undeclared[0]' <<<"$p")" "…named"
l="$(dyn_hosts_line "$p")"
assert_contains "$l" "DYNAMIC-FINDING: 5.1.2 [dyn-hosts-contacted]" "undeclared vendor host -> FINDING"
assert_contains "$l" "graph.facebook.com (Meta" "…with vendor"
p="$(dyn_hosts_parity "$T/hosts.txt" "")"
assert_eq "2" "$(jq -r '.undeclared|length' <<<"$p")" "no privacy manifest -> both undeclared"
printf 'api.receipts.example.com\n' > "$T/hosts2.txt"
l="$(dyn_hosts_line "$(dyn_hosts_parity "$T/hosts2.txt" "")")"
assert_contains "$l" "DYNAMIC-PASS: 5.1.2" "no vendor host -> PASS"
assert_contains "$l" "none matches a known ad/attribution vendor" "…saying so"
: > "$T/empty.txt"
l="$(dyn_hosts_line "$(dyn_hosts_parity "$T/empty.txt" "")" "Flutter HttpClient bypasses CFNetwork; use --pktap")"
assert_contains "$l" "DYNAMIC-SKIP: 5.1.2" "no host seen -> SKIP"
assert_contains "$l" "pktap" "…with the note the runner passed"
assert_gt "$(dyn_tracking_domain_catalogue | grep -c .)" "15" "the vendor catalogue is populated"
assert_eq "0" "$(dyn_tracking_domain_catalogue | awk -F'\t' 'NF!=2' | grep -c .)" "every catalogue row is vendor<TAB>domain"

# ---------------------------------------------------------------------------------
section "plist readers: the XML fallback (ubuntu CI) agrees with plutil (macOS)"
B="$FX/dynamic-bundle"
if command -v plutil >/dev/null 2>&1; then
  for k in CFBundleIdentifier CFBundleExecutable DTXcode NSMicrophoneUsageDescription NSCameraUsageDescription NotAKey; do
    assert_eq "$(dyn_plist_string "$B/Installed.app/Info.plist" "$k")" "$(DYN_NO_PLUTIL=1 dyn_plist_string "$B/Installed.app/Info.plist" "$k")" "string $k: fallback == plutil"
  done
  assert_eq "$(dyn_plist_keys "$B/Installed.app/Info.plist" | tr '\n' ' ')" "$(DYN_NO_PLUTIL=1 dyn_plist_keys "$B/Installed.app/Info.plist" | tr '\n' ' ')" "keys: fallback == plutil"
  assert_eq "$(dyn_plist_array_strings "$B/Installed.app/PrivacyInfo.xcprivacy" NSPrivacyTrackingDomains)" "$(DYN_NO_PLUTIL=1 dyn_plist_array_strings "$B/Installed.app/PrivacyInfo.xcprivacy" NSPrivacyTrackingDomains)" "array strings: fallback == plutil"
  assert_eq "$(dyn_plist_supports_ipad "$B/Installed.app/Info.plist" && echo y || echo n)" "$(DYN_NO_PLUTIL=1 dyn_plist_supports_ipad "$B/Installed.app/Info.plist" && echo y || echo n)" "UIDeviceFamily: fallback == plutil"
else
  echo "  ok: no plutil here; the fallback is what runs below"
fi
# One-line and pretty-printed plists read the same through the fallback.
printf '<plist version="1.0">\n<dict>\n  <key>CFBundleIdentifier</key>\n  <string>com.pretty.app</string>\n  <key>UIDeviceFamily</key>\n  <array>\n    <integer>1</integer>\n  </array>\n  <key>Empty</key>\n  <string></string>\n</dict>\n</plist>\n' > "$T/pretty.plist"
assert_eq "com.pretty.app" "$(DYN_NO_PLUTIL=1 dyn_plist_string "$T/pretty.plist" CFBundleIdentifier)" "pretty-printed string"
assert_eq "" "$(DYN_NO_PLUTIL=1 dyn_plist_string "$T/pretty.plist" Empty)" "empty string is empty"
assert_eq "" "$(DYN_NO_PLUTIL=1 dyn_plist_string "$T/pretty.plist" UIDeviceFamily)" "a non-string value is not a string"
assert_eq "n" "$(DYN_NO_PLUTIL=1 dyn_plist_supports_ipad "$T/pretty.plist" && echo y || echo n)" "iPhone-only family"
assert_eq "y" "$(DYN_NO_PLUTIL=1 dyn_plist_supports_ipad "$B/Installed.app/Info.plist" && echo y || echo n)" "universal family (one-line array)"

section "installed bundle: plist keys, per-key purpose strings, drift"
keys="$(dyn_plist_keys "$B/Installed.app/Info.plist")"
assert_contains "$keys" "DTXcode" "top-level keys read"
assert_absent "$keys" "integer" "array members are not keys"
lines="$(dyn_bundle_plist_lines "$B/Installed.app/Info.plist" "$B/repo/Info.plist")"
assert_contains "$lines" "DYNAMIC-PASS: 5.1.1 [dyn-shipped-bundle:NSCameraUsageDescription]" "declared camera key -> per-key PASS"
assert_contains "$lines" 'We scan receipts' "…quoting the string"
assert_contains "$lines" "DYNAMIC-PASS: 5.1.2 [dyn-shipped-bundle:NSUserTrackingUsageDescription]" "tracking key under 5.1.2"
assert_contains "$lines" "DYNAMIC-FINDING: 5.1.1 [dyn-shipped-bundle:NSMicrophoneUsageDescription]" "an EMPTY purpose string is a FINDING"
assert_contains "$lines" "DYNAMIC-FINDING: 5.1.1 [dyn-shipped-bundle:NSPhotoLibraryUsageDescription]" "a key in the repo plist but not the bundle is a FINDING"
assert_contains "$lines" "DYNAMIC-PASS: 5.1.1 [dyn-shipped-bundle] —" "keyless drift summary present"
assert_contains "$lines" "only in repo: NSPhotoLibraryUsageDescription" "…naming the drift"
assert_absent "$(grep 'dyn-shipped-bundle\]' <<<"$lines")" "DTXcode" "toolchain keys are not reported as drift"
lines="$(dyn_bundle_plist_lines "$B/Installed.app/Info.plist" "")"
assert_contains "$lines" "no repo Info.plist to compare" "no repo plist -> summary says so"
assert_contains "$(dyn_bundle_plist_lines "$T/none.plist" "")" "DYNAMIC-SKIP: 5.1.1 [dyn-shipped-bundle]" "unreadable installed plist -> SKIP"

section "installed bundle: DTXcode is the SDK floor evidence"
assert_contains "$(dyn_bundle_sdk_line "$B/Installed.app/Info.plist")" "DYNAMIC-PASS: 2.1 [dyn-shipped-sdk] — installed Info.plist: DTXcode=2660" "2660 -> PASS"
sed 's/2660/1540/' "$B/Installed.app/Info.plist" > "$T/old.plist"
assert_contains "$(dyn_bundle_sdk_line "$T/old.plist")" "DYNAMIC-FINDING: 2.1 [dyn-shipped-sdk]" "1540 -> FINDING"
grep -v DTXcode "$B/Installed.app/Info.plist" > "$T/nodt.plist"
assert_contains "$(dyn_bundle_sdk_line "$T/nodt.plist")" "DYNAMIC-SKIP: 2.1 [dyn-shipped-sdk]" "no DTXcode -> SKIP"

section "installed bundle: otool -L linkage (shimmed)"
shim="$(mktemp -d)"
cat > "$shim/otool" <<'EOF'
#!/bin/sh
printf '%s:\n' "$2"
printf '\t/System/Library/Frameworks/UIKit.framework/UIKit (compatibility version 1.0.0)\n'
printf '\t/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices (compatibility version 1.0.0)\n'
printf '\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0)\n'
EOF
chmod +x "$shim/otool"
l="$(PATH="$shim:$PATH" dyn_bundle_links_line "$B/Installed.app")"
assert_contains "$l" "DYNAMIC-FINDING: 2.5.1 [dyn-shipped-links]" "private framework link -> FINDING"
assert_contains "$l" "BackBoardServices" "…named"
cat > "$shim/otool" <<'EOF'
#!/bin/sh
printf '%s:\n' "$2"
printf '\t/System/Library/Frameworks/UIKit.framework/UIKit (compatibility version 1.0.0)\n'
printf '\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0)\n'
EOF
l="$(PATH="$shim:$PATH" dyn_bundle_links_line "$B/Installed.app")"
assert_contains "$l" "DYNAMIC-PASS: 2.5.1 [dyn-shipped-links]" "clean linkage -> PASS"
assert_contains "$l" "linkage only" "…stated as partial"
# Xcode 16+ Debug layout: a stub executable plus <Exe>.debug.dylib holding the code.
mkdir -p "$T/dbg.app"; cp "$B/Installed.app/Info.plist" "$B/Installed.app/Installed" "$T/dbg.app/"; : > "$T/dbg.app/Installed.debug.dylib"
cat > "$shim/otool" <<'EOF'
#!/bin/sh
printf '%s:\n' "$2"
case "$2" in
  *.debug.dylib) printf '\t/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices (compatibility version 1.0.0)\n' ;;
  *) printf '\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0)\n' ;;
esac
EOF
l="$(PATH="$shim:$PATH" dyn_bundle_links_line "$T/dbg.app")"
assert_contains "$l" "DYNAMIC-FINDING: 2.5.1 [dyn-shipped-links]" "a private link inside the .debug.dylib is found"
assert_contains "$l" "Installed.debug.dylib" "…and the line says the dylib was read"
mkdir -p "$T/noexe.app"; cp "$B/Installed.app/Info.plist" "$T/noexe.app/"
assert_contains "$(PATH="$shim:$PATH" dyn_bundle_links_line "$T/noexe.app")" "DYNAMIC-SKIP" "missing executable -> SKIP"
rm -rf "$shim"

section "Maestro \${...} markers are refused, never evaluated or echoed"
DEMO="$L/dyn-demo-login.py"; EXPLORE="$L/dyn-explore.py"
mb="$T/mbin"; mkdir -p "$mb"
printf '#!/bin/sh\necho "$@" >> "%s/maestro-calls"\nexit 0\n' "$T" > "$mb/maestro"; chmod +x "$mb/maestro"
demo() { # demo <username> <password> [submit-label]
  PATH="$mb:$PATH" PRECHECK_DEMO_USERNAME="$1" PRECHECK_DEMO_PASSWORD="$2" PRECHECK_DEMO_SUBMIT="${3:-Sign In}" \
    PRECHECK_DEMO_SUCCESS_TEXT=Dashboard PRECHECK_DEMO_FAILURE_TEXT=Invalid \
    PRECHECK_DEMO_AUTHORIZED_TEST=1 PRECHECK_DEMO_ENVIRONMENT=sandbox python3 "$DEMO" UDID org.example.app
}
rm -f "$T/maestro-calls"
r="$(demo reviewer@example.invalid 'pa${process.env.HOME}ss')"
assert_eq "SKIP" "$(kind "$r")" "a password containing \${ is a SKIP"
assert_contains "$r" "password" "…the reason names the field"
assert_absent "$r" 'process.env' "…and never echoes the credential value"
assert_absent "$r" 'pa${' "…not even a prefix of it"
r="$(demo 'me${1+1}@example.invalid' 'plain-pass')"
assert_eq "SKIP" "$(kind "$r")" "a username containing \${ is a SKIP"
assert_contains "$r" "username" "…named as the username"
assert_absent "$r" '1+1' "…without echoing it"
r="$(demo reviewer@example.invalid plain-pass '${label}')"
assert_eq "SKIP" "$(kind "$r")" "a submit label containing \${ is a SKIP"
[[ ! -e "$T/maestro-calls" ]] && echo "  ok: Maestro was never invoked for any refused value" || { echo "  FAIL: Maestro ran with a \${ value"; fails=$((fails+1)); }
r="$(demo reviewer@example.invalid 'pa$$w{0}rd')"
assert_absent "$r" "Maestro would evaluate" "a bare \$ or { is not refused"
[[ -e "$T/maestro-calls" ]] && echo "  ok: the guard is not over-broad (Maestro is reached for a plain \$ / {)" || { echo "  FAIL: benign special characters were refused"; fails=$((fails+1)); }
explore_probe="$(python3 - "$EXPLORE" <<'PY'
import importlib.util, pathlib, sys, tempfile
spec = importlib.util.spec_from_file_location('explore', sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
calls = []
m.command = lambda argv, timeout, cwd=None: calls.append(argv) or '{"children":[]}'
def auth(selector):
    return {'schema_version': 1, 'authorized': True, 'environment': 'sandbox', 'selectors': [selector]}
with tempfile.TemporaryDirectory() as tmp:
    try:
        m.live_explore('owned', 'org.example.app', pathlib.Path(tmp), 25, 1, auth('Sett${ings}'))
        print('accepted-marker')
    except ValueError:
        print('refused-marker calls=%d' % len(calls))
    try:
        m.live_explore('owned', 'org.example.app', pathlib.Path(tmp), 25, 1, auth('Settings'))
        print('accepted-plain')
    except ValueError:
        print('refused-plain')
PY
)"
assert_contains "$explore_probe" "refused-marker calls=0" "an authorized navigation selector containing \${ is refused before Maestro runs"
assert_contains "$explore_probe" "accepted-plain" "a plain selector is still accepted"

section "dyn-explore.py: --out must not be inside --repo"
mkdir -p "$T/xrepo" "$T/xscreens"
python3 "$EXPLORE" --screens "$T/xscreens" --out "$T/xrepo/inner/out" --repo "$T/xrepo" >/dev/null 2>"$T/xerr"; st=$?
assert_eq "64" "$st" "--out inside --repo is a usage error (64)"
assert_contains "$(cat "$T/xerr")" "--out must not be inside --repo" "…with a clear message"
[[ ! -e "$T/xrepo/inner" ]] && echo "  ok: nothing was created inside the repo" || { echo "  FAIL: created under the repo"; fails=$((fails+1)); }
python3 "$EXPLORE" --screens "$T/xscreens" --out "$T/xout-outside" --repo "$T/xrepo" >/dev/null 2>&1; st=$?
assert_eq "0" "$st" "an --out outside --repo works"

section "every generated line is accepted by dynamic.sh under a catalogued id"
all="$( { dyn_bundle_plist_lines "$B/Installed.app/Info.plist" "$B/repo/Info.plist"; dyn_bundle_sdk_line "$B/Installed.app/Info.plist"; dyn_hosts_line "$(dyn_hosts_parity "$T/hosts.txt" "")"; dyn_geometry_line "$(dyn_geometry_report "$H/clipped.json" 393 852)" 4.0 dyn-dark-mode dark; } )"
recs="$(printf '%s\n' "$all" | bash "$S/dynamic.sh" --format jsonl --build-config debug)"
assert_eq "0" "$(jq -r 'select(.confidence==null and .severity!="SKIP") | .rule_id' <<<"$recs" | grep -c .)" "no non-SKIP record is unclassified (every id is in dyn_rule_confidence)"
assert_eq "$(printf '%s\n' "$all" | grep -c '^DYNAMIC-')" "$(grep -c . <<<"$recs")" "one record per line"

rm -rf "$T"
exit "$fails"
