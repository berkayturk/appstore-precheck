# Build worker integration notes

`skills/appstore-precheck/scripts/build-run.sh` is an **opt-in** iOS simulator build
entry point. Call only after an explicit `--build` or `dynamic.build: true` setting.
It executes project build scripts inside a temporary `rsync` copy, so the scan's
default read-only path must never call it.

CLI: `bash build-run.sh --repo "$ROOT" [--framework native|rn|flutter|kmp]
[--platform ios] [--out "$ARTIFACT_DIR"] [--timeout 1200] [--dry-run] [--keep-build]`.
Exit 0 yields `app_path=<absolute path>`, `artifact_dir=<absolute path>`, and
`build_config=release|debug`; exit 3 prints `SKIP: build-run` or
`SKIP: platform-not-audited` with a reason and `--app <path>` hint. Exit 64 is a
usage error, 66 a missing input. On success, pass `app_path` to `dynamic-run.sh
--app` and `build_config` to `dynamic.sh --build-config`. The exported bundle is
also discoverable with `app-discover.sh --derived-data "$ARTIFACT_DIR"`.
The caller owns `artifact_dir` cleanup after artifact/runtime inspection. The
project copy and DerivedData are removed on exit unless `--keep-build` was passed.

The build runner removes secret/config/signing files from the copy (`.env*`,
`.appstore-precheck.json`, `*asc-key*.json`, `.p8`, `.p12`, mobileprovision), gives
tools a minimal environment, and records only structured statuses. It never
persists or prints raw tool output. It rejects symlinks in copied source files
because build scripts could follow a link into the original tree. Build scripts
are arbitrary code and could themselves use absolute paths; document this
limitation in SECURITY.md and SKILL.md along with the fact that opt-in build
executes project code and may access the network.

Shared-file changes requested from integrator:

- Wire `scan.sh --build`, CLI `dynamic --build`, and config `dynamic.build: true`
  to this runner. Do not call it for the default scan.
- Replace the old “never builds” statements in `app-discover.sh` comments,
  `dynamic-run.sh` comments, SECURITY.md, SKILL.md, and user docs with the
  distinction between default discovery and explicit isolated build.
- Add `tests/test-build-run.sh` to `tests/all.sh` and the `build-run` check IDs
  to the registry/coverage output (this worker cannot edit shared files).
- Preserve `build_config=debug` for Flutter simulator builds and Xcode Debug
  fallback; it must not clear `needs_build_verification`.
- Classify build failure as SKIP/NOT_RUN, never PASS. `--platform` values other
  than `ios` return `platform-not-audited`.

Test with `bash tests/test-build-run.sh`. An actual project build smoke test is
at `bash tests/local/build-run.sh /path/to/project` and intentionally stays out
of Ubuntu CI.
