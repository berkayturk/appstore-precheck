# Guideline obligation coverage

`python3 scripts/coverage.py --merge` combines the reviewed section files in `references/obligations/` and check fragments in `references/registry/`. It validates every route against an implementation and fixture test, then writes `guideline-obligations.json`, `check-registry.json`, the repository `coverage.json`, and `docs/guideline-coverage.md`. Run `python3 scripts/coverage.py --require-complete` in CI. Counts in the generated files are authoritative; route counts overlap.

An obligation can have several partial routes. A static, artifact, runtime, or metadata signal is only a full automatic decision when its route declares `decides: full`. A `PASS` from a partial check does not prove that the obligation passed. Semantic review requires evidence and human judgment. Attestation records a developer answer and evidence pointer; `ATTESTED_YES` is not a verified pass. Process text and definitions carry a documented `not_app_checkable` reason rather than a false app result.

The optional local workflow is:

```bash
bash skills/appstore-precheck/scripts/scan.sh --dir /path/to/app --build --metadata --out /tmp/precheck-review --format json
bash skills/appstore-precheck/scripts/scan.sh --dir /path/to/app --app /path/to/App.app --out /tmp/precheck-review --format json
appstore-precheck dynamic --build --dir /path/to/app --out /tmp/precheck-review
```

`--build` and `.appstore-precheck.json` `dynamic.build: true` are explicit build opt-ins. The build uses a temporary project copy and DerivedData there. It may run project scripts and access networks or backends. The runtime tier creates, erases, and deletes its own simulator, and executes the app. `--dry-run` prints the build plan without building. `--metadata` reads local fastlane data; `--asc-app-id` enables read-only App Store Connect queries using environment credentials. `--check-urls` explicitly enables public URL checks. Keep `--out` outside the app project. Without `--out`, a generated temporary report directory is retained and named in `opt_in.report_dir` so evidence pointers stay valid. The generated run results, source signal packets, artifact review, metadata review, runtime transcript, and screen inventory live there.

`scan.sh --format json` includes `coverage_run`, `coverage_summary`, and per-obligation results. `ran`, `skipped`, and `not_run` describe this particular run, not catalog capability. Missing tools, unreadable evidence, a failed build, or a timed-out simulator yield `SKIP` or `NOT_RUN`; a clean static scan alone does not turn unexecuted checks into passes. The attestation report can be generated with:

```bash
python3 skills/appstore-precheck/scripts/attestation-report.py --config /path/to/app/.appstore-precheck.json --run-results /tmp/precheck-review/run-results.json --out /tmp/precheck-review/attestation.json --markdown /tmp/precheck-review/attestation.md
```

The config may contain `attestations` keyed by obligation ID, each with `answer` (`yes`, `no`, or `unknown`), `evidence`, and `answered_on`. Keep sensitive evidence in a private location; the report stores the pointer rather than uploading the material.

Runtime exploration uses a bounded screen and time budget. Its detected patterns are leads for review, especially with sparse Flutter or Compose accessibility trees. Only explicit `--dynamic-blocking` can add a `FAIL:` for a repeated 3/3 launch crash or demo login failure. Other runtime observations remain advisory. A Debug build never clears a build verification qualifier. The default invocation remains offline and keeps its existing text and verdict contract.
