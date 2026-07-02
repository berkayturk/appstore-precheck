# Screenshot vision review (agent-mode, non-blocking)

Deepens Pierre deep-review check #8 (2.3.5) into a dedicated, structured screenshot review.
This is the **vision layer** of the Review Simulator: the host model reads the actual screenshot
images and cross-checks their content against the metadata and the shipped app.

**Identity:** this runs ONLY in agent-skill mode (Claude Code / Codex / …), using the host LLM's
vision capability — exactly like Pierre reads code and the drift phase fetches URLs. It is NOT a
bundled dependency and does NOT run in the offline CLI / npx / GitHub-Action path.

**This phase does not change the GREEN/YELLOW/RED verdict** (verdict comes only from scan
`FAIL:`/`WARN:` counts). It emits `REVIEW-PASS:` / `REVIEW-FINDING: … WARN` lines, like Pierre
deep-review.

## Rules

- Read-only. Never modify project files.
- Evidence-based: cite the screenshot **filename** (and locale) for every finding. If you cannot
  read an image, say so — do not invent findings.
- Read at least one screenshot per primary locale; when several are present, scan them all.
- All five checks, every run: report each as `REVIEW-PASS:` or `REVIEW-FINDING: … WARN`.
- If there are no in-repo screenshots, report each check as
  `REVIEW-PASS: <guideline> — not applicable (no in-repo screenshots; managed in App Store Connect)`.
- Severity is always WARN (advisory). Cautious language ("may trigger review questions").
- Write Pierre's 2–3 sentence explanations in the user's conversation language.

## The 5 checks

| # | Guideline | Question |
|---|-----------|----------|
| S1 | 2.3.3 / 2.3.7 | Placeholder / dev-debug / empty-state content: Lorem ipsum, debug overlays or logs, visible TODO/FIXME, empty lists or skeleton loaders shown as content, simulator status bar with placeholder carrier/time. |
| S2 | 2.3.3 | Text overflow / truncation / clipping: clipped or overlapping labels, cut-off buttons, text running off-screen. |
| S3 | 2.3.5 | Wrong device frame / aspect: an iPad screenshot in an iPhone slot (or vice-versa), letterboxing, obviously stretched/squished aspect. |
| S4 | 2.3.3 / 2.3.10 | Misleading marketing: 2.3.3 "show the app in use" — the shot is a splash/title/logo/pure marketing art, not actual app UI; 2.3.10 — a feature is depicted that the app does not ship. |
| S5 | 2.3.5 | Metadata ↔ screenshot claim mismatch: visible UI text/features contradict the description, keywords, or promo text. |

## Per-check procedure

### S1 — Placeholder / dev-debug / empty-state
1. Open each screenshot; read visible text and UI state.
2. Flag Lorem ipsum, debug HUDs, log text, "TODO"/"FIXME", empty/skeleton content presented as real, or a simulator status bar with placeholder carrier/time.
3. Cite the filename. Not applicable if no screenshots.

### S2 — Text overflow / truncation
1. Inspect labels, buttons, and headings for clipping, overlap, or off-screen text.
2. Flag any truncation that suggests an unfinished or broken layout.

### S3 — Wrong device frame / aspect
1. Compare each screenshot's aspect to its locale/slot (iPhone vs iPad).
2. Flag an iPad-aspect image in an iPhone slot (or vice-versa), letterboxing, or stretched aspect.

### S4 — Misleading marketing
1. Determine whether each screenshot shows the app actually in use (real UI) vs pure title/splash/logo art.
2. Flag shots that are marketing art rather than the app in use (2.3.3), or that depict a feature absent from the build (2.3.10).

### S5 — Metadata ↔ screenshot mismatch
1. Read the visible UI text/features and compare to the description, keywords, and promo text.
2. Flag direct contradictions (a feature/claim in the screenshot not in metadata, or vice-versa).

## Output format

```
REVIEW-PASS: <guideline> — <one-line why it looks OK, with screenshot filename>
```
or
```
REVIEW-FINDING: <guideline> WARN — <one-line concrete issue, with screenshot filename>
Pierre: <2–3 sentences: why Apple cares, what you saw, what to fix or verify>
```
