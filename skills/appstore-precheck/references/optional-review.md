# Explicit optional review tiers

The default scan reads the project and emits static findings. These optional tiers
require an explicit CLI choice; they are not evidence that every guideline passed.

```bash
# Read an existing artifact, without executing it.
bash skills/appstore-precheck/scripts/scan.sh --dir /path/to/project \
  --app /path/to/Debug-iphonesimulator/App.app --no-runtime --format json

# Local metadata only; ASC access and URL checks require their separate options.
bash skills/appstore-precheck/scripts/scan.sh --dir /path/to/project \
  --metadata --format json --out /path/outside/project/review

# Explicitly execute build scripts in a disposable source copy.
bash skills/appstore-precheck/scripts/build-run.sh --repo /path/to/project \
  --out /path/outside/project/build
```

`--app` without `--no-runtime` requests simulator execution. `--build` requests both
an isolated build and runtime review unless `--no-runtime` is supplied. The dynamic
runner itself never builds. Missing tools or an ambiguous project/scheme produce
SKIP with the reason; an existing `.app` can be supplied instead. Expo preparation
requires a locked package manager install before generating its iOS project.

Build scripts are arbitrary code. The temporary source copy is not an OS or network
sandbox. Release scripts may upload dSYMs. The child environment is restricted and
credential files are excluded, but do not supply ASC/demo credentials to an untrusted
build. Compiler output is retained in the reported artifact directory's `build.log`.
Approved Flutter plugin and xcframework version links are materialized in the copy;
other source links are refused. Build evidence reports whether source hashes changed.

`--out` must be outside the input project. Text and JSON reports identify retained
output; automatically allocated SARIF output is removed after rendering. Reports
contain paths, screenshots and compiler diagnostics and should be treated as private.
The JSON additions contain tier summaries and pointers, not a guideline text corpus.

Repository `dynamic.build` and `dynamic.demoLogin` require
`APPSTORE_PRECHECK_TRUST_CONFIG=1`. Explicit CLI flags authorize the corresponding
operation. The GitHub Action clears repository trust on each scan invocation.

Demo login also requires `PRECHECK_DEMO_AUTHORIZED_TEST=1`,
`PRECHECK_DEMO_ENVIRONMENT=test` or `sandbox`, `PRECHECK_DEMO_USERNAME`,
`PRECHECK_DEMO_PASSWORD`, `PRECHECK_DEMO_SUCCESS_TEXT` and
`PRECHECK_DEMO_FAILURE_TEXT`. Field labels can be set with `PRECHECK_DEMO_USER_FIELD`,
`PRECHECK_DEMO_PASSWORD_FIELD` and `PRECHECK_DEMO_SUBMIT`. Values containing Maestro
expressions are refused. Credentials are used only in a private temporary flow and
are not retained in reports. A rejected login is a FINDING; missing or ambiguous
postconditions are SKIP, never a fabricated successful authentication.

`--dynamic-blocking` is a separate, explicit escalation option. Only launch failure
with a dead process or crash log, or an explicit rejected demo login, can qualify.
The validator requires three unanimous fresh-erase observations on an owned device;
driver failures, a uniform screenshot alone, dry runs and mixed results cannot qualify.
Other runtime observations remain advisory. Debug evidence cannot clear a requirement
for shipping-build verification. The verdict/token implementation remains unchanged.
