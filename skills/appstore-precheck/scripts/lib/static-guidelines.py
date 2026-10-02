#!/usr/bin/env python3
"""Narrow, advisory source/manifest/metadata checks; never shipping proof."""
import argparse
import fnmatch
import json
import os
import pathlib
import plistlib
import re
from xml.parsers.expat import ExpatError

PRUNE = {'.git', 'Pods', 'Carthage', '.build', 'build', 'DerivedData',
         'SourcePackages', 'checkouts', '.swiftpm', '.claude', 'worktrees',
         'node_modules', 'vendor', '.planning', '.symlinks', '*.app', '*.xcarchive', '*.dSYM', '*.xcframework'}
SOURCE = {'.swift', '.m', '.mm', '.h', '.js', '.jsx', '.ts', '.tsx'}
RESOURCE = {'.strings', '.xcstrings'}
ADS = (r'GoogleMobileAds|GADMobileAds|AppLovinSDK|ALSdk|AppsFlyerLib|\bAdjust\b|'
       r'FBAudienceNetwork|BranchSDK|IronSource|UnityAds|VungleAds|Chartboost|'
       r'InMobi|IMSdk|MTGSDK|PAGAdSDK|BUAdSDK|\bSingular\b|KochavaTracker|TenjinSDK')
TOKEN = re.compile(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|//[^\n]*|/\*.*?\*/', re.S)


def uncomment(text):
    return TOKEN.sub(lambda m: '\n' * m[0].count('\n') if m[0].startswith(('/', '/*')) else m[0], text)


def checked_text(path):
    if path.is_symlink():
        raise ValueError('symlink input not followed')
    limit = 8 if path.suffix in RESOURCE else 2
    if path.stat().st_size > limit * 1024 * 1024:
        raise ValueError('input exceeds %d MiB read limit' % limit)
    with path.open('rb') as stream:
        bom = stream.read(2)
    encoding = 'utf-16' if path.suffix == '.strings' and bom in (b'\xff\xfe', b'\xfe\xff') else 'utf-8'
    return path.read_text(encoding=encoding)


def input_error(path, exc, root=None):
    path = pathlib.Path(path)
    try:
        name = str(path.relative_to(root)) if root else path.name
    except ValueError:
        name = path.name
    return name


def read_candidate(path):
    if path.suffix in {'.plist', '.entitlements'}:
        if path.is_symlink() or path.stat().st_size > 2 * 1024 * 1024:
            raise ValueError('manifest is a symlink or exceeds 2 MiB read limit')
        with path.open('rb') as stream:
            value = plistlib.load(stream)
        if not isinstance(value, dict):
            raise ValueError('manifest root is not a dictionary')
        return plistlib.dumps(value).decode('utf-8')
    return checked_text(path)


def read_files(root, excludes):
    result, gaps = {}, []
    onerror = lambda exc: gaps.append(input_error(exc.filename, exc, root))
    for folder, dirs, files in os.walk(root, followlinks=False, onerror=onerror):
        keep = [d for d in dirs if not any(fnmatch.fnmatch(d, pattern) for pattern in PRUNE | set(excludes))]
        for d in keep:
            if (pathlib.Path(folder) / d).is_symlink():
                gaps.append(input_error(pathlib.Path(folder) / d, ValueError('symlink'), root))
        dirs[:] = [d for d in keep if not (pathlib.Path(folder) / d).is_symlink()]
        for name in files:
            path = pathlib.Path(folder) / name
            if path.suffix not in SOURCE | RESOURCE | {'.plist', '.entitlements', '.pbxproj'} and name not in {'Podfile', 'Package.swift', 'Package.resolved'}:
                continue
            try:
                result[path] = read_candidate(path)
            except (OSError, UnicodeError, ValueError, plistlib.InvalidFileException, ExpatError) as exc:
                gaps.append(input_error(path, exc, root))
    return result, gaps


def context(root, metadata, main, excludes):
    files, gaps = read_files(root, excludes)
    src = {p: uncomment(t) for p, t in files.items() if p.suffix in SOURCE}
    resources = {p: t for p, t in files.items() if p.suffix in RESOURCE}
    plists = {p: plistlib.loads(t.encode('utf-8')) for p, t in files.items()
              if p.suffix in {'.plist', '.entitlements'}}
    main_data = plists.get(main, {})
    if main not in plists and main.exists():
        try:
            main_data = plistlib.loads(read_candidate(main).encode('utf-8'))
        except (OSError, UnicodeError, ValueError, plistlib.InvalidFileException, ExpatError) as exc:
            gaps.append(input_error(main, exc, root))
    extensions = {p: v for p, v in plists.items() if 'NSExtension' in v or 'NSAppClip' in v}
    return dict(root=root, metadata=metadata, main=main_data, files=files, gaps=gaps,
                src=src, resources=resources, plists=plists, extensions=extensions)


def outcome(hit=False, reason='', path=None, skip=False):
    return dict(status='SKIP' if skip else 'WARN' if hit else 'PASS',
                reason=reason or 'No matching risk signal in scanned inputs.',
                file=str(path) if path else '')


def hit_file(files, pattern):
    return next((p for p, text in files.items() if re.search(pattern, text, re.I)), None)


def metadata_files(c, names):
    base = c['metadata']
    if not base.is_dir() or base.is_symlink():
        return []
    files = [p for locale in sorted(base.iterdir()) if locale.is_dir() and not locale.is_symlink()
             and locale.name not in {'default', 'review_information', 'trade_representative_contact_information'}
             for name in names for p in [locale / (name + '.txt')] if p.is_file() or p.is_symlink()]
    for p in files:
        try:
            checked_text(p)
        except (OSError, UnicodeError, ValueError) as exc:
            raise ValueError(input_error(p, exc)) from exc
    return files


def release_notes(c):
    files = metadata_files(c, ['release_notes'])
    if not files:
        return outcome(skip=True, reason='Release notes metadata unavailable.')
    for p in files:
        value = checked_text(p).strip()
        desc = p.with_name('description.txt')
        same = desc.is_file() and not desc.is_symlink() and value == checked_text(desc).strip()
        version_file = c['metadata'] / 'version.txt'
        version = checked_text(version_file).strip() if version_file.is_file() else ''
        if not value and version == '1.0':
            continue
        if not value and not version:
            return outcome(True, 'Empty release notes with unknown version; low-confidence update review.', p)
        if not value or re.fullmatch(r'lorem(?: ipsum)?[.!]?|TODO|N[/-]A', value, re.I) or same:
            return outcome(True, 'Release notes are empty, a placeholder, or repeat the description.', p)
    return outcome(reason='Release notes contain specific non-placeholder text.')


def restart(c):
    source = {p: t for p, t in c['src'].items()
              if not re.search(r'(?m)^\s*(?:@testable\s+)?import\s+(?:Testing|XCTest)\b', t)}
    p = hit_file(source, r'"[^"\n]*(?:restart your device|reboot|change your settings in Settings\s*>\s*General)[^"\n]*"')
    p = p or hit_file(c['resources'], r'restart your device|\breboot\b|change your settings in Settings\s*>\s*General')
    return outcome(bool(p), 'Device restart/settings instruction string; inspect the user-facing context.' if p else '', p)


def browser(c):
    deps = {p: uncomment(t) for p, t in c['files'].items() if p.name in {'Podfile', 'Package.swift', 'Package.resolved'} or p.suffix == '.pbxproj'}
    p = next((p for p, text in deps.items()
              if re.search(r"[\"'][^\"'\n]*\b(?:Chromium|CEF|Gecko|Blink)\b(?![^\"'\n]*\.(?:swift|m|mm|h|storyboard|xib)[\"'])|\b(?:Chromium|CEF|Gecko|Blink)\.framework", text)), None)
    legacy = hit_file(c['src'], r'\bUIWebView\s*(?:\(|[*>])|:\s*UIWebView\b')
    if legacy:
        return outcome(True, 'Deprecated UIWebView reference; verify the shipping target and Xcode SDK before removal.', legacy)
    return outcome(bool(p), 'Non-WebKit engine dependency signal; verify entitlement and regional eligibility.' if p else '', p)


def intents(c):
    declared = any(v.get('INIntentsSupported') or
                   re.search(r'intent', json.dumps(v.get('NSExtension', {})), re.I) for v in c['plists'].values())
    handler = hit_file(c['src'], r'\b(?:INExtension|INIntentHandlerProviding|\w+IntentHandling)\b|func\s+handler\s*\(\s*for\s+intent')
    modern = hit_file(c['src'], r':\s*(?:\w+\s*,\s*)?(?:AppIntent|AppShortcutsProvider)\b')
    bad = (declared and not (handler or modern)) or (handler and not declared)
    return outcome(bool(bad), 'Intent declaration/legacy handler mismatch; inspect target membership. AppIntent discovery needs no legacy plist.' if bad else 'No intent parity mismatch (or intents not used).', handler)


def call_filter(c):
    p = hit_file(c['src'], r'\b(?:ILMessageFilterExtension|CXCallDirectoryProvider|CXCallDirectoryManager)\b')
    ui = hit_file(c['src'], r'"[^"\n]*(?:blocked (?:numbers|callers)|call blocking|spam filter|blocking settings)[^"\n]*"') or hit_file(c['resources'], r'blocked numbers|call blocking|spam filter')
    return outcome(bool(p and not ui), 'Call/filter API signal without a visible blocking-control label; inspect reachable settings.' if p and not ui else 'No missing filter-control signal (or APIs not used).', p)


def face_auth(c):
    native = hit_file(c['src'], r'\b(?:LocalAuthentication|LAContext)\b')
    for p, text in c['src'].items():
        face = re.search(r'\b(?:VNFaceObservation|VNDetectFace\w*|FaceTecSDK|FacePhi)\b', text)
        auth = re.search(r'login|authenticate|authentication|identity verification', text, re.I)
        if face and auth and not native:
            return outcome(True, 'Face recognition and authentication context coexist without LocalAuthentication; inspect authentication design.', p)
    return outcome(reason='No custom face-authentication signal (or native authentication present).')


def documents(c):
    picker = hit_file(c['src'], r'\bUIDocumentPicker\w*\b|\.fileImporter\s*\(|\bUIDocumentBrowserViewController\b')
    if picker:
        return outcome(reason='System document access is used; inspect custom browser reachability separately.')
    custom = next((p for p, t in c['src'].items()
                   if re.search(r'FileManager\.default\.contentsOfDirectory', t)
                   and re.search(r'\b(?:List|Table|UICollectionView|UITableView)\b', t)), None)
    custom = custom or hit_file(c['src'], r'(?:navigationTitle|Text|title\s*=)\s*\(?\s*"(?:My Files|Files|Documents)"')
    custom = custom or hit_file(c['resources'], r'"(?:My Files|Files|Documents)"')
    return outcome(bool(custom), 'Custom file-browser signal without system document access; inspect Files/iCloud availability.' if custom else 'No custom file-browser signal.', custom)


def extension_parity(c):
    if not c['extensions']:
        return outcome(reason='No discoverable extension target.')
    main_id = c['main'].get('CFBundleIdentifier', '')
    if not main_id or '$(' in main_id or '${' in main_id:
        return outcome(skip=True, reason='Main bundle identifier is absent or build-setting-derived; archive verification required.')
    for p, value in c['extensions'].items():
        bid = value.get('CFBundleIdentifier', '')
        if not bid or '$(' in bid or '${' in bid:
            return outcome(skip=True, reason='Extension bundle id resolved by build settings; archive verification required.', path=p)
        if not bid or not bid.startswith(main_id + '.'):
            return outcome(True, 'Extension bundle identifier is missing or lacks the main-app prefix; verify target configuration.', p)
    return outcome(reason='Literal extension bundle identifiers share the main-app prefix.')


def matter(c):
    p = hit_file(c['src'], r'\bimport\s+(?:MatterSupport|Matter)\b')
    entitlement = any('com.apple.developer.matter.allow-setup-payload' in v for v in c['plists'].values())
    supported = any(re.search('matter', json.dumps(v.get('NSExtension', {})), re.I) for v in c['extensions'].values())
    return outcome(bool((p or entitlement) and not supported), 'Matter setup signal without a discoverable MatterSupport extension; verify target configuration.' if (p or entitlement) and not supported else 'No missing Matter extension signal (or Matter not used).', p)


def extension_ads(c):
    if not c['extensions']:
        return outcome(skip=True, reason='No discoverable extension target; not applicable.')
    for plist in c['extensions']:
        if plist.parent == c['root'] or plist.parent.name in {'ios', 'Sources', 'src'}:
            return outcome(skip=True, reason='Extension source dir unresolved; inspect target membership.', path=plist)
        files = {p: t for p, t in c['src'].items() if plist.parent in p.parents}
        p = hit_file(files, r'(?:import\s+|@import\s+|#import\s*[<"])(?:' + ADS + r')\b')
        if p:
            return outcome(True, 'Advertising/attribution SDK imported by extension-directory source; verify extension target membership.', p)
    return outcome(reason='No advertising import in discovered extension directories; resolved link phases are not audited.')


def ar_depth(c):
    p = hit_file(c['src'], r'\bimport\s+ARKit\b') or hit_file(c['files'], r'ARKit\.framework')
    if not p:
        return outcome(reason='ARKit not used.')
    sessions = [f for f, t in c['src'].items() if re.search(r'\b(?:ARSession|ARView|RealityKit)\b', t)]
    screens = sum(len(re.findall(r'struct\s+\w+\s*:\s*View\b|class\s+\w+\s*:\s*UIViewController\b', t)) for t in c['src'].values())
    bad = len(sessions) == 1 and screens < 2
    return outcome(bad, 'AR use is confined to one source file with fewer than two view declarations; low-confidence depth review, not proof of inadequate AR.' if bad else 'No narrow AR-depth signal.', p)


def companion(c):
    p = hit_file(c['src'], r'"[^"\n]*(?:download|install)\s+[^"\n]{1,60}\s+to (?:continue|proceed|use)[^"\n]*"') or hit_file(c['resources'], r'(?:download|install)\s+[^"\n]{1,60}\s+to (?:continue|proceed|use)')
    bad = bool(c['main'].get('LSApplicationQueriesSchemes') and p)
    return outcome(bad, 'App-query schemes coexist with an install-to-continue instruction; inspect whether core functionality requires another app.' if bad else '', p if bad else None)


def game_ids(c):
    for p, text in c['src'].items():
        if re.search(r'\bGameKit\b', text) and re.search(r'\b(?:playerID|gamePlayerID|teamPlayerID)\b', text) and re.search(r'\b(?:URLRequest|URLSession|Analytics\.logEvent|Mixpanel|Amplitude)\b', text):
            return outcome(True, 'Game Center identifier and network/analytics code coexist in one file; trace actual data flow before concluding sharing.', p)
    return outcome(reason='No co-located Game Center identifier/network signal (or GameKit not used).')


def emoji(c):
    if not c['root'].is_dir():
        return outcome(skip=True, reason='Asset root is unavailable.')
    seen = 0
    for folder, dirs, files in os.walk(c['root'], followlinks=False):
        seen += len(files)
        dirs[:] = [d for d in dirs if not any(fnmatch.fnmatch(d, pattern) for pattern in PRUNE)
                   and not (pathlib.Path(folder) / d).is_symlink()]
        for name in dirs + files:
            p = pathlib.Path(folder) / name
            suspect = (name.lower().endswith('.imageset') and 'emoji' in name.lower())
            suspect = suspect or name.lower() == 'applecoloremoji.ttc'
            suspect = suspect or bool(re.search(r'(?:^|[_ -])(?:applecoloremoji|emoji)(?:[_ -]|\.)', name, re.I) and p.suffix.lower() == '.png')
            if suspect:
                return outcome(True, 'Possible embedded Apple emoji artwork by asset name; low-confidence visual/license review required.', p)
    if seen == 0:
        return outcome(skip=True, reason='No project files were read; emoji artwork assets not audited.')
    return outcome(reason='Apple emoji artwork asset signal not used.')


def miniapp(c):
    for p, text in c['src'].items():
        terms = [r'\bWKScriptMessageHandler\b', r'https?://[^"\s]{1,2048}(?:\.js\b|/scripts?/)', r'\bevaluateJavaScript\b', r'\b(?:CLLocationManager|AVCaptureSession|CNContactStore|requestWhenInUseAuthorization)\b']
        if all(re.search(term, text) for term in terms):
            return outcome(True, 'Remote JavaScript, message handler, evaluation and native-sensitive API coexist; inspect mini-app bridge exposure.', p)
    return outcome(reason='No combined remote-script/native-sensitive bridge signal (or webview not used).')


def endorsements(c):
    files = metadata_files(c, ['name', 'subtitle', 'description', 'keywords', 'promotional_text', 'release_notes'])
    if not files:
        return outcome(skip=True, reason='Store metadata unavailable.')
    for p in files:
        if re.search(r'Apple recommends|featured by Apple|Apple.s choice|Apple Design Award|#1 on the App Store|(?:official|endorsed by|approved by)\s+(?:Apple|App Store)', checked_text(p), re.I):
            return outcome(True, 'Apple endorsement/official-product marketing claim; verify authorization and accuracy.', p)
    return outcome(reason='No matched Apple endorsement claim in metadata.')


CHECKS = {'release-notes-specificity': release_notes, 'device-restart-instructions': restart,
          'browser-engine': browser, 'intent-handler-parity': intents,
          'call-filter-controls': call_filter, 'face-authentication': face_auth,
          'document-browser-access': documents, 'extension-bundle-parity': extension_parity,
          'matter-extension': matter, 'extension-advertising': extension_ads,
          'ar-integration-depth': ar_depth, 'companion-app-required': companion,
          'game-center-id-sharing': game_ids, 'metadata-emoji': emoji,
          'miniapp-native-bridge': miniapp, 'apple-endorsement-claims': endorsements}


def evaluate(root, metadata, main, excludes):
    c = context(root, metadata, main, excludes)
    result = {}
    independent = {'release-notes-specificity', 'metadata-emoji', 'apple-endorsement-claims'}
    if c['gaps']:
        result['_input_gaps'] = {'count': len(set(c['gaps'])), 'paths': sorted(set(c['gaps']))[:3]}
    for key, check in CHECKS.items():
        if key not in independent and not c['src']:
            result[key] = outcome(skip=True, reason='Source directory unavailable or no source files were read.')
            continue
        if key in {'intent-handler-parity', 'companion-app-required'} and not c['main']:
            result[key] = outcome(skip=True, reason='Main Info.plist unavailable for manifest comparison.')
            continue
        try:
            result[key] = check(c)
        except (OSError, UnicodeError, ValueError) as exc:
            result[key] = outcome(skip=True, reason='Input could not be completely read: ' + str(exc)[:500])
    for key, row in result.items():
        if key.startswith('_'):
            continue
        if row['file']:
            try:
                row['file'] = str(pathlib.Path(row['file']).relative_to(root))
            except ValueError:
                pass
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=pathlib.Path, required=True)
    parser.add_argument('--metadata', type=pathlib.Path, required=True)
    parser.add_argument('--plist', type=pathlib.Path, required=True)
    parser.add_argument('--exclude-dir', action='append', default=[])
    args = parser.parse_args()
    print(json.dumps(evaluate(args.root.resolve(), args.metadata.resolve(), args.plist.resolve(), args.exclude_dir)))


if __name__ == '__main__':
    main()
