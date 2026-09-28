#!/usr/bin/env python3
"""Portable recorded transition tests; synthetic evidence, no simulator/network."""
import copy
import hashlib
import importlib.util
import json
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('transitions', ROOT / 'skills/appstore-precheck/scripts/lib/dyn-transitions.py')
m = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(m)


class ReplayTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = pathlib.Path(self.tmp.name)
        self.record = {'schema_version': 1, 'flows': []}

    def artifact(self, name, data):
        raw = json.dumps(data).encode()
        (self.root / name).write_bytes(raw)
        return {'path': name, 'sha256': hashlib.sha256(raw).hexdigest()}

    def tree(self, name, text):
        return self.artifact(name, {'children': [{'attributes': {'text': x}} for x in text]})

    def flow(self, name='navigation', fail=False):
        before = self.tree('before.json', ['Home', 'Open details', 'Help', 'Settings'])
        after = self.tree('after.json', ['Error' if fail else 'Details', 'Back', 'Help', 'Settings'])
        trace = self.artifact('trace.json', {'events': [{'action': 'tap', 'selector': 'Open details', 'result': 'completed'}]})
        attempt = {'id': 'a1', 'environment_id': 'fresh-1', 'fresh': True, 'driver_status': 'completed',
                   'start': {'evidence': before, 'selector': 'Home'},
                   'action': {'evidence': trace, 'type': 'tap', 'selector': 'Open details'},
                   'expected': {'success': 'Details', 'failure': 'Error'}, 'postcondition': {'evidence': after}}
        return {'id': name, 'flow': name, 'attempts': [attempt]}

    def evaluate(self, flow):
        return m.evaluate({'schema_version': 1, 'flows': [flow]}, self.root)['flows'][0]

    def test_state_transition(self):
        self.assertEqual('OBSERVED_PASS', self.evaluate(self.flow())['status'])

    def test_discovery_is_not_completion(self):
        flow = self.flow()
        del flow['attempts'][0]['action']
        self.assertEqual('UNRESOLVED', self.evaluate(flow)['status'])

    def test_corrupt_or_degenerate_evidence(self):
        flow = self.flow()
        flow['attempts'][0]['postcondition']['evidence']['sha256'] = '0' * 64
        self.assertEqual('UNRESOLVED', self.evaluate(flow)['status'])
        flow = self.flow()
        flow['attempts'][0]['postcondition']['evidence'] = self.tree('tiny.json', ['Details'])
        self.assertEqual('UNRESOLVED', self.evaluate(flow)['status'])

    def test_failure_requires_three_distinct_fresh_environments(self):
        flow = self.flow(fail=True)
        self.assertEqual('UNRESOLVED', self.evaluate(flow)['status'])
        flow['attempts'] *= 3
        self.assertEqual('UNRESOLVED', self.evaluate(flow)['status'])
        flow['attempts'] = [dict(copy.deepcopy(flow['attempts'][0]), id=str(n), environment_id='fresh-%d' % n) for n in range(3)]
        self.assertEqual('OBSERVED_FAILURE', self.evaluate(flow)['status'])
        flow['attempts'][1]['driver_status'] = 'timeout'
        self.assertEqual('UNRESOLVED', self.evaluate(flow)['status'])

    def test_restore_and_deletion_ui_cannot_close(self):
        for name in ('restore', 'deletion'):
            flow = self.flow(name)
            flow['authorized_test_environment'] = True
            self.assertEqual('UNRESOLVED', self.evaluate(flow)['status'])
            flow['confirmation'] = {'confirmed': True, 'entitlement': True, 'backend_ready': True}
            self.assertEqual('UNRESOLVED', self.evaluate(flow)['status'])

    def test_backend_claim_is_not_proof(self):
        flow = self.flow('login', fail=True)
        flow['backend_ready'] = True
        flow['attempts'] = [dict(copy.deepcopy(flow['attempts'][0]), id=str(n), environment_id=str(n)) for n in range(3)]
        self.assertEqual('UNRESOLVED', self.evaluate(flow)['status'])

    def test_all_flow_types_and_malformed_record_survival(self):
        for name in m.FLOWS:
            self.assertIn(self.evaluate(self.flow(name))['status'], ('OBSERVED_PASS', 'UNRESOLVED'))
        result = m.evaluate({'schema_version': 1, 'flows': [None, self.flow()]}, self.root)
        self.assertEqual(2, len(result['flows']))
        self.assertEqual('OBSERVED_PASS', result['flows'][1]['status'])


if __name__ == '__main__':
    unittest.main()
