# Local dynamic corpus

This corpus exercises the opt-in simulator build and runtime paths. Each framework
has a `clean/` and `broken/` source variant. `clean` means only that the *targeted
synthetic defects* below are absent. The buttons use local state; they do not
implement a production account service, purchase restoration, or moderation backend.

| Framework | How the iOS host is obtained | Broken target |
| --- | --- | --- |
| SwiftUI | Checked-in XcodeGen project and Swift sources | Deterministic launch crash |
| React Native bare | Official Community CLI template in temporary storage; checked-in `App.js` replaces its screen | Missing account deletion, third-party sign-in without Apple parity, inert Restore, missing UGC report |
| Expo | Official `create-expo-app` blank template in temporary storage; checked-in screen and app config replace the defaults | Placeholder, inert Restore, missing UGC report, absent camera purpose text in shipped bundle |
| Flutter | `flutter create` iOS host in temporary storage; checked-in Dart screen replaces the default | Placeholder, missing account deletion and UGC report |
| KMP | Checked-in XcodeGen iOS host plus Kotlin shared framework source; Gradle builds the framework inside the build copy | Placeholder, missing account deletion and UGC report, extra HealthKit entitlement |

Every `build.sh clean|broken` calls `skills/appstore-precheck/scripts/build-run.sh`,
which copies the staged project again before building and exports only the `.app`.
The source and generated host are never modified by that build. SwiftUI and KMP
Xcode project files are committed as text so XcodeGen is optional at run time. No
binary, package cache, generated host, or build output is committed.

Run one variant:

```bash
bash corpus/dynamic/swiftui/build.sh clean --out /tmp/precheck-swiftui-clean
```

Run the full local matrix and keep its machine-readable result:

```bash
bash tests/local/dynamic-panel.sh --out /tmp/precheck-dynamic-panel
```

The panel runs the checked-in builder, `dynamic-run.sh --explore` when available,
then `dynamic.sh`. It writes `panel.json` and `panel.tsv`, preserving per-case
build and runtime artifacts under the chosen output directory. It compares
`dyn-launch` with the manifest for every runnable case and selected exploratory
checks with the broken variants. A missing tool, registry access, framework
dependency, simulator runtime, or usable accessibility tree is recorded as
`SKIP` or `NOT_RUN` rather than a successful observation. Flutter and KMP
interactive checks may remain `SKIP` when accessibility semantics are unavailable.

The manifest's `expected_bundle` fields also compare Info.plist seed expectations
(`absent` or `nonempty`). These are corpus integrity checks, not App Store verdicts;
they catch generation defaults that accidentally repair a broken fixture.

RN and Expo templates are fetched at run time; the current compatible packages
and generated lockfile are temporary. To reproduce an exact third-party build,
retain the panel's exported `.app` and record the generated template/package
versions externally. The panel runs app code and may contact package registries;
it requires explicit invocation.
