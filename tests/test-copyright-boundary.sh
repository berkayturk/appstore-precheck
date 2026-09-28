#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
import json,re,subprocess
from pathlib import Path

catalog=json.loads(Path('skills/appstore-precheck/references/guideline-obligations.json').read_text())
for item in catalog['obligations']:
    assert 'text' not in item, item['id']
    assert len(item['criterion'].split()) <= 55, item['id']

source=Path('.planning/opus-work/skills/appstore-precheck/references/requirement-catalog.json')
if not source.exists():
    print('copyright overlap: SKIP (local source cache absent)')
else:
    private=json.loads(source.read_text())
    def words(value):
        return re.findall(r"[\w’'-]+", value.lower(), re.UNICODE)
    phrases=set()
    for item in private['requirements']:
        tokens=words(item['text'])
        phrases.update(tuple(tokens[i:i+8]) for i in range(len(tokens)-7))
    tracked=subprocess.check_output(['git','ls-files'],text=True).splitlines()
    modified=set(subprocess.check_output(['git','diff','--name-only','main'],text=True).splitlines())
    modified.update(subprocess.check_output(['git','ls-files','--others','--exclude-standard'],text=True).splitlines())
    # Inspect feature additions; pre-existing licensed citation fixtures are not
    # introduced by this branch. Binary files are skipped.
    for name in sorted((set(tracked)|modified)&modified):
        path=Path(name)
        if not path.is_file() or path.suffix.lower() in {'.png','.jpg','.jpeg','.gif','.pdf','.ipa','.app'}:
            continue
        raw=path.read_bytes()
        if b'\0' in raw:
            continue
        tokens=words(raw.decode('utf-8','replace'))
        current={tuple(tokens[i:i+8]) for i in range(len(tokens)-7)}
        baseline=subprocess.run(['git','show','main:'+name],capture_output=True,check=False)
        old=words(baseline.stdout.decode('utf-8','replace')) if baseline.returncode == 0 else []
        inherited={tuple(old[i:i+8]) for i in range(len(old)-7)}
        assert not (current & phrases) - inherited, '{}: new eight-word source overlap'.format(name)
    print('copyright overlap: OK')
PY
if command -v npm >/dev/null 2>&1; then
  npm_config_cache="$(mktemp -d)" npm pack --dry-run --json | python3 -c 'import json,sys; names=[f["path"] for f in json.load(sys.stdin)[0]["files"]]; assert not any(p.startswith(".planning/") or "requirement-catalog" in p or "sections.json" in p for p in names); print("npm package boundary: OK")'
fi
