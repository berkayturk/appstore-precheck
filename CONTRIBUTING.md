# Contributing to appstore-precheck

Thanks for helping make App Store submissions less painful. This project is a small,
focused, **read-only** scanner packaged as a portable Agent Skill. Contributions that keep
it small, portable, and faithful are very welcome.

## Ground rules

- **Read-only.** The skill never edits code, metadata, or assets. It only reports and writes
  a pass token. Keep it that way.
- **Machine-faithful output.** `scan.sh` emits `FAIL:` / `WARN:` / `PASS:` lines that other
  tools parse. Never paraphrase or reformat that output; the Pierre voice is a thin
  presentation wrapper, applied only when a human reads the verdict.
- **Portable Bash.** `scan.sh` must run on stock macOS bash 3.2 *and* modern bash. Forward-slash
  paths only; guard empty-array expansion (`"${arr[@]+"${arr[@]}"}"`) and initialize arrays with
  `=()`. The CI runner uses a newer bash, so test locally on macOS too.
- **No secrets, ever.** The App Store Connect API key is built from the environment at runtime
  and deleted immediately after use. `.gitignore` blocks `*asc-key*.json` and `.env`. Don't
  weaken it.

## Dev loop

```bash
npm test                 # fixture + unit suite (tests/all.sh)
npm run lint             # bash -n on every script
claude plugin validate . # Claude + Cursor + Codex plugin manifests
shellcheck -x --severity=warning skills/appstore-precheck/scripts/*.sh hooks/*.sh tests/*.sh
```

CI runs ShellCheck, JSON validation, a version-consistency guard, and the full test suite on
every push and PR. Keep it green.

## Adding a rejection-vector check

See [`docs/adding-a-check.md`](docs/adding-a-check.md) for the full walkthrough. In short:
add the check to `scan.sh` (emit `FAIL`/`WARN`/`PASS` with a `file:line` where possible), add
or extend a fixture under `tests/fixtures/`, assert the new line in `tests/run.sh`, and update
the check table in `references/methodology.md`.

## Commits & PRs

- Conventional Commits (`feat:`, `fix:`, `test:`, `docs:`, `ci:`, `chore:`, `refactor:`, `perf:`).
- One logical change per commit; explain *why* in the body when it isn't obvious.
- Open a PR against `main`. Fill in the PR template, including how you verified the change.
- By contributing, you agree your work is licensed under the project's [MIT License](LICENSE).

## Reporting bugs / requesting checks

Use the issue templates. For a false positive or false negative, a minimal repro layout
(or a public repo + the `scan.sh` output) is worth a thousand words.
