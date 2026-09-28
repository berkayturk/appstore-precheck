# Runtime transition evidence (version 1)

Screen inventory and flow completion are separate. A visible Restore, Delete,
Report or Continue button is only a discovery lead. Default `--explore` captures
the current hierarchy and screenshot without running a Maestro navigation flow.

Explicit sandbox navigation is available on the runner:

```sh
bash scripts/dynamic-run.sh --app /tmp/Example.app --explore \
  --authorized-navigation /tmp/navigation.json --out /tmp/runtime-review
```

An authorization file names exact labels and the expected states. It must be an
explicit authorization for test data in a test/sandbox backend; do not infer this
from an app's source. Destructive purchase, deletion, submission and logout labels
remain excluded from generic exploration. Dedicated test flows can supply recorded
evidence for review without enabling blind destructive navigation.

```json
{
  "schema_version": 1,
  "authorized": true,
  "environment": "sandbox",
  "selectors": ["Settings"],
  "transitions": {
    "Settings": {
      "flow": "navigation",
      "start": "Home",
      "success": "Preferences",
      "failure": "Unable to open settings"
    }
  }
}
```

Authorization is permission to drive that test, not proof of backend readiness or
compliance. The runner writes `transition-evidence.json`, start/post hierarchy
files and action completion traces with SHA-256 references. A generated navigation
attempt has `fresh: false`: clearing app state is not a fresh simulator. Replays
never grant N=3 freshness based on screen relaunching.

Replay is offline and portable:

```sh
bash scripts/runtime-review.sh --transitions /tmp/runtime-review/transition-evidence.json \
  --out /tmp/runtime-replay
```

The packet has `schema_version: 1`, optional target `scope`, and `flows`. Each flow
has `id`, `flow`, and `attempts`. Each attempt has `id`, `environment_id`, `fresh`,
`driver_status`, `start`, `action`, `expected`, and `postcondition`. Start and
postcondition contain an `evidence: {path, sha256}` reference; start also has a
`selector`. Action has `type: tap`, an exact `selector` and a hashed JSON event
trace containing `{action: tap, selector, result: completed}`. Expected contains
exact `success` and optional `failure` labels. Paths stay inside the packet.

Supported flow names: `login`, `logout`, `guest`, `deletion`, `siwa`, `restore`,
`paywall`, `permission-grant`, `permission-deny`, `ugc-report`, `ugc-block`,
`ugc-filter`, `navigation`. Replay verifies the selected start, a completed action,
and a new postcondition against hashed recorded files. Four distinct accessible
labels are required per state. Persistent labels, ambiguous outcomes, malformed
records, mismatched hashes, timeouts and mixed attempts remain unresolved. A bad
flow does not erase other valid observations.

`transition-review.json` reports `OBSERVED_PASS`, `OBSERVED_FAILURE`, or
`UNRESOLVED`. These are observations, not `VERIFIED_PASS`/`VERIFIED_FINDING`.
Recorded explicit failure requires exactly three distinct fresh attempts even to
produce an observed failure. Collector provenance and simulator creation evidence
still need independent validation. Caller-selected labels cannot define the whole
policy criterion; the verification adapter returns UNKNOWN and advertises no full
positive or decisive finding capability.

Restore stays unresolved without independently validated receipt/transaction and
entitlement evidence. Deletion needs authorized test-backend completion, session
revocation and retention review. Login requires account/session/backend review;
SIWA requires provider parity and exceptions. UGC operations require server-side
outcomes, filtering/report/block scope and operational review. Paywall content must
match product, period, price, terms, privacy and storefront evidence. Permission
flows need OS grant/deny state and observed feature behavior. Simulator replay
cannot establish a physical-device or signed distribution requirement.

## Demo login and cleanup

`--demo-login` requires three fresh simulator repeats, credentials/selectors in
`PRECHECK_DEMO_USERNAME`, `PRECHECK_DEMO_PASSWORD`, `PRECHECK_DEMO_SUCCESS_TEXT`,
`PRECHECK_DEMO_FAILURE_TEXT`; optional field selectors are
`PRECHECK_DEMO_USER_FIELD`, `PRECHECK_DEMO_PASSWORD_FIELD`, `PRECHECK_DEMO_SUBMIT`.
It additionally requires `PRECHECK_DEMO_AUTHORIZED_TEST=1` and
`PRECHECK_DEMO_ENVIRONMENT=test` or `sandbox`. Do not put secrets in argv or config.
`PRECHECK_DEMO_BACKEND_READY=1` never promotes a rejection to an app violation.
Wrong selectors, ambiguous/degenerate trees and driver errors are SKIP. The success
selector must be absent before and present after the action.

The credentials YAML is mode 0600 in a disposable private directory. Maestro debug
and test artifacts are directed there and removed on completion, error or graceful
cancellation. Persistent geometry/exploration screenshots after credential entry
are suppressed. These output flags follow the [Maestro artifact documentation](https://docs.maestro.dev/maestro-flows/workspace-management/test-reports-and-artifacts).

The runner uses a process-group supervisor (default deadline 1200 seconds;
`PRECHECK_RUNTIME_DEADLINE_SECONDS` overrides it). Timeout returns 124; cancellation
returns 143. TERM allows up to 15 seconds for child cleanup before KILL. The runner
records `owned-simulators.txt`, successful `deleted-simulators.txt`, and any
`cleanup-failures.txt`. A forced OS kill, machine failure, or stalled simctl can
still prevent deletion: compare ownership/deletion evidence and live inventory;
do not claim unconditional cleanup. Never erase/delete a pre-existing simulator.

## Timing

`run.json.d1_d2_seconds` retains its legacy per-repeat timing definition, including
reset/boot/install when performed. `timing.observation_seconds` separately records
launch, the full observation window and signal collection. Removing one-second
polling from bounded hierarchy commands avoids polling overhead without shortening
observation windows or reducing fresh repeats. Compare the historical 70.5-second
benchmark to the legacy metric; the separate observation metric cannot satisfy the
old 60-second gate.
