#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAN="skills/appstore-precheck/scripts"
# shellcheck source=tests/_assert.sh
source "$ROOT/tests/_assert.sh"
# shellcheck source=skills/appstore-precheck/scripts/project-model.sh
source "$ROOT/$SCAN/project-model.sh"

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

# --- pm_app_targets: only application productType, ignore tests/extensions ---
cat > "$work/sample.pbxproj" <<'EOF'
		AAA /* MyApp */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = BBB /* list for "MyApp" */;
			name = MyApp;
			productName = MyApp;
			productType = "com.apple.product-type.application";
		};
		CCC /* MyAppTests */ = {
			isa = PBXNativeTarget;
			name = MyAppTests;
			productType = "com.apple.product-type.bundle.unit-test";
		};
		DDD /* MyWidget */ = {
			isa = PBXNativeTarget;
			name = MyWidget;
			productType = "com.apple.product-type.app-extension";
		};
EOF
got="$(pm_app_targets "$work/sample.pbxproj")"
assert_eq "$got" "MyApp" "pm_app_targets returns only the application target"

# --- quoted target name with spaces ---
cat > "$work/quoted.pbxproj" <<'EOF'
		EEE /* app */ = {
			isa = PBXNativeTarget;
			name = "My Cool App";
			productType = "com.apple.product-type.application";
		};
EOF
assert_eq "$(pm_app_targets "$work/quoted.pbxproj")" "My Cool App" "pm_app_targets strips quotes"

# --- pm_infoplist_files: collect, unquote, dedupe ---
cat > "$work/plists.pbxproj" <<'EOF'
				INFOPLIST_FILE = MyWidget/Info.plist;
				INFOPLIST_FILE = "MyApp/Info.plist";
				INFOPLIST_FILE = MyWidget/Info.plist;
EOF
got="$(pm_infoplist_files "$work/plists.pbxproj" | tr '\n' '|')"
assert_eq "$got" "MyApp/Info.plist|MyWidget/Info.plist|" "pm_infoplist_files unquotes + dedupes + sorts"

# --- pm_resolve: GENERATE_INFOPLIST_FILE app + extension owns the only plist ---
gen="$(mktemp -d)"
mkdir -p "$gen/App.xcodeproj" "$gen/MyApp" "$gen/MyWidget"
cat > "$gen/App.xcodeproj/project.pbxproj" <<'EOF'
		AAA /* MyApp */ = {
			isa = PBXNativeTarget;
			name = MyApp;
			productType = "com.apple.product-type.application";
		};
		DDD /* MyWidget */ = {
			isa = PBXNativeTarget;
			name = MyWidget;
			productType = "com.apple.product-type.app-extension";
		};
EOF
# only the extension declares a plist; the app uses GENERATE_INFOPLIST_FILE
printf 'INFOPLIST_FILE = MyWidget/Info.plist;\n' >> "$gen/App.xcodeproj/project.pbxproj"
touch "$gen/MyApp/App.swift" "$gen/MyApp/ContentView.swift" "$gen/MyWidget/Widget.swift"
touch "$gen/MyWidget/Info.plist"
assert_eq "$(pm_resolve "$gen")" "$(printf 'MyApp\t')" "resolve picks the app dir, not the extension plist"
rm -rf "$gen"

# --- pm_resolve: older app that declares its own INFOPLIST_FILE ---
old="$(mktemp -d)"
mkdir -p "$old/App.xcodeproj" "$old/MyApp"
cat > "$old/App.xcodeproj/project.pbxproj" <<'EOF'
		AAA /* MyApp */ = {
			isa = PBXNativeTarget;
			name = MyApp;
			productType = "com.apple.product-type.application";
		};
EOF
printf 'INFOPLIST_FILE = MyApp/Info.plist;\n' >> "$old/App.xcodeproj/project.pbxproj"
touch "$old/MyApp/App.swift" "$old/MyApp/Info.plist"
assert_eq "$(pm_resolve "$old")" "$(printf 'MyApp\tMyApp/Info.plist')" "resolve returns app dir + its declared plist"
rm -rf "$old"

# --- pm_resolve: nested .xcodeproj (ios/) yields ROOT-relative paths ---
nest="$(mktemp -d)"
mkdir -p "$nest/ios/App.xcodeproj" "$nest/ios/MyApp"
cat > "$nest/ios/App.xcodeproj/project.pbxproj" <<'EOF'
		AAA /* MyApp */ = {
			isa = PBXNativeTarget;
			name = MyApp;
			productType = "com.apple.product-type.application";
		};
EOF
printf 'INFOPLIST_FILE = MyApp/Info.plist;\n' >> "$nest/ios/App.xcodeproj/project.pbxproj"
touch "$nest/ios/MyApp/App.swift" "$nest/ios/MyApp/Info.plist"
assert_eq "$(pm_resolve "$nest")" "$(printf 'ios/MyApp\tios/MyApp/Info.plist')" "resolve prefixes the .xcodeproj parent dir"
rm -rf "$nest"

# --- pm_resolve: multi-app picks the one with more sources ---
multi="$(mktemp -d)"
mkdir -p "$multi/App.xcodeproj" "$multi/AppA" "$multi/AppB"
cat > "$multi/App.xcodeproj/project.pbxproj" <<'EOF'
		AAA /* AppA */ = {
			isa = PBXNativeTarget;
			name = AppA;
			productType = "com.apple.product-type.application";
		};
		BBB /* AppB */ = {
			isa = PBXNativeTarget;
			name = AppB;
			productType = "com.apple.product-type.application";
		};
EOF
touch "$multi/AppA/One.swift"
touch "$multi/AppB/One.swift" "$multi/AppB/Two.swift" "$multi/AppB/Three.swift"
assert_eq "$(pm_resolve "$multi" | cut -f1)" "AppB" "resolve picks the app with more sources"
rm -rf "$multi"

# --- pm_resolve: no pbxproj -> empty + non-zero ---
none="$(mktemp -d)"; touch "$none/readme.md"
pm_resolve "$none" >/dev/null && r=0 || r=1
assert_eq "$r" "1" "resolve fails cleanly when no pbxproj is present"
rm -rf "$none"

# --- pm_resolve: trailing-slash root still yields ROOT-relative paths (Fix 1) ---
slash="$(mktemp -d)"
mkdir -p "$slash/ios/App.xcodeproj" "$slash/ios/MyApp"
cat > "$slash/ios/App.xcodeproj/project.pbxproj" <<'EOF'
		AAA /* MyApp */ = {
			isa = PBXNativeTarget;
			name = MyApp;
			productType = "com.apple.product-type.application";
		};
EOF
printf 'INFOPLIST_FILE = MyApp/Info.plist;\n' >> "$slash/ios/App.xcodeproj/project.pbxproj"
touch "$slash/ios/MyApp/App.swift" "$slash/ios/MyApp/Info.plist"
assert_eq "$(pm_resolve "$slash/")" "$(printf 'ios/MyApp\tios/MyApp/Info.plist')" "resolve stays ROOT-relative when root has a trailing slash"
rm -rf "$slash"

# --- pm_resolve: dir name merely resembling a pruned dir is not pruned (Fix 2) ---
lookalike="$(mktemp -d)"
mkdir -p "$lookalike/xbuild/App.xcodeproj" "$lookalike/xbuild/MyApp"
cat > "$lookalike/xbuild/App.xcodeproj/project.pbxproj" <<'EOF'
		AAA /* MyApp */ = {
			isa = PBXNativeTarget;
			name = MyApp;
			productType = "com.apple.product-type.application";
		};
EOF
printf 'INFOPLIST_FILE = MyApp/Info.plist;\n' >> "$lookalike/xbuild/App.xcodeproj/project.pbxproj"
touch "$lookalike/xbuild/MyApp/App.swift" "$lookalike/xbuild/MyApp/Info.plist"
got="$(pm_resolve "$lookalike")"
assert_eq "$([[ -n "$got" ]] && echo nonempty || echo empty)" "nonempty" "resolve finds a pbxproj under a dir merely resembling a pruned name"
assert_eq "$(printf '%s' "$got" | cut -f1)" "xbuild/MyApp" "resolve does not prune a dir that only resembles .build/.git"
rm -rf "$lookalike"

# --- pm_find_pbxprojs: returns ALL pruned project.pbxproj, not just the shallowest ---
multiproj="$(mktemp -d)"
mkdir -p "$multiproj/Sample.xcodeproj" "$multiproj/SampleApp" \
         "$multiproj/app/RealApp.xcodeproj" "$multiproj/app/RealApp"
cat > "$multiproj/Sample.xcodeproj/project.pbxproj" <<'EOF'
		AAA /* SampleApp */ = {
			isa = PBXNativeTarget;
			name = SampleApp;
			productType = "com.apple.product-type.application";
		};
EOF
printf 'INFOPLIST_FILE = SampleApp/Info.plist;\n' >> "$multiproj/Sample.xcodeproj/project.pbxproj"
touch "$multiproj/SampleApp/App.swift" "$multiproj/SampleApp/Info.plist"
cat > "$multiproj/app/RealApp.xcodeproj/project.pbxproj" <<'EOF'
		AAA /* RealApp */ = {
			isa = PBXNativeTarget;
			name = RealApp;
			productType = "com.apple.product-type.application";
		};
EOF
printf 'INFOPLIST_FILE = RealApp/Info.plist;\n' >> "$multiproj/app/RealApp.xcodeproj/project.pbxproj"
touch "$multiproj/app/RealApp/App.swift" "$multiproj/app/RealApp/A.swift" "$multiproj/app/RealApp/B.swift"
touch "$multiproj/app/RealApp/Info.plist"

found_count="$(pm_find_pbxprojs "$multiproj" | wc -l | tr -d ' ')"
assert_eq "$found_count" "2" "pm_find_pbxprojs returns both pbxproj paths in a multi-project tree"

# --- pm_resolve: monorepo with a shallow sample .xcodeproj and a deeper real app;
# the real app (more swift sources) must win, even though it is NOT the shallowest ---
got="$(pm_resolve "$multiproj")"
assert_eq "$(printf '%s' "$got" | cut -f1)" "app/RealApp" "resolve picks the real app across all pbxproj, not the shallow sample"
assert_eq "$(printf '%s' "$got" | cut -f2)" "app/RealApp/Info.plist" "resolve returns the real app's declared plist"
rm -rf "$multiproj"

# --- pm_resolve: multi-app tie on equal .swift counts keeps the first-seen target
# (n > best_n is a strict inequality, so ordering — not magnitude — decides ties) ---
tie="$(mktemp -d)"
mkdir -p "$tie/App.xcodeproj" "$tie/AppOne" "$tie/AppTwo"
cat > "$tie/App.xcodeproj/project.pbxproj" <<'EOF'
		AAA /* AppOne */ = {
			isa = PBXNativeTarget;
			name = AppOne;
			productType = "com.apple.product-type.application";
		};
		BBB /* AppTwo */ = {
			isa = PBXNativeTarget;
			name = AppTwo;
			productType = "com.apple.product-type.application";
		};
EOF
printf 'INFOPLIST_FILE = AppOne/Info.plist;\n' >> "$tie/App.xcodeproj/project.pbxproj"
printf 'INFOPLIST_FILE = AppTwo/Info.plist;\n' >> "$tie/App.xcodeproj/project.pbxproj"
touch "$tie/AppOne/App.swift" "$tie/AppOne/Info.plist"
touch "$tie/AppTwo/App.swift" "$tie/AppTwo/Info.plist"
assert_eq "$(pm_resolve "$tie" | cut -f1)" "AppOne" "resolve keeps the first-seen target on an equal-count tie"
rm -rf "$tie"

# --- pm_target_infoplist: attribute a target's OWN INFOPLIST_FILE via the
# build-config graph (PBXNativeTarget -> buildConfigurationList UUID ->
# XCConfigurationList block -> buildConfigurations list -> XCBuildConfiguration
# blocks), even when the plist's leading path component != the target name.
# Models brave-ios's real App/Client.xcodeproj shape. ---
graph="$(mktemp -d)"
cat > "$graph/graph.pbxproj" <<'EOF'
		AAA /* Client */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = BCLIST1 /* Build configuration list for PBXNativeTarget "Client" */;
			name = Client;
			productName = Client;
			productType = "com.apple.product-type.application";
		};
		BCLIST1 /* Build configuration list for PBXNativeTarget "Client" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				CFG1 /* Debug */,
				CFG2 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Debug;
		};
		CFG1 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				INFOPLIST_FILE = "iOS/Supporting Files/Info.plist";
				PRODUCT_NAME = Client;
			};
			name = Debug;
		};
		CFG2 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				INFOPLIST_FILE = "iOS/Supporting Files/Info.plist";
				PRODUCT_NAME = Client;
			};
			name = Release;
		};
EOF
assert_eq "$(pm_target_infoplist "$graph/graph.pbxproj" "Client")" "iOS/Supporting Files/Info.plist" \
  "pm_target_infoplist attributes the target's own quoted-with-space plist via the build-config graph"
rm -rf "$graph"

# --- pm_resolve: a real ("Client"-shaped) app whose plist is only attributable
# via the build-config graph (no Client/ dir, projdir "App") must beat a
# vendored sample app (projdir "ThirdParty/Sample") even though the sample has
# more .swift sources. This reproduces the brave-ios false positive where the
# old code (a) fails the leading-component match, (b) then `find -type d -name
# Client` finds nothing and SKIPS Client entirely, letting the vendored sample
# win by default. ---
brave="$(mktemp -d)"
mkdir -p "$brave/App/Client.xcodeproj" "$brave/App/iOS/Supporting Files" \
         "$brave/ThirdParty/Sample/Sample.xcodeproj" "$brave/ThirdParty/Sample/Example"
cat > "$brave/App/Client.xcodeproj/project.pbxproj" <<'EOF'
		AAA /* Client */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = BCLIST1 /* Build configuration list for PBXNativeTarget "Client" */;
			name = Client;
			productType = "com.apple.product-type.application";
		};
		BCLIST1 /* Build configuration list for PBXNativeTarget "Client" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				CFG1 /* Debug */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Debug;
		};
		CFG1 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				INFOPLIST_FILE = "iOS/Supporting Files/Info.plist";
			};
			name = Debug;
		};
EOF
# NOTE: no "Client/" directory exists anywhere under App/ — sources live
# elsewhere in the real repo. This is the crux of the brave-ios bug: the old
# GENERATE fallback `find -type d -name Client` finds nothing and `continue`s,
# skipping Client entirely.
touch "$brave/App/iOS/Supporting Files/Info.plist"
cat > "$brave/ThirdParty/Sample/Sample.xcodeproj/project.pbxproj" <<'EOF'
		BBB /* Example */ = {
			isa = PBXNativeTarget;
			name = Example;
			productType = "com.apple.product-type.application";
		};
EOF
printf 'INFOPLIST_FILE = Example/Info.plist;\n' >> "$brave/ThirdParty/Sample/Sample.xcodeproj/project.pbxproj"
touch "$brave/ThirdParty/Sample/Example/Info.plist"
touch "$brave/ThirdParty/Sample/Example/One.swift" \
      "$brave/ThirdParty/Sample/Example/Two.swift" \
      "$brave/ThirdParty/Sample/Example/Three.swift"
got="$(pm_resolve "$brave")"
assert_eq "$(printf '%s' "$got" | cut -f1)" "App/iOS/Supporting Files" \
  "resolve picks Client's real plist dir via the build-config graph, not the vendored sample"
assert_eq "$(printf '%s' "$got" | cut -f2)" "App/iOS/Supporting Files/Info.plist" \
  "resolve returns Client's build-config-attributed plist"
rm -rf "$brave"

# --- pm_target_infoplist: comment-LESS buildConfigurationList (generator-written
# pbxproj, e.g. XcodeGen/Tuist, which omit the "/* comment */") must still
# resolve. The UUID extraction used to rely on the comment's leading space to
# truncate the line, so `buildConfigurationList = BCLIST1;` (no comment) left
# a trailing ";" attached to the UUID, which then failed to match the
# XCConfigurationList block-opener and silently fell back to nothing. ---
nocomment="$(mktemp -d)"
cat > "$nocomment/nocomment.pbxproj" <<'EOF'
		AAA /* Client */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = BCLIST1;
			name = Client;
			productType = "com.apple.product-type.application";
		};
		BCLIST1 = {
			isa = XCConfigurationList;
			buildConfigurations = (
				CFG1,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Debug;
		};
		CFG1 = {
			isa = XCBuildConfiguration;
			buildSettings = {
				INFOPLIST_FILE = Client/Info.plist;
			};
			name = Debug;
		};
EOF
assert_eq "$(pm_target_infoplist "$nocomment/nocomment.pbxproj" "Client")" "Client/Info.plist" \
  "pm_target_infoplist resolves INFOPLIST_FILE when buildConfigurationList has no trailing comment (Fix 1)"
rm -rf "$nocomment"

# --- pm_resolve: a target resolvable via the GENERATE dir-name branch (a dir
# named after the target EXISTS) must win over build-config attribution, even
# when the target's build config also declares an (unusable) INFOPLIST_FILE
# under an unexpanded build variable. Models eigen's real Artsy.xcodeproj
# shape: the Artsy target's build config has
# INFOPLIST_FILE = "$(SRCROOT)/Artsy/Supporting/Info.plist" (an Xcode
# variable, never expanded by this script), but an "Artsy/" dir exists next
# to the .xcodeproj. Before this fix, pm_target_infoplist was consulted
# FIRST and won unconditionally, producing the broken dir
# "ios/$(SRCROOT)/Artsy/Supporting". The GENERATE branch (Priority 2) must
# take precedence over build-config attribution (Priority 3, last resort). ---
eigenclass="$(mktemp -d)"
mkdir -p "$eigenclass/ios/Artsy.xcodeproj" "$eigenclass/ios/Artsy"
cat > "$eigenclass/ios/Artsy.xcodeproj/project.pbxproj" <<'EOF'
		AAA /* Artsy */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = BCLIST1 /* Build configuration list for PBXNativeTarget "Artsy" */;
			name = Artsy;
			productType = "com.apple.product-type.application";
		};
		BCLIST1 /* Build configuration list for PBXNativeTarget "Artsy" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				CFG1 /* Debug */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Debug;
		};
		CFG1 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				INFOPLIST_FILE = "$(SRCROOT)/Artsy/Supporting/Info.plist";
			};
			name = Debug;
		};
EOF
# No leading-component-matching INFOPLIST_FILE is declared anywhere (the only
# one lives under the unexpanded $(SRCROOT) variable, which pm_infoplist_files
# would return as "$(SRCROOT)/Artsy/Supporting/Info.plist" — leading component
# "$(SRCROOT)", not "Artsy" — so the leading-component match also legitimately
# fails). The "Artsy/" dir DOES exist, so the GENERATE branch must resolve it.
touch "$eigenclass/ios/Artsy/AppDelegate.swift"
got="$(pm_resolve "$eigenclass")"
assert_eq "$(printf '%s' "$got" | cut -f1)" "ios/Artsy" \
  "resolve uses the GENERATE dir-name branch, not build-config attribution, when a dir named after the target exists (eigen class)"
assert_eq "$(printf '%s' "$got" | cut -f2)" "" \
  "resolve does not surface the unusable \$(SRCROOT) build-variable plist when GENERATE already resolved a dir"
rm -rf "$eigenclass"

# --- pm_target_infoplist / pm_resolve: a resolved plist path must never
# contain an unexpanded Xcode build variable such as "$(SRCROOT)" — a literal
# "$(...)" path can never be found on disk. This guards the last-resort
# build-config-attribution branch directly (no GENERATE dir exists here, so
# pm_resolve is forced to fall through to pm_target_infoplist, which must be
# rejected for the build-variable path, leaving the target skipped). ---
buildvar="$(mktemp -d)"
mkdir -p "$buildvar/ios/Foo.xcodeproj"
cat > "$buildvar/ios/Foo.xcodeproj/project.pbxproj" <<'EOF'
		AAA /* Foo */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = BCLIST1 /* Build configuration list for PBXNativeTarget "Foo" */;
			name = Foo;
			productType = "com.apple.product-type.application";
		};
		BCLIST1 /* Build configuration list for PBXNativeTarget "Foo" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				CFG1 /* Debug */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Debug;
		};
		CFG1 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				INFOPLIST_FILE = "$(SRCROOT)/Foo/Info.plist";
			};
			name = Debug;
		};
EOF
# pm_target_infoplist itself must still return the raw (unguarded) value —
# the guard lives at the pm_resolve call site, not inside the attribution walk.
assert_eq "$(pm_target_infoplist "$buildvar/ios/Foo.xcodeproj/project.pbxproj" "Foo")" '$(SRCROOT)/Foo/Info.plist' \
  "pm_target_infoplist returns the raw build-variable path unguarded"
# No "Foo/" dir exists anywhere and no leading-component plist is declared, so
# pm_resolve must fall through to the last resort, reject the $(SRCROOT) path,
# and skip the target entirely (no *.swift sources anywhere -> resolve fails).
pm_resolve "$buildvar" >/dev/null && r=0 || r=1
assert_eq "$r" "1" \
  "resolve never yields a path containing an unexpanded build variable; skips the target instead"
rm -rf "$buildvar"

# --- pm_resolve: PM_SAMPLE_PATH must NOT deprioritize a primary app that lives
# under a Demo/-named dir (common for library repos whose real deliverable app
# is the demo). Only ThirdParty/Vendored are high-confidence vendored markers.
# DemoApp has more .swift sources than OtherApp (which lives under a dir that
# never matches PM_SAMPLE_PATH), so DemoApp must win normal best-vs-best
# comparison — if Demo/ were still deprioritized into the alt bucket, OtherApp
# would win instead since a non-empty "best" always beats "alt" (Fix 2). ---
demo="$(mktemp -d)"
mkdir -p "$demo/Demo/App.xcodeproj" "$demo/Demo/DemoApp" \
         "$demo/Elsewhere/Other.xcodeproj" "$demo/Elsewhere/OtherApp"
cat > "$demo/Demo/App.xcodeproj/project.pbxproj" <<'EOF'
		AAA /* DemoApp */ = {
			isa = PBXNativeTarget;
			name = DemoApp;
			productType = "com.apple.product-type.application";
		};
EOF
touch "$demo/Demo/DemoApp/One.swift" "$demo/Demo/DemoApp/Two.swift" "$demo/Demo/DemoApp/Three.swift"
cat > "$demo/Elsewhere/Other.xcodeproj/project.pbxproj" <<'EOF'
		BBB /* OtherApp */ = {
			isa = PBXNativeTarget;
			name = OtherApp;
			productType = "com.apple.product-type.application";
		};
EOF
touch "$demo/Elsewhere/OtherApp/One.swift"
got="$(pm_resolve "$demo")"
assert_eq "$(printf '%s' "$got" | cut -f1)" "Demo/DemoApp" \
  "resolve treats a Demo/-named dir as primary, not deprioritized (Fix 2)"
rm -rf "$demo"

# --- pm_resolve: PM_SAMPLE_PATH must deprioritize an app target whose project
# lives under a bare "Vendor/" path segment, even when that vendored app has
# MORE .swift sources than the primary (non-vendored) app. This guards against
# a regex bug where '(^|/)(ThirdParty|Vendored?)(/|$)' — the trailing "?"
# binds only to the "d" in "Vendored" — matches "Vendore"/"Vendored" but NOT
# the bare canonical "Vendor", so a Vendor/-rooted app would wrongly be
# treated as primary and win on source count alone. ---
vendor="$(mktemp -d)"
mkdir -p "$vendor/Main/PrimaryApp.xcodeproj" "$vendor/Main/PrimaryApp" \
         "$vendor/Vendor/VendorApp.xcodeproj" "$vendor/Vendor/VendorApp"
cat > "$vendor/Main/PrimaryApp.xcodeproj/project.pbxproj" <<'EOF'
		AAA /* PrimaryApp */ = {
			isa = PBXNativeTarget;
			name = PrimaryApp;
			productType = "com.apple.product-type.application";
		};
EOF
touch "$vendor/Main/PrimaryApp/One.swift"
cat > "$vendor/Vendor/VendorApp.xcodeproj/project.pbxproj" <<'EOF'
		BBB /* VendorApp */ = {
			isa = PBXNativeTarget;
			name = VendorApp;
			productType = "com.apple.product-type.application";
		};
EOF
touch "$vendor/Vendor/VendorApp/One.swift" "$vendor/Vendor/VendorApp/Two.swift" "$vendor/Vendor/VendorApp/Three.swift"
got="$(pm_resolve "$vendor")"
assert_eq "$(printf '%s' "$got" | cut -f1)" "Main/PrimaryApp" \
  "resolve deprioritizes a bare Vendor/-rooted app even though it has more .swift sources"
rm -rf "$vendor"

# --- pm_resolve: same as above, but for the "Vendored/" spelling, to guard the
# other side of the regex (must still match the longer form too). ---
vendored="$(mktemp -d)"
mkdir -p "$vendored/Main/PrimaryApp.xcodeproj" "$vendored/Main/PrimaryApp" \
         "$vendored/Vendored/VendorApp.xcodeproj" "$vendored/Vendored/VendorApp"
cat > "$vendored/Main/PrimaryApp.xcodeproj/project.pbxproj" <<'EOF'
		AAA /* PrimaryApp */ = {
			isa = PBXNativeTarget;
			name = PrimaryApp;
			productType = "com.apple.product-type.application";
		};
EOF
touch "$vendored/Main/PrimaryApp/One.swift"
cat > "$vendored/Vendored/VendorApp.xcodeproj/project.pbxproj" <<'EOF'
		BBB /* VendorApp */ = {
			isa = PBXNativeTarget;
			name = VendorApp;
			productType = "com.apple.product-type.application";
		};
EOF
touch "$vendored/Vendored/VendorApp/One.swift" "$vendored/Vendored/VendorApp/Two.swift" "$vendored/Vendored/VendorApp/Three.swift"
got="$(pm_resolve "$vendored")"
assert_eq "$(printf '%s' "$got" | cut -f1)" "Main/PrimaryApp" \
  "resolve deprioritizes a Vendored/-rooted app even though it has more .swift sources"
rm -rf "$vendored"

echo "test-project-model: OK"
exit "$fails"
