# Security Policy

## Scope

The default `appstore-precheck` scan reads local source and metadata without executing
project code or changing app code/assets. Optional operations have broader effects:
explicit builds execute project tooling in a temporary copy, runtime checks execute
application code, and `--check-urls` sends HTTP HEAD requests to public URL targets.
It does not run as a network service or collect telemetry. App Store Connect access
uses credentials explicitly supplied for that optional metadata operation.

The optional, opt-in **Phase 6 dynamic tier** (agent mode or explicit `--app` / `--build`
CLI invocation; never a default scan) **executes your application code** on a throwaway
local simulator that it creates and deletes itself. It does not change your repository.
Explicit `--udid` mode may relaunch an app on an existing simulator, but never erases,
resets or deletes that device. The app it launches does whatever your app does: it reaches the backends
it is configured for, it receives the review demo credentials you supplied for D5, and its
screenshots may show data the app renders. The tier states this before the first launch; see
[`simulator-dynamic-review.md`](skills/appstore-precheck/references/simulator-dynamic-review.md).
`scripts/dynamic.sh`, which turns the transcript into findings, is a pure text transform and
launches nothing. `scripts/app-discover.sh` only *reads* `~/Library/Developer/Xcode/DerivedData`
and the repo's build output to list simulator apps you already built; it never builds (no
`xcodebuild`, `flutter`, `gradle`) and never launches. `scripts/dynamic-run.sh` is the runner:
it creates and deletes its own simulator, and its optional `--pktap` host capture needs `sudo
tcpdump` (off by default; you are asked by sudo, never by the script).

## Explicit build and credential boundaries

`scan.sh --build` is an explicit opt-in to execute project build scripts in a temporary
copy, with a separate DerivedData directory. Depending on the project, this can run
`npm ci`, `pod install`, `expo prebuild`, `flutter pub get` or `gradle`; dependency
installation and project hooks can execute code and make network requests.
Build scripts are arbitrary code; a copy
is source isolation, not a network or operating-system sandbox. Release build scripts can access the network
(for example Crashlytics/Sentry dSYM uploads). Do not export ASC or demo environment
variables when building an untrusted repository. Compiler diagnostics are retained in
`--out/build.log` (or the reported artifact directory); treat that directory as private.
The build subprocess environment is restricted and common credential files are excluded.

Repository `dynamic.build` and `dynamic.demoLogin` configuration is ignored unless
`APPSTORE_PRECHECK_TRUST_CONFIG=1`; explicit CLI flags authorize their corresponding
operation. The GitHub Action removes that trust variable on every scanner invocation.
The dynamic runner still never builds: it accepts an already-built simulator `.app`.

Demo login runs after normal screenshots and layout observations. Persisted hierarchy
JSON redacts email addresses before writing; demo credential values are redacted verbatim; secure-field detection is not relied on. Exploration
is separately opt-in; after `--demo-login` it additionally requires an explicit
`--authorized-navigation` JSON allowlist. In that mode arbitrary text/identity values
are redacted, only authorized navigation labels remain, and screenshots are withheld.
Maestro debug/test artifacts stay in temporary directories under the requested output
and are deleted after each navigation call. An allowlist never overrides the destructive
or permission-changing action denylist. Reviewers should still treat output as private;
source/build logs and explicitly requested non-authenticated screenshots may contain app data.

## Reporting a vulnerability

Please report security issues **privately**. Do not open a public issue for anything
exploitable.

- Use GitHub's **"Report a vulnerability"** (Security → Advisories) on this repository, or
- email **berkaytrk6@gmail.com** with the details and a repro.

You can expect an acknowledgement within a few days. Once a fix is available, we'll credit you
in the release notes unless you prefer to remain anonymous.

## What we care about most

- **Secret handling.** The Phase 2 ASC API key must be generated from the environment at
  runtime and deleted right after `precheck` runs. The key, `*asc-key*.json`, and `.env` are
  git-ignored. A change that risks committing or logging a secret is a security bug.
- **Command construction.** `scan.sh`, the guard hook, and `install.sh` operate on
  repo-controlled paths and filenames. Report any path/argument handling that could lead to
  unintended command execution or writing outside the repo.
- **The upload guard.** `hooks/fastlane-guard.sh` is a safety gate, not a sandbox; a bypass
  that lets a stale/forged `.precheck-pass` allow an upload is worth reporting.
- **The dynamic tier's device policy.** Phase 6 must only ever boot, erase or delete a device it
  created in the same run. A path by which it touches a pre-existing simulator, or writes into
  the user's project, is a security bug.

## Good to know (not vulnerabilities)

- The scanner is a heuristic aid, not a guarantee of App Store approval. A missed rejection
  vector is a coverage gap (file a normal issue), not a security flaw.
- Phase 0 drift detection is intentionally non-blocking and advisory.
