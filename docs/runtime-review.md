# Runtime screen review

`dynamic-run.sh --app PATH.app --explore --out OUT` runs bounded navigation on a
throwaway simulator created by that same invocation. The inventory is
`OUT/screen-inventory.json`; each captured screen also has a hierarchy JSON
and PNG screenshot. The default limit is 25 distinct screens or six minutes,
whichever occurs first. The explorer uses one Maestro flow per path and refuses
obvious destructive actions such as delete, purchase, submit, send, and logout.
It does not submit content, purchase products, or erase an existing simulator.

`runtime-review.sh --screens DIR --out OUT` evaluates recorded hierarchy JSON
without Xcode or Maestro. This is the portable fixture interface for CI.
Checks use `PASS` only for an observable negative marker (for example, no
placeholder copy in captured accessible text). A missing control cannot prove
an app lacks a feature when navigation is incomplete, so most decisions are
`NEEDS_REVIEW` or `SKIP`. A single-node accessibility tree is always `SKIP`.
Screenshots and hierarchy files provide evidence for semantic inspection.

`dynamic-run.sh --app PATH.app --demo-login` attempts login three times using
`PRECHECK_DEMO_USERNAME`, `PRECHECK_DEMO_PASSWORD`, success/failure text
selectors, and an optional `PRECHECK_DEMO_BACKEND_READY=1` assertion. The
Maestro flow containing credentials lives in a temporary private directory
and is deleted after each attempt; credentials are never printed into the
transcript or inventory. A rejected login without backend health evidence
is `SKIP`, not a finding.

`dynamic-run.sh --app PATH.app --dynamic-blocking` explicitly enables Phase 3
blocking for a three-repeat run. This mode erases the newly created simulator
before each repeat. Only unanimous 3/3 `dyn-launch` or `dyn-demo-login`
findings bearing the fresh-erase marker can yield `FAIL:` lines. Mixed
observations remain advisory. The generated line explains that rerunning
without `--dynamic-blocking` bypasses the experimental gate. Demo login
needs `--demo-login` and all selectors plus asserted backend health before
it can block.

The explorer does not itself establish login success, purchase restoration,
privacy compliance, account deletion completion, or layout correctness.
StoreKit may be unavailable in the simulator; `SKIP` leaves that gap visible.
The runtime inventory is separate from the legacy default scanner and does not
change its verdict.
