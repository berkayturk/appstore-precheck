#!/usr/bin/env python3
"""Driver timeout/cancel kills grandchildren and cleans private artifact directories."""
import importlib.util
import os
import pathlib
import signal
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULE = ROOT / 'skills/appstore-precheck/scripts/lib/dyn-process.py'
SPEC = importlib.util.spec_from_file_location('driver_process', MODULE)
m = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(m)


class ProcessTests(unittest.TestCase):
    def test_timeout_kills_grandchild(self):
        with tempfile.TemporaryDirectory() as temp:
            pidfile = pathlib.Path(temp) / 'pid'
            with self.assertRaises(subprocess.TimeoutExpired):
                m.run(['sh', '-c', 'sleep 60 & echo $! > "$1"; wait', '_', str(pidfile)], timeout=0.3)
            pid = int(pidfile.read_text())
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                return
            # Linux can briefly retain a terminated orphan as a zombie.
            status = pathlib.Path('/proc/%d/status' % pid)
            self.assertTrue(status.exists() and 'State:\tZ' in status.read_text())

    def test_demo_cancel_removes_credentials_and_artifacts(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            driver = root / 'maestro'
            driver.write_text("#!/usr/bin/env python3\nimport json, os, pathlib, sys, time\n"
                              "if 'test' in sys.argv:\n"
                              "    flow = pathlib.Path(sys.argv[-1])\n"
                              "    pathlib.Path(os.environ['PRIVATE_LOCATION']).write_text(str(flow.parent))\n"
                              "    (flow.parent / 'secret-debug.log').write_text(os.environ['PRECHECK_DEMO_PASSWORD'])\n"
                              "    time.sleep(60)\n"
                              "else:\n"
                              "    print(json.dumps({'children':[{'attributes':{'text':x}} for x in ['Email','Password','Sign In','Welcome']]}))\n")
            driver.chmod(0o755)
            locator = root / 'location'
            env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ['PATH'],
                       PRECHECK_DEMO_USERNAME='synthetic-user', PRECHECK_DEMO_PASSWORD='synthetic-secret',
                       PRECHECK_DEMO_SUCCESS_TEXT='Dashboard', PRECHECK_DEMO_FAILURE_TEXT='Rejected',
                       PRECHECK_DEMO_AUTHORIZED_TEST='1', PRECHECK_DEMO_ENVIRONMENT='sandbox',
                       PRIVATE_LOCATION=str(locator))
            demo = MODULE.with_name('dyn-demo-login.py')
            proc = subprocess.Popen([sys.executable, str(demo), 'owned', 'org.example.app'],
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
            try:
                limit = time.monotonic() + 5
                while not locator.exists() and time.monotonic() < limit:
                    time.sleep(0.02)
                self.assertTrue(locator.exists())
                private = pathlib.Path(locator.read_text())
                proc.terminate()
                stdout, stderr = proc.communicate(timeout=8)
                self.assertFalse(private.exists())
                self.assertNotIn(b'synthetic-secret', stdout + stderr)
                self.assertNotIn(b'synthetic-user', stdout + stderr)
            finally:
                if proc.poll() is None:
                    proc.kill()

    def test_cancel_runs_child_cleanup(self):
        with tempfile.TemporaryDirectory() as temp:
            ready, cleaned = pathlib.Path(temp) / 'ready', pathlib.Path(temp) / 'cleaned'
            proc = subprocess.Popen([sys.executable, str(MODULE), '--timeout', '60', '--', 'sh', '-c',
                                     'trap \'touch "$2"; exit 143\' TERM; touch "$1"; sleep 60 & wait',
                                     '_', str(ready), str(cleaned)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:
                limit = time.monotonic() + 5
                while not ready.exists() and time.monotonic() < limit:
                    time.sleep(0.02)
                self.assertTrue(ready.exists())
                proc.send_signal(signal.SIGTERM)
                proc.wait(timeout=8)
                self.assertTrue(cleaned.exists())
            finally:
                if proc.poll() is None:
                    proc.kill()


if __name__ == '__main__':
    unittest.main()
