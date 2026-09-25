# Runtime integration notes

- Merge `references/registry/runtime.json` into the central registry with
  `python3 scripts/coverage.py --merge`.
- Add `tests/test-runtime-review.sh` to `tests/all.sh`.
- Expose `dynamic-run.sh --explore` and `--dynamic-blocking` only behind
  explicit opt-in in `scan.sh` / CLI. The default scanner stays unchanged.
- Import `screen-inventory.json` checks into the run report. The JSON object
  has `checks[{check_id,status,reason,evidence_class,evidence}]`.
- Blocking output is emitted by the runner after its transcript. Demo login
  runs only with `--demo-login` and the documented `PRECHECK_DEMO_*` env
  selectors; a 3/3 explicit rejection needs `PRECHECK_DEMO_BACKEND_READY=1`.
  Config `demo_credentials` can be mapped to those env vars without logging.
- The live explorer is intentionally conservative: screen paths with navigation
  side effects may diverge, and missing patterns are not findings. Maestro
  timeout yields omitted screens, then SKIP/NEEDS_REVIEW.
