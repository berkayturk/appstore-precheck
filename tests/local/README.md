# tests/local — macOS-only checks

Nothing here runs in CI (`ubuntu-latest`) or in `tests/all.sh`. These scripts need a Mac with
Xcode and a simulator runtime, and they **execute the app under test**.

| Script | What it does | When |
|---|---|---|
| `run-dynamic.sh` | Discovers a simulator `.app` you already built, asks for an explicit `yes`, runs `dynamic-run.sh` (throwaway device, 3 launch repeats, dark mode / Dynamic Type / shipped-bundle / hosts observations) and reconciles the transcript with the static scan via `dynamic.sh`. | Before each release; after any change to `dynamic-run.sh` or `scripts/lib/dyn-*.sh`. |

```bash
bash tests/local/run-dynamic.sh --repo /path/to/app-repo            # proposes the newest DerivedData build
bash tests/local/run-dynamic.sh --repo . --app /path/To.app --ipad   # explicit app, plus the iPad pass
```

It never builds: if discovery finds nothing it prints the `xcodebuild -sdk iphonesimulator …` /
`flutter build ios --simulator` command for **you** to run, then exits 3.

The CI-safe counterparts live in `tests/test-dynamic-run.sh` (the runner against a shimmed
`xcrun`/`maestro`), `tests/test-dynamic-libs.sh` (decision rules, PNG decoder, geometry, hosts,
bundle readers) and `tests/test-dynamic-reconcile.sh` (transcript → findings → reconciliation).
