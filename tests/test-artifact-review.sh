#!/usr/bin/env bash
# Artifact review fixtures run on Linux and macOS without an iOS toolchain.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REVIEW="$ROOT/skills/appstore-precheck/scripts/artifact-review.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/clean.app" "$TMP/risky.app/Frameworks/Tracker.framework" "$TMP/tools"
python3 - "$TMP" <<'PY'
import pathlib, plistlib, sys
p = pathlib.Path(sys.argv[1])
def put(path, data):
    path.write_bytes(plistlib.dumps(data))
common = {'CFBundleIdentifier':'org.example.sample', 'CFBundleExecutable':'Sample',
          'MinimumOSVersion':'17.0', 'DTSDKName':'iphoneos18.0', 'DTXcode':'1600'}
put(p/'clean.app/Info.plist', common)
(p/'clean.app/Sample').write_bytes(b'ordinary binary')
put(p/'clean.app/PrivacyInfo.xcprivacy', {'NSPrivacyAccessedAPITypes':[]})
bad = dict(common, NSAppTransportSecurity={'NSAllowsArbitraryLoads':True},
           LSApplicationQueriesSchemes=['cydia'],
           UIBackgroundModes=['remote-notification'])
put(p/'risky.app/Info.plist', bad)
(p/'risky.app/Sample').write_bytes(b'dlopen HTTP download executable task_for_pid _stat _OBJC_CLASS_$_NSUserDefaults')
put(p/'risky.app/Frameworks/Tracker.framework/Info.plist',
    {'CFBundleExecutable':'Tracker','CFBundleIdentifier':'org.example.tracker'})
(p/'risky.app/Frameworks/Tracker.framework/Tracker').write_bytes(b'framework')
(p/'risky.app/debug.mobileprovision').write_text('fixture')
PY
cat > "$TMP/tools/nm" <<'SH'
#!/bin/sh
case "$*" in *risky*) printf '%s\n' ' U _stat' ' U _OBJC_CLASS_$_NSUserDefaults' ' U _task_for_pid';; esac
SH
cat > "$TMP/tools/otool" <<'SH'
#!/bin/sh
case "$*" in *risky*) printf '%s\n' '/System/Library/PrivateFrameworks/PrivateKit.framework/PrivateKit';; esac
SH
cat > "$TMP/tools/codesign" <<'SH'
#!/bin/sh
case "$*" in
  *--entitlements*risky*) printf '%s\n' '<?xml version="1.0"?><plist version="1.0"><dict><key>com.apple.developer.healthkit</key><true/><key>get-task-allow</key><true/></dict></plist>';;
  *--entitlements*) printf '%s\n' '<?xml version="1.0"?><plist version="1.0"><dict></dict></plist>';;
  *--verify*) exit 0;;
esac
SH
chmod +x "$TMP/tools/"*
PATH="$TMP/tools:$PATH" bash "$REVIEW" --app "$TMP/clean.app" --format json > "$TMP/clean.json"
PATH="$TMP/tools:$PATH" bash "$REVIEW" --app "$TMP/risky.app" --format json > "$TMP/risky.json"
bash "$REVIEW" --format json > "$TMP/absent.json"
python3 - "$TMP" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
def checks(name):
    data = json.loads((p/name).read_text())
    return {c['check_id']:c for c in data['checks']}
clean, risky, absent = map(checks, ('clean.json','risky.json','absent.json'))
ids = {'artifact-entitlements','artifact-reason-api','artifact-private-api',
       'artifact-url-schemes','artifact-ats','artifact-sdk','artifact-embedded-sdk',
       'artifact-executable-loading','artifact-debug'}
assert set(clean) == ids and set(risky) == ids and set(absent) == ids
assert all(c['status'] == 'NOT_RUN' for c in absent.values())
assert clean['artifact-ats']['status'] == 'PASS'
assert clean['artifact-url-schemes']['status'] == 'PASS'
assert clean['artifact-private-api']['status'] == 'PASS'
assert clean['artifact-debug']['status'] == 'PASS'
for id in ('artifact-entitlements','artifact-reason-api','artifact-private-api',
           'artifact-url-schemes','artifact-ats','artifact-embedded-sdk',
           'artifact-executable-loading','artifact-debug'):
    assert risky[id]['status'] in ('FINDING','NEEDS_REVIEW'), (id,risky[id])
assert risky['artifact-reason-api']['status'] == 'NEEDS_REVIEW'
assert risky['artifact-private-api']['status'] == 'FINDING'
assert risky['artifact-entitlements']['status'] == 'NEEDS_REVIEW'
assert all(c['evidence_class'] == 'artifact' and c['reason'] for c in risky.values())
PY

# Packaging routes use an extracted temporary copy and never alter the supplied archive.
python3 - "$TMP" <<'PY'
import pathlib, sys, zipfile
p = pathlib.Path(sys.argv[1])
with zipfile.ZipFile(p/'sample.ipa','w') as z:
    for f in (p/'clean.app').rglob('*'):
        if f.is_file(): z.write(f, 'Payload/Sample.app/'+str(f.relative_to(p/'clean.app')))
archive = p/'sample.xcarchive/Products/Applications/Sample.app'
archive.mkdir(parents=True)
for f in (p/'clean.app').iterdir():
    (archive/f.name).write_bytes(f.read_bytes())
PY
PATH="$TMP/tools:$PATH" bash "$REVIEW" --app "$TMP/sample.ipa" --format json > "$TMP/ipa.json"
PATH="$TMP/tools:$PATH" bash "$REVIEW" --app "$TMP/sample.xcarchive" --format json > "$TMP/archive.json"
python3 - "$TMP" <<'PY'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1])
for name in ('ipa.json','archive.json'):
    data=json.loads((p/name).read_text())
    assert data['artifact_type'] in ('ipa','xcarchive')
    assert any(c['status']=='PASS' for c in data['checks'])
PY

# A missing Apple tool is SKIP, never a successful inspection.
mkdir "$TMP/python-only"
for command in python3 dirname; do
    ln -s "$(command -v "$command")" "$TMP/python-only/$command"
done
PATH="$TMP/python-only" /bin/bash "$REVIEW" --app "$TMP/clean.app" --format json > "$TMP/no-tools.json"
python3 - "$TMP/no-tools.json" <<'PY'
import json, sys
c={x['check_id']:x for x in json.load(open(sys.argv[1]))['checks']}
for key in ('artifact-entitlements','artifact-reason-api','artifact-private-api','artifact-debug'):
    assert c[key]['status']=='SKIP', (key,c[key])
PY

# Do not extract hostile IPA paths or report them as inspected.
python3 - "$TMP" <<'PY'
import pathlib, sys, zipfile
p=pathlib.Path(sys.argv[1])
with zipfile.ZipFile(p/'unsafe.ipa','w') as z:
    z.writestr('Payload/Sample.app/../../escape', 'bad')
PY
bash "$REVIEW" --app "$TMP/unsafe.ipa" --format json > "$TMP/unsafe.json"
python3 - "$TMP/unsafe.json" <<'PY'
import json, sys
assert all(c['status']=='NOT_RUN' for c in json.load(open(sys.argv[1]))['checks'])
PY
printf 'artifact review fixtures passed\n'
