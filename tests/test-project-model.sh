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

echo "test-project-model: OK"
