<!-- Thanks for the PR! Keep changes small and focused. -->

## What & why

<!-- What does this change, and why? Link any issue (e.g. Closes #12). -->

## Type

- [ ] `fix`: false positive / false negative / crash
- [ ] `feat`: new check or capability
- [ ] `test` / `ci`
- [ ] `docs`
- [ ] `refactor` / `chore` / `perf`

## How I verified

<!-- Paste the relevant output. -->

- [ ] `npm test` (fixture + unit suite) passes
- [ ] `npm run lint` passes
- [ ] `claude plugin validate .` passes
- [ ] `shellcheck -x --severity=warning` clean on changed scripts
- [ ] Tested on macOS bash 3.2 (if `scan.sh`/hooks/install changed)

## Checklist

- [ ] Scanner stays **read-only** (no edits to user code/metadata/assets)
- [ ] `scan.sh` output stays machine-faithful (no paraphrasing; Pierre voice stays in presentation only)
- [ ] No secrets added; `.gitignore` protections intact
- [ ] Added/updated a fixture + assertion for any detection change
- [ ] Updated `references/methodology.md` / docs if behavior changed
