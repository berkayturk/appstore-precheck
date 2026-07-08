// Simulates a vendored SPM checkout that would land under a gitignored
// build/ directory when iosSourceDir resolves to the repo root ("."). It
// deliberately contains a tracking-SDK signal (AppsFlyerLib import) so the
// scan asserts this checkout is pruned rather than scanned for App Store
// rejection vectors — see GREP_PRUNE in scan.sh.
import Foundation
import AppsFlyerLib

final class VendoredTracker {}
