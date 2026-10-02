"""Regenerate current coverage counts; released changelog entries stay historical."""
import argparse
import importlib.util
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SURFACES = ('README.md', 'MAINTENANCE.md', 'CHANGELOG.md', 'AGENTS.md',
            'skills/appstore-precheck/SKILL.md',
            'skills/appstore-precheck/references/methodology.md')


def prose_counts(text, report):
    vectors, deep = str(report['static_vectors']), str(report['deep_checks'])
    text = re.sub(r'\b\d+(?= (?:static |rejection )?vectors\b)', vectors, text)
    adjectives = r'(?:semantic deep-review|deep semantic|semantic|deep-review|evidence-based|read-only, evidence-based|Pierre deep-review)'
    text = re.sub(r'\b\d+(?= ' + adjectives + r' checks\b)', deep, text)
    text = re.sub(r'(?<=all )\d+(?= (?:checks|every time|passed))', deep, text)
    text = re.sub(r'\b\d+(?=-check table)', deep, text)
    text = re.sub(r'(?<=N of )\d+(?= findings)', deep, text)
    text = re.sub(r'(?<=of )\d+(?=[)"`])', deep, text)
    text = re.sub(r'(?<=deep review \()\d+(?= checks)', deep, text)
    text = re.sub(r'(?<=phase-4-pierre-deep-review-)\d+(?=-semantic-checks)', deep, text)
    return text


def replacements(report, summary, markdown):
    changed = {}
    for name in SURFACES:
        path = ROOT / name; old = path.read_text()
        parts = re.split(r'(?m)(^## \[(?!Unreleased)[^]]+\].*$)', old, maxsplit=1) if name == 'CHANGELOG.md' else [old]
        current, history = parts[0], ''.join(parts[1:])
        current = re.sub(r'^Coverage inventory: .*$', lambda _: summary, current, flags=re.M)
        current = prose_counts(current, report)
        if current + history != old:
            changed[path] = current + history
    path = ROOT / 'docs/guideline-coverage.md'
    if path.read_text() != markdown:
        changed[path] = markdown
    return changed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true'); args = parser.parse_args()
    skill = ROOT / 'skills/appstore-precheck'
    spec = importlib.util.spec_from_file_location('coverage_sections', skill / 'scripts/lib/coverage-sections.py')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    report = module.build_report(skill, json.loads((skill / 'guidelines-baseline.json').read_text()))
    if report['errors']:
        parser.exit(1, '\n'.join(report['errors']) + '\n')
    changed = replacements(report, module.summary_line(report), module.markdown(report))
    if args.check and changed:
        parser.exit(1, 'Stale derived coverage: ' + ', '.join(str(p.relative_to(ROOT)) for p in changed) + '\n')
    for path, content in changed.items():
        path.write_text(content)
    print('Coverage documentation is derived and current.' if args.check else 'Updated %d coverage documents.' % len(changed))


if __name__ == '__main__':
    main()
