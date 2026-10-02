"""Reject newly introduced long verbatim source spans; never publish the source cache."""
import json
import re
import subprocess
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def grams(text):
    words = re.findall(r"[\w’'-]+", text.casefold())
    return {tuple(words[i:i + 26]) for i in range(len(words) - 25)}


class Text(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []

    def handle_data(self, data):
        self.parts.append(data)


def introduced(current, old, source):
    return (grams(current) - grams(old)) & grams(source)


def check_quotes():
    file = 'skills/appstore-precheck/guidelines-fingerprints.json'
    current = json.loads((ROOT / file).read_text())['sections']
    old = json.loads(subprocess.check_output(['git', 'show', 'HEAD:' + file], cwd=ROOT))['sections']
    for section, entry in current.items():
        if entry.get('quote') != old.get(section, {}).get('quote'):
            if len(entry.get('quote', '').split()) > 25:
                raise AssertionError('new pinned quote exceeds 25 words: ' + section)
    print('PASS: no new oversized pinned quotes (legacy quotes unchanged)')


def main():
    check_quotes()
    probe = ' '.join('syntheticword%d' % i for i in range(40))
    if not introduced(probe, '', probe) or introduced(probe, probe, probe):
        raise AssertionError('copyright checker mutation probe failed')
    snapshot = ROOT / '.planning/guideline-verification/20260927/apple-guidelines.html'
    if not snapshot.is_file():
        print('SKIP: verbatim-source comparison requires the ignored local HTML snapshot')
        return
    parser = Text()
    parser.feed(snapshot.read_text())
    source = ' '.join(parser.parts)
    changed = subprocess.check_output(['git', 'diff', '--name-only', 'HEAD'], cwd=ROOT, text=True).splitlines()
    added = subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard'], cwd=ROOT, text=True).splitlines()
    for name in sorted(set(changed + added)):
        if name.startswith('.planning/') or name.endswith('.html'):
            raise AssertionError('private source archive in public diff: ' + name)
        path = ROOT / name
        if not path.is_file():
            continue
        raw = path.read_bytes()
        if b'\0' in raw:
            continue
        old = subprocess.run(['git', 'show', 'HEAD:' + name], cwd=ROOT, capture_output=True)
        if introduced(raw.decode('utf-8', 'replace'), old.stdout.decode('utf-8', 'replace'), source):
            raise AssertionError('new 26-word verbatim source span: ' + name)
    print('PASS: changed public files introduce no 26-word source spans')


if __name__ == '__main__':
    main()
