#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -B - <<'PY'
import importlib.util,tempfile
from pathlib import Path
s=importlib.util.spec_from_file_location('snapshot','skills/appstore-precheck/scripts/source-snapshot.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'source.swift').write_text('fixture');(p/'build').mkdir();(p/'build'/'out').write_text('output')
 first=m.snapshot(p);assert first['stable_read']
 (p/'build'/'out').write_text('generated change');assert m.snapshot(p)['sha256']==first['sha256']
 (p/'source.swift').write_text('source changed');assert m.snapshot(p)['sha256']!=first['sha256']
 (p/'external').symlink_to('/unavailable/private');assert m.snapshot(p)['entries']['external']['kind']=='symlink'
 (p/'source.swift').chmod(0o755);assert m.snapshot(p)['entries']['source.swift']['mode']==0o755
print('source snapshot: read-only manifest, exclusions, change and symlink tests passed')
PY
