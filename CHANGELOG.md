# Changelog

All notable changes to this project are documented here. Versioning follows
[SemVer](https://semver.org/). Released as git tags.

## [1.14.0] - 2026-07-23

### Added
- **§42 `permission-priming-cta` (catalog vector 43, 5.1.1(iv))**: static scan for custom
  pre-permission ("priming") screens whose consent CTA steers users toward granting access
  ("Allow and continue", "Grant access to start", bare "Enable notifications" buttons).
  Signal-gated on real permission-request APIs; scans String Catalog source-language values
  AND hardcoded Swift/ObjC literals; excludes post-denial "Enable X in Settings" guidance
  (Apple's own recommended pattern) and code comments. Driven by a real July 2026 App Review
  rejection of a GREEN-verdict app — the exact wording "Allow and continue" was rejected under
  5.1.1(iv) with Apple asking for "Continue"/"Next" (see `corpus/outcomes/ledger.json`,
  first `missed` record). Fixture: `tests/fixtures/permission-priming-app`.
- **Pierre deep-review check 21 (Tier A, 5.1.1(iv))**: pre-permission priming CTA neutrality —
  the semantic companion to scan §42 (is the flagged string really on a consent gate; does the
  flow stay usable on decline). Former checks 21–28 renumbered 22–29; Tier B set is now
  4, 5, 7, 10, 15, 29. Totals: 43 scan vectors, 29 deep-review checks (23 Tier A + 6 Tier B).
- **First real App Store outcome recorded**: `corpus/outcomes/ledger.json` seeds its first
  `missed` record (the 5.1.1(iv) rejection above) — the recall gap that motivated vector 43.
- **§43 `paywall-trial-emphasis` (catalog vector 44, 3.1.2)**: flags paywall purchase CTAs that
  promote the free trial over the billed price ("Continue with free trial", "Start your free
  trial") and the "free-trial toggle" paywall pattern — the early-2026 App Review rejection wave
  under 3.1.2 (the field-proven fix is a neutral "Continue"/"Subscribe" CTA with the price and
  renewal term legible next to it). Signal-gated on IAP signals; scans String Catalog
  source-language values + hardcoded literals; a CTA that already carries a price is excluded.
  Fixture: `tests/fixtures/trial-cta-paywall-app`.
- **§44 `metadata-pricing-language` (catalog vector 45, 2.3.1)**: flags "Free", "% off", "sale",
  "discount", or currency amounts in `name.txt`/`subtitle.txt` (2.3.1/2.3.7 accurate metadata) —
  the offline complement to `fastlane precheck`'s pricing rules, which need ASC credentials.
  Hyphen compounds ("ad-free") excluded; keywords/descriptions not scanned. Fixture:
  `tests/fixtures/promo-metadata-app`.
- **§45 `generic-purpose-string` (catalog vector 46, 5.1.1(ii))**: flags non-empty
  `NS*UsageDescription` values that are very short or pure permission-restating boilerplate
  ("This app needs camera access") — vector 2 checks presence, this checks substance; the static
  complement to deep-review check 18. Fixture: `tests/fixtures/generic-purpose-app`.
- **§46 `ai-provider-consent` (catalog vector 47, 5.1.1)**: an external AI endpoint/SDK
  (OpenAI, Anthropic, Gemini, Mistral, OpenRouter, Groq, Perplexity, Together) with no
  user-facing string naming the provider — the 2026 consent-screen requirement for sharing user
  data with third-party AI (5.1.1 / 5.1.2(i)). The endpoint URL literal itself does not count
  as a mention. Fixture: `tests/fixtures/ai-chat-app`.
- **§47 `paywall-urgency` (catalog vector 48, 3.1.2)**: fake-urgency purchase pressure —
  "limited time" / "only today" / "last chance" copy (multilingual) and countdown timers
  combined with discount wording in paywall views (3.1.2 / 2.3.1). Fixture:
  `tests/fixtures/urgency-paywall-app`.
- **§48 `rating-sentiment-gate` (catalog vector 49, 5.6.1)**: "Enjoying the app?"-style
  sentiment pre-filtering next to a rating-prompt API — routing only happy users to the review
  sheet is rating manipulation. Fixture: `tests/fixtures/rating-gate-app`.
- **§49 `forced-login` (catalog vector 50, 5.1.1(v))**: a credential login UI with no
  skip/guest/continue-without-account affordance (WARN-verify heuristic). Fixture:
  `tests/fixtures/forced-login-app`.
- **§50 `push-marketing-optout` (catalog vector 51, 4.5.4)**: a marketing-push SDK (OneSignal,
  Braze, CleverTap, Iterable, Airship, MoEngage) registering for notifications without a
  notification-preferences/opt-out signal. Fixture: `tests/fixtures/push-marketing-app`.
- **§51 `xcode-sdk-requirement` (catalog vector 52, 2.1)**: `LastUpgradeCheck` clearly pre-26
  vs the April 2026 iOS 26 SDK (Xcode 26) upload minimum (WARN-verify heuristic — the field
  tracks the upgrade-check, not the build toolchain). Fixture: `tests/fixtures/old-xcode-app`.
- **Multilingual steering/trial patterns for vectors 43–44**: the permission-priming (§42) and
  trial-CTA (§43) regexes now also match common Turkish/German/French/Spanish wording in both
  word orders ("İzin ver ve devam et", "Ücretsiz denemeyi başlat", "Kostenlos testen") — a
  non-English source language is no longer a blind spot for these checks.
- **Pre-submit manual checklist extended** with the ASC-side items the scanner cannot see:
  exact paywall↔ASC price match, trial configured as an Introductory Offer, the updated
  age-rating questionnaire (13+/16+/18+), EU DSA trader status, and the AI-consent screen.
  Totals: 52 scan vectors.

### Fixed
- **Version lockstep**: `package.json` and both plugin manifests were left at 1.13.1 when
  SKILL.md moved to 1.14.0 (`scripts/check-versions.sh` was failing); all four now agree.
- **Last-section fingerprint churn (guideline drift)**: `gd_section_text` ran to end-of-page
  for the last numbered section (5.6.4), gluing the "After You Submit" block, the
  "last updated" date, and the whole site footer onto its prose — so ANY footer edit fired a
  false "5.6.4 text drift" WARN (exactly what happened on 2026-07-23; the actual 5.6.4 prose
  was unchanged). Extraction now truncates at those page-chrome markers; fingerprints
  reconciled (only 5.6.4's hash changed).
- **`--reconcile` wrote a literal placeholder date**: `reconciled_on` was set to the string
  `"RECONCILE_DATE"` instead of today's date (single-quoted jq program); now `--arg`-injected.
- **README drift from the vector-43 commit**: the static-scan table was missing the
  5.1.1(iv) permission-priming row, the deep-review table was missing check 21 (priming CTA
  neutrality), and the Tier A count still read 22 (should be 23).

### Added (eval, dev-only — not part of the distributed package)
- **RAG-grounded Pierre experiment**: `eval/rag/` — ingests the full App Store Review
  Guidelines text (all ~125 sections, not just the officially-mapped subset), embeds it
  (Gemini `gemini-embedding-001`, MRL-truncated to 1024 dims), stores it in a local pgvector
  instance, and retrieves top-k relevant sections to ground Pierre's eval-harness prompt
  (`eval/run.sh --rag`, `eval/lib/build_request.py --retrieved`). Measured against the
  existing 21-case labeled dataset: grounded and ungrounded runs scored identically
  (F1 1.00 on both, all tiers) — a ceiling effect, not a broken pipeline (retrieval was
  independently confirmed to surface the correct guideline section per case). See
  `docs/rag-eval-results.md` and `docs/specs/2026-07-17-rag-grounded-pierre-eval-design.md`.

### Fixed (eval, dev-only)
- **Gemini embedding requests now actually apply `taskType`/`outputDimensionality`**: the
  request builders nested both fields inside an `embedContentConfig` object, which the v1beta
  REST endpoint silently ignores (the documented curl examples put them at the top level) —
  the published 2026-07-17 run therefore used embeddings without
  `RETRIEVAL_DOCUMENT`/`RETRIEVAL_QUERY` task optimization, and the API's 3072-dim responses
  were only tamed by the client-side MRL truncation safety net. Fields moved to the top level;
  results doc amended (conclusion unchanged — both configurations were at the F1 ceiling).
- **RAG corpus deliberately not committed**: `eval/rag/corpus/sections.json` (full Apple
  guideline prose) is now gitignored with the copyright rationale documented in
  `eval/rag/README.md`; the design spec's "this file is committed" line is amended.
- **RAG CLI/network edge cases hardened** (dev-only): `retrieve.py` malformed args exit 64
  with a usage message instead of a traceback; a bare network failure (no HTTP response) in
  the shared Gemini client raises a clear error instead of an unhandled traceback; `run.sh
  --rag` no longer leaks its temp request file when retrieval fails.

### Added (eval, dev-only — not part of the distributed package)
- **Two guideline-drift-sensitive check-16 (4.8) cases** — the follow-up proposed in
  `docs/rag-eval-results.md`: `check16-eid-login-exempt` (sole eID/BankID login — exempt under
  the *current* 4.8 wording, likely flagged by stale parametric memory; the first case where
  grounded and ungrounded runs may genuinely diverge) and `check16-google-login-only` (clear
  violation under any wording; control twin). Both `label_confirmed: false` (UNLABELED,
  excluded from all metrics) pending human label review; first eval coverage for check 16.
  Labels human-confirmed 2026-07-18.
- **23-case RAG re-run — first measured divergence**: both configurations re-run with
  task-typed embeddings on the expanded dataset. F1 still 1.00 everywhere (ceiling), but
  consistency split 0.96 vs 1.00 — the single non-unanimous case was exactly the
  drift-sensitive `check16-eid-login-exempt` (ungrounded: `pass/pass/not-applicable` wording
  drift; grounded: unanimous `pass`, citing the retrieved 4.8 exemption, top-1 similarity
  0.76). A consistency effect, not an accuracy effect — documented with scope caveats in
  `docs/rag-eval-results.md`.

## [1.13.1] - 2026-07-12

### Fixed
- **Pierre pass-vs-not-applicable boundary**: the deep-review output format now states
  explicitly that "not applicable" is only for checks whose subject matter is entirely
  absent from the project; material that exists and is clean gets a plain `REVIEW-PASS`
  with evidence. Found by the eval consistency metric (3 of 63 clean-case verdicts drifted
  across Opus 4.8 and Fable 5); verified fixed by full re-runs of all three models —
  consistency 1.00 across the board, with no regression on genuine not-applicable cases.

### Added (eval)
- **Multi-model scorecard**: `docs/llm-scorecard.md` now opens with a comparison table and
  renders every committed baseline (currently Sonnet 5, Opus 4.8, and Fable 5 — before and
  after the prompt clarification); the CI Tier-A F1 floor gates each baseline separately.
- **Always-on-thinking model support**: `eval/run.sh --model claude-fable-5` works — the
  request omits the `thinking` field for Fable/Mythos-tier models and raises `max_tokens`
  for thinking headroom, both recorded in the manifest.
- **Prompt fingerprint + stricter resume**: every run manifest records a `prompt_sha256` of
  `pierre-deep-review.md`, and the resume guard refuses to reuse a cache dir produced with
  a different model or a different (or unrecorded) prompt version.

## [1.13.0] - 2026-07-12

### Added
- **LLM eval harness (`eval/`)**: Pierre's Phase 4 deep review (28 semantic checks,
  incl. the 6 heuristic Tier B checks) is now measured, not just described. Additive and
  opt-in — nothing in the default scan path changes, no new network calls, verdict logic
  untouched.
  - 21-case human-labelled dataset (`eval/dataset/`): positive+negative pairs per check,
    deliberate false-positive traps, borderline cases, and pre-fetched-URL cases for the
    privacy-policy check. Unconfirmed labels report as UNLABELED and never enter headline
    metrics.
  - Runner (`eval/run.sh`): pinned model + generation params recorded per run, `--repeat`
    for consistency measurement, response caching with resume; `ANTHROPIC_API_KEY` read
    from the environment only. Baseline cache dirs are per-model
    (`eval/baseline/<date>-<model>/`) and a resume guard refuses to mix models in one dir.
  - Offline scorer (`eval/score.py` → `docs/llm-scorecard.md`): per-check and per-tier
    precision/recall/F1, Tier-B false-positive rate, majority-vote scoring, unanimity-based
    consistency metric.
  - Committed baselines: Sonnet 5 and Opus 4.8, both 21/21 correct (Tier-A F1 1.00,
    Tier-B FP rate 0.00); consistency 1.00 (Sonnet) vs 0.95 (Opus — one pass/not-applicable
    wording drift). See the honesty section in `docs/llm-scorecard.md` for what these
    numbers do and do not mean.
  - CI: blocking offline gate (dataset validity, scorecard freshness, Tier-A F1 ≥ 0.80
    floor on the committed baseline) plus a non-blocking live smoke job that skips politely
    without the API secret.
  - Tests: verdict parsing, request building, scorer math, and the model-mismatch guard —
    all offline, no key needed.

## [1.12.2] - 2026-07-08

### Fixed
- **`iosSourceDir` root scans no longer sweep build checkouts**: the code-level greps
  scoped to `$IOS_DIR` (purpose-string, tracking/ATT, IAP, private-API, and the other
  `${SRC_INC[@]}`-based checks) now apply the same `GREP_PRUNE` exclude-dirs as the
  repo-wide passes. When `iosSourceDir` resolves to the repo root (a common config, e.g.
  `"."`), these greps previously swept gitignored `build/`, `DerivedData/`, and
  `SourcePackages/checkouts/` output, misreading vendored SDK code as the app's own and
  producing false FAILs/WARNs — observed in the wild as an ATT 5.1.2 FAIL citing a
  RevenueCat mock under a `build/SourcePackages` checkout, and a 2.5.1 private-API FAIL
  citing the `sentry-cocoa` checkout under `.build/`.

## [1.12.1] - 2026-07-08

Quality patch from a full fresh-eyes review (three independent review passes over the
scanner core, the tooling shell, and the docs). No new checks; every change either removes
a false-RED path, fixes a real bug, or hardens the release surface.

### Fixed (scanner accuracy — false-RED cluster)
- **3.1.2 Restore Purchases** no longer misses StoreKit 2 paywalls: the match is
  case-insensitive and recognizes `AppStore.sync()` (a capitalized `Button("Restore
  Purchases")` used to force a false RED).
- **3.1.2 Terms/Privacy links** match human-readable labels ("Terms of Use", "Privacy
  Policy") and nonstandard URL paths (`/legal/tos`, `/eula`, `datenschutz`, `gizlilik`),
  case-insensitively.
- **Remote-configured paywalls** (RevenueCatUI `PaywallView`, `presentPaywall`,
  `paywallFooter`, AdaptyUI): missing Restore/Terms/Privacy in app source now downgrades
  to a verify-in-dashboard WARN instead of a hard FAIL — the SDK renders those controls
  from the vendor dashboard.
- **5.1.1 FileTimestamp Required Reason** check is anchored to real filesystem APIs;
  plain `creationDate` / `modificationDate` model properties no longer false-FAIL.

### Fixed (coverage and correctness)
- **Objective-C blind spot closed**: all code-level greps now share one include-set
  (`*.swift`, `*.m`, `*.mm`, `*.h`). Camera/mic/photo purpose-string FAILs, ATT/tracking
  signals, SIWA, analytics and the other code checks now fire on ObjC sources too.
- **`--dir` is authoritative**: `scan.sh --dir <path>` (new flag) scans exactly that
  directory instead of snapping to the enclosing git toplevel; the npx CLI passes it
  through and the GitHub Action uses it, fixing monorepo-subdir scans and SARIF paths
  (SARIF upload now also sets `checkout_path`).
- **Rule 42 suppressible**: `.precheck-ignore` accepted only rules 1–41; the bound is now
  derived from the catalog, so `screenshot-dimensions` (and any future rule) can be
  suppressed.
- **Verdict thresholds deduplicated** into `scripts/thresholds.sh`, shared by `verdict.sh`
  and the JSON renderer so the two can never diverge.
- **CLI**: a signal-killed scanner now exits 70 instead of masquerading as success.

### Added
- Fixtures + assertions for every fix above (`storekit2-paywall-app`,
  `revenuecat-paywall-app`, `objc-camera-app`, monorepo `--dir` case, rule-42 suppression),
  all labelled in the synthetic scorecard corpus.
- **`tests/test-pack.sh`**: packs the real npm tarball and runs the CLI from the extracted
  layout — a `files`-array regression can no longer ship silently.

### Changed (docs and CI hardening)
- README: CI example pins `@v1` (was stale `@v1.5.0`), "How it works" gains the opt-in
  Phase 6 row and the screenshot-vision mention, new Troubleshooting section, Windows/exit-code
  notes; coverage table reflects ObjC support.
- SKILL.md: Phase 6's Maestro MCP tools added to `allowed-tools`; Phase 2 gains an explicit
  skip-without-credentials instruction; scanner paths phrased skill-relative; the Phase 4
  summary separates the "+5 vision checks" from the "of 28" count; upload-guard hook note
  scoped to plugin installs. `simulator-dynamic-review.md` now names the real Maestro MCP
  tools (`list_devices`, `run`, `inspect_screen`, `take_screenshot`).
- Workflows: least-privilege `permissions:` blocks everywhere; all third-party actions
  pinned to commit SHAs (also in `action.yml`).
- MAINTENANCE.md: stale "41 vectors" corrected; docs index expanded.

## [1.12.0] - 2026-07-02

Roadmap #5 (final roadmap item): an **optional, opt-in local dynamic simulator tier** —
agent-mode, advisory, and off by default. It never changes the verdict and never runs
in the offline CLI / npx / GitHub-Action path.

When the user explicitly asks for a dynamic check and supplies a built app (or a booted
simulator UDID + bundle id), the host model can run the app on a disposable simulator via
`xcrun simctl` + Maestro MCP tools and observe real behavior a static scan cannot — launch
without crashing (2.1), core screen reachable, paywall actually renders with terms (3.1.2),
permission prompt matches its `Info.plist` purpose string (5.1.1), a demo/login path works
(2.1), and live UI matches the marketing screenshots (2.3.5). It emits advisory
`DYNAMIC-PASS:` / `DYNAMIC-FINDING:` lines, exactly like Pierre deep-review's `REVIEW-*`
lines. It is the free/local alternative to a paid cloud device farm — a pre-submit local
smoke signal, **not** a TestFlight / crash-reporter / QA replacement.

### Added
- **`skills/appstore-precheck/references/simulator-dynamic-review.md`** — the 6-check
  agent-mode dynamic checklist (D1–D6) with advisory output format, modeled on the existing
  deep-review reference docs.
- **`SKILL.md`** — an optional "Phase 6" section (off by default) plus a scoped READ-ONLY
  caveat and an updated "Known limits" note.
- Methodology + README notes describing the tier.

### Notes
- Documentation-only: the offline scan path (`scan.sh`/`verdict.sh`/`bin/cli.js`/`action.yml`)
  is byte-identical. READ-ONLY preserved — the tier touches only disposable simulator state,
  never the user's repo. It is permanently local-only (macOS + Xcode + a simulator; it cannot
  run in this project's `ubuntu-latest` CI). A deterministic `simulator-smoke.sh` and authored
  Maestro flows are deliberately deferred (simulator crash-timing is too flaky to ship as an
  unvalidated deterministic check).

## [1.11.0] - 2026-07-02

Roadmap #3: **rejection-outcome feedback loop** — a third, honestly-scoped measurement
axis. Reporting layer only; the scan and GREEN/YELLOW/RED verdict are untouched.

Alongside the synthetic and real-panel corpora, the tool now tracks **real App Store
review outcomes** (approved / rejected + Apple's cited guideline) in a committed,
human-reviewed ledger (`corpus/outcomes/ledger.json`, starts empty) and summarizes them
in `docs/scorecard.md`. The summary is **honesty-floored**: below 10 recorded outcomes
it shows only a raw tally and computes **no rate**; at/above the floor it may show a
directional recall estimate with a permanent survivorship-bias caveat. Because the
ledger is committed and read offline, the section is deterministic and covered by the
existing `scorecard.sh --check` — no network, no new CI job.

### Added
- **`corpus/outcomes/ledger.json`** (empty `[]`) + **`corpus/outcomes/README.md`** —
  record schema, anonymization/privacy rules (no verbatim Apple text, no real identity),
  contribution/review process, and the sample-size floor.
- **`scripts/scorecard-outcomes.sh`** — pure `bash`+`jq`, offline, deterministic; renders
  the "Real App Store outcomes (n=N)" section with the honesty floor. Also
  `scorecard.sh --outcomes`.
- The outcomes section is baked into `docs/scorecard.md`; Methodology now describes three
  measurements.
- **`.github/ISSUE_TEMPLATE/app-store-outcome.md`** — anonymized outcome contribution that
  funnels into a maintainer-reviewed PR.
- Test: `tests/test-scorecard-outcomes.sh`.

### Notes
- Reporting/measurement only — outcome data never influences the verdict or which rules
  fire (a future, human-only decision). No verbatim Apple Resolution Center text is stored.
  The scan path (`scan.sh`/`verdict.sh`/`bin/cli.js`/`action.yml`) is unchanged.

## [1.10.0] - 2026-07-02

Roadmap #4: **SARIF output + opt-in GitHub PR annotations** — read-only, no auto-fix.

The scanner can now emit its deterministic findings as **SARIF 2.1.0**
(`scan.sh --format sarif`, also `npx appstore-precheck --format sarif`), built from
the same structured findings as `--format json` with pure `jq` (no new dependency).
`results[]` contains the non-suppressed FAIL and WARN findings (FAIL → `error`,
WARN → `warning`); PASS and suppressed findings are excluded; findings that carry a
`file`/`line` become SARIF `physicalLocation`s so GitHub can anchor annotations. Only
the deterministic scan findings are included — the agent-mode Pierre deep-review
findings are not (SARIF is a deterministic CI artifact).

The GitHub Action gains two **opt-in** inputs (both default `false`, so existing
usage is unchanged): `sarif` uploads the SARIF to code-scanning via `upload-sarif`
(PR annotations + Security tab; needs `permissions: security-events: write`), and
`annotations` emits inline `::error`/`::warning` PR annotations. Both run even when
the scan verdict fails, and neither modifies the project.

### Added
- **`skills/appstore-precheck/scripts/sarif.sh`** — `render_sarif()`, a SARIF 2.1.0
  writer over the findings buffer (pure `jq`).
- **`scan.sh --format sarif`** (and `bin/cli.js --format text|json|sarif`).
- **`action.yml`** opt-in inputs `sarif` and `annotations` (default off): SARIF
  upload via `github/codeql-action/upload-sarif@v3` and inline PR annotations.
- Tests: `tests/test-sarif.sh` and `tests/test-action-sarif.sh`.

### Notes
- Read-only preserved: the scanner writes only to stdout; the Action redirects SARIF
  to a CI workspace file. No auto-fix. Default `--format text`/`--format json` output
  and the Action's default behavior are byte-identical to before.

## [1.9.0] - 2026-07-02

Smarter analysis (roadmap #2a): **screenshot vision**, in two layers.

**Layer 1 (deterministic, offline, zero-dependency).** The static scanner now
reads each in-repo screenshot's file format and, for PNGs, its pixel dimensions —
a new `screenshot-dimensions` check (catalog vector 42) under guideline 2.3.3. It
WARNs on a file whose content does not match its extension, a truncated PNG, or a
PNG whose dimensions match no known App Store screenshot size (either orientation).
WARN-only: it never forces a RED verdict, and the offline scan stays
byte-identical on inputs without real screenshots. Parsing uses only `bash`+`od`+
`awk` — no new runtime dependency.

**Layer 2 (agent-mode, non-blocking).** A dedicated structured screenshot vision
review that uses the host model's vision capability to check screenshots for
placeholder / dev-debug / empty-state content, text overflow / truncation, wrong
device frame / aspect, misleading marketing (2.3.3 "show the app in use" / 2.3.10),
and metadata mismatches. Like Pierre deep-review it is advisory (`REVIEW-FINDING`)
and never changes the GREEN/YELLOW/RED verdict. It runs only in agent-skill mode
(host vision model), never in the CLI / npx / GitHub-Action path.

### Added
- **`skills/appstore-precheck/scripts/image-dims.sh`** — zero-dependency PNG
  magic-byte + IHDR pixel-dimension parser (pure `bash`+`od`+`awk`) and the Apple
  accepted-screenshot-size table (verified against Apple's screenshot
  specifications page).
- **`scan.sh` §7b** — screenshot format + PNG-dimension validation (rule
  `screenshot-dimensions`, catalog vector 42), WARN-only.
- **`skills/appstore-precheck/references/screenshot-vision-review.md`** — agent-mode
  structured screenshot vision checklist (5 checks), non-blocking, wired into
  Pierre deep-review check #8 and SKILL.md Phase 4.
- Tests: `tests/test-image-dims.sh` (parser unit tests) and
  `tests/fixtures/screenshots-app/` (end-to-end fixture); `tests/make-png.py`
  fixture generator.

### Changed
- Advertised deterministic rejection-vector count **41 → 42** (the new
  screenshot-dimensions check) across README, SKILL.md, and methodology.
- Existing screenshot test fixtures: replaced 1-byte placeholders with real
  accepted-size PNGs (scan output byte-identical).

### Notes
- JPEG dimensions are not parsed in this release; JPEGs are format-validated
  (magic bytes) and counted only.

## [1.8.0] - 2026-07-02

Smarter analysis (roadmap #2c): a deterministic **semantic guideline-drift**
detector. Beyond the existing section-number check, the tool now fingerprints the
*text* of every guideline section our checks depend on and reports when Apple
rewrites a section's meaning (even if its number is unchanged), naming the
affected check(s). It is a maintainer/CI tool — network-using (`curl`), never
sourced by `scan.sh`, never in the offline user scan path. Zero new runtime
dependency for the distributed scanner; default scan output stays byte-identical.

### Added
- **`scripts/guideline-drift.sh`** (maintainer/CI): fetches the full live App
  Store Review Guidelines and reports section-number drift AND text drift of
  covered sections, deriving the affected check(s) from `scan.sh`'s `set_rule`
  blocks. Non-blocking (WARN lines, always exits 0); the parse/diff logic is
  unit-tested offline via `--html`. `--reconcile` regenerates the fingerprint
  baseline (a deliberate human step) and skips/ WARNs on sections Apple has
  removed rather than writing empty placeholders.
- **`skills/appstore-precheck/guidelines-fingerprints.json`** — human-reconciled
  per-covered-section text fingerprints (57 sections).
- A non-blocking scheduled + manual GitHub workflow (`guideline-drift.yml`) that
  surfaces drift; it never gates a PR.

### Changed
- **Baseline reconciled to Apple's current guidelines** (the drift tool's first
  run caught real drift): Apple consolidated section 5.6 to end at **5.6.4** —
  the removed **5.6.5–5.6.7** were dropped from the baseline and Pierre
  deep-review check 28 (rating/review-manipulation) was remapped to the surviving
  **5.6.1 / 5.6.3**. Six sub-sections a prior truncated fetch had missed
  (2.5.7, 2.5.10, 4.2.4, 4.2.5, 4.4.3, 4.6) were added to `all_sections`.

## [1.7.0] - 2026-07-02

Smarter analysis (roadmap #2b): the scanner now resolves the iOS source directory
and `Info.plist` from the Xcode **project model** (`.pbxproj`) instead of a pure
grep heuristic, eliminating the dominant remaining false-positive source in
monorepo / SPM / multi-target layouts. Zero new runtime dependencies (pure
bash + awk), READ-ONLY preserved, and default text output stays byte-identical for
any repo without a `.pbxproj`.

### Added
- **Project-model detection** (`skills/appstore-precheck/scripts/project-model.sh`):
  parses `.pbxproj` to find the primary `application`-type target and resolve its
  source dir + `INFOPLIST_FILE` authoritatively, across ALL `.xcodeproj` in a
  monorepo. `detect_ios_dir` now chains: config `.iosSourceDir` > project-model
  parse > the original grep heuristic (unchanged, kept as fallback).
- Per-target `INFOPLIST_FILE` attribution via the build-config graph
  (target → `buildConfigurationList` → `XCBuildConfiguration`), used as a last
  resort so already-correct apps are untouched; unexpanded build-variable paths
  (`$(SRCROOT)` etc.) are guarded, and app targets under vendored paths
  (`ThirdParty`/`Vendor`) are deprioritized so a vendored sample app never wins.

### Measured impact (18-app open-source panel, candidate/directional labels)
- Corrects detection on `wikipedia-ios`, `pocket-casts-ios`, `cwa-app-ios`
  (now read their real custom-named plists) and `brave-ios` (real app over a
  vendored sample). `usage-description-crosscheck` false positives 9 → 6, with
  content-grounded findings surfaced by finally reading the correct plist; zero
  true-positive loss. See `docs/fp-reduction-report.md`.

## [1.6.0] - 2026-07-01

Measurement release: structured findings, suppression, and a published
precision/recall scorecard, plus a measurement-driven false-positive reduction
round. Default text output stays byte-identical (verified across 11 fixtures);
every behavior change is gated by TDD and the synthetic-corpus `--check`.

### Added
- **`scan.sh --format json`**: structured findings envelope (`{tool, version, verdict, summary{fail,warn,pass,suppressed}, findings[{rule_id, severity, guideline, message, file, line, suppressed}]}`) for tooling and measurement. Stable `rule_id` per vector via a 41-slug catalog. Default text output is unchanged.
- **`.precheck-ignore` suppression**: repo-root rules (`<rule-id>`, `<rule-id> <path-glob>`, `<path-glob>`-exclude) and inline `# precheck:ignore [rule-id]` directives (`//`, `#`, `<!-- -->`). Suppression is emit-time — a suppressed FAIL no longer forces RED — and always transparent: suppressed findings stay in `findings[]` with `suppressed:true`, count in `summary.suppressed`, and a text footer reports the count only when non-zero (byte-identity preserved otherwise).
- **Precision/recall scorecard**: `scripts/scorecard.sh` (`--check` / `--selftest` / default) over a synthetic labelled corpus (`corpus/synthetic/labels.json`), plus `scripts/scorecard-real.sh` over an 18-app commit-pinned open-source real panel (`corpus/real/`). Published to `docs/scorecard.md` with a mandatory honesty section (neither corpus claims agreement with Apple's actual decisions). Synthetic `--check` is a blocking CI gate; the real panel is non-blocking.
- File/line threading into locatable checks (surfaced in JSON; text output unchanged).

### Fixed
- **False-positive reduction round** (measurement-driven; ~33 FP eliminated across the 18-app panel with zero true-positive loss, char-limit-excluded precision 0.37 → ~0.54):
  - **Analytics detection** now requires an import/API-qualified form, so a bare `Segment` substring (e.g. `UISegmentedControl`) no longer trips 5.1.1.
  - **IAP gate** requires a real purchase API, ignoring `SKStoreReviewController` / `SKAdNetwork` / the `AppStore.` namespace.
  - **Usage-description checks** are capture-gated: playback-only AVFoundation / PhotosPicker no longer false-fire; mic matches `.playAndRecord`; video-only `AVCaptureDevice` no longer triggers the microphone check.
  - **Minimum-functionality navigation** detects UIKit / `NavigationView` / React-Navigation repo-wide.
  - **Screenshots-per-locale**: no in-repo screenshots directory is an advisory PASS (managed in App Store Connect), not a WARN.

## [1.5.2] - 2026-06-30

### Fixed

- **§23 (1.6 ATS) false positive**: the App Transport Security check now anchors to the exact `NSAllowsArbitraryLoads` key, so the scoped exceptions `NSAllowsArbitraryLoadsInWebContent` / `NSAllowsArbitraryLoadsForMedia` — which do not disable ATS app-wide and are Apple's recommended alternative — no longer trip a spurious WARN.
- **Kids-signal double-count (§27 ↔ §39)**: when a child-audience term and a third-party ads/analytics SDK are both present, only §39 (5.1.4) fires now; §27 (2.3.8) is cross-gated so one root signal no longer costs two WARNs against the 5-WARN YELLOW threshold.
- **§33 (2.5.4) background-mode coverage**: `audio` now recognizes AVKit / `VideoPlayer` / `AVPlayerViewController` / MediaPlayer now-playing APIs, and `fetch` / `processing` recognize `BGTaskScheduler`, reducing "declared but unused" false positives.
- Pierre deep-review docs: corrected the Tier A definition (22 = all 28 except the 6 Tier B items; previously implied 17), fixed the stale "22 checks" label and broken table-of-contents anchor in the methodology and example files.
- §28 / §37 evidence now print the plist basename, matching the rest of the batch.

## [1.5.1] - 2026-06-30

### Changed

- Plugin manifest descriptions no longer embed drifting check counts
- README uninstall: Codex uses /plugins UI
- cross-tool-verification.md plugin install paths documented
- GitHub release v1.5.0 notes amended; npm 1.5.1 published

## [1.5.0] - 2026-06-30

### Added
- **Tier B v1 — 6 heuristic Pierre deep-review checks** (28 total, up from 22). New Phase 4 items
  in guideline order: **2.1** review notes / demo account quality, **2.2** beta/test language,
  **2.3.4** app preview consistency, **2.3.9** incentivized review copy, **4.5.1–4.5.3** push /
  HomeKit abuse patterns, **5.6.4–5.6.7** rating manipulation dark patterns. Marked † in docs;
  higher false-positive risk — advisory `REVIEW-FINDING: WARN` only.
- Expanded `covered_by_pierre_deep_review` in `guidelines-baseline.json` with 2.2, 2.3.4, 2.3.9,
  4.5.1–4.5.3, 5.6.4–5.6.7.

### Changed
- Phase 4 checklist 22 → **28** across `pierre-deep-review.md`, `SKILL.md`, `methodology.md`, README
  (full guideline-ordered table with † Tier B labels), plugin manifest, and social preview
  (`41 static + 28 Pierre deep checks`).

## [1.4.0] - 2026-06-30

### Added
- **Phase 4: Pierre deep review — 22 semantic checks.** After Phase 3 (explaining every scan
  FAIL/WARN), Pierre runs a read-only Review Simulator: fetches privacy/support URLs, reads
  screenshots, compares metadata claims to Swift code, validates paywall disclosure quality, and
  cross-checks permissions vs policy. Each check emits `REVIEW-PASS:` or advisory
  `REVIEW-FINDING: … WARN` (does not change GREEN/YELLOW/RED counts). Full checklist in
  [`references/pierre-deep-review.md`](skills/appstore-precheck/references/pierre-deep-review.md).
- **`covered_by_pierre_deep_review`** in `guidelines-baseline.json` (26 guideline numbers across
  the 22 checks). Consolidation moves to **Phase 5** (6 phases total: 0–5).
- [`examples/pierre-deep-review.md`](examples/pierre-deep-review.md) showing `REVIEW-FINDING` output.

### Changed
- Flow is now **6 phases (0–5)**: Phase 3 = scan commentary, Phase 4 = deep review, Phase 5 =
  verdict + token. Updated `SKILL.md`, `methodology.md`, README (static table + deep-review table
  in guideline order), examples, plugin manifest, and social preview copy (`41 static + 22 Pierre
  deep checks`).

## [1.3.1] - 2026-06-30

### Changed
- **Phase 3 (Pierre) now explains every FAIL and WARN** from Phases 0–2 in **2–3 sentences
  each** — no more random 5-guideline sampling. Pierre repeats each machine line verbatim,
  then explains why Apple cares, what the scan found, and what to fix. Updated `SKILL.md`,
  `methodology.md`, the README example, `examples/red-reject.md`, and behavioral eval
  assertions in lockstep.
- Phase 4 presentation order clarified: trilingual verdict block → Pierre commentary → verbatim
  scan lines + `file:line` fixes → verdict/token.
- **Trilingual verdict block format:** each language in its own **bold label + blockquote**, separated
  by horizontal rules (`---`) under a `### Pierre` heading — never FR/EN/user-lang compressed on one line.

## [1.3.0] - 2026-06-30

### Added
- **Eleven new signal-gated advisory checks (30 → 41 rejection vectors), all WARN-only:**
  - **2.1** a login-gated app with no demo account / credentials for App Review (fastlane
    `review_information` or `.reviewPrepNotes`).
  - **2.5.2** executable-code download / native hot-patching (JSPatch, Rollout, DynamicCocoa).
    Allowed JS-bundle OTA (React Native CodePush) is deliberately **not** flagged.
  - **2.5.4** a background mode declared in `UIBackgroundModes` with no matching API used in Swift.
  - **3.1.5(a)** a cryptocurrency wallet / exchange / mining signal.
  - **4.2.3** a thin WKWebView wrapper around a website (heuristic: WKWebView + very few Swift files).
  - **4.2.7** a remote-desktop / host-mirroring signal.
  - **4.4.2** a Safari content-blocker / web extension.
  - **5.1.1(v)** account creation offered without an in-app account-deletion path (the real
    5.1.1(v) Account Sign-In rule).
  - **5.1.4** metadata targeting a child audience while a third-party ads/analytics SDK is linked.
  - **5.3.4** real-money gambling language in metadata.
  - **5.5** a Mobile Device Management (MDM) signal.
- `tests/fixtures/risky-app-2` (advisory §31–§41 except web-wrapper) and `tests/fixtures/webview-app`
  (the 4.2.3 heuristic), with assertions in `tests/run.sh`. Both are advisory-only (no FAIL).

### Changed
- **Corrected the Required Reason API label from `5.1.1(v)` to `5.1.1`.** Apple documents the
  Required Reason API rules under 5.1.1 + the privacy-manifest developer docs; sub-item **(v)** is
  "Account Sign-In", a different rule. The `(v)` label now belongs to the new account-deletion
  check (vector 38). Updated `scan.sh` output, the methodology table, the README table, the
  examples, and the field-test notes in lockstep.
- §18 (support / privacy URL) now also cites the guidelines it satisfies: **1.5** (developer
  contact via the support URL) and **5.1.1(i)** (privacy policy link).
- Expanded `guidelines-baseline.json` `covered_by_scan` with 1.5, 2.5.2, 2.5.4, 3.1.5, 4.2.3,
  4.2.7, 4.4.2, 5.1.4, 5.3.4, and 5.5.

## [1.2.0] - 2026-06-30

### Added
- **Ten new signal-gated advisory checks (20 → 30 rejection vectors), all WARN-only:**
  - **3.1.1** third-party payment SDK (Stripe, Braintree, PayPal, Square, Adyen, …) linked for
    digital goods instead of in-app purchase.
  - **1.2** user-generated content detected without a report / block / moderation affordance.
  - **1.6** App Transport Security disabled app-wide (`NSAllowsArbitraryLoads=true`).
  - **4.9** recurring Apple Pay without the renewal / cancel disclosure.
  - **5.6.1** a direct App Store write-review link/prompt without the system `requestReview` API.
  - **2.3.1** misleading marketing claims (iOS virus / malware scanners, fake speed boosters) in metadata.
  - **2.3.8** "For Kids" / "For Children" wording outside the Kids Category.
  - **4.4.1** keyboard extension requiring full access (`RequestsOpenAccess=true`).
  - **5.1.3** HealthKit used together with an iCloud / CloudKit sync path.
  - **5.4** VPN / NetworkExtension (`NEVPNManager`) usage.
- `tests/fixtures/risky-app` plus assertions in `tests/run.sh` exercising all ten new vectors
  (advisory only — the fixture is YELLOW, never RED).

### Changed
- **YELLOW threshold raised from 3+ to 5+ WARN.** The ten new advisory checks are signal-gated
  (most apps trip only one or two), but the bump keeps a normal submission from sliding into
  YELLOW on advisory noise alone. GREEN is now 0 FAIL and ≤4 WARN; YELLOW is 0 FAIL and ≥5 WARN.
  Updated `verdict.sh`, the verdict tests, the output-contract tables, and the docs in lockstep.
- Corrected the minimum-functionality check's label from `4.0` to `4.2` (its real guideline
  number) in the scanner output, the methodology table, and the README.
- Reconciled `guidelines-baseline.json` against the live guidelines (Last Updated June 8, 2026):
  no structural section drift; expanded `covered_by_scan` to reflect every guideline the scan now
  touches (adds 1.2, 1.6, 2.1, 2.3, 2.3.8, 3.1.1, 4.4.1, 4.8, 4.9, 5.1.3, 5.4, 5.6.1; 4.0 → 4.2).

## [1.1.1] - 2026-06-30

### Changed
- **Pierre now speaks in a trilingual block.** The verdict opens with his native **French** line,
  then an **English** rendering, then a rendering in the **user's conversation language** — each an
  idiomatic, in-character re-expression in that language's own rhythm, not a literal translation.
  Collapses to two lines when the user already converses in French or English. The block stays
  flavor only; the FAIL/WARN list, `file:line` references, and fixes below it remain plain and
  machine-faithful. Updated the output contract, Phase 4 step 3, and the behavioral eval
  assertions accordingly.

### Fixed
- **Pierre no longer treats local-only files as Apple submission evidence.** The Phase 3 prompt
  now scopes reject-risk evidence to Apple-facing artifacts (fastlane metadata, paywall Swift,
  String Catalog, Info.plist, PrivacyInfo.xcprivacy). Internal/local files (`.planning/` notes,
  `reviewPrepNotes` drafts, build scripts) and Google Play / non-Apple sections are out of scope —
  cited at most as a WARN labeled "internal draft — not submitted to Apple", never REJECT-RISK. A
  REJECT risk now requires a contradiction *within* submission-facing artifacts, not an internal
  doc disagreeing with metadata. An eligibility-gated/conditional offer paired with metadata that
  mentions it is WARN at most (unless the metadata promises it unconditionally). Prevents the
  false REJECT-RISK overreach seen when dogfooding an already-approved build.
- **2.3.7 locale check no longer hard-FAILs on a config/disk mismatch.** A locale listed in
  `.appstore-precheck.json` `locales` but with no metadata folder on disk is now a WARN (with an
  actionable "add it or remove it from the config" message), not a FAIL — that locale was simply
  never submitted, so it must not turn an approved set RED. A missing *file* inside a present
  locale folder is still a FAIL.
- **2.1 placeholder check no longer false-fires on words containing "changeme".** The `changeme`
  pattern is now word-bounded (`\bchangeme\b`) in both the metadata-URL and store-copy scans, so
  legitimate copy such as the French "changement" ("change") is not flagged as unfinished.
- Added regression coverage in `tests/test-config.sh` for both fixes.
- CI: bumped `actions/checkout@v4 -> v7` and `actions/setup-node@v4 -> v6` to clear the
  GitHub Actions Node.js 20 deprecation warning (both now run natively on Node 24).

## [1.1.0] - 2026-06-28

### Added
- `npx appstore-precheck` CLI (`bin/cli.js`): run the static scan with no clone and no install.
  It scans the current directory (or `--dir <path>`), prints the scan output and the verdict
  verbatim, and exits non-zero on RED (or on YELLOW with `--fail-on YELLOW`), mirroring the
  GitHub Action. A thin wrapper over the bundled `scan.sh` / `verdict.sh`; it adds no new checks.
- Published to npm under the package name `appstore-precheck`.
- `tests/test-cli.sh`: covers the CLI's verdict mapping and exit codes (GREEN/RED/YELLOW,
  `--fail-on`, `--version`, `--help`, bad-usage), wired into the suite and `npm run lint`.

## [1.0.0] - 2026-06-28

Initial release.

### Added
- `appstore-precheck` Agent Skill: read-only iOS App Store pre-submission gate.
- `scripts/scan.sh`: portable Bash scanner for 20 rejection vectors (including advisory Sign in
  with Apple parity and external-purchase-link checks) with zero-config
  auto-detection of a standard fastlane + Xcode layout, plus `.appstore-precheck.json` overrides.
- Five more signal-gated advisory checks (15 → 20): tracking/IDFA SDK shipped without an ATT
  prompt (5.1.2, the reverse of the existing ATT check), the export-compliance key
  (`ITSAppUsesNonExemptEncryption`), support/privacy URL presence in fastlane metadata (2.3),
  analytics SDK vs `PrivacyInfo.xcprivacy` data-type declarations (5.1.1), and placeholder/dummy
  copy in store metadata (2.1). All WARN-only, with a `tracking-app` fixture that exercises them.
- `scripts/verdict.sh`: deterministic GREEN/YELLOW/RED verdict and `.precheck-pass` token
  action from the scan output, so the verdict is machine-testable, not just an agent judgement.
- 5-phase flow: guideline-drift check, static scan, Apple `fastlane precheck` wrapper,
  adversarial reviewer pass, consolidation + `.precheck-pass` token.
- Optional Claude Code upload-guard hook (`hooks/fastlane-guard.sh`) that blocks
  `fastlane deliver/pilot/release` without a fresh token.
- Cross-tool support: native `SKILL.md` for Claude Code / Codex / Cursor / Gemini CLI,
  root `AGENTS.md`, and an `install.sh` multi-host installer. Claude Code and Codex CLI runs
  verified end-to-end (`docs/cross-tool-verification.md`).
- Claude Code plugin + single-plugin marketplace manifests.
- Test suite (`tests/`): fixture scans plus unit tests for verdict thresholds, the upload-guard
  hook, config overrides, and the installer. CI runs ShellCheck, JSON validation, a
  version-consistency guard, and the full suite on every push and PR.
- Documentation: methodology reference, a how-to-add-a-check guide, an agent-portability note,
  real Phase 0 drift-check and Phase 2 `fastlane precheck` examples, and a field-test report
  from dogfooding real App Store apps (`docs/`).
- Community health files: contributing guide, security policy, code of conduct, and issue/PR
  templates.
- Behavioral eval suite (`skills/appstore-precheck/evals/`) in the Agent Skills format: RED /
  GREEN / no-IAP cases with self-contained inputs and assertions.
- Branding: logo, social preview, and **Pierre**, the French App Review critic mascot whose
  voice drives the Phase 3 adversarial review.

### Fixed
- More reliable app-target auto-detection: resolve the iOS source dir via the app entry point
  (`@main` / `AppDelegate`), not Info.plist position alone, so a Watch app, extension, or
  framework is no longer mistaken for the main target. Required-link checks now scan the whole
  paywall cluster instead of a single auto-picked file. (Found by dogfooding Pocket Casts,
  Wikipedia, and DuckDuckGo.)
- Portable empty-array handling under `set -u` on stock macOS bash 3.2 and modern bash.
