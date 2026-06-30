# Example: Phase 0 guideline drift check

**Real run, 2026-06-28**, of the two-pass drift procedure (see
[`methodology.md` § Phase 0](../skills/appstore-precheck/references/methodology.md#phase-0-guideline-drift-check))
against the live [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/),
diffed against `guidelines-baseline.json` (`reconciled_on: 2026-06-30`).

The page truncates after ~5.4 when fetched, so the check runs as **two focused passes**, each
embedding only the relevant slice of `all_sections`.

## Pass A: Sections 1–3

> Report ONLY (NEW) section numbers present on the live page but missing from the baseline, and
> (REMOVED) numbers in the baseline but absent. Ignore parenthetical (a)/(b) suffixes. If nothing
> differs, output NO DRIFT.

**Result:** `NO DRIFT`, every baseline section number for Sections 1–3 was present on the live
page; none added, none removed.

## Pass B: Section 4 + 5.1–5.4

> Same as Pass A, plus: the page reliably truncates after ~5.4, that is EXPECTED; do not report
> 5.5 / 5.6.x as removed and do not output TRUNCATED for the tail.

**Result:** `NO DRIFT`, every baseline section number for Section 4 and Sections 5.1–5.4 matched
the live page.

## Interpretation

Both passes returned `NO DRIFT`, so Phase 0 emits:

```
PASS: guideline-drift none (baseline reconciled 2026-06-30)
```

The baseline is **not** modified. Reconciliation is a deliberate human step taken only when drift
appears (a NEW/REMOVED section). Auto-bumping the date on a clean run would erode the meaning of
`reconciled_on` (the last time the section set was hand-reviewed) and risk silently swallowing
future drift. The 5.5–5.6.x tail (Developer Code of Conduct) can't be fetched reliably and is
structurally the most stable region, so it is reviewed by hand at reconciliation time.

> Had either pass reported a NEW or REMOVED section, Phase 0 would instead emit a non-blocking
> `WARN: guideline-drift — NEW: … / REMOVED: …`, and the baseline would be reconciled by hand
> (update `all_sections`, set `reconciled_on` to today) after deciding whether `scan.sh` needs a
> new check.
