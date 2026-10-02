"""Derive leaf coverage and check baseline claims against their maintained sources."""
import argparse
import ast
import json
import re
from pathlib import Path

ROUTES = {'scan': 'covered_by_scan', 'deep': 'covered_by_pierre_deep_review',
          'dynamic': 'covered_by_dynamic', 'vision': 'covered_by_vision'}
SECTION = re.compile(r'(?<![\w.])([1-5](?:\.\d+)+)(?![\w.])')

POSITIVE_ONLY_SOURCES = {'dyn-capture-indicator', 'dyn-musickit-auth'}


def order(section):
    return tuple(int(n) for n in section.split('.'))


def add(mapping, guideline, source):
    for section in SECTION.findall(guideline):
        mapping.setdefault(section, set()).add(source)


def scan_sources(skill):
    scripts = skill / 'scripts'
    slugs = dict((slug, int(number)) for number, slug in re.findall(
        r'(\d+)\)\s+echo ([\w-]+)', (scripts / 'findings.sh').read_text()))
    entry = (scripts / 'scan.sh').read_text()
    # Only direct, literal source calls participate. A dormant scan-*.sh is not a check.
    modules = re.findall(r'^\s*(?:source|\.) "\$SCRIPT_DIR/(lib/scan-[\w-]+\.sh)"', entry, re.M)
    result = {}
    for text in [entry] + [(scripts / name).read_text() for name in modules]:
        text = '\n'.join(line for line in text.splitlines() if not line.lstrip().startswith('#'))
        table = re.search(r"done <<'STATIC_GUIDELINE_TABLE'\n(.*?)\nSTATIC_GUIDELINE_TABLE", text, re.S)
        if table:
            for slug, guideline, evidence in re.findall(
                    r'^([\w-]+)\|([1-5](?:\.\d+)+)\|(source|metadata|resource)$', table[1], re.M):
                if slug in slugs:
                    add(result, guideline, '§%d' % slugs[slug])
        chunks = re.split(r'set_rule "([\w-]*)"', text)
        for index in range(1, len(chunks), 2):
            slug = chunks[index]
            if slug not in slugs:
                continue
            for message in re.findall(r'\b(?:fail|warn|pass)\s+"((?:[^"\\]|\\.)*)"', chunks[index + 1]):
                add(result, message, '§%d' % slugs[slug])
    return result, len(slugs)


def table_sources(path, dynamic=False):
    result, ids = {}, set()
    for line in path.read_text().splitlines():
        cells = [cell.strip() for cell in line.split('|')]
        if dynamic and len(cells) >= 6 and re.fullmatch(r'D\d+[a-z]?', cells[1]):
            names = re.findall(r'`(dyn-[\w-]+)', cells[2])
            for name in names:
                if name != 'dyn-install':
                    add(result, cells[3], name)
                    ids.add(name)
        elif not dynamic and len(cells) >= 5 and re.fullmatch(r'S\d+', cells[1]):
            name = 'vision-' + cells[1]
            add(result, cells[2], name)
            ids.add(name)
    return result, ids


def semantic_input_kinds(skill):
    folder = skill / 'scripts/semantic'
    tree = ast.parse((folder / 'collect.py').read_text())
    function = next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == 'input_kinds')
    # The collector returns literal kind lists; extract the actual return values.
    kinds = {item.value for node in ast.walk(function) if isinstance(node, ast.Return)
             for value in ast.walk(node) if isinstance(value, ast.List)
             for item in value.elts if isinstance(item, ast.Constant) and isinstance(item.value, str)}
    tree = ast.parse((folder / 'review_v4.py').read_text())
    declaration = next(node for node in tree.body if isinstance(node, ast.Assign)
                       and any(isinstance(target, ast.Name) and target.id == 'HOST_INPUT_KINDS' for target in node.targets))
    return kinds, set(ast.literal_eval(declaration.value))


def deep_check_errors(check, prose, cases, local_kinds, host_kinds):
    prefix = 'deep-%d' % check['number']
    errors = []
    procedure = re.search(r'^### %d — .*?(?=^### |^---$|\Z)' % check['number'], prose, re.M | re.S)
    if not procedure or check['question'] not in procedure[0] or len(procedure[0].strip().splitlines()) < 3:
        errors.append(prefix + ' has no matching executable review procedure')
    if not any(c.get('check_number') == check['number'] and c.get('check_key') == check['key']
               and c.get('guideline') == check['guideline'] and c.get('text', '').strip()
               and c.get('expected') in ('finding', 'no_signal', 'insufficient_evidence') for c in cases):
        errors.append(prefix + ' has no matching labeled semantic fixture')
    inputs = check.get('evidence_inputs', [])
    if not inputs:
        errors.append(prefix + ' has no declared evidence inputs')
    for kind in inputs:
        if kind not in local_kinds and not (kind in host_kinds and check.get('requires_vision')
                                            and 'host_' + kind.replace('-', '_') in check.get('required_context', [])):
            errors.append(prefix + ' cannot obtain evidence input: ' + kind)
    return errors


def deep_sources(skill, catalog):
    result, errors = {}, []
    refs = skill / 'references'
    prose = (refs / 'pierre-deep-review.md').read_text()
    case_path = skill.parents[1] / 'corpus/synthetic/semantic-v4/cases.json'
    try:
        cases = json.loads(case_path.read_text())['cases']
        local_kinds, host_kinds = semantic_input_kinds(skill)
    except (OSError, ValueError, KeyError, StopIteration) as exc:
        cases, local_kinds, host_kinds = [], set(), set()
        errors.append('cannot validate semantic review inputs: ' + str(exc))
    for check in catalog['checks']:
        problems = deep_check_errors(check, prose, cases, local_kinds, host_kinds) if check['number'] >= 32 else []
        errors.extend(problems)
        if not problems:
            add(result, check['guideline'], 'deep-%d' % check['number'])
    return result, errors


def sources(skill):
    scan, vectors = scan_sources(skill)
    refs = skill / 'references'
    catalog = json.loads((refs / 'review-catalog.json').read_text())
    deep, deep_errors = deep_sources(skill, catalog)
    dynamic, dynamic_ids = table_sources(refs / 'simulator-dynamic-review.md', True)
    vision, vision_ids = table_sources(refs / 'screenshot-vision-review.md')
    text = (skill / 'scripts/dynamic.sh').read_text()
    body = re.search(r'dyn_catalogue\(\) \{(.*?)\n\}', text, re.S)
    registered = set(re.findall(r'\bdyn-[\w-]+', body[1] if body else '')) - {'dyn-install'}
    errors = deep_errors + ['dynamic table/catalog mismatch: ' + name for name in sorted(dynamic_ids ^ registered)]
    numbers = [c['number'] for c in catalog['checks']]
    keys = [c['key'] for c in catalog['checks']]
    if len(numbers) != len(set(numbers)) or len(keys) != len(set(keys)):
        errors.append('duplicate deep-review number/key')
    return {'scan': scan, 'deep': deep, 'dynamic': dynamic, 'vision': vision}, {
        'static_vectors': vectors, 'deep_checks': len(numbers),
        'dynamic_checks': len(registered), 'vision_checks': len(vision_ids),
        'catalog_version': catalog['version']}, errors


def validate_baseline(base, evidence, errors):
    all_sections = set(base['all_sections'])
    if len(all_sections) != len(base['all_sections']):
        errors.append('duplicate all_sections entry')
    for field in ('not_counted', 'human_only'):
        for section, reason in base[field].items():
            if section not in all_sections or not isinstance(reason, str) or not reason.strip():
                errors.append('%s invalid section/reason: %s' % (field, section))
    for route, field in ROUTES.items():
        entries = base[field]
        if len(entries) != len(set(entries)):
            errors.append('%s contains duplicate sections' % field)
        for section in entries:
            if section not in all_sections:
                errors.append('%s unknown section: %s' % (field, section))
            if section in base['human_only'] or section in base['not_counted']:
                errors.append('%s excluded section claimed covered: %s' % (field, section))
            if section not in evidence[route]:
                errors.append('%s has no check source: %s' % (field, section))


def build_report(skill, base):
    evidence, counts, errors = sources(skill)
    validate_baseline(base, evidence, errors)
    all_sections = set(base['all_sections'])
    parents = {s for s in all_sections if any(t.startswith(s + '.') for t in all_sections)}
    leaves = all_sections - parents - set(base['not_counted'])
    if set(base['human_only']) - leaves:
        errors.append('human_only contains non-leaf sections')
    routes, combined, pointers = {}, set(), {}
    for route, field in ROUTES.items():
        # Invalid claims are shown as errors and never inflate the reported numerator.
        touched = set(base[field]) & leaves & set(evidence[route])
        touched -= set(base['human_only'])
        routes[route] = {'covered': len(touched), 'sections': sorted(touched, key=order)}
        combined |= touched
        for section in touched:
            pointers.setdefault(section, set()).update(evidence[route][section])
    partial = sorted((s for s in pointers if pointers[s] <= POSITIVE_ONLY_SOURCES), key=order)
    return dict(counts, denominator=len(leaves), covered=len(combined), touched=len(combined),
                positive_only=len(partial), positive_only_sections=partial,
                source_details=source_details(pointers),
                percentage=round(100 * len(combined) / len(leaves)) if leaves else 0,
                human_only=len(base['human_only']), human_only_sections=base['human_only'],
                not_counted_count=len(base['not_counted']), not_counted=base['not_counted'],
                parent_sections_count=len(parents), parent_sections=sorted(parents, key=order),
                covered_sections=sorted(combined, key=order),
                uncovered_sections=sorted(leaves - combined, key=order),
                sources={s: sorted(pointers[s]) for s in sorted(pointers, key=order)},
                routes=routes, errors=errors)


def source_details(pointers):
    partial = 'partial (positive-only observation)'
    normal = 'maintained check; evidence-dependent'
    return {section: {'scope': partial if checks <= POSITIVE_ONLY_SOURCES else normal,
                      'sources': [{'check': check, 'scope': partial if check in POSITIVE_ONLY_SOURCES else normal}
                                  for check in sorted(checks)]}
            for section, checks in sorted(pointers.items(), key=lambda pair: order(pair[0]))}


def summary_line(report):
    return ('Coverage inventory: {covered}/{denominator} leaf sections ({percentage}%); '
            '{touched} touched, {positive_only} positive-only; '
            '{static_vectors} static vectors, {deep_checks} deep-review checks, '
            '{dynamic_checks} dynamic checks, {vision_checks} vision checks, '
            '{human_only} human-only sections.').format(**report)


def markdown(report):
    lines = ['# Guideline section coverage', '',
             'Generated by `skills/appstore-precheck/scripts/coverage-sections.sh --markdown`.', '',
             summary_line(report), '',
             'This percentage counts sections touched by maintained checks, not automated verification of all requirements.',
             'Routes overlap; advisory and vision checks require their evidence and may SKIP on a particular run.', '',
             '| Route | Leaf sections |', '|---|---:|']
    lines += ['| %s | %s |' % (route, entry['covered']) for route, entry in report['routes'].items()]
    lines += ['', '## Covered sections and check sources', '', '| Section | Sources | Scope |', '|---|---|---|']
    lines += ['| %s | %s | %s |' % (s, ', '.join(v), report['source_details'][s]['scope'])
              for s, v in report['sources'].items()]
    lines += ['', '## Not audited', '', 'Uncovered sections: ' + ', '.join(report['uncovered_sections']) + '.', '',
              'Human-only sections require external evidence or a human decision:', '']
    lines += ['- %s: %s' % (s, reason) for s, reason in report['human_only_sections'].items()]
    lines += ['', '## Denominator exclusions', '',
              'Parents (not inherited by their children): ' + ', '.join(report['parent_sections']) + '.', '']
    lines += ['- %s: %s' % (s, reason) for s, reason in report['not_counted'].items()]
    lines += ['', 'Cross-validation errors: %d.' % len(report['errors'])]
    lines += ['- ' + e for e in report['errors']]
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument('--json', action='store_true')
    group.add_argument('--markdown', action='store_true')
    parser.add_argument('--baseline', type=Path)
    args = parser.parse_args()
    skill = Path(__file__).resolve().parents[2]
    try:
        base = json.loads((args.baseline or skill / 'guidelines-baseline.json').read_text())
        report = build_report(skill, base)
    except (OSError, ValueError, KeyError, TypeError) as exc:
        parser.exit(1, 'coverage-sections: cannot validate inputs: %s\n' % exc)
    print(json.dumps(report, indent=2, ensure_ascii=False) if args.json else markdown(report), end='\n' if args.json else '')
    return 1 if report['errors'] else 0


if __name__ == '__main__':
    raise SystemExit(main())
