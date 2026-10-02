"""Choose a shared scheme using project identity, then verified application targets."""
import json
import os
from pathlib import Path
import subprocess


def listings(output):
    decoder = json.JSONDecoder()
    for index, char in enumerate(output):
        if char != '{':
            continue
        try:
            data, _ = decoder.raw_decode(output[index:])
        except ValueError:
            continue
        if isinstance(data, dict):
            for key in ('project', 'workspace'):
                value = data.get(key)
                if isinstance(value, dict) and isinstance(value.get('schemes'), list):
                    yield value


def scheme_list(output):
    return sorted({s for value in listings(output) for s in value['schemes'] if isinstance(s, str)})


def application_targets(copy, excluded):
    targets = set()
    model = Path(__file__).resolve().parents[1] / 'project-model.sh'
    for base, dirs, files in os.walk(copy):
        dirs[:] = [d for d in dirs if not excluded(Path(base) / d) and not (Path(base) / d).is_symlink()]
        if Path(base).suffix != '.xcodeproj' or 'project.pbxproj' not in files:
            continue
        result = subprocess.run(['bash', '-c', 'source "$1"; pm_app_targets "$2"',
                                 'build-schemes', str(model), str(Path(base) / 'project.pbxproj')],
                                capture_output=True, text=True, timeout=10)
        if result.returncode == 0:
            targets.update(result.stdout.splitlines())
    return targets


def select(output, project, copy, excluded):
    schemes = scheme_list(output)
    if len(schemes) == 1:
        return schemes[0]
    name = Path(project).stem
    if name in schemes:
        return name
    listed_targets = {t for value in listings(output) for t in value.get('targets', []) if isinstance(t, str)}
    targets = application_targets(copy, excluded)
    if listed_targets:
        targets &= listed_targets
    if len(targets) == 1 and targets.issubset(schemes):
        return targets.pop()
    raise ValueError('select one shared application scheme; candidates: ' + (', '.join(schemes) or '(none)'))
