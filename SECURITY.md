# Security Policy

## Scope

`appstore-precheck` is a **read-only**, local scanner. It does not run as a network service,
does not collect data, and does not modify your code or assets. Its security surface is small
but real, because it can be pointed at a repository and, in Phase 2, handed App Store Connect
credentials.

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

## Good to know (not vulnerabilities)

- The scanner is a heuristic aid, not a guarantee of App Store approval. A missed rejection
  vector is a coverage gap (file a normal issue), not a security flaw.
- Phase 0 drift detection is intentionally non-blocking and advisory.
