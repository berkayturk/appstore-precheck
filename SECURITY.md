# Security Policy

## Scope

`appstore-precheck` is a **read-only**, local scanner. It does not run as a network service,
does not collect data, and does not modify your code or assets. Its security surface is small
but real, because it can be pointed at a repository and, in Phase 2, handed App Store Connect
credentials.

The optional local dynamic tier **executes your application code** on a throwaway
simulator that it creates and deletes itself. It never writes to your repository or to an
existing simulator, but the app it launches can reach configured backends and display
private data in screenshots. Demo credentials are passed only to the login flow and
must not enter logs or report metadata. The tier states this before the first launch; see
[`simulator-dynamic-review.md`](skills/appstore-precheck/references/simulator-dynamic-review.md).
`scripts/dynamic.sh`, which turns the transcript into findings, is a pure text transform and
launches nothing. `scripts/app-discover.sh` only *reads* `~/Library/Developer/Xcode/DerivedData`
and the repo's build output to list simulator apps you already built; it never builds or
launches. An explicit `--build` or `dynamic.build: true` setting uses `build-run.sh` to
copy the project with `rsync` into a temporary directory, excluding Git history,
dependencies, build output, `.env*`, App Store Connect keys, provisioning profiles,
and the precheck config. Xcode, package managers, CocoaPods, Flutter, and project build
scripts run in that copy, with DerivedData there too. The copy is deleted after the
run unless `--keep-build` is selected. Build scripts are arbitrary code: a script
using an absolute path can still access the original project or the network, which
the copy alone cannot prevent. `scripts/dynamic-run.sh` is the simulator runner:
it creates and deletes its own simulator, and its optional `--pktap` host capture needs
`sudo tcpdump` (off by default; you are asked by sudo, never by the script).

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
- **The opt-in build boundary.** Build commands must run in a disposable project copy with
  DerivedData there, avoid copying secrets, and never print tool output containing credentials.

## Good to know (not vulnerabilities)

- The scanner is a heuristic aid, not a guarantee of App Store approval. A missed rejection
  vector is a coverage gap (file a normal issue), not a security flaw.
- Phase 0 drift detection is intentionally non-blocking and advisory.
