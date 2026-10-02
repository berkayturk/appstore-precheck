# Local guideline expansion run

2026-10-02, macOS, Bash 3.2.57. ControlDopamine default scans completed read-only.
JSON: 0 FAIL, 3 WARN, 40 PASS, one suppressed record; text verdict: GREEN with
41 PASS including the unstructured layout line. No token was applied. Run-local
coverage: 26/102 sections touched, two input/visual SKIP records, nine human-only.
Before/after `git status --porcelain` was identical; no content-hash claim is made.

The only new WARN was a reboot-related Swift Testing test description. Manual
inspection identified a false positive; the check now excludes Testing/XCTest
files, and a real rerun reports no new WARN. Full decisions: `docs/field-tests.md`.

Discovery returned exit 3, `candidates: []`, `launched: false`. Live dynamic review
was NOT_RUN because no existing simulator `.app` was found. No build was attempted.
D12–D17 have offline synthetic producer/evaluator fixtures; they were not validated
live. D13/D14 only establish positive evidence, and D17 does not compare permission
scope. Details: `guideline-runtime-notes.md`.

When an authorized simulator bundle is available:

```bash
bash tests/local/run-dynamic.sh --repo /path/to/app --app /path/to/Release-iphonesimulator/App.app --repeats 3 --ipad --yes
```
