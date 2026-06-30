# How to add a rejection-vector check

The scanner ([`scan.sh`](../skills/appstore-precheck/scripts/scan.sh)) is one portable Bash
file made of small, independent check blocks. Adding a check is mechanical once you know the
shape. This walks through it end to end.

## The contract a check must follow

Every check emits one or more lines on stdout, each prefixed exactly:

```
FAIL: <guideline> <topic> — <detail> [file:line]
WARN: <guideline> <topic> — <detail> [file:line]
PASS: <guideline> <topic> — <detail>
```

- **FAIL** → blocks submission (drives RED). Use only for a confident, real defect.
- **WARN** → advisory (5+ WARN drives YELLOW). Use when the signal is uncertain or non-blocking.
- **PASS** → confirms the check ran and found nothing wrong.
- Include a `file:line` (or at least a file) whenever you can, so the fix is actionable.
- The exit code is always 0; the verdict comes from *counting* these lines (see
  [`verdict.sh`](../skills/appstore-precheck/scripts/verdict.sh)).

**Never** print prose that another tool would have to parse around. The Pierre voice is added
later, only when a human reads the verdict. `scan.sh` output stays machine-faithful.

## Steps

1. **Pick the guideline and a static signal.** A check must be decidable from files on disk:
   a grep over Swift, a key in `Info.plist`/`PrivacyInfo.xcprivacy`, a file presence/parity
   rule, a metadata length. If it needs runtime behavior, it belongs on the manual checklist in
   [`methodology.md`](../skills/appstore-precheck/references/methodology.md), not in `scan.sh`.

2. **Add a numbered block to `scan.sh`.** Follow the existing `# === §N — <guideline> ===`
   style. Reuse the resolved paths (`$IOS_DIR`, `$META_DIR`, `$INFO_PLIST`, `$PRIVACY_FILE`,
   `$XCSTRINGS`, `${LOCALES[@]}`) and the `fail` / `warn` / `pass` helpers. Keep it portable:
   stock macOS bash 3.2 *and* modern bash, forward-slash paths, guard empty-array expansion
   with `"${arr[@]+"${arr[@]}"}"`, and initialize new arrays with `=()`.

3. **Gate it if it's conditional.** IAP checks (§8–10) only run when in-app-purchase signals
   exist; an opt-in check (like §13 FamilyControls) reads a config flag via `cfg_bool`. Don't
   emit a FAIL for a check that doesn't apply to the project.

4. **Make it configurable if paths are involved.** Read overrides through `cfg '.someKey'` and
   document the key in [`config.example.json`](../skills/appstore-precheck/config.example.json).

5. **Add a fixture + assertion.** Put a minimal app under `tests/fixtures/<name>/` that
   triggers the new line, then assert it in [`tests/run.sh`](../tests/run.sh) with `assert_has`
   / `assert_absent`. If detection or thresholds are involved, prefer a deterministic,
   platform-independent assertion (see the existing fixtures for the pattern).

6. **Document it.** Add a row to the check table in
   [`methodology.md`](../skills/appstore-precheck/references/methodology.md#phase-1-rejection-vectors)
   and bump the vector count in `SKILL.md` if it changed.

7. **Verify.** `npm test`, `npm run lint`, `claude plugin validate .`, and
   `shellcheck -x --severity=warning` on the changed scripts, all green.

## A note on precision

A false **FAIL** erodes trust faster than a missed check; a false **PASS** gives false
confidence. When a signal is genuinely ambiguous (e.g. a symbol whose required-reason status
Apple hasn't pinned down), prefer **WARN** with a "verify manually" detail over a hard FAIL.
The [field tests](field-tests.md) show how real apps stress these edges.
