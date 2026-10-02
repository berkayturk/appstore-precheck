import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import shutil
import stat
from unittest import mock
import unittest

ROOT = Path(__file__).resolve().parents[1]
S = ROOT / 'skills/appstore-precheck/scripts'


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), S / 'lib' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class BuildHarvest(unittest.TestCase):
    def test_monorepo_flutter_links_require_trusted_cache_or_sdk(self):
        plan = load('build-plan')
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary); repo = base / 'repo'; repo.mkdir()
            cache = base / 'cache/hosted/pub.dev/plugin'; cache.mkdir(parents=True)
            (cache / 'plugin.swift').write_text('plugin source')
            sdk = base / 'flutter'; (sdk / 'bin').mkdir(parents=True)
            (sdk / 'bin/flutter').write_text('tool')
            (sdk / 'packages/flutter').mkdir(parents=True)
            (sdk / 'packages/flutter/pubspec.yaml').write_text('name: flutter')
            link = repo / 'apps/mobile/ios/.symlinks/plugins/plugin'; link.parent.mkdir(parents=True)
            with mock.patch.dict(os.environ, PUB_CACHE=str(base / 'cache'), FLUTTER_ROOT=str(sdk)):
                link.symlink_to(cache, target_is_directory=True)
                self.assertEqual(plan.checked_links(repo), [link])
                plan.copy_inputs(repo, base / 'copy')
                copied = base / 'copy/apps/mobile/ios/.symlinks/plugins/plugin'
                self.assertFalse(copied.is_symlink())
                self.assertEqual((copied / 'plugin.swift').read_text(), 'plugin source')
                link.unlink(); link.symlink_to(sdk / 'packages/flutter', target_is_directory=True)
                self.assertEqual(plan.checked_links(repo), [link])
                link.unlink(); arbitrary = repo / 'arbitrary'; arbitrary.mkdir()
                link.symlink_to(arbitrary, target_is_directory=True)
                with self.assertRaises(ValueError):
                    plan.checked_links(repo)

    def test_root_flutter_link_cannot_materialize_arbitrary_repo_directory(self):
        plan = load('build-plan')
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary); target = repo / 'source'; target.mkdir()
            link = repo / 'ios/.symlinks/plugins/plugin'; link.parent.mkdir(parents=True)
            link.symlink_to(target, target_is_directory=True)
            with self.assertRaises(ValueError):
                plan.checked_links(repo)

    def test_repository_home_boundary_rejects_home_and_ancestors_only(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary); home = base / 'home'; home.mkdir()
            (home / 'project').mkdir(); (home / 'project/App.xcodeproj').mkdir()
            for repo in (base, home):
                result = subprocess.run(['bash', str(S / 'build-run.sh'), '--repo', str(repo), '--framework', 'native', '--dry-run'],
                                        env=dict(os.environ, HOME=str(home)), capture_output=True, timeout=5)
                self.assertEqual(result.returncode, 64, str(repo))
            result = subprocess.run(['bash', str(S / 'build-run.sh'), '--repo', str(home / 'project'), '--framework', 'native', '--dry-run'],
                                    env=dict(os.environ, HOME=str(home)), capture_output=True, timeout=5)
            self.assertNotEqual(result.returncode, 64, 'projects under HOME must stay buildable')

    def test_private_credentials_are_excluded_from_build_copy(self):
        plan = load('build-plan')
        names = ('id_rsa', 'id_rsa.pub', 'id_ed25519_work', '.git-credentials',
                 'login.keychain-db', 'credentials-prod.json', 'service-account-admin.json')
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary); repo = base / 'repo'; repo.mkdir()
            for name in names:
                (repo / name).write_text('secret')
            (repo / 'App.swift').write_text('source')
            plan.copy_inputs(repo, base / 'copy')
            for name in names:
                self.assertFalse((base / 'copy' / name).exists(), name)

    def test_snapshot_ignores_fifo_without_blocking(self):
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary); os.mkfifo(repo / 'a.fifo')
            command = ['python3', '-c', "import importlib.util,pathlib,json; s=importlib.util.spec_from_file_location('e',%r);m=importlib.util.module_from_spec(s);s.loader.exec_module(m); print(json.dumps(m.snapshot(pathlib.Path(%r))))" % (str(S / 'lib/build-evidence.py'), str(repo))]
            result = subprocess.run(command, capture_output=True, text=True, timeout=2)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout), {})

    def test_snapshot_ignores_socket_and_device_modes(self):
        original = Path.lstat
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary); (repo / 'special').write_text('not a regular file')
            for mode in (stat.S_IFSOCK, stat.S_IFCHR):
                def special_mode(path):
                    values = list(original(path))
                    if path.name == 'special':
                        values[0] = mode | 0o600
                    return os.stat_result(values)
                with mock.patch.object(Path, 'lstat', special_mode):
                    self.assertEqual(load('build-evidence').snapshot(repo), {})

    def test_snapshot_prunes_generated_dependency_trees(self):
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary); (repo / 'App.swift').write_text('source')
            for folder in ('node_modules', 'Pods', 'build'):
                path = repo / folder / 'large-file'; path.parent.mkdir(); path.write_text('unused')
            self.assertEqual(set(load('build-evidence').snapshot(repo)), {'App.swift'})

    def test_action_trust_without_ripgrep(self):
        with tempfile.TemporaryDirectory() as temporary:
            tools = Path(temporary)
            for name in ('grep', 'cat', 'dirname'):
                (tools / name).symlink_to(shutil.which(name))
            env = dict(os.environ, PATH=str(tools))
            result = subprocess.run([shutil.which('bash'), str(ROOT / 'tests/test-action-trust.sh')], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotIn('command not found', result.stderr)

    def test_copy_preserves_source_and_materializes_allowed_links(self):
        plan = load('build-plan')
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary); repo = base / 'repo'; repo.mkdir()
            (repo / 'src').mkdir(); (repo / 'src/code.swift').write_text('original')
            for secret in ('.npmrc', '.netrc', 'private.pem', 'release.key', 'store.jks', 'store.keystore', 'key.properties', '.sentryclirc', 'AppSecrets.xcconfig'):
                (repo / secret).write_text('sensitive')
            (repo / 'review_information').mkdir()
            (repo / 'review_information/demo_user').write_text('sensitive')
            cache = base / 'pub-cache/hosted/pub.dev/plugin'; cache.mkdir(parents=True)
            (cache / 'code.swift').write_text('original')
            link = repo / 'ios/.symlinks/plugins/plugin'; link.parent.mkdir(parents=True)
            link.symlink_to(cache, target_is_directory=True)
            before = load('build-evidence').snapshot(repo)
            with mock.patch.dict(os.environ, PUB_CACHE=str(base / 'pub-cache')):
                plan.copy_inputs(repo, base / 'copy')
            copied = base / 'copy'
            self.assertFalse((copied / 'ios/.symlinks/plugins/plugin').is_symlink())
            self.assertEqual((copied / 'ios/.symlinks/plugins/plugin/code.swift').read_text(), 'original')
            (copied / 'src/code.swift').write_text('changed')
            self.assertEqual(before, load('build-evidence').snapshot(repo))
            self.assertFalse(any('sensitive' in p.read_text() for p in copied.rglob('*') if p.is_file()))

    def test_framework_link_and_unsafe_link(self):
        plan = load('build-plan')
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary) / 'repo'; repo.mkdir()
            version = repo / 'Kit.xcframework/Kit.framework/Versions/A'; version.mkdir(parents=True)
            (version / 'binary').write_text('binary')
            (version.parent / 'Current').symlink_to('A', target_is_directory=True)
            plan.copy_inputs(repo, Path(temporary) / 'copy')
            (repo / 'escape').symlink_to('/tmp', target_is_directory=True)
            with self.assertRaises(ValueError):
                plan.copy_inputs(repo, Path(temporary) / 'copy2')

    def test_ambiguous_project_and_root_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary); (repo / 'One.xcodeproj').mkdir(); (repo / 'Two.xcodeproj').mkdir()
            r = subprocess.run(['bash', str(S / 'build-run.sh'), '--repo', str(repo), '--dry-run'], capture_output=True, text=True)
            self.assertEqual(r.returncode, 3, r.stdout + r.stderr)
            self.assertIn('One.xcodeproj', r.stdout); self.assertIn('Two.xcodeproj', r.stdout)
        for path in ('/', str(Path.home())):
            r = subprocess.run(['bash', str(S / 'build-run.sh'), '--repo', path, '--dry-run'], capture_output=True)
            self.assertEqual(r.returncode, 64)

    def test_react_native_preparation_uses_frozen_installs(self):
        from types import SimpleNamespace
        module = load('build-run')
        with tempfile.TemporaryDirectory() as temporary:
            copy = Path(temporary); (copy / 'package-lock.json').write_text('{}')
            (copy / 'package.json').write_text('{"dependencies":{"expo":"1.0.0"}}')
            commands = []
            module.prepare_framework(SimpleNamespace(framework='rn'), copy, lambda command: (commands.append(command) or (0, '')))
            self.assertIn(['npm', 'ci'], commands)
            self.assertIn(['npx', 'expo', 'prebuild', '--platform', 'ios', '--no-install'], commands)
            (copy / 'package-lock.json').unlink()
            with self.assertRaises(ValueError):
                module.prepare_framework(SimpleNamespace(framework='rn'), copy, lambda command: (0, ''))

    def test_native_release_fallback_exports_app_without_source_changes(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary); repo = base / 'repo'; repo.mkdir()
            (repo / 'App.xcodeproj').mkdir(); (repo / 'source.swift').write_text('source')
            tools = base / 'bin'; tools.mkdir()
            tool = tools / 'xcodebuild'
            tool.write_text("#!/usr/bin/env python3\nimport sys,json\nfrom pathlib import Path\na=sys.argv\nif '-list' in a: print(json.dumps({'project':{'schemes':['App']}})); sys.exit(0)\nif 'Release' in a: print('release diagnostic'); sys.exit(1)\np=Path(a[a.index('-derivedDataPath')+1])/'Build/Products/Debug-iphonesimulator/App.app'\np.mkdir(parents=True); (p/'Info.plist').write_text('<plist/>')\n")
            tool.chmod(0o755)
            before = load('build-evidence').snapshot(repo)
            env = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ['PATH'])
            result = subprocess.run(['bash', str(S / 'build-run.sh'), '--repo', str(repo), '--out', str(base / 'out')], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('build_config=debug', result.stdout)
            self.assertIn('release diagnostic', (base / 'out/build.log').read_text())
            self.assertTrue((base / 'out/Debug-iphonesimulator/App.app/Info.plist').is_file())
            self.assertEqual(before, load('build-evidence').snapshot(repo))

    def test_expo_without_generated_ios_project_can_plan(self):
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary)
            (repo / 'package.json').write_text('{"dependencies":{"expo":"1.0.0","react-native":"1.0.0"}}')
            (repo / 'package-lock.json').write_text('{}')
            result = subprocess.run(['bash', str(S / 'build-run.sh'), '--repo', str(repo), '--framework', 'rn', '--dry-run'], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('PLAN:', result.stdout)

    def test_build_log_link_is_never_followed(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary); victim = base / 'victim'; victim.write_text('unchanged')
            log = base / 'build.log'; log.symlink_to(victim)
            with self.assertRaises(OSError):
                load('build-exec').execute(['python3', '-c', 'print("diagnostic")'], base, base, log, 5)
            self.assertEqual(victim.read_text(), 'unchanged')

    def test_execution_logs_and_does_not_inherit_secrets(self):
        runner = load('build-exec')
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary); log = base / 'compiler.log'
            os.environ['PRECHECK_DEMO_PASSWORD'] = 'hidden'
            result = runner.execute(['python3', '-c', 'import os; print("compiler diagnostic"); print(os.getenv("PRECHECK_DEMO_PASSWORD", "absent"))'], base, base, log, 5)
            self.assertEqual(result[0], 0)
            self.assertIn('compiler diagnostic', log.read_text())
            self.assertIn('absent', log.read_text()); self.assertNotIn('hidden', log.read_text())
            self.assertEqual(runner.execute(['nonexistent-precheck-tool'], base, base, log, 1)[0], 127)
            self.assertEqual(runner.execute(['python3', '-c', 'import time; time.sleep(5)'], base, base, log, 0.05)[0], 124)


if __name__ == '__main__':
    unittest.main()
