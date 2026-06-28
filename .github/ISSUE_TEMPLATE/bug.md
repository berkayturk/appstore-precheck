---
name: Bug report
about: A false positive, false negative, crash, or wrong output from the scanner
title: "[bug] "
labels: bug
---

## What happened

<!-- A clear description. If it's a false positive/negative, say which check (e.g. 3.1.2, 5.1.1(v)). -->

## Repro

<!-- The smallest layout that reproduces it. A public repo + the exact scan.sh output is ideal.
     Paste the relevant FAIL/WARN/PASS lines verbatim, do not paraphrase. -->

```
# scan.sh output
```

## Expected

<!-- What the scanner should have reported instead. -->

## Environment

- OS + bash version (`bash --version`):
- How you ran it (Claude Code skill / Codex / Cursor / Gemini / `scan.sh` directly):
- `.appstore-precheck.json` overrides, if any:
- Repo layout note (where are sources / fastlane metadata / paywall view?):
