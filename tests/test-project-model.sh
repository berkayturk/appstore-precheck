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

echo "test-project-model: OK"
exit "$fails"
